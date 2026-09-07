import AppKit
import Combine
import CryptoKit
import PlateShelfCore
import SwiftUI
import UniformTypeIdentifiers

typealias ShelfItem = PlateShelfCore.LibraryItem

struct ShelfPreferences: Codable {
    var folders: [String] = []
    var studioPath = "/Applications/BambuStudio.app"
    var archivePath = ""
    var automaticScan = true
    var folderBookmarks: [String: Data] = [:]
    var completedMoveMode = "source"
    var completedFolder = ""
    enum CodingKeys: String, CodingKey { case folders, studioPath, archivePath, automaticScan, folderBookmarks, completedMoveMode, completedFolder }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = try c.decodeIfPresent([String].self, forKey: .folders) ?? []
        studioPath = try c.decodeIfPresent(String.self, forKey: .studioPath) ?? "/Applications/BambuStudio.app"
        archivePath = try c.decodeIfPresent(String.self, forKey: .archivePath) ?? ""
        automaticScan = try c.decodeIfPresent(Bool.self, forKey: .automaticScan) ?? true
        folderBookmarks = try c.decodeIfPresent([String: Data].self, forKey: .folderBookmarks) ?? [:]
        completedMoveMode = try c.decodeIfPresent(String.self, forKey: .completedMoveMode) ?? "source"
        completedFolder = try c.decodeIfPresent(String.self, forKey: .completedFolder) ?? ""
    }
}
enum ShelfFilter: Hashable {
    case makerWorld, all, favorites, printed, unprinted, duplicates, tag(String)
    var title: String {
        switch self {
        case .makerWorld: return "MakerWorld"
        case .all: return L("library.title")
        case .favorites: return L("filter.favorites")
        case .printed: return L("filter.printed")
        case .unprinted: return L("filter.unprinted")
        case .duplicates: return L("filter.duplicates")
        case .tag(let tag): return tag
        }
    }
}
enum ShelfSort: CaseIterable {
    case recent, oldest, name
    var title: String {
        switch self {
        case .recent: return L("sort.recent")
        case .oldest: return L("sort.oldest")
        case .name: return L("sort.name")
        }
    }
    func precedes(_ lhs: ShelfItem, _ rhs: ShelfItem) -> Bool {
        let left = lhs.fileAddedAt ?? lhs.importedAt, right = rhs.fileAddedAt ?? rhs.importedAt
        switch self {
        case .recent: return left == right ? lhs.id > rhs.id : left > right
        case .oldest: return left == right ? lhs.id < rhs.id : left < right
        case .name:
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }
}
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var items: [ShelfItem] = []
    @Published var selectionID: String?
    @Published var filter: ShelfFilter = .all
    @Published var search = ""
    @Published var isBusy = false
    @Published var isScanning = false
    var isWorking: Bool { isBusy || isScanning }
    private var grantedURLs: [URL] = []
    @Published var errorMessage: String?
    @Published var statusMessage = ""
    @Published var preferences = ShelfPreferences()
    @Published var showSettings = false
    @Published var listMode = false
    @Published var sort: ShelfSort = .recent
    @Published var archiveStatus = ""
    @Published var browserRequest: BrowserLocation?
    @Published var browserReloadRequest = 0
    let rootURL: URL
    var repository: LibraryRepository?
    private var linkService: MakerWorldLinkService
    private var started = false
    private var watchTimer: Timer?
    private var fileSignatures: [String: String] = [:]
    var archiveSignatures: [String: String] = [:]
    var isReadingInbox = false
    private var workWaiters: [CheckedContinuation<Void, Never>] = []

