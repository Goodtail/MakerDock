import AppKit
import PlateShelfCore

enum AppIdentity {
    static let name = "MakerDock"
    /// Automatic capture is experimental; ordinary embedded browsing is available in all builds.
    static var makerWorldCaptureEnabled: Bool {
        #if MAKERWORLD_INTEGRATION
        true
        #else
        false
        #endif
    }
    static var isDevelopment: Bool { Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true }
    static var logo: String { isDevelopment ? "BrandIconDev" : "BrandIcon" }
    static var displayName: String { isDevelopment ? "MakerDock-dev" : name }

    static func legacyIdentifier(for identifier: String) -> String? {
        switch identifier {
        case "com.ninepiece.app.mac.makerdock": return "com.ninepiece.app.mac.plateshelf"
        case "com.ninepiece.app.mac.makerdock.dev": return "com.ninepiece.app.mac.plateshelf.dev"
        default: return nil
        }
    }

    /// Run before the repository or WebKit is opened. Production and development never mix.
    static func prepareUpgrade(root: URL, identifier: String) throws {
        guard let legacy = legacyIdentifier(for: identifier) else { return }
        guard !UserDefaults.standard.bool(forKey: "makerdock.legacyPreferencesImported") else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: legacy).isEmpty else {
            throw ShelfError.message(L("기존 PlateShelf 앱을 종료한 뒤 MakerDock을 다시 열어 주세요. 보관함을 안전하게 이어서 가져옵니다."))
        }
        try LibraryMigration.copyIfNeeded(from: root.deletingLastPathComponent().appendingPathComponent(legacy), to: root)
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        for (folder, suffix) in [("WebKit", ""), ("HTTPStorages", ""), ("HTTPStorages", ".binarycookies")] {
            let parent = library.appendingPathComponent(folder)
            try LibraryMigration.copyEntryIfAbsent(from: parent.appendingPathComponent(legacy + suffix),
                                                  to: parent.appendingPathComponent(identifier + suffix))
        }
        migrateDefaults(from: legacy, to: identifier, defaults: .standard)
    }

    static func migrateDefaults(from legacy: String, to identifier: String, defaults: UserDefaults) {
        var current = defaults.persistentDomain(forName: identifier) ?? [:]
        guard current["makerdock.legacyPreferencesImported"] as? Bool != true else { return }
        for (key, value) in defaults.persistentDomain(forName: legacy) ?? [:] where current[key] == nil {
            current[key] = value
        }
        current["makerdock.legacyPreferencesImported"] = true
        defaults.setPersistentDomain(current, forName: identifier)
    }

    static func shouldMigrateLink(owner: String?, to identifier: String) -> Bool {
        guard let legacy = legacyIdentifier(for: identifier) else { return false }
        return owner == legacy
    }

    @MainActor static func migrateLegacyLinks() async -> String? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        for scheme in ["plateshelf", "bambustudioopen", "bambustudio"] {
            let url = URL(string: scheme + "://open")!
            let owner = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
            // Transfer only the old app's registrations; preserve official Studio and the other variant.
            guard shouldMigrateLink(owner: owner, to: identifier) else { continue }
            let error: Error? = await withCheckedContinuation { continuation in
                NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) {
                    continuation.resume(returning: $0)
                }
            }
            if let error { return L("MakerDock 링크 연결을 옮기지 못했습니다: ") + error.localizedDescription }
        }
        return nil
    }
}

enum LibraryMigration {
    /// Stage a complete copy and validate it before publishing the new library. Keep the original as a backup.
    static func copyIfNeeded(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path), fm.fileExists(atPath: source.path) else { return }
        for journal in [".archive-move.json", ".print-move.json"] where fm.fileExists(atPath: source.appendingPathComponent(journal).path) {
            throw ShelfError.message(L("기존 PlateShelf의 파일 이동 복구가 필요합니다. 기존 앱을 한 번 열고 종료한 뒤 다시 시도해 주세요."))
        }
        let index = source.appendingPathComponent("index.json")
        let originalIndex = try fm.fileExists(atPath: index.path) ? Data(contentsOf: index) : nil
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".makerdock-upgrade-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: staging)
        if let originalIndex {
            guard try Data(contentsOf: staging.appendingPathComponent("index.json")) == originalIndex else { throw LibraryError.libraryChanged }
            try rewriteJSON(at: staging.appendingPathComponent("index.json"), source: source, destination: destination)
        }
        let preferences = staging.appendingPathComponent("preferences.json")
        if fm.fileExists(atPath: preferences.path) {
            try rewriteJSON(at: preferences, source: source, destination: destination)
            _ = try JSONDecoder().decode(ShelfPreferences.self, from: Data(contentsOf: preferences))
        }
        _ = try LibraryRepository(rootURL: staging)
        if let originalIndex { guard try Data(contentsOf: index) == originalIndex else { throw LibraryError.libraryChanged } }
        try fm.moveItem(at: staging, to: destination)
    }

    static func copyEntryIfAbsent(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path), fm.fileExists(atPath: source.path) else { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".makerdock-upgrade-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)
        try fm.moveItem(at: temporary, to: destination)
    }

    private static func rewriteJSON(at url: URL, source: URL, destination: URL) throws {
        let pathKeys: Set<String> = ["sourcePaths", "movedFrom", "movedTo", "archivePath", "folders", "completedFolder"]
        func relocate(_ value: String) -> String {
            if value == source.path { return destination.path }
            if value.hasPrefix(source.path + "/") { return destination.path + value.dropFirst(source.path.count) }
            return value
        }
        func rewrite(_ value: Any, key: String? = nil) -> Any {
            if let dictionary = value as? [String: Any] {
                return dictionary.reduce(into: [String: Any]()) { result, pair in
                    // Bookmark values stay opaque. Only their lookup paths move.
                    if pair.key == "folderBookmarks", let bookmarks = pair.value as? [String: Any] {
                        result[pair.key] = Dictionary(uniqueKeysWithValues: bookmarks.map { (relocate($0.key), $0.value) })
                    } else { result[pair.key] = rewrite(pair.value, key: pair.key) }
                }
            }
            if let array = value as? [Any] { return array.map { rewrite($0, key: key) } }
            if let string = value as? String, let key, pathKeys.contains(key) { return relocate(string) }
            return value
        }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        try JSONSerialization.data(withJSONObject: rewrite(object), options: [.sortedKeys, .prettyPrinted]).write(to: url, options: .atomic)
    }
}
