import XCTest
import WebKit
@testable import PlateShelf

private actor FreshDownloadTransport: MakerWorldHTTPTransport {
    private let data: Data
    private(set) var calls = 0
    init(data: Data) { self.data = data }
    func fetch(_ request: URLRequest, to destination: URL, maximumBytes: Int64) async throws -> MakerWorldHTTPResult {
        calls += 1
        try data.write(to: destination)
        return MakerWorldHTTPResult(statusCode: 200, finalURL: request.url!, etag: nil, byteCount: Int64(data.count))
    }
}

final class BrowserWorkflowTests: XCTestCase {
    @MainActor func testSectionsRestoreTheirOwnTabsAndReselectGoesHome() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let workspace = MakerWorldWorkspace { _ in
            let view = RecordingBrowserWebView()
            let browser = MakerWorldBrowser(collectionsLookup: { _, _, callback in view.resolutions.append(callback) })
            browser.webView = view
            return browser
        }
        model.selectFilter(.makerWorld); workspace.show(model: model)
        let first = try XCTUnwrap(workspace.active)
        let view = try XCTUnwrap(first.browser.webView as? RecordingBrowserWebView)
        first.browser.load(URL(string: "https://makerworld.com/en/models/123-hook")!)
        model.selectFilter(.all)
        model.selectFilter(.makerWorld); workspace.show(model: model)
        XCTAssertEqual(workspace.active?.id, first.id)
        XCTAssertEqual(view.requests.count, 2, "Returning must not navigate")
        model.selectFilter(.makerWorld); workspace.show(model: model)
        XCTAssertEqual(view.requests.last, MakerWorldBrowserPolicy.home)
        XCTAssertEqual(view.requests.count, 3)
        model.selectFilter(.makerWorldCollections); workspace.show(model: model)
        let collections = try XCTUnwrap(workspace.active)
        XCTAssertNotEqual(collections.id, first.id)
        let collectionView = try XCTUnwrap(collections.browser.webView as? RecordingBrowserWebView)
        collections.browser.load(URL(string: "https://makerworld.com/en/@me/collections/models")!)
        collections.browser.load(URL(string: "https://makerworld.com/en/collections/987")!)
        let count = collectionView.requests.count
        model.selectFilter(.queue)
        model.selectFilter(.makerWorldCollections); workspace.show(model: model)
        XCTAssertEqual(workspace.active?.id, collections.id)
        XCTAssertEqual(collectionView.requests.count, count)
        model.selectFilter(.makerWorld); workspace.show(model: model)
        XCTAssertEqual(workspace.active?.id, first.id)
    }

    @MainActor func testBackgroundTabsDoNotNavigateParentAndClosingSelectsNeighbor() throws {
        let model = LibraryViewModel(rootOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: model.rootURL) }
        let workspace = MakerWorldWorkspace { _ in
            let browser = MakerWorldBrowser(); browser.webView = RecordingBrowserWebView(); return browser
        }
        model.selectFilter(.makerWorld); workspace.show(model: model)
        let first = try XCTUnwrap(workspace.active)
        let view = try XCTUnwrap(first.browser.webView as? RecordingBrowserWebView)
        let before = view.requests
        let url = URL(string: "https://makerworld.com/en/models/456-another")!
        let child = first.browser.openTab?(URLRequest(url: url), nil, false)
        XCTAssertEqual(workspace.visibleTabs.count, 2)
        XCTAssertEqual(workspace.active?.id, first.id)
        XCTAssertEqual(view.requests, before)
        XCTAssertEqual((child as? RecordingBrowserWebView)?.requests, [url])
        let second = workspace.visibleTabs[1]
        second.browser.currentURL = url
        workspace.select(second.id)
        XCTAssertTrue(workspace.handleTabShortcut(keyCode: 13, shifted: false))
        XCTAssertEqual(workspace.active?.id, first.id)
        XCTAssertTrue(workspace.canReopen)
        XCTAssertTrue(workspace.handleTabShortcut(keyCode: 17, shifted: true))
        XCTAssertEqual(workspace.visibleTabs.count, 2)
        XCTAssertEqual((workspace.active?.browser.webView as? RecordingBrowserWebView)?.requests, [url])
        workspace.active?.browser.transferCount = 1
        workspace.close(workspace.active!.id)
        XCTAssertEqual(workspace.visibleTabs.count, 2, "Keep active imports alive")
    }

    @MainActor func testDownloadOriginIsBoundToDocumentGestureAndTab() {
        let browser = MakerWorldBrowser(), other = MakerWorldBrowser()
        let collection = URL(string: "https://makerworld.com/en/@me/collections/models")!
        let model = URL(string: "https://makerworld.com/en/models/123-hook?tracking=discarded#profileId-99")!
        let now = Date()
        browser.recordGesture(document: collection, page: model, now: now)
        XCTAssertEqual(browser.origin(document: collection, fallback: nil, now: now)?.absoluteString, "https://makerworld.com/en/models/123-hook")
        XCTAssertNil(browser.origin(document: collection, fallback: nil, now: now.addingTimeInterval(16)))
        XCTAssertNil(browser.origin(document: MakerWorldBrowserPolicy.home, fallback: nil, now: now))
        XCTAssertNil(other.origin(document: collection, fallback: nil, now: now))
        browser.recordGesture(document: collection, page: nil, now: now)
        XCTAssertNil(browser.origin(document: collection, fallback: nil, now: now))
        browser.recordGesture(document: URL(string: "https://evil.test")!, page: model, now: now)
        XCTAssertNil(browser.origin(document: collection, fallback: nil, now: now))
    }

    @MainActor func testNativeReuseRepairsSourceAndForceReachesNetworkWithoutETag() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        let transport = FreshDownloadTransport(data: try Data(contentsOf: fixture))
        let service = MakerWorldLinkService(cacheDirectory: root.appendingPathComponent("Downloads"), transport: transport)
        let model = LibraryViewModel(rootOverride: root, linkServiceOverride: service)
        let remote = URL(string: "https://public-cdn.bblmw.com/hook.3mf?Signature=one")!
        let link = try MakerWorldBrowserPolicy.handoff(remote: remote, name: "Hook.3mf", page: nil)
        let first = try await model.receiveNativeBrowserDownload(link)
        let withSource = try MakerWorldBrowserPolicy.handoff(remote: remote, name: "Hook.3mf", page: URL(string: "https://makerworld.com/en/models/123-hook"))
        let second = try await model.receiveNativeBrowserDownload(withSource)
        XCTAssertEqual(first.itemID, second.itemID)
        XCTAssertTrue(second.usedLibrary)
        let count = await transport.calls; XCTAssertEqual(count, 1)
        XCTAssertEqual(model.items.first?.makerWorldSource?.pageURL, "https://makerworld.com/en/models/123-hook")
        _ = try await model.receiveNativeBrowserDownload(withSource, forceDownload: true)
        let forced = await transport.calls; XCTAssertEqual(forced, 2)
        XCTAssertEqual(model.items.count, 1)
        _ = try await model.receiveNativeBrowserDownload(withSource, preferStored: false)
        let uncached = await transport.calls; XCTAssertEqual(uncached, 3)
    }

    @MainActor func testFreshWorkingCopyPreservesEditsAndBecomesTheNextDefault() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        await model.importFiles([fixture])
        let item = try XCTUnwrap(model.items.first)
        let original = try Data(contentsOf: model.fileURL(item))
        let old = try model.workingCopy(for: item)
        try Data("user edits".utf8).write(to: old)
        let fresh = try model.workingCopy(for: item, fresh: true)
        XCTAssertNotEqual(fresh, old)
        XCTAssertEqual(try Data(contentsOf: old), Data("user edits".utf8))
        XCTAssertEqual(try Data(contentsOf: fresh), original)
        XCTAssertEqual(try model.workingCopy(for: item), fresh)
        XCTAssertEqual(try Data(contentsOf: model.fileURL(item)), original)
    }
}
