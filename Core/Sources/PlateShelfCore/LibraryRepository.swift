import Foundation
import CryptoKit

public actor LibraryRepository {
    public nonisolated let rootURL: URL
    private var records: [LibraryItem]
    private var lastIndexData: Data?
    private let fileManager = FileManager.default
    private var indexURL: URL { rootURL.appendingPathComponent("index.json") }

    private struct Index: Codable {
        var schemaVersion: Int = 1
        var items: [LibraryItem]
    }

    public init(rootURL: URL) throws {
        self.rootURL = rootURL.standardizedFileURL
        let indexURL = rootURL.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let values = try indexURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? Int.max) <= 64 * 1_024 * 1_024 else { throw LibraryError.corruptIndex }
            let data = try Data(contentsOf: indexURL)
            guard let index = try? Self.decoder().decode(Index.self, from: data), index.schemaVersion == 1,
                  Self.valid(index.items) else { throw LibraryError.corruptIndex }
            self.records = index.items; self.lastIndexData = data
        } else { self.records = []; self.lastIndexData = nil }
        try FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        for directory in ["Files", "Previews", ".staging"] {
            let url = self.rootURL.appendingPathComponent(directory, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath(directory) }
            } else { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        }
    }

    public func items() -> [LibraryItem] {
        records.sorted { lhs, rhs in lhs.importedAt == rhs.importedAt ? lhs.id < rhs.id : lhs.importedAt > rhs.importedAt }
    }

    public func importFile(at source: URL, expectedSHA256: String? = nil) throws -> ImportResult {
        let expectedHash = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let expectedHash {
            guard expectedHash.utf8.count == 64,
                  expectedHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw LibraryError.invalidArchive("SHA256 확인값이 올바르지 않습니다")
            }
        }
        var source = source.standardizedFileURL
        guard source.isFileURL, source.pathExtension.lowercased() == "3mf" else { throw LibraryError.unsupportedFile }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let before = try source.resourceValues(forKeys: keys)
        guard before.isRegularFile == true, before.isSymbolicLink != true else { throw LibraryError.unsupportedFile }
        guard UInt64(before.fileSize ?? 0) <= ArchiveLimits.archiveBytes else { throw LibraryError.limitExceeded("원본 파일 크기") }
        let staging = rootURL.appendingPathComponent(".staging/\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let stagedArchive = staging.appendingPathComponent("archive.3mf")
        try fileManager.copyItem(at: source, to: stagedArchive)
        source.removeAllCachedResourceValues()
        let after = try source.resourceValues(forKeys: keys)
        guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else {
            throw LibraryError.sourceChanged
        }
        let id = try Self.hashFile(stagedArchive)
        // Verify the independent staged copy before dedup metadata, files, or the index can change.
        if let expectedHash, id != expectedHash {
            throw LibraryError.invalidArchive("파일 확인값이 기록과 일치하지 않습니다")
        }
        let archiveRelative = "Files/\(id).3mf"
        let finalArchive = rootURL.appendingPathComponent(archiveRelative)
        var candidate = records
        let duplicate = candidate.firstIndex { $0.id == id }
        var item: LibraryItem
        var previews: [String: Data] = [:]
        if let duplicate {
            item = candidate[duplicate]
            if !item.sourcePaths.contains(source.path) { item.sourcePaths.append(source.path) }
            candidate[duplicate] = item
        } else {
            let parsed = try ThreeMFReader(url: stagedArchive).parse()
            previews = parsed.previews
            let meta = parsed.metadata
            item = LibraryItem(id: id, title: meta["title"]?.nonEmpty ?? source.deletingPathExtension().lastPathComponent,
                               filename: source.lastPathComponent, filePath: archiveRelative,
                               thumbnailPath: parsed.thumbnailPath, sourcePaths: [source.path],
                               designer: meta["designer"]?.nonEmpty,
                               modelID: (meta["designmodelid"] ?? meta["bambustudio:designmodelid"])?.nonEmpty,
                               profileID: (meta["designprofileid"] ?? meta["profileid"] ?? meta["bambustudio:designprofileid"])?.nonEmpty,
                               profileTitle: meta["profiletitle"]?.nonEmpty, materials: parsed.materials,
                               printerModel: parsed.printerModel, plates: parsed.plates, hasGCode: parsed.hasGCode)
            candidate.append(item)
        }

        var created: [URL] = []
        do {
            // Only hashed, app-selected filenames ever reach the filesystem.
            if !fileManager.fileExists(atPath: finalArchive.path) {
                try fileManager.moveItem(at: stagedArchive, to: finalArchive)
                created.append(finalArchive)
                try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: finalArchive.path)
            } else {
                let values = try finalArchive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      try Self.hashFile(finalArchive) == id else { throw LibraryError.invalidArchive("보관한 원본의 무결성 검사 실패") }
            }
            for (relative, bytes) in previews {
                let destination = rootURL.appendingPathComponent(relative)
                if !fileManager.fileExists(atPath: destination.path) {
                    try bytes.write(to: destination, options: .atomic)
                    created.append(destination)
                } else {
                    let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath(relative) }
                }
            }
            try commit(candidate)
        } catch {
            for url in created { try? fileManager.removeItem(at: url) }
            throw error
        }
        return ImportResult(item: item, isDuplicate: duplicate != nil)
    }

    public func updateUserMetadata(id: String, tags: [String], favorite: Bool, note: String) throws {
        guard let offset = records.firstIndex(where: { $0.id == id }) else { throw LibraryError.itemNotFound }
        var candidate = records
        var seen = Set<String>()
        candidate[offset].tags = tags.compactMap(\.nonEmpty).filter { seen.insert($0).inserted }
        candidate[offset].favorite = favorite
        candidate[offset].note = note
        try commit(candidate)
    }

    /// Update only the user's text fields using current actor state; concurrent favorite changes survive.
    public func updateTagsAndNote(id: String, tags: [String], note: String) throws {
        guard let offset = records.firstIndex(where: { $0.id == id }) else { throw LibraryError.itemNotFound }
        var candidate = records
        var seen = Set<String>()
        candidate[offset].tags = tags.compactMap(\.nonEmpty).filter { seen.insert($0).inserted }
        candidate[offset].note = note
        try commit(candidate)
    }

    /// Toggle inside the actor instead of writing a potentially stale UI snapshot.
    public func toggleFavorite(id: String) throws {
        guard let offset = records.firstIndex(where: { $0.id == id }) else { throw LibraryError.itemNotFound }
        var candidate = records
        candidate[offset].favorite.toggle()
        try commit(candidate)
    }

    public func updateSource(id: String, source: MakerWorldSource) throws {
        guard let offset = records.firstIndex(where: { $0.id == id }) else { throw LibraryError.itemNotFound }
        var candidate = records
        candidate[offset].makerWorldSource = try source.merging(previous: records[offset].makerWorldSource)
        try commit(candidate)
    }

    /// Studio's stable run ID allows prepared/submitted updates without creating duplicate history.
    public func appendRun(itemID: String, run: PrintRun) throws {
        guard let offset = records.firstIndex(where: { $0.id == itemID }) else { throw LibraryError.itemNotFound }
        var candidate = records
        if let existing = candidate[offset].printRuns.firstIndex(where: { $0.id == run.id }) {
            candidate[offset].printRuns[existing] = run
        } else { candidate[offset].printRuns.append(run) }
        try commit(candidate)
    }

    private func commit(_ candidate: [LibraryItem]) throws {
        // Preserve edits or corruption introduced after this repository opened.
        let existing: Data?
        if fileManager.fileExists(atPath: indexURL.path) {
            let values = try indexURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? Int.max) <= 64 * 1_024 * 1_024 else { throw LibraryError.libraryChanged }
            existing = try Data(contentsOf: indexURL)
        } else { existing = nil }
        guard existing == lastIndexData else { throw LibraryError.libraryChanged }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Index(items: candidate))
        try data.write(to: indexURL, options: .atomic)
        records = candidate; lastIndexData = data
    }

    static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var total: UInt64 = 0
        while let bytes = try handle.read(upToCount: 1_024 * 1_024), !bytes.isEmpty {
            total += UInt64(bytes.count)
            guard total <= ArchiveLimits.archiveBytes else { throw LibraryError.limitExceeded("원본 파일 크기") }
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }

    private static func valid(_ items: [LibraryItem]) -> Bool {
        var seen = Set<String>()
        return items.allSatisfy { item in
            guard item.id.count == 64, item.id.allSatisfy({ $0.isASCII && ("0"..."9").contains($0) || ("a"..."f").contains($0) }),
                  seen.insert(item.id).inserted, item.filePath == "Files/\(item.id).3mf" else { return false }
            if let source = item.makerWorldSource, (try? source.validated()) != source { return false }
            return ([item.thumbnailPath] + item.plates.map(\.thumbnailPath)).compactMap { $0 }.allSatisfy { path in
                path.hasPrefix("Previews/") && !path.dropFirst("Previews/".count).contains("/") &&
                !path.contains("\\") && !path.contains("..") && !path.contains("\0")
            }
        }
    }
}
