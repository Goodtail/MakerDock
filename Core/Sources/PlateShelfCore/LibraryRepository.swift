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
        let printed = self.rootURL.appendingPathComponent("Files/Printed")
        if FileManager.default.fileExists(atPath: printed.path) {
            let values = try printed.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath("Files/Printed") }
        }
        try Self.recoverPrintMove(root: self.rootURL, records: self.records)
    }

    public func items() -> [LibraryItem] {
        records.sorted { lhs, rhs in lhs.importedAt == rhs.importedAt ? lhs.id < rhs.id : lhs.importedAt > rhs.importedAt }
    }

    /// Recover the original chronology for libraries created before source dates were recorded.
    public func backfillFileAddedDates() throws {
        var candidate = records
        var changed = false
        for index in candidate.indices where candidate[index].fileAddedAt == nil {
            let dates = candidate[index].sourcePaths.compactMap { path -> Date? in
                guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
                return values.creationDate
            }
            if let date = dates.max() { candidate[index].fileAddedAt = date; changed = true }
        }
        if changed { try commit(candidate) }
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
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
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
        let archiveRelative = records.first(where: { $0.id == id })?.filePath ?? "Files/\(id).3mf"
        let finalArchive = rootURL.appendingPathComponent(archiveRelative)
        var candidate = records
        let duplicate = candidate.firstIndex { $0.id == id }
        var item: LibraryItem
        var previews: [String: Data] = [:]
        if let duplicate {
            item = candidate[duplicate]
            if !item.sourcePaths.contains(source.path) { item.sourcePaths.append(source.path) }
            if let date = before.creationDate, item.fileAddedAt == nil || date > item.fileAddedAt! { item.fileAddedAt = date }
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
                               printerModel: parsed.printerModel, plates: parsed.plates, hasGCode: parsed.hasGCode,
                               fileAddedAt: before.creationDate)
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

    private struct PrintMove: Codable {
        let from: String
        let to: String
    }
    private struct PrintMoveJournal: Codable {
        let itemID: String
        let runID: String
        let moves: [PrintMove]
    }

    /// Move the archived original and, when selected, one external source; preserve all other copies.
    /// The journal rolls incomplete moves back after interruption, before the library is used again.
    public func completePrint(itemID: String, note: String, sourceURL: URL? = nil, directoryURL: URL? = nil) throws -> PrintRun {
        try Self.recoverPrintMove(root: rootURL, records: records)
        guard let offset = records.firstIndex(where: { $0.id == itemID }) else { throw LibraryError.itemNotFound }
        let item = records[offset]
        let archived = rootURL.appendingPathComponent(item.filePath)
        let completedRelative = "Files/Printed/\(item.id).3mf"
        let completed = rootURL.appendingPathComponent(completedRelative)
        try Self.verifyMoveFile(archived, id: itemID)
        let printedDirectory = completed.deletingLastPathComponent()
        try fileManager.createDirectory(at: printedDirectory, withIntermediateDirectories: true)
        let printedValues = try printedDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard printedValues.isDirectory == true, printedValues.isSymbolicLink != true else { throw LibraryError.unsafePath("Files/Printed") }
        var moves: [PrintMove] = []
        if archived != completed { moves.append(PrintMove(from: archived.path, to: completed.path)) }
        var externalMove: PrintMove?
        if let sourceURL {
            let source = sourceURL.standardizedFileURL
            guard source.isFileURL, !source.path.hasPrefix(rootURL.path + "/"), item.sourcePaths.contains(source.path),
                  let directoryURL, directoryURL.isFileURL else { throw LibraryError.fileMove("이 모델의 원본 파일과 이동 폴더를 선택해 주세요.") }
            try Self.verifyMoveFile(source, id: itemID)
            let directory = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
            guard directory != rootURL, !directory.path.hasPrefix(rootURL.path + "/") else {
                throw LibraryError.fileMove("원본 파일의 이동 위치는 앱 보관함 밖의 폴더를 선택해 주세요.")
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.fileMove("이동할 폴더를 사용할 수 없습니다.") }
            var destination = directory.appendingPathComponent(source.lastPathComponent)
            if source != destination {
                var suffix = 2
                while fileManager.fileExists(atPath: destination.path) {
                    guard suffix <= 10_000 else { throw LibraryError.fileMove("같은 이름의 파일이 너무 많습니다. 다른 폴더를 선택해 주세요.") }
                    destination = directory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) (\(suffix)).3mf")
                    suffix += 1
                }
                let move = PrintMove(from: source.path, to: destination.path)
                externalMove = move; moves.append(move)
            }
        }
        for move in moves {
            guard !fileManager.fileExists(atPath: move.to) else { throw LibraryError.fileMove("이동 위치에 파일이 이미 있습니다. 기존 파일은 보존했습니다.") }
        }
        let run = PrintRun(status: "completed", source: "manual", note: note,
                           movedFrom: externalMove?.from ?? (archived == completed ? nil : archived.path),
                           movedTo: externalMove?.to ?? sourceURL?.path ?? completed.path)
        var candidate = records
        candidate[offset].filePath = completedRelative
        if let move = externalMove {
            candidate[offset].sourcePaths = item.sourcePaths.map { $0 == move.from ? move.to : $0 }
        }
        candidate[offset].printRuns.append(run)
        let journal = PrintMoveJournal(itemID: itemID, runID: run.id, moves: moves)
        let journalURL = rootURL.appendingPathComponent(".print-move.json")
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        do {
            for move in moves {
                let from = URL(fileURLWithPath: move.from), to = URL(fileURLWithPath: move.to)
                try Self.verifyMoveFile(from, id: itemID)
                try fileManager.moveItem(at: from, to: to)
                try Self.verifyMoveFile(to, id: itemID)
            }
            try commit(candidate)
        } catch {
            do { try Self.recoverPrintMove(root: rootURL, records: records) }
            catch { throw LibraryError.fileMove("파일 이동 복구를 완료하지 못했습니다. 파일을 삭제하지 말고 앱을 다시 열어 주세요. \(error.localizedDescription)") }
            throw error
        }
        // A leftover committed journal is harmless and is cleared on the next open.
        try? fileManager.removeItem(at: journalURL)
        return run
    }

    private static func verifyMoveFile(_ url: URL, id: String) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, try hashFile(url) == id else {
            throw LibraryError.fileMove("파일이 보관 당시와 달라 이동하지 않았습니다. 변경한 파일을 먼저 다시 가져와 주세요.")
        }
    }
    private static func recoverPrintMove(root: URL, records: [LibraryItem]) throws {
        let manager = FileManager.default, journalURL = root.appendingPathComponent(".print-move.json")
        guard manager.fileExists(atPath: journalURL.path) else { return }
        let values = try journalURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 65_536,
              let journal = try? JSONDecoder().decode(PrintMoveJournal.self, from: Data(contentsOf: journalURL)),
              let item = records.first(where: { $0.id == journal.itemID }), journal.moves.count <= 2,
              UUID(uuidString: journal.runID) != nil else { throw LibraryError.fileMove("출력 완료 파일의 이동 기록을 확인할 수 없습니다.") }
        if item.printRuns.contains(where: { $0.id == journal.runID && $0.status == "completed" }) {
            try manager.removeItem(at: journalURL); return
        }
        for move in journal.moves {
            let archiveFrom = root.appendingPathComponent("Files/\(item.id).3mf").path
            let archiveTo = root.appendingPathComponent("Files/Printed/\(item.id).3mf").path
            let archiveMove = move.from == archiveFrom && move.to == archiveTo && item.filePath == "Files/\(item.id).3mf"
            let externalMove = item.sourcePaths.contains(move.from) && !move.from.hasPrefix(root.path + "/") &&
                move.to.hasPrefix("/") && !move.to.hasPrefix(root.path + "/") && URL(fileURLWithPath: move.to).pathExtension.lowercased() == "3mf"
            guard archiveMove || externalMove else { throw LibraryError.fileMove("파일 이동 기록의 경로를 확인할 수 없습니다.") }
        }
        for move in journal.moves.reversed() {
            let from = URL(fileURLWithPath: move.from), to = URL(fileURLWithPath: move.to)
            // A failed rename (including a destination collision) leaves the source in place.
            // Preserve both files if another process created one; never overwrite a source while recovering.
            if manager.fileExists(atPath: from.path) { continue }
            guard manager.fileExists(atPath: to.path) else { throw LibraryError.fileMove("이동 중인 파일을 찾을 수 없습니다: \(from.lastPathComponent)") }
            try verifyMoveFile(to, id: item.id)
            try manager.moveItem(at: to, to: from)
        }
        try manager.removeItem(at: journalURL)
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
                  seen.insert(item.id).inserted,
                  ["Files/\(item.id).3mf", "Files/Printed/\(item.id).3mf"].contains(item.filePath) else { return false }
            if let source = item.makerWorldSource, (try? source.validated()) != source { return false }
            return ([item.thumbnailPath] + item.plates.map(\.thumbnailPath)).compactMap { $0 }.allSatisfy { path in
                path.hasPrefix("Previews/") && !path.dropFirst("Previews/".count).contains("/") &&
                !path.contains("\\") && !path.contains("..") && !path.contains("\0")
            }
        }
    }
}
