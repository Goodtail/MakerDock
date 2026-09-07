import XCTest
@testable import PlateShelf

private actor BrowserTestTransport: MakerWorldHTTPTransport {
    private(set) var requests = 0
    struct NoNetwork: Error {}
    func fetch(_ request: URLRequest, to destination: URL, maximumBytes: Int64) async throws -> MakerWorldHTTPResult {
        requests += 1
        throw NoNetwork()
    }
}

final class BrowserTests: XCTestCase {
    func testNavigationAndStableProfileIdentity() throws {
        XCTAssertTrue(MakerWorldBrowserPolicy.isMakerWorld(URL(string: "https://makerworld.com/ko")))
        for raw in ["https://makerworld.com.evil.test", "http://makerworld.com", "https://makerworld.com:8443", "https://user@makerworld.com"] {
            XCTAssertFalse(MakerWorldBrowserPolicy.isMakerWorld(URL(string: raw)))
        }
        let query = try XCTUnwrap(MakerWorldBrowserPolicy.address("필라멘트 랙 + 받침"))
        XCTAssertEqual(URLComponents(url: query, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "필라멘트 랙 + 받침")
        XCTAssertNil(MakerWorldBrowserPolicy.address("file:///tmp/model.3mf"))
        XCTAssertNil(MakerWorldBrowserPolicy.address("javascript:alert(1)"))
        let ko = "https://makerworld.com/ko/models/123-original#profileId-456"
        let en = "https://makerworld.com/en/models/123-new-title?printProfileId=456"
        XCTAssertEqual(MakerWorldBrowserPolicy.profileKey(ko), MakerWorldBrowserPolicy.profileKey(en))
        XCTAssertNotEqual(MakerWorldBrowserPolicy.profileKey(ko), MakerWorldBrowserPolicy.profileKey("https://makerworld.com/en/models/124-new-title#profileId-456"))
        XCTAssertNotEqual(MakerWorldBrowserPolicy.profileKey(ko), MakerWorldBrowserPolicy.profileKey("https://makerworld.com/en/models/123-new-title#profileId-457"))
        XCTAssertNil(MakerWorldBrowserPolicy.profileKey("https://makerworld.com/en/models/123"))
    }
    func testContextBoundsAndFallbackNeverGuessesProfile() throws {
        let page = "https://makerworld.com/ko/models/123-rack"
        let raw = #"{"pageURL":"https://makerworld.com/ko/models/123-rack","profileURL":"https://makerworld.com/ko/models/123-rack#profileId-456","capturedAt":"2026-01-01T00:00:00Z","title":"랙 + 받침","estimatedSeconds":42120,"plateCount":7}"#
        let source = try XCTUnwrap(MakerWorldBrowserPolicy.context(raw))
        XCTAssertEqual(source.title, "랙 + 받침"); XCTAssertEqual(source.estimatedSeconds, 42120)
        XCTAssertThrowsError(try MakerWorldBrowserPolicy.context(raw.replacingOccurrences(of: page, with: "https://evil.test/ko/models/123-rack")))
        XCTAssertThrowsError(try MakerWorldBrowserPolicy.context(String(repeating: "a", count: 24_001)))
        let remote = URL(string: "https://public-cdn.bblmw.com/model.3mf?Signature=A+B%2BC")!
        let link = try MakerWorldBrowserPolicy.handoff(remote: remote, name: "랙 + 받침.3mf", page: URL(string: page + "#profileId-456"))
        let parsed = try MakerWorldLinkPolicy.parse(link)
        XCTAssertEqual(parsed.downloadURL, remote); XCTAssertEqual(parsed.displayName, "랙 + 받침.3mf")
        XCTAssertEqual(parsed.provenance?.pageURL, page); XCTAssertNil(parsed.provenance?.profileURL)
        XCTAssertFalse(parsed.openStudio)
    }
    @MainActor func testStoredProfileReusesBytesWithoutNetworkAndMissingFileFallsBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = BrowserTestTransport()
        let service = MakerWorldLinkService(cacheDirectory: root.appendingPathComponent("Downloads"), transport: transport)
        let model = LibraryViewModel(rootOverride: root, linkServiceOverride: service)
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        await model.importFiles([fixture])
        let item = try XCTUnwrap(model.items.first)
        try await model.saveSource(item, page: "https://makerworld.com/ko/models/123-rack", profile: "https://makerworld.com/ko/models/123-rack#profileId-456")
        var parts = URLComponents(string: "plateshelf://open")!
        parts.queryItems = [
            .init(name: "url", value: "https://public-cdn.bblmw.com/never-requested.3mf"),
            .init(name: "action", value: "import"),
            .init(name: "source", value: "https://makerworld.com/en/models/123-renamed"),
            .init(name: "profile", value: "https://makerworld.com/en/models/123-renamed#profileId-456")
        ]
        let incoming = try XCTUnwrap(parts.url)
        let result = try await model.receiveBrowserDownload(incoming, preferStored: true)
        XCTAssertTrue(result.usedLibrary); XCTAssertEqual(result.itemID, item.id)
        let count = await transport.requests; XCTAssertEqual(count, 0)
        XCTAssertEqual(model.items.count, 1)
        do { _ = try await model.receiveBrowserDownload(incoming, preferStored: true, forceDownload: true); XCTFail("Explicit latest must reach transport") }
        catch is BrowserTestTransport.NoNetwork {}
        try FileManager.default.removeItem(at: model.fileURL(item))
        do { _ = try await model.receiveBrowserDownload(incoming, preferStored: true); XCTFail("Missing original must not be reused") }
        catch is BrowserTestTransport.NoNetwork {}
        let after = await transport.requests; XCTAssertEqual(after, 2)
        XCTAssertFalse(model.isWorking)
    }
}
