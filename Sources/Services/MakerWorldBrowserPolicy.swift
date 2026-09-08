import Foundation

enum MakerWorldBrowserPolicy {
    static var websiteLanguage: String {
        let code = UserDefaults.standard.string(forKey: "MakerDockLanguage").flatMap { $0.isEmpty ? nil : $0 } ?? Bundle.main.preferredLocalizations.first ?? "en"
        return code.hasPrefix("zh") ? "zh" : code.hasPrefix("ja") ? "ja" : code.hasPrefix("ko") ? "ko" : "en"
    }
    static var home: URL { URL(string: "https://makerworld.com/" + websiteLanguage)! }
    static func isMakerWorld(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return ["makerworld.com", "www.makerworld.com"].contains(url.host?.lowercased() ?? "")
    }
    static func isCollections(_ url: URL) -> Bool {
        guard isMakerWorld(url), url.query == nil, url.fragment == nil else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.count == 3 && ["en", "ko", "ja", "zh"].contains(parts[0]) &&
            parts[1].hasPrefix("@") && parts[1].count > 1 && parts[2] == "collections"
    }
    static func address(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 4096 else { return nil }
        if value.contains("://") || value.hasPrefix("makerworld.com/") || value.hasPrefix("www.makerworld.com/") {
            let raw = value.contains("://") ? value : "https://" + value
            guard let url = URL(string: raw), isMakerWorld(url) else { return nil }
            return url
        }
        guard !value.lowercased().hasPrefix("javascript:"), !value.lowercased().hasPrefix("file:") else { return nil }
        var parts = URLComponents(string: home.absoluteString + "/search/models")!
        parts.queryItems = [URLQueryItem(name: "keyword", value: value)]
        return parts.url
    }
    // Locale, title slug and tracking parameters don't define model/profile identity.
    static func modelKey(_ raw: String) -> String? {
        guard let url = try? MakerWorldLinkPolicy.canonicalPage(raw, includeProfile: false),
              let models = url.pathComponents.firstIndex(of: "models"),
              url.pathComponents.indices.contains(models + 1),
              let id = url.pathComponents[models + 1].split(separator: "-").first else { return nil }
        return (url.host ?? "") + "/models/" + id
    }
    static func profileKey(_ raw: String?) -> String? {
        guard let raw, let url = try? MakerWorldLinkPolicy.canonicalPage(raw, includeProfile: true),
              let model = modelKey(raw), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let id = parts.fragment?.replacingOccurrences(of: "profileId-", with: "") ?? parts.queryItems?.first?.value
        return id.map { model + "/profiles/" + $0 }
    }
    static func context(_ json: String) throws -> CapturedMakerWorldSource? {
        guard json.utf8.count <= 24_000, let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let page = object["pageURL"] as? String, isMakerWorld(URL(string: page)) else { throw MakerWorldLinkError.invalidLink }
        var items = [URLQueryItem(name: "source", value: page), URLQueryItem(name: "snapshot", value: json)]
        if let profile = object["profileURL"] as? String { items.append(URLQueryItem(name: "profile", value: profile)) }
        return try MakerWorldLinkPolicy.parseProvenance(items)
    }
    static func handoff(remote: URL, name: String, page: URL?) throws -> URL {
        var parts = URLComponents(string: "makerdock://open")!
        parts.queryItems = [URLQueryItem(name: "url", value: remote.absoluteString),
                            URLQueryItem(name: "name", value: name), URLQueryItem(name: "action", value: "import")]
        // A fallback navigation has no request-time profile evidence; keep only the observed page.
        if let page, let canonical = try? MakerWorldLinkPolicy.canonicalPage(page.absoluteString, includeProfile: false) {
            parts.queryItems?.append(URLQueryItem(name: "source", value: canonical.absoluteString))
        }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw MakerWorldLinkError.invalidLink }
        _ = try MakerWorldLinkPolicy.parse(url)
        return url
    }
}

struct BrowserImportResult {
    let itemID: String
    let name: String
    let usedLibrary: Bool
    let openedStudio: Bool
}