    init(rootOverride: URL? = nil, linkServiceOverride: MakerWorldLinkService? = nil) {
        let args = ProcessInfo.processInfo.arguments
        if let rootOverride {
            rootURL = rootOverride
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("PlateShelf-TestHost-\(ProcessInfo.processInfo.processIdentifier)")
        } else if let index = args.firstIndex(of: "--library-root"), args.indices.contains(index + 1) {
            rootURL = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        } else {
            rootURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ninepiece.app.mac.plateshelf.dev")
        }
        linkService = linkServiceOverride ?? MakerWorldLinkService(cacheDirectory: rootURL.appendingPathComponent("Downloads"))
        do {
            repository = try LibraryRepository(rootURL: rootURL)
            let prefs = rootURL.appendingPathComponent("preferences.json")
            if FileManager.default.fileExists(atPath: prefs.path) { preferences = try JSONDecoder().decode(ShelfPreferences.self, from: Data(contentsOf: prefs)) }
            else if rootOverride == nil {
                let isDevelopment = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
                let studioName = isDevelopment ? "PlateShelfStudio-dev.app" : "PlateShelfStudio.app"
                let studioIdentifier = "com.ninepiece.app.mac.plateshelfstudio" + (isDevelopment ? ".dev" : "")
                let candidates = [Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(studioName), URL(fileURLWithPath: "/Applications/" + studioName)]
                if let fork = candidates.first(where: { Bundle(url: $0)?.bundleIdentifier == studioIdentifier }) { preferences.studioPath = fork.path }
            }
            if preferences.archivePath.isEmpty { preferences.archivePath = rootURL.appendingPathComponent("StudioInbox").path }
        } catch { errorMessage = error.localizedDescription }
    }
    var selected: ShelfItem? { items.first { $0.id == selectionID } }
    var allTags: [String] { Array(Set(items.flatMap(\.tags))).sorted() }
    func copyCount(_ item: ShelfItem) -> Int { item.sourcePaths.filter { !$0.hasPrefix(rootURL.path + "/") }.count }
    var duplicateCount: Int { items.reduce(0) { $0 + max(0, copyCount($1) - 1) } }
    var printedCount: Int { items.filter(isPrinted).count }
    func isPrinted(_ item: ShelfItem) -> Bool { item.printRuns.contains { $0.status == "completed" } }
    var visibleItems: [ShelfItem] {
        items.filter { item in
            let matches: Bool
            switch filter {
            case .all, .makerWorld: matches = true
            case .favorites: matches = item.favorite
            case .printed: matches = isPrinted(item)
            case .unprinted: matches = !isPrinted(item)
            case .duplicates: matches = copyCount(item) > 1
            case .tag(let tag): matches = item.tags.contains(tag)
            }
            let text = [item.title, item.filename, item.designer ?? "", item.profileTitle ?? "", item.note, item.tags.joined(separator: " "), item.materials.joined(separator: " ")].joined(separator: " ")
            return matches && (search.isEmpty || text.localizedStandardContains(search))
        }.sorted(by: sort.precedes)
    }
    func start() async {
        guard !started else { return }; started = true
        for data in preferences.folderBookmarks.values {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() { grantedURLs.append(url) }
        }
        await reload()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--import-folder"), args.indices.contains(i + 1) {
            let path = args[i + 1]
            if !preferences.folders.contains(path) { preferences.folders.append(path); savePreferences() }
        }
        await refresh()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.automaticScan else { return }
                await self.refresh(quiet: true)
            }
        }
    }
    func reload() async {
        guard let repository else { return }
        do { try await repository.backfillFileAddedDates() }
        catch { errorMessage = error.localizedDescription }
        items = await repository.items()
        if selectionID == nil { selectionID = visibleItems.first?.id }
    }
    func fileURL(_ item: ShelfItem) -> URL { rootURL.appendingPathComponent(item.filePath) }
    func imageURL(_ item: ShelfItem, plate: PlateRecord? = nil) -> URL? {
        (plate?.thumbnailPath ?? item.thumbnailPath).map { rootURL.appendingPathComponent($0) }
    }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "3mf") ?? .data]; panel.prompt = L("import.action")
        if panel.runModal() == .OK { Task { await importFiles(panel.urls) } }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = L("folder.watch")
        if panel.runModal() == .OK, let url = panel.url {
            if !preferences.folders.contains(url.path) { preferences.folders.append(url.path) }
            if url.startAccessingSecurityScopedResource() { grantedURLs.append(url) }
            preferences.folderBookmarks[url.path] = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            savePreferences()
            Task { await refresh() }
        }
    }
    func importFiles(_ urls: [URL], quiet: Bool = false) async {
        guard repository != nil, !urls.isEmpty else { return }
        await acquireWork(); defer { releaseWork() }
        _ = await importFilesUnlocked(urls, quiet: quiet)
    }
    private func acquireWork() async {
        if isBusy { await withCheckedContinuation { workWaiters.append($0) } }
        isBusy = true
    }
    private func releaseWork() {
        if workWaiters.isEmpty { isBusy = false }
        else { workWaiters.removeFirst().resume() }
    }
    private func importFilesUnlocked(_ urls: [URL], quiet: Bool) async -> Bool {
        guard let repository else { return false }
        var added = 0, reused = 0; var errors: [String] = []
        for url in urls {
            statusMessage = String(format: L("import.progress"), url.lastPathComponent)
            do {
                let result = try await repository.importFile(at: url)
                if result.isDuplicate { reused += 1 } else { added += 1 }
                if urls.count == 1 && !quiet && !isScanning { selectionID = result.item.id }
            } catch { errors.append(url.lastPathComponent + ": " + error.localizedDescription) }
        }
        await reload()
        if !quiet || !urls.isEmpty { statusMessage = String(format: L("import.result"), added, reused) }
        if !errors.isEmpty { errorMessage = errors.prefix(4).joined(separator: "\n") }
        return errors.isEmpty
    }
    func refresh(quiet: Bool = false) async {
        guard !isWorking else { return }
        await acquireWork()
        isScanning = true
        defer { isScanning = false; releaseWork() }
        if !quiet { statusMessage = L("folder.scanning") }
        let folders = preferences.folders + [rootURL.appendingPathComponent("WorkingCopies").path], previous = fileSignatures
        let scan = await Task.detached(priority: .utility) { () -> ([URL], [String: String]) in
            var urls: [URL] = [], signatures: [String: String] = [:]
            for path in folders {
                guard let en = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                while let url = en.nextObject() as? URL {
                    guard url.pathExtension.lowercased() == "3mf", let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]), v.isRegularFile == true, v.isSymbolicLink != true else { continue }
                    let sig = "\(v.fileSize ?? 0):\(v.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                    signatures[url.path] = sig
                    if previous[url.path] != sig { urls.append(url) }
                }
            }
            return (urls, signatures)
        }.value
        let successful = scan.0.isEmpty ? true : await importFilesUnlocked(scan.0, quiet: quiet)
        if successful { fileSignatures = scan.1 }
        await scanStudioInbox(duringRefresh: true)
        if !quiet && scan.0.isEmpty { statusMessage = L("refresh.done") }
    }
    func saveMetadata(_ item: ShelfItem, tags: String, note: String) async {
        guard let repository else { return }
        let parsed = Array(Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        do { try await repository.updateTagsAndNote(id: item.id, tags: parsed, note: note); await reload(); statusMessage = L("saved") }
        catch { errorMessage = error.localizedDescription }
    }
    func toggleFavorite(_ item: ShelfItem) {
        Task {
            do { try await repository?.toggleFavorite(id: item.id); await reload() }
            catch { errorMessage = error.localizedDescription }
        }
    }
    @discardableResult func recordPrint(_ item: ShelfItem, status: String, note: String, moveFiles: Bool = false,
                                       sourceURL: URL? = nil, directoryURL: URL? = nil) async -> Bool {
        await acquireWork(); defer { releaseWork() }
        guard let repository else { errorMessage = L("library.unavailable"); return false }
        do {
            if status == "completed", moveFiles {
                _ = try await repository.completePrint(itemID: item.id, note: note, sourceURL: sourceURL, directoryURL: directoryURL)
            } else {
                try await repository.appendRun(itemID: item.id, run: PrintRun(status: status, source: "manual", note: note))
            }
            await reload()
            statusMessage = status == "completed" && moveFiles ? "출력 완료로 표시하고 파일을 이동했습니다." : L("history.saved")
            return true
        }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func printSources(_ item: ShelfItem) -> [URL] {
        item.sourcePaths.compactMap { path in
            guard !path.hasPrefix(rootURL.path + "/") else { return nil }
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return url
        }
    }
    func printDestination(for source: URL?) -> URL {
        guard let source else { return rootURL.appendingPathComponent("Files/Printed", isDirectory: true) }
        if preferences.completedMoveMode == "custom", !preferences.completedFolder.isEmpty {
            return URL(fileURLWithPath: preferences.completedFolder, isDirectory: true)
        }
        let parent = source.deletingLastPathComponent()
        return parent.lastPathComponent == "출력 완료" ? parent : parent.appendingPathComponent("출력 완료", isDirectory: true)
    }
    @discardableResult func selectCompletedFolder() -> URL? {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.title = "출력 완료 파일을 모을 폴더"; panel.prompt = "이 폴더로 이동"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if url.startAccessingSecurityScopedResource() { grantedURLs.append(url) }
        preferences.folderBookmarks[url.path] = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        preferences.completedFolder = url.path; preferences.completedMoveMode = "custom"; savePreferences()
        return url
    }
    func workingCopy(for item: ShelfItem) throws -> URL {
        let folder = rootURL.appendingPathComponent("WorkingCopies").appendingPathComponent(item.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let working = folder.appendingPathComponent(URL(fileURLWithPath: item.filename).lastPathComponent)
        if !FileManager.default.fileExists(atPath: working.path) {
            try FileManager.default.copyItem(at: fileURL(item), to: working)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: working.path)
        }
        return working
    }
    func openInStudio(_ item: ShelfItem) {
        do {
            let studioURL = URL(fileURLWithPath: preferences.studioPath)
            guard FileManager.default.fileExists(atPath: studioURL.path) else { throw ShelfError.message(L("studio.missing")) }
            let working = try workingCopy(for: item)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.allowsRunningApplicationSubstitution = false
            let isShelfStudio = Bundle(url: studioURL)?.bundleIdentifier?.hasPrefix("com.ninepiece.app.mac.plateshelfstudio") == true
            if isShelfStudio {
                try FileManager.default.createDirectory(at: URL(fileURLWithPath: preferences.archivePath), withIntermediateDirectories: true)
                configuration.environment = ["PLATESHELF_ARCHIVE_DIR": preferences.archivePath,
                                             "PLATESHELF_CACHE_DIR": rootURL.appendingPathComponent("StudioCache").path]
                // The fork accepts file paths on its command line. A fresh process also ensures
                // the archive environment is applied without disturbing an already edited project.
                configuration.arguments = [working.path]
                configuration.createsNewApplicationInstance = true
            }
            let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { [weak self] _, error in
                Task { @MainActor in
                    if let error { self?.errorMessage = error.localizedDescription }
                    else { self?.statusMessage = L("studio.opened") }
                }
            }
            if isShelfStudio {
                NSWorkspace.shared.openApplication(at: studioURL, configuration: configuration, completionHandler: completion)
            } else {
                NSWorkspace.shared.open([working], withApplicationAt: studioURL, configuration: configuration, completionHandler: completion)
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([fileURL(item)]) }
    func openSource(_ item: ShelfItem) {
        if let source = item.makerWorldSource, let url = URL(string: source.pageURL) { showMakerWorld(url); return }
        // Internal model IDs are not public page IDs. Search avoids fabricating a page URL.
        var parts = URLComponents(string: "https://makerworld.com/en/search/models")!
        parts.queryItems = [URLQueryItem(name: "keyword", value: item.title)]
        if let url = parts.url { showMakerWorld(url) }
    }
    func showMakerWorld(_ url: URL) {
        guard MakerWorldBrowserPolicy.isMakerWorld(url) else { return }
        browserRequest = BrowserLocation(url: url)
        filter = .makerWorld
    }
    func showLibraryItem(_ id: String) { filter = .all; search = ""; selectionID = id }
    func savedProfile(_ profileURL: String?) -> ShelfItem? {
        guard let key = MakerWorldBrowserPolicy.profileKey(profileURL) else { return nil }
        return items.filter { MakerWorldBrowserPolicy.profileKey($0.makerWorldSource?.profileURL) == key }
            .sorted { ($0.makerWorldSource?.capturedAt ?? $0.importedAt) > ($1.makerWorldSource?.capturedAt ?? $1.importedAt) }.first
    }
    func receiveBrowserDownload(_ url: URL, preferStored: Bool, forceDownload: Bool = false) async throws -> BrowserImportResult {
        await acquireWork(); defer { releaseWork() }
        let parsed = try MakerWorldLinkPolicy.parse(url)
        if preferStored, !forceDownload, let stored = savedProfile(parsed.provenance?.profileURL) {
            let original = fileURL(stored)
            // Reuse only an intact archived file, never a same-name or different-profile guess.
            let actual = await Task.detached { try? MakerWorldLinkPolicy.fileSHA256(original).hash }.value
            if actual == stored.id {
                selectionID = stored.id
                if parsed.openStudio { openInStudio(stored) }
                return BrowserImportResult(itemID: stored.id, name: stored.title, usedLibrary: true, openedStudio: parsed.openStudio)
            }
        }
        statusMessage = L("link.resolving")
        let result = try await linkService.resolve(url, forceDownload: forceDownload)
        guard let repository else { throw ShelfError.message(L("library.unavailable")) }
        let imported = try await repository.importFile(at: result.fileURL)
        if let source = result.source { try await applyCapturedSource(source, itemID: imported.item.id) }
        await reload(); selectionID = imported.item.id
        statusMessage = result.reused ? L("link.reused") : L("link.downloaded")
        if result.openStudio { openInStudio(imported.item) }
        return BrowserImportResult(itemID: imported.item.id, name: imported.item.title, usedLibrary: false, openedStudio: result.openStudio)
    }
    func saveSource(_ item: ShelfItem, page: String, profile: String) async throws {
        guard let repository else { throw ShelfError.message(L("library.unavailable")) }
        let profile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = MakerWorldSource(pageURL: page.trimmingCharacters(in: .whitespacesAndNewlines), profileURL: profile.isEmpty ? nil : profile, capturedAt: Date())
        try await repository.updateSource(id: item.id, source: source)
        await reload()
    }
    func handle(_ url: URL) async {
        if url.isFileURL { await importFiles([url]); return }
        await acquireWork(); defer { releaseWork() }
        statusMessage = L("link.resolving")
        do {
            let result = try await linkService.resolve(url)
            guard let repository else { throw ShelfError.message(L("library.unavailable")) }
            let imported = try await repository.importFile(at: result.fileURL)
            if let source = result.source { try await applyCapturedSource(source, itemID: imported.item.id) }
            await reload(); selectionID = imported.item.id
            statusMessage = result.reused ? L("link.reused") : L("link.downloaded")
            if result.openStudio { openInStudio(imported.item) }
        } catch { errorMessage = error.localizedDescription }
    }
    func applyCapturedSource(_ source: CapturedMakerWorldSource, itemID: String) async throws {
        guard let repository else { throw ShelfError.message(L("library.unavailable")) }
        let plates = source.plates?.map { WebPlateRecord(id: $0.id, name: $0.name, estimatedSeconds: $0.estimatedSeconds, weightGrams: $0.weightGrams, plateType: $0.plateType) }
        try await repository.updateSource(id: itemID, source: MakerWorldSource(pageURL: source.pageURL, profileURL: source.profileURL, capturedAt: source.capturedAt, title: source.title, profileTitle: source.profileTitle, estimatedSeconds: source.estimatedSeconds, plateCount: source.plateCount, plates: plates))
    }
    func savePreferences() {
        do { try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true); try JSONEncoder().encode(preferences).write(to: rootURL.appendingPathComponent("preferences.json"), options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }
    func selectStudio() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.prompt = L("select")
        if panel.runModal() == .OK, let url = panel.url { preferences.studioPath = url.path; savePreferences() }
    }
    func selectInbox() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { preferences.archivePath = url.path; archiveSignatures = [:]; savePreferences(); Task { await scanStudioInbox() } }
    }
    func registerLinks() {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "bambustudioopen") { [weak self] error in
            Task { @MainActor in if let error { self?.errorMessage = error.localizedDescription } else { self?.statusMessage = L("link.registered") } }
        }
    }
    func restoreStudioLinks() {
        guard let officialStudio = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.bambulab.bambu-studio") else { errorMessage = L("studio.missing"); return }
        NSWorkspace.shared.setDefaultApplication(at: officialStudio, toOpenURLsWithScheme: "bambustudioopen") { [weak self] error in
            Task { @MainActor in if let error { self?.errorMessage = error.localizedDescription } else { self?.statusMessage = L("link.restored") } }
        }
    }
}
enum ShelfError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): return message } }
}
struct BrowserLocation: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}
