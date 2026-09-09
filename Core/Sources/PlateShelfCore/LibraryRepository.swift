import Foundation
import CryptoKit

public actor LibraryRepository {
    public nonisolated let rootURL: URL
    private var records: [LibraryItem]
    private var categoryRecords: [LibraryCategory]
    private var queueRecords: [PrintQueueEntry]
    private var lastIndexData: Data?
    private let fileManager = FileManager.default
    private var indexURL: URL { rootURL.appendingPathComponent("index.json") }

    private struct Index: Codable {
        var schemaVersion: Int = 1
        var items: [LibraryItem]
        var categories: [LibraryCategory]?
        var printQueue: [PrintQueueEntry]?
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
                  Self.valid(index.items), Self.validCategories(index.categories ?? [], items: index.items),
                  Self.validQueue(index.printQueue ?? [], items: index.items) else { throw LibraryError.corruptIndex }
            self.records = index.items; self.categoryRecords = index.categories ?? []; self.queueRecords = index.printQueue ?? []; self.lastIndexData = data
        } else { self.records = []; self.categoryRecords = []; self.queueRecords = []; self.lastIndexData = nil }
        try FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        for directory in ["Files", "Previews", ".staging"] {
            let url = self.rootURL.appendingPathComponent(directory, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath(directory) }
            } else { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        }
        for directory in ["Files/Printed", "Files/Trash"] {
            let url = self.rootURL.appendingPathComponent(directory)
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath(directory) }
            }
        }
        try Self.recoverArchiveMove(root: self.rootURL, records: self.records)
        try Self.recoverPrintMove(root: self.rootURL, records: self.records)
    }

    public func items(includeTrashed: Bool = false) -> [LibraryItem] {
        records.filter { includeTrashed || !$0.isTrashed }.sorted { lhs, rhs in lhs.importedAt == rhs.importedAt ? lhs.id < rhs.id : lhs.importedAt > rhs.importedAt }
    }

    public func recoverFilaments() throws {
        var candidate = records; var changed = false
        for i in candidate.indices where candidate[i].filaments == nil {
            guard let parsed = try? ThreeMFReader(url: rootURL.appendingPathComponent(candidate[i].filePath)).parse() else { continue }
            candidate[i].filaments = parsed.filaments
            for p in candidate[i].plates.indices {
                candidate[i].plates[p].filaments = parsed.plates.first { $0.id == candidate[i].plates[p].id }?.filaments
            }
            changed = true
        }
        if changed { try commit(candidate) }
    }

    public func recoverSavedGCodeTimes() throws {
        var candidate = records
        var changed = false
        for index in candidate.indices where candidate[index].hasGCode && candidate[index].plates.contains(where: { $0.estimatedSeconds == nil }) {
            guard let parsed = try? ThreeMFReader(url: rootURL.appendingPathComponent(candidate[index].filePath)).parse() else { continue }
            for p in candidate[index].plates.indices where candidate[index].plates[p].estimatedSeconds == nil {
                if let value = parsed.plates.first(where: { $0.id == candidate[index].plates[p].id })?.estimatedSeconds {
                    candidate[index].plates[p].estimatedSeconds = value; changed = true
                }
            }
        }
        if changed { try commit(candidate) }
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

    public func importFile(at source: URL, expectedSHA256: String? = nil, restoreTrashed: Bool = true) throws -> ImportResult {
        let expectedHash = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let expectedHash {
            guard expectedHash.utf8.count == 64,
                  expectedHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw LibraryError.invalidArchive(CL("SHA256 확인값이 올바르지 않습니다"))
            }
        }
        var source = source.standardizedFileURL
        guard source.isFileURL, source.pathExtension.lowercased() == "3mf" else { throw LibraryError.unsupportedFile }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        let before = try source.resourceValues(forKeys: keys)
        guard before.isRegularFile == true, before.isSymbolicLink != true else { throw LibraryError.unsupportedFile }
        guard UInt64(before.fileSize ?? 0) <= ArchiveLimits.archiveBytes else { throw LibraryError.limitExceeded(CL("원본 파일 크기")) }
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
            throw LibraryError.invalidArchive(CL("파일 확인값이 기록과 일치하지 않습니다"))
        }
        if let deleted = records.first(where: { $0.id == id && $0.isTrashed }) {
            // Background scans must never resurrect a deliberately removed model.
            guard restoreTrashed else { return ImportResult(item: deleted, isDuplicate: true) }
            try restore(itemID: id)
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
                               fileAddedAt: before.creationDate, filaments: parsed.filaments)
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
                      try Self.hashFile(finalArchive) == id else { throw LibraryError.invalidArchive(CL("보관한 원본의 무결성 검사 실패")) }
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
    private static func validatePrintDetails(_ seconds: Double?, _ filaments: [FilamentRecord]?) throws {
        guard seconds == nil || (seconds!.isFinite && seconds! > 0),
              (filaments ?? []).allSatisfy({ f in
                  [f.grams, f.meters].allSatisfy { $0 == nil || ($0!.isFinite && $0! >= 0) }
              }) else { throw LibraryError.invalidSettings }
    }
    public func appendRun(itemID: String, run: PrintRun) throws {
        try Self.validatePrintDetails(run.durationSeconds, run.filaments)
        guard let offset = records.firstIndex(where: { $0.id == itemID }) else { throw LibraryError.itemNotFound }
        var candidate = records
        if let existing = candidate[offset].printRuns.firstIndex(where: { $0.id == run.id }) {
            candidate[offset].printRuns[existing] = run
        } else { candidate[offset].printRuns.append(run) }
        let newlyCompleted = run.status == "completed" && !records[offset].printRuns.contains { $0.id == run.id && $0.status == "completed" }
        try commit(candidate, queue: newlyCompleted ? queueRecords.filter { $0.id != itemID } : queueRecords)
    }

    public func printQueue() -> [PrintQueueEntry] { queueRecords }

    @discardableResult public func enqueue(itemIDs: [String]) throws -> Int {
        let validIDs = Set(records.filter { !$0.isTrashed }.map(\.id))
        guard itemIDs.allSatisfy(validIDs.contains) else { throw LibraryError.itemNotFound }
        var queue = queueRecords, seen = Set(queue.map(\.id)), added = 0
        for id in itemIDs where seen.insert(id).inserted { queue.append(PrintQueueEntry(id: id)); added += 1 }
        if added > 0 { try commit(records, queue: queue) }
        return added
    }
    public func reorderQueue(itemIDs: [String]) throws {
        guard itemIDs.count == queueRecords.count, Set(itemIDs) == Set(queueRecords.map(\.id)) else { throw LibraryError.invalidSettings }
        let entries = Dictionary(uniqueKeysWithValues: queueRecords.map { ($0.id, $0) })
        try commit(records, queue: itemIDs.compactMap { entries[$0] })
    }
    public func removeFromQueue(itemIDs: Set<String>) throws {
        try commit(records, queue: queueRecords.filter { !itemIDs.contains($0.id) })
    }
    public func setQueueDuration(itemID: String, seconds: Double?) throws {
        guard seconds == nil || PrintQueuePlan.duration(seconds) != nil else { throw LibraryError.invalidSettings }
        guard let offset = queueRecords.firstIndex(where: { $0.id == itemID }) else { throw LibraryError.itemNotFound }
        var queue = queueRecords; queue[offset].durationSeconds = seconds
        try commit(records, queue: queue)
    }
    private static func validQueue(_ queue: [PrintQueueEntry], items: [LibraryItem]) -> Bool {
        let ids = Set(items.filter { !$0.isTrashed }.map(\.id))
        return queue.count <= 10_000 && Set(queue.map(\.id)).count == queue.count && queue.allSatisfy {
            ids.contains($0.id) && ($0.durationSeconds == nil || PrintQueuePlan.duration($0.durationSeconds) != nil)
        }
    }

    public func categories() -> [LibraryCategory] {
        categoryRecords.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult public func saveCategory(id: String? = nil, name: String, assigningTo itemID: String? = nil) throws -> LibraryCategory {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !name.contains("\n"), !name.contains("\0") else {
            throw LibraryError.fileMove(CL("분류 이름은 1~80자로 입력해 주세요."))
        }
        guard !categoryRecords.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            throw LibraryError.fileMove(CL("같은 이름의 분류가 이미 있습니다."))
        }
        var categories = categoryRecords
        let category: LibraryCategory
        if let id {
            guard let index = categories.firstIndex(where: { $0.id == id }) else { throw LibraryError.itemNotFound }
            categories[index].name = name; category = categories[index]
        } else {
            category = LibraryCategory(name: name); categories.append(category)
        }
        var candidate = records
        if let itemID {
            guard let index = candidate.firstIndex(where: { $0.id == itemID && !$0.isTrashed }) else { throw LibraryError.itemNotFound }
            candidate[index].categoryID = category.id
        }
        try commit(candidate, categories: categories)
        return category
    }

    public func assignCategory(itemID: String, categoryID: String?) throws {
        guard let offset = records.firstIndex(where: { $0.id == itemID && !$0.isTrashed }),
              categoryID == nil || categoryRecords.contains(where: { $0.id == categoryID }) else { throw LibraryError.itemNotFound }
        var candidate = records; candidate[offset].categoryID = categoryID
        try commit(candidate)
    }

    public func deleteCategory(id: String) throws {
        guard categoryRecords.contains(where: { $0.id == id }) else { throw LibraryError.itemNotFound }
        var candidate = records
        for index in candidate.indices where candidate[index].categoryID == id { candidate[index].categoryID = nil }
        try commit(candidate, categories: categoryRecords.filter { $0.id != id })
    }

    /// Recoverable app trash: only our immutable archive moves. External sources stay untouched.
    public func trash(itemID: String) throws {
        try Self.recoverPrintMove(root: rootURL, records: records)
        try Self.recoverArchiveMove(root: rootURL, records: records)
        guard let index = records.firstIndex(where: { $0.id == itemID }) else { throw LibraryError.itemNotFound }
        guard !records[index].isTrashed else { return }
        var candidate = records
        candidate[index].trashedFromPath = records[index].filePath
        candidate[index].filePath = "Files/Trash/\(itemID).3mf"
        candidate[index].deletedAt = Date()
        try moveArchive(index: index, candidate: candidate)
    }

    public func restore(itemID: String) throws {
        try Self.recoverArchiveMove(root: rootURL, records: records)
        guard let index = records.firstIndex(where: { $0.id == itemID }) else { throw LibraryError.itemNotFound }
        guard records[index].isTrashed, let previous = records[index].trashedFromPath else { return }
        var candidate = records
        candidate[index].filePath = previous
        candidate[index].deletedAt = nil; candidate[index].trashedFromPath = nil
        try moveArchive(index: index, candidate: candidate)
    }

    private struct ArchiveMoveJournal: Codable {
        let itemID: String
        let from: String
        let to: String
    }
    private func moveArchive(index: Int, candidate: [LibraryItem]) throws {
        let before = records[index], after = candidate[index]
        let from = rootURL.appendingPathComponent(before.filePath), to = rootURL.appendingPathComponent(after.filePath)
        try Self.verifyMoveFile(from, id: before.id)
        try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        let values = try to.deletingLastPathComponent().resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath(after.filePath) }
        guard !fileManager.fileExists(atPath: to.path) else { throw LibraryError.fileMove(CL("이동 위치에 파일이 이미 있습니다. 기존 파일을 보존했습니다.")) }
        let journal = ArchiveMoveJournal(itemID: before.id, from: before.filePath, to: after.filePath)
        let journalURL = rootURL.appendingPathComponent(".archive-move.json")
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        do {
            try fileManager.moveItem(at: from, to: to)
            try commit(candidate)
        } catch {
            try Self.recoverArchiveMove(root: rootURL, records: records)
            throw error
        }
        try? fileManager.removeItem(at: journalURL)
    }
    private static func recoverArchiveMove(root: URL, records: [LibraryItem]) throws {
        let manager = FileManager.default, journalURL = root.appendingPathComponent(".archive-move.json")
        guard manager.fileExists(atPath: journalURL.path) else { return }
        let values = try journalURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 65_536,
              let journal = try? JSONDecoder().decode(ArchiveMoveJournal.self, from: Data(contentsOf: journalURL)),
              let item = records.first(where: { $0.id == journal.itemID }) else { throw LibraryError.corruptIndex }
        let active = ["Files/\(item.id).3mf", "Files/Printed/\(item.id).3mf"], trash = "Files/Trash/\(item.id).3mf"
        guard (active.contains(journal.from) && journal.to == trash) || (journal.from == trash && active.contains(journal.to)),
              item.filePath == journal.from || item.filePath == journal.to else { throw LibraryError.corruptIndex }
        for path in [journal.from, journal.to] {
            let directory = root.appendingPathComponent(path).deletingLastPathComponent()
            let v = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard v.isDirectory == true, v.isSymbolicLink != true else { throw LibraryError.unsafePath(path) }
        }
        if item.filePath == journal.from {
            let from = root.appendingPathComponent(journal.from), to = root.appendingPathComponent(journal.to)
            if !manager.fileExists(atPath: from.path) {
                try verifyMoveFile(to, id: item.id)
                try manager.moveItem(at: to, to: from)
            }
        }
        try manager.removeItem(at: journalURL)
    }
    private static func validCategories(_ categories: [LibraryCategory], items: [LibraryItem]) -> Bool {
        let ids = Set(categories.map(\.id))
        return ids.count == categories.count && categories.allSatisfy {
            UUID(uuidString: $0.id) != nil && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80
        } && items.allSatisfy { $0.categoryID == nil || ids.contains($0.categoryID!) }
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
    public func completePrint(itemID: String, note: String, sourceURL: URL? = nil, directoryURL: URL? = nil, durationSeconds: Double? = nil, durationSource: String? = nil, filaments: [FilamentRecord]? = nil) throws -> PrintRun {
        try Self.validatePrintDetails(durationSeconds, filaments)
        try Self.recoverPrintMove(root: rootURL, records: records)
        guard let offset = records.firstIndex(where: { $0.id == itemID && !$0.isTrashed }) else { throw LibraryError.itemNotFound }
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
                  let directoryURL, directoryURL.isFileURL else { throw LibraryError.fileMove(CL("이 모델의 원본 파일과 이동 폴더를 선택해 주세요.")) }
            try Self.verifyMoveFile(source, id: itemID)
            let directory = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
            guard directory != rootURL, !directory.path.hasPrefix(rootURL.path + "/") else {
                throw LibraryError.fileMove(CL("원본 파일의 이동 위치는 앱 보관함 밖의 폴더를 선택해 주세요."))
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.fileMove(CL("이동할 폴더를 사용할 수 없습니다.")) }
            var destination = directory.appendingPathComponent(source.lastPathComponent)
            if source != destination {
                var suffix = 2
                while fileManager.fileExists(atPath: destination.path) {
                    guard suffix <= 10_000 else { throw LibraryError.fileMove(CL("같은 이름의 파일이 너무 많습니다. 다른 폴더를 선택해 주세요.")) }
                    destination = directory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) (\(suffix)).3mf")
                    suffix += 1
                }
                let move = PrintMove(from: source.path, to: destination.path)
                externalMove = move; moves.append(move)
            }
        }
        for move in moves {
            guard !fileManager.fileExists(atPath: move.to) else { throw LibraryError.fileMove(CL("이동 위치에 파일이 이미 있습니다. 기존 파일은 보존했습니다.")) }
        }
        let run = PrintRun(status: "completed", source: "manual", note: note,
                           movedFrom: externalMove?.from ?? (archived == completed ? nil : archived.path),
                           movedTo: externalMove?.to ?? sourceURL?.path ?? completed.path,
                           durationSeconds: durationSeconds, durationSource: durationSource, filaments: filaments)
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
            try commit(candidate, queue: queueRecords.filter { $0.id != itemID })
        } catch {
            do { try Self.recoverPrintMove(root: rootURL, records: records) }
            catch { throw LibraryError.fileMove(String(format: CL("파일 이동 복구를 완료하지 못했습니다. 파일을 삭제하지 말고 앱을 다시 열어 주세요. %@"), String(error.localizedDescription))) }
            throw error
        }
        // A leftover committed journal is harmless and is cleared on the next open.
        try? fileManager.removeItem(at: journalURL)
        return run
    }

    private static func verifyMoveFile(_ url: URL, id: String) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, try hashFile(url) == id else {
            throw LibraryError.fileMove(CL("파일이 보관 당시와 달라 이동하지 않았습니다. 변경한 파일을 먼저 다시 가져와 주세요."))
        }
    }
    private static func recoverPrintMove(root: URL, records: [LibraryItem]) throws {
        let manager = FileManager.default, journalURL = root.appendingPathComponent(".print-move.json")
        guard manager.fileExists(atPath: journalURL.path) else { return }
        let values = try journalURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 65_536,
              let journal = try? JSONDecoder().decode(PrintMoveJournal.self, from: Data(contentsOf: journalURL)),
              let item = records.first(where: { $0.id == journal.itemID }), journal.moves.count <= 2,
              UUID(uuidString: journal.runID) != nil else { throw LibraryError.fileMove(CL("출력 완료 파일의 이동 기록을 확인할 수 없습니다.")) }
        if item.printRuns.contains(where: { $0.id == journal.runID && $0.status == "completed" }) {
            try manager.removeItem(at: journalURL); return
        }
        for move in journal.moves {
            let archiveFrom = root.appendingPathComponent("Files/\(item.id).3mf").path
            let archiveTo = root.appendingPathComponent("Files/Printed/\(item.id).3mf").path
            let archiveMove = move.from == archiveFrom && move.to == archiveTo && item.filePath == "Files/\(item.id).3mf"
            let externalMove = item.sourcePaths.contains(move.from) && !move.from.hasPrefix(root.path + "/") &&
                move.to.hasPrefix("/") && !move.to.hasPrefix(root.path + "/") && URL(fileURLWithPath: move.to).pathExtension.lowercased() == "3mf"
            guard archiveMove || externalMove else { throw LibraryError.fileMove(CL("파일 이동 기록의 경로를 확인할 수 없습니다.")) }
        }
        for move in journal.moves.reversed() {
            let from = URL(fileURLWithPath: move.from), to = URL(fileURLWithPath: move.to)
            // A failed rename (including a destination collision) leaves the source in place.
            // Preserve both files if another process created one; never overwrite a source while recovering.
            if manager.fileExists(atPath: from.path) { continue }
            guard manager.fileExists(atPath: to.path) else { throw LibraryError.fileMove(String(format: CL("이동 중인 파일을 찾을 수 없습니다: %@"), String(from.lastPathComponent))) }
            try verifyMoveFile(to, id: item.id)
            try manager.moveItem(at: to, to: from)
        }
        try manager.removeItem(at: journalURL)
    }

    private func commit(_ candidate: [LibraryItem], categories: [LibraryCategory]? = nil, queue: [PrintQueueEntry]? = nil) throws {
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
        let activeIDs = Set(candidate.filter { !$0.isTrashed }.map(\.id))
        let pending = (queue ?? queueRecords).filter { activeIDs.contains($0.id) }
        guard Self.validQueue(pending, items: candidate) else { throw LibraryError.invalidSettings }
        let data = try encoder.encode(Index(items: candidate, categories: categories ?? categoryRecords, printQueue: pending))
        try data.write(to: indexURL, options: .atomic)
        records = candidate; categoryRecords = categories ?? categoryRecords; queueRecords = pending; lastIndexData = data
    }

    static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var total: UInt64 = 0
        while let bytes = try handle.read(upToCount: 1_024 * 1_024), !bytes.isEmpty {
            total += UInt64(bytes.count)
            guard total <= ArchiveLimits.archiveBytes else { throw LibraryError.limitExceeded(CL("원본 파일 크기")) }
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
                  ["Files/\(item.id).3mf", "Files/Printed/\(item.id).3mf", "Files/Trash/\(item.id).3mf"].contains(item.filePath),
                  item.isTrashed == (item.filePath == "Files/Trash/\(item.id).3mf") else { return false }
            if item.isTrashed {
                guard let previous = item.trashedFromPath,
                      ["Files/\(item.id).3mf", "Files/Printed/\(item.id).3mf"].contains(previous) else { return false }
            } else if item.trashedFromPath != nil { return false }
            if let source = item.makerWorldSource, (try? source.validated()) != source { return false }
            return ([item.thumbnailPath] + item.plates.map(\.thumbnailPath)).compactMap { $0 }.allSatisfy { path in
                path.hasPrefix("Previews/") && !path.dropFirst("Previews/".count).contains("/") &&
                !path.contains("\\") && !path.contains("..") && !path.contains("\0")
            }
        }
    }
}
