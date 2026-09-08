import XCTest
import WebKit
import PlateShelfCore
@testable import PlateShelf

@MainActor
final class RecordingBrowserWebView: WKWebView {
    var requests: [URL] = []
    var resolutions: [(Result<Any, Error>) -> Void] = []
    override var url: URL? { requests.last }
    override var isLoading: Bool { false }
    override func load(_ request: URLRequest) -> WKNavigation? {
        if let url = request.url { requests.append(url) }
        return nil
    }

}

final class BrowserNavigationTests: XCTestCase {
    @MainActor func testSourceProfileHomeAndCollectionsStayInsideApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let view = RecordingBrowserWebView()
        let browser = MakerWorldBrowser(collectionsLookup: { _, _, completion in view.resolutions.append(completion) })
        browser.webView = view
        let page = URL(string: "https://makerworld.com/en/models/123-example")!
        var item = ShelfItem(id: "example", title: "Example", filename: "example.3mf", filePath: "example.3mf")
        item.makerWorldSource = MakerWorldSource(pageURL: page.absoluteString, capturedAt: Date())
        model.openSource(item)
        XCTAssertEqual(model.filter, .makerWorld)
        browser.start(model: model, location: model.browserRequest)
        XCTAssertEqual(view.requests, [page])
        browser.start(model: model, location: model.browserRequest)
        XCTAssertEqual(view.requests.count, 1, "Returning to the view must not reload an old request")
        let profile = URL(string: page.absoluteString + "#profileId-456")!
        model.showMakerWorld(profile)
        browser.start(model: model, location: model.browserRequest)
        XCTAssertEqual(view.requests.last, profile)
        model.selectFilter(.makerWorld)
        browser.start(model: model, location: model.browserRequest)
        XCTAssertEqual(view.requests.last, MakerWorldBrowserPolicy.home)
        model.selectFilter(.makerWorldCollections)
        XCTAssertTrue(model.filter.isBrowser)
        XCTAssertEqual(model.filter, .makerWorldCollections)
        XCTAssertTrue(try XCTUnwrap(model.browserRequest).opensMyCollections)
        browser.start(model: model, location: model.browserRequest)
        XCTAssertEqual(view.resolutions.count, 1)
        view.resolutions[0](.success("https://makerworld.com/ko/@test-account/collections"))
        XCTAssertEqual(view.requests.last?.path, "/ko/@test-account/collections")
        XCTAssertNil(browser.collectionsMessage)
        model.selectFilter(.all)
        XCTAssertFalse(model.filter.isBrowser)
        let previous = model.browserRequest
        model.showMakerWorld(URL(string: "https://makerworld.com.evil.test/en/models/1")!)
        XCTAssertEqual(model.browserRequest, previous)
        XCTAssertEqual(model.filter, .all)
    }

    @MainActor func testAbandonedCollectionsRequestCannotReplaceNewNavigation() {
        let view = RecordingBrowserWebView()
        let browser = MakerWorldBrowser(collectionsLookup: { _, _, completion in view.resolutions.append(completion) })
        browser.webView = view
        browser.load(MakerWorldBrowserPolicy.home)
        browser.openMyCollections()
        XCTAssertEqual(view.resolutions.count, 1)
        let next = URL(string: "https://makerworld.com/en/models/456-another")!
        browser.load(next)
        view.resolutions[0](.success("https://makerworld.com/en/@test-account/collections"))
        XCTAssertEqual(view.requests.last, next)
        XCTAssertNil(browser.collectionsMessage)
        browser.openMyCollections()
        view.resolutions[1](.success("https://evil.test/en/@test-account/collections"))
        XCTAssertEqual(view.requests.last, next)
        XCTAssertEqual(browser.collectionsMessage, L("browser.collectionsRetry"))
    }

    func testCollectionsURLMustBeAnActualMakerWorldAccountPage() {
        for locale in ["en", "ko", "ja", "zh"] {
            XCTAssertTrue(MakerWorldBrowserPolicy.isCollections(URL(string: "https://makerworld.com/\(locale)/@test-account/collections")!))
        }
        for raw in ["http://makerworld.com/en/@test/collections", "https://makerworld.com.evil.test/en/@test/collections", "https://user@makerworld.com/en/@test/collections", "https://makerworld.com/en/search/collections", "https://makerworld.com/en/@/collections", "https://makerworld.com/en/@test/collections?redirect=evil"] {
            XCTAssertFalse(MakerWorldBrowserPolicy.isCollections(URL(string: raw)!))
        }
    }

    @MainActor func testCollectionsLookupUsesOwnSidebarAndWaitsForHydration() async throws {
        let scriptURL = try XCTUnwrap(Bundle.main.url(forResource: "CollectionsNavigation", withExtension: "js"))
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        let delegate = NavigationFixtureDelegate()
        view.navigationDelegate = delegate
        for locale in ["en", "ko", "ja", "zh"] {
            let ready = expectation(description: "Local fixture \(locale)")
            delegate.finished = { ready.fulfill() }
            view.loadHTMLString("<html><body><nav><ul><li><a href='/\(locale)/@test-account/browsing-history'>History</a></li></ul></nav><main><a href='/\(locale)/@another-creator/collections'>Creator collections</a></main></body></html>", baseURL: URL(string: "https://makerworld.com/\(locale)"))
            await fulfillment(of: [ready], timeout: 10)
            // Simulate the site's delayed account sidebar, using only a local fixture.
            try await view.evaluateJavaScript("setTimeout(() => { const a = document.createElement('a'); a.href = '/\(locale)/@test-account/collections?tracking=example'; document.querySelector('ul').append(a); }, 60); void 0")
            let value = try await view.callAsyncJavaScript(script, arguments: ["timeoutMilliseconds": 1_000], in: nil, contentWorld: .page)
            XCTAssertEqual(value as? String, "https://makerworld.com/\(locale)/@test-account/collections")
        }
        let ready = expectation(description: "Logged-out local fixture")
        delegate.finished = { ready.fulfill() }
        view.loadHTMLString("<html><body><nav><a href='/en/@another-creator/collections'>Creator collections</a></nav></body></html>", baseURL: URL(string: "https://makerworld.com/en"))
        await fulfillment(of: [ready], timeout: 10)
        let missing = try await view.callAsyncJavaScript(script, arguments: ["timeoutMilliseconds": 50], in: nil, contentWorld: .page)
        XCTAssertTrue(missing == nil || missing is NSNull)
    }
}

@MainActor
private final class NavigationFixtureDelegate: NSObject, WKNavigationDelegate {
    var finished: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished?() }
}
