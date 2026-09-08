import XCTest
@testable import PlateShelf

final class PublicDistributionTests: XCTestCase {
    @MainActor func testBuildSeparatesPublicAndDevelopmentIntegration() async throws {
        #if MAKERWORLD_INTEGRATION
        XCTAssertTrue(AppIdentity.makerWorldCaptureEnabled)
        #else
        XCTAssertFalse(AppIdentity.makerWorldCaptureEnabled)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let link = URL(string: "makerdock://open?url=https%3A%2F%2Fmakerworld.com%2Fexample.3mf")!
        await model.handle(link)
        XCTAssertEqual(model.errorMessage, L("integration.unavailable"))
        XCTAssertTrue(model.items.isEmpty)
        do {
            _ = try await model.receiveBrowserDownload(link, preferStored: true)
            XCTFail("Public builds must reject remote transfers before transport")
        } catch { XCTAssertEqual(error.localizedDescription, L("integration.unavailable")) }
        let browser = MakerWorldBrowser()
        XCTAssertTrue(browser.webView.configuration.userContentController.userScripts.isEmpty)
        let view = RecordingBrowserWebView()
        browser.webView = view
        model.showMakerWorld(URL(string: "https://makerworld.com/en/models/123-example")!)
        browser.start(model: model, location: model.browserRequest)
        XCTAssertEqual(view.requests.last, model.browserRequest?.url)
        XCTAssertEqual(model.filter, .makerWorld)
        XCTAssertTrue(browser.transferMessage.isEmpty)
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
        XCTAssertFalse(schemes.contains("bambustudioopen"))
        XCTAssertFalse(schemes.contains("bambustudio"))
        #endif
    }
}
