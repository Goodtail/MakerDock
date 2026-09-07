import XCTest
import PlateShelfCore
@testable import PlateShelf

final class LocalizationTests: XCTestCase {
    func testAllCatalogsHaveSameKeysAndMatchingFormatArguments() throws {
        var reference: [String:String] = [:]
        for language in ["ko", "en", "ja", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let entries = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String:String])
            if language == "ko" { reference = entries; continue }
            XCTAssertEqual(Set(entries.keys), Set(reference.keys))
            let regex = try NSRegularExpression(pattern: "%[@df]")
            for (key, value) in entries {
                let args: (String) -> [String] = { text in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) } }
                XCTAssertEqual(args(value), args(reference[key]!), "\(language): \(key)")
                XCTAssertNil(value.range(of: "[가-힣]", options: .regularExpression), "Untranslated \(language): \(key)")
            }
        }
        XCTAssertGreaterThan(reference.count, 360)
    }
    func testLanguageOverrideAppliesToAppCoreAndMakerWorldNavigation() throws {
        let old = UserDefaults.standard.object(forKey: "MakerDockLanguage")
        defer { if let old { UserDefaults.standard.set(old, forKey: "MakerDockLanguage") } else { UserDefaults.standard.removeObject(forKey: "MakerDockLanguage") } }
        for (language,title) in [("en","Model Library"),("ja","モデルライブラリ"),("zh-Hans","模型库"),("ko","모델 보관함")] {
            UserDefaults.standard.set(language, forKey: "MakerDockLanguage")
            XCTAssertEqual(L("library.title"), title)
            XCTAssertEqual(MakerWorldBrowserPolicy.home.path, language == "zh-Hans" ? "/zh" : "/" + language)
            let description = try XCTUnwrap(LibraryError.itemNotFound.errorDescription)
            if language == "en" { XCTAssertEqual(description, "The file wasn’t found in the library.") }
        }
    }
}
