import XCTest
@testable import PlateShelf

final class StudioHandoffTests: XCTestCase {
    func testDevelopmentAndProductionDeclareSeparateOwnSchemes() {
        XCTAssertEqual(AppIdentity.linkSchemes(for: "com.ninepiece.app.mac.makerdock"), ["makerdock", "plateshelf"])
        XCTAssertEqual(AppIdentity.linkSchemes(for: "com.ninepiece.app.mac.makerdock.dev"), ["makerdock-dev", "plateshelf-dev"])
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let declared = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertEqual(declared, AppIdentity.linkSchemes(for: Bundle.main.bundleIdentifier!))
        XCTAssertTrue(Set(declared).isDisjoint(with: OfficialStudioHandoff.schemes))
    }
    func testStudioDestinationRejectsDevAppAndUsesOfficialApplication() {
        let dev = URL(fileURLWithPath: "/Applications/MakerDock-dev.app")
        let studio = URL(fileURLWithPath: "/Applications/BambuStudio.app")
        let identify: (URL) -> String? = { $0 == studio ? OfficialStudioHandoff.bundleIdentifier : "com.ninepiece.app.mac.makerdock.dev" }
        XCTAssertEqual(OfficialStudioHandoff.destination(preferred: dev, installed: studio, identifier: identify), studio)
        XCTAssertNil(OfficialStudioHandoff.destination(preferred: dev, installed: dev, identifier: identify))
        XCTAssertTrue(OfficialStudioHandoff.accepts(URL(string: "bambustudioopen://open?file=example")!))
        XCTAssertTrue(OfficialStudioHandoff.accepts(URL(string: "bambustudio://open?file=example")!))
        XCTAssertFalse(OfficialStudioHandoff.accepts(URL(string: "https://makerworld.com")!))
    }
    func testOnlyOurOldRegistrationsAreRestored() {
        XCTAssertTrue(AppIdentity.shouldRestoreStudioLink(owner: "com.ninepiece.app.mac.makerdock.dev"))
        XCTAssertTrue(AppIdentity.shouldRestoreStudioLink(owner: "com.ninepiece.app.mac.plateshelf"))
        XCTAssertFalse(AppIdentity.shouldRestoreStudioLink(owner: OfficialStudioHandoff.bundleIdentifier))
        XCTAssertFalse(AppIdentity.shouldRestoreStudioLink(owner: "org.other.slicer"))
        XCTAssertFalse(AppIdentity.shouldRestoreStudioLink(owner: nil))
    }
}
