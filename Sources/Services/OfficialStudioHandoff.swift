import AppKit

enum OfficialStudioHandoff {
    static let bundleIdentifier = "com.bambulab.bambu-studio"
    static let schemes = ["bambustudioopen", "bambustudio"]
    static func accepts(_ url: URL) -> Bool { schemes.contains(url.scheme?.lowercased() ?? "") }

    static func destination(preferred: URL?, installed: URL?, identifier: (URL) -> String?) -> URL? {
        [preferred, installed].compactMap { $0 }.first { identifier($0) == bundleIdentifier }
    }

    @MainActor static func open(_ url: URL, preferredPath: String, completion: @escaping (Error?) -> Void) {
        guard accepts(url) else { completion(ShelfError.message(L("studio.missing"))); return }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        guard let app = destination(preferred: URL(fileURLWithPath: preferredPath), installed: installed,
                                    identifier: { Bundle(url: $0)?.bundleIdentifier }) else {
            completion(ShelfError.message(L("studio.missing"))); return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in completion(error) }
    }
}
