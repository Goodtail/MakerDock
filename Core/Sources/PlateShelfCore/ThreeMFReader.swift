import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CryptoKit
import ZIPFoundation

/// Bounds apply before allocation and again while consuming decompressed chunks.
struct ArchiveLimits {
    static let entryCount = 10_000
    static let archiveBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024
    static let expandedBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024
    static let modelXMLBytes = 64 * 1_024 * 1_024
    static let settingsBytes = 16 * 1_024 * 1_024
    static let imageBytes = 16 * 1_024 * 1_024
    static let imagePixels: UInt64 = 16_777_216
}

struct ParsedArchive {
    var metadata: [String: String]
    var plates: [PlateRecord]
    var previews: [String: Data]
    var thumbnailPath: String?
    var materials: [String]
    var printerModel: String?
    var hasGCode: Bool
}

struct ThreeMFReader {
    let archive: Archive
    var entries: [String: Entry] = [:]

    init(url: URL) throws {
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw LibraryError.invalidArchive(url.lastPathComponent) }
        var total: UInt64 = 0
        var count = 0
        for entry in archive {
            count += 1
            guard count <= ArchiveLimits.entryCount else { throw LibraryError.limitExceeded("압축 항목 수") }
            try Self.validateEntryPath(entry.path)
            guard entry.type != .symlink else { throw LibraryError.unsafePath(entry.path) }
            guard entry.uncompressedSize <= ArchiveLimits.expandedBytes - total else {
                throw LibraryError.limitExceeded("압축 해제 크기")
            }
            total += entry.uncompressedSize
            let key = entry.path.lowercased()
            guard entries[key] == nil else { throw LibraryError.invalidArchive("중복된 내부 경로") }
            entries[key] = entry
        }
        let hasModel = entries["3d/3dmodel.model"]?.type == .file
        let hasGCode = entries.values.contains { $0.type == .file && $0.path.lowercased().hasSuffix(".gcode") }
        guard entries["[content_types].xml"]?.type == .file,
              hasModel || (hasGCode && entries["metadata/slice_info.config"] != nil) else {
            throw LibraryError.invalidArchive("3MF 모델 또는 출력 데이터가 없습니다")
        }
    }

    static func validateEntryPath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              !path.contains(":"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(".") else {
            throw LibraryError.unsafePath(path)
        }
    }

    private func read(_ path: String, limit: Int) throws -> Data? {
        guard let entry = entries[path.lowercased()] else { return nil }
        guard entry.type == .file else { throw LibraryError.invalidArchive(path) }
        guard entry.uncompressedSize <= UInt64(limit) else { throw LibraryError.limitExceeded(path) }
        var bytes = Data()
        let checksum = try archive.extract(entry, bufferSize: 64 * 1_024) { chunk in
            guard chunk.count <= limit - bytes.count else { throw LibraryError.limitExceeded(path) }
            bytes.append(chunk)
        }
        guard bytes.count == Int(entry.uncompressedSize), checksum == entry.checksum else {
            throw LibraryError.invalidArchive("\(path) 무결성 검사 실패")
        }
        return bytes
    }

    func parse() throws -> ParsedArchive {
        if let types = try read("[Content_Types].xml", limit: ArchiveLimits.settingsBytes) {
            _ = try XMLMetadata.read(types, path: "[Content_Types].xml", root: "Types")
        }
        let model = try xml("3D/3dmodel.model", limit: ArchiveLimits.modelXMLBytes, root: "model")
        let settings = try xml("Metadata/model_settings.config", root: "config")
        let slices = try xml("Metadata/slice_info.config", root: "config")
        var materials: [String] = slices?.materials ?? []
        var printer: String?
        if let bytes = try read("Metadata/project_settings.config", limit: ArchiveLimits.settingsBytes) {
            guard let json = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
                throw LibraryError.invalidSettings
            }
            if let types = json["filament_type"] as? [String] { materials = types + materials }
            else if let type = json["filament_type"] as? String { materials.insert(type, at: 0) }
            printer = (json["printer_model"] as? String)?.nonEmpty
        }

        var plateIDs: [String] = []
        var plateSettings: [String: [String: String]] = [:]
        for (offset, plate) in (settings?.plates ?? []).enumerated() {
            let id = normalizeID(plate["plater_id"] ?? plate["plate_id"] ?? plate["index"] ?? String(offset + 1))
            guard plateSettings[id] == nil else { throw LibraryError.invalidArchive("중복 플레이트 번호") }
            plateSettings[id] = plate; plateIDs.append(id)
        }
        var plateSlices: [String: [String: String]] = [:]
        for plate in slices?.plates ?? [] {
            guard let raw = plate["index"] ?? plate["plater_id"] ?? plate["plate_id"], raw.nonEmpty != nil else {
                throw LibraryError.invalidXML("slice_info.config 플레이트 번호")
            }
            let id = normalizeID(raw)
            guard plateSlices[id] == nil else { throw LibraryError.invalidArchive("중복 출력 플레이트 번호") }
            plateSlices[id] = plate
            if !plateIDs.contains(id) { plateIDs.append(id) }
            if printer == nil { printer = plate["printer_model_id"]?.nonEmpty }
        }

        var previews: [String: Data] = [:]
        func preview(_ path: String?) throws -> String? {
            guard let path = path?.nonEmpty else { return nil }
            let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
            try Self.validateEntryPath(normalized)
            let ext = (normalized as NSString).pathExtension.lowercased()
            guard ["png", "jpg", "jpeg"].contains(ext),
                  let data = try read(normalized, limit: ArchiveLimits.imageBytes) else { return nil }
            guard Self.validImageDimensions(data, extension: ext) else { return nil }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let relative = "Previews/\(hash).\(ext == "jpeg" ? "jpg" : ext)"
            previews[relative] = data
            return relative
        }
        var plates: [PlateRecord] = []
        for id in plateIDs {
            let config = plateSettings[id] ?? [:]
            let sliced = plateSlices[id] ?? [:]
            let thumbnail = try preview(config["thumbnail_file"] ?? "Metadata/plate_\(id).png")
            let gcodePath = sliced["gcode_file"] ?? config["gcode_file"] ?? "Metadata/plate_\(id).gcode"
            let seconds = try positive(sliced["prediction"]) ?? gcodeTime(gcodePath)
            plates.append(PlateRecord(id: id, name: config["plater_name"]?.nonEmpty ?? config["name"]?.nonEmpty ?? "플레이트 \(id)",
                                      thumbnailPath: thumbnail, estimatedSeconds: seconds,
                                      weightGrams: positive(sliced["weight"])))
        }
        let meta = model?.metadata ?? [:]
        var thumbnail = try preview("Auxiliaries/.thumbnails/thumbnail_3mf.png")
        if thumbnail == nil { thumbnail = try preview(meta["thumbnail_middle"]) }
        if thumbnail == nil { thumbnail = plates.compactMap(\.thumbnailPath).first }
        if thumbnail == nil { thumbnail = try preview("Metadata/plate_1.png") }
        if thumbnail == nil { thumbnail = try preview("Metadata/thumbnail.png") }
        return ParsedArchive(metadata: meta, plates: plates, previews: previews, thumbnailPath: thumbnail,
                             materials: Array(Set(materials.compactMap(\.nonEmpty))).sorted(), printerModel: printer,
                             hasGCode: entries.values.contains { $0.type == .file && $0.path.lowercased().hasSuffix(".gcode") })
    }

    private func xml(_ path: String, limit: Int = ArchiveLimits.settingsBytes, root: String) throws -> XMLMetadata? {
        guard let bytes = try read(path, limit: limit) else { return nil }
        return try XMLMetadata.read(bytes, path: path, root: root)
    }

    private func gcodeTime(_ path: String) throws -> Double? {
        try Self.validateEntryPath(path)
        guard let entry = entries[path.lowercased()], entry.type == .file,
              path.lowercased().hasSuffix(".gcode"), entry.uncompressedSize <= 512 * 1_024 * 1_024 else { return nil }
        // Retain only the header; still consume the stream to verify its CRC.
        var header = Data(), consumed: UInt64 = 0
        let checksum = try archive.extract(entry, bufferSize: 64 * 1_024) { chunk in
            consumed += UInt64(chunk.count)
            guard consumed <= entry.uncompressedSize else { throw LibraryError.limitExceeded(path) }
            if header.count < 64 * 1_024 { header.append(chunk.prefix(64 * 1_024 - header.count)) }
        }
        guard consumed == entry.uncompressedSize, checksum == entry.checksum else { throw LibraryError.invalidArchive("G-code 무결성 검사 실패") }
        return Self.gcodeHeaderTime(String(decoding: header, as: UTF8.self))
    }

    static func gcodeHeaderTime(_ header: String) -> Double? {
        for line in header.split(separator: "\n").prefix(100) {
            guard line.hasPrefix(";") else { continue }
            let markers = ["total estimated time:", "estimated printing time (normal mode) ="]
            guard let range = markers.compactMap({ line.range(of: $0) }).first else { continue }
            let duration = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard duration.range(of: #"^(?:\d+(?:\.\d+)?[dhms]\s*)+$"#, options: .regularExpression) != nil else { continue }
            let regex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)([dhms])"#)
            let ns = duration as NSString
            var seconds = 0.0
            for match in regex.matches(in: duration, range: NSRange(location: 0, length: ns.length)) {
                let value = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let unit = ns.substring(with: match.range(at: 2))
                seconds += value * (["d": 86400.0, "h": 3600, "m": 60, "s": 1][unit] ?? 0)
            }
            if seconds.isFinite, seconds > 0 { return seconds }
        }
        return nil
    }

    private func normalizeID(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(value).map(String.init) ?? value
    }
    private func positive(_ value: String?) -> Double? {
        guard let value, let number = Double(value), number.isFinite, number > 0 else { return nil }
        return number
    }

    // Read pixel dimensions without decoding potentially enormous bitmaps.
    static func validImageDimensions(_ data: Data, extension ext: String) -> Bool {
        let bytes = [UInt8](data)
        func allowed(_ width: UInt64, _ height: UInt64) -> Bool {
            width > 0 && height > 0 && width <= 8_192 && height <= 8_192 && width * height <= ArchiveLimits.imagePixels
        }
        if ext == "png" {
            guard bytes.count >= 24, Array(bytes[0..<8]) == [137, 80, 78, 71, 13, 10, 26, 10],
                  Array(bytes[12..<16]) == [73, 72, 68, 82] else { return false }
            let width = bytes[16..<20].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let height = bytes[20..<24].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return allowed(width, height)
        }
        guard bytes.count > 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { return false }
        var offset = 2
        while offset + 3 < bytes.count {
            guard bytes[offset] == 0xff else { return false }
            while offset < bytes.count && bytes[offset] == 0xff { offset += 1 }
            guard offset + 2 < bytes.count else { return false }
            let marker = bytes[offset]; offset += 1
            if marker == 0xd9 || marker == 0xda { return false }
            if marker == 0x01 || (0xd0...0xd7).contains(marker) { continue }
            let length = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
            guard length >= 2, length <= bytes.count - offset else { return false }
            if [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].contains(marker) {
                guard length >= 7 else { return false }
                let height = UInt64(bytes[offset + 3]) * 256 + UInt64(bytes[offset + 4])
                let width = UInt64(bytes[offset + 5]) * 256 + UInt64(bytes[offset + 6])
                return allowed(width, height)
            }
            offset += length
        }
        return false
    }
}

