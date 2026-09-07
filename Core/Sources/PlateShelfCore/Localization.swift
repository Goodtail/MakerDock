import Foundation

public enum ShelfLocalization {
    public static let languages = ["ko", "en", "ja", "zh-Hans"]
    public static var override: String? {
        guard let code = UserDefaults.standard.string(forKey: "MakerDockLanguage"), languages.contains(code) else { return nil }
        return code
    }
    public static func text(_ key: String, bundle: Bundle) -> String {
        if let code = override, let path = bundle.path(forResource: code, ofType: "lproj"), let localized = Bundle(path: path) {
            return localized.localizedString(forKey: key, value: nil, table: nil)
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    public static var locale: Locale { override.map(Locale.init(identifier:)) ?? .current }
}
func CL(_ key: String) -> String { ShelfLocalization.text(key, bundle: .module) }