private final class XMLMetadata: NSObject, XMLParserDelegate {
    var metadata: [String: String] = [:]
    var plates: [[String: String]] = []
    var materials: [String] = []
    var elementStack: [String] = []
    var plate: [String: String]?
    var plateDepth: Int?
    var currentName: String?
    var text = ""
    var failed = false
    var count = 0
    let expectedRoot: String

    init(root: String) { expectedRoot = root }

    static func read(_ data: Data, path: String, root: String) throws -> XMLMetadata {
        // Reject declarations before XMLParser receives them. The files produced by Studio use UTF-8.
        guard let source = String(data: data, encoding: .utf8),
              !source.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !source.localizedCaseInsensitiveContains("<!ENTITY") else { throw LibraryError.invalidXML(path) }
        let delegate = XMLMetadata(root: root)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        guard parser.parse(), !delegate.failed, delegate.count > 0 else { throw LibraryError.invalidXML(path) }
        return delegate
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        count += 1
        if count > 2_000_000 || elementStack.count >= 128 || (elementStack.isEmpty && elementName != expectedRoot) {
            failed = true; parser.abortParsing(); return
        }
        let parent = elementStack.last
        elementStack.append(elementName)
        if elementName == "plate", parent == "config" {
            plate = attributeDict; plateDepth = elementStack.count
        }
        if elementName == "metadata", parent == "model", let name = attributeDict["name"] {
            currentName = name.lowercased(); text = ""
        } else if elementName == "metadata", parent == "plate", let key = attributeDict["key"], let value = attributeDict["value"] {
            plate?[key.lowercased()] = value
        } else if elementName == "filament", parent == "plate", let material = attributeDict["type"] {
            materials.append(material)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentName != nil {
            guard text.utf8.count + string.utf8.count <= 2 * 1_024 * 1_024 else { failed = true; parser.abortParsing(); return }
            text += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "metadata", let name = currentName { metadata[name] = text; currentName = nil; text = "" }
        if elementName == "plate", elementStack.count == plateDepth {
            if let plate { plates.append(plate) }; plate = nil; plateDepth = nil
        }
        if !elementStack.isEmpty { elementStack.removeLast() }
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        failed = true; parser.abortParsing(); return nil
    }
}

extension String {
    var nonEmpty: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
}
