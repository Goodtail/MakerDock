import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private final class AssertionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
private let assertionCounter = AssertionCounter()

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(description: message) }
    assertionCounter.increment()
}

private func expectFailure(_ message: String, _ block: () throws -> Void) throws {
    var failed = false
    do { try block() } catch { failed = true }
    try expect(failed, message)
}

private func expectAsyncFailure(_ message: String, _ block: () async throws -> Void) async throws {
    var failed = false
    do { try await block() } catch { failed = true }
    try expect(failed, message)
}

private func encoded(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
}

private func macLink(_ remote: String, name: String? = nil) -> URL {
    URL(string: "bambustudioopen://" + encoded(remote + (name.map { "&name=" + $0 } ?? "")))!
}

private let remote = "https://public-cdn.bblmw.com/models/123.3mf?version=7"
private let zipA = Data([0x50, 0x4b, 0x03, 0x04]) + Data("fixture A; archive structure is tested by PlateShelfCore".utf8)
private let zipB = Data([0x50, 0x4b, 0x03, 0x04]) + Data("fixture B; archive structure is tested by PlateShelfCore".utf8)

private actor MockTransport: MakerWorldHTTPTransport {
    struct Reply: Sendable {
        let status: Int
        let etag: String?
        let data: Data
        var finalURL: URL? = nil
        var reportedSize: Int64? = nil
    }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func fetch(_ request: URLRequest, to destination: URL, maximumBytes: Int64) async throws -> MakerWorldHTTPResult {
        guard !replies.isEmpty else { throw TestFailure(description: "Unexpected extra network request") }
        requests.append(request)
        let reply = replies.removeFirst()
        try reply.data.write(to: destination)
        return MakerWorldHTTPResult(statusCode: reply.status, finalURL: reply.finalURL ?? request.url!,
                                   etag: reply.etag, byteCount: reply.reportedSize ?? Int64(reply.data.count))
    }
}

/// All default transport tests are intercepted in process; no DNS or remote transfer occurs.
private final class StubURLProtocol: URLProtocol {
    struct Reply {
        let status: Int
        let headers: [String: String]
        let chunks: [Data]
        var responseURL: URL? = nil
    }
    private static let lock = NSLock()
    private static var reply: Reply?

    static func setReply(_ value: Reply) {
        lock.lock()
        reply = value
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let reply = Self.reply!
        Self.lock.unlock()
        let response = HTTPURLResponse(url: reply.responseURL ?? request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct LinkTests {
    static func main() async throws {
        try policyTests()
        try provenanceTests()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plateshelf-link-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await cacheTests(root)
        try await streamingTests(root)
        print("PASS (\(assertionCounter.value) assertions): MakerWorld URL parsing, exact trust policy, signed identity preservation, cache revalidation/invalidation, provenance/action metadata, privacy, and bounded streaming (no remote network).")
    }

    static func policyTests() throws {
        let parsed = try MakerWorldLinkPolicy.parse(macLink(remote, name: "작은 선반.3mf"))
        try expect(parsed.downloadURL.absoluteString == remote, "Mac handoff must preserve remote URL")
        try expect(parsed.displayName == "작은 선반.3mf", "Unicode display name must survive decoding")
        let separated = URL(string: "bambustudioopen://" + encoded(remote) + "&name=" + encoded("A & B.3mf"))!
        try expect(try MakerWorldLinkPolicy.parse(separated).displayName == "A & B.3mf", "Separately encoded name")
        let legacy = URL(string: "bambustudio://open?file=" + encoded(remote) + "&name=model.3mf")!
        try expect(try MakerWorldLinkPolicy.parse(legacy).downloadURL.absoluteString == remote, "Legacy Studio URI")
        let shelf = URL(string: "plateshelf://open?url=" + encoded(remote) + "&name=model.3mf")!
        try expect(try MakerWorldLinkPolicy.parse(shelf).downloadURL.absoluteString == remote, "PlateShelf URI")
        let noName = try MakerWorldLinkPolicy.parse(macLink("https://makerworld.com/api/download/123"))
        try expect(noName.displayName.hasSuffix(".3mf"), "API endpoint without name gets a safe fallback")
        let nameQuery = "https://makerworld.com/download?version=9&name=variant&file=123"
        let preserveName = URL(string: "plateshelf://open?url=" + encoded(nameQuery) + "&name=model.3mf")!
        try expect(try MakerWorldLinkPolicy.parse(preserveName).downloadURL.absoluteString == nameQuery, "Wrapped content name parameter is preserved")

        let rejectedLinks = [
            "https://makerworld.com/model.3mf", "file:///tmp/a.3mf", "other://open?file=x",
            "plateshelf://open?url=", "plateshelf://other?url=" + encoded(remote),
            "bambustudio://open?file=" + encoded(remote) + "&file=" + encoded(remote),
            "plateshelf://open?url=" + encoded("file:///tmp/a.3mf"),
            "plateshelf://open?url=" + encoded(remote) + "&name=a.3mf&name=b.3mf",
            "plateshelf://open?url=" + encoded(remote) + "#fragment"
        ]
        for link in rejectedLinks {
            try expectFailure("Must reject invalid handoff: \(link)") { _ = try MakerWorldLinkPolicy.parse(URL(string: link)!) }
        }
        for name in ["../a.3mf", "a/b.3mf", "a\\b.3mf", "a:bad.3mf", "a.txt", "", "x\u{0}.3mf", String(repeating: "a", count: 241) + ".3mf"] {
            try expectFailure("Must reject invalid name") { _ = try MakerWorldLinkPolicy.parse(macLink(remote, name: name)) }
        }
        try expectFailure("Malformed percent escape in embedded URL") {
            _ = try MakerWorldLinkPolicy.parse(macLink("https://makerworld.com/model%GG.3mf"))
        }
        try expectFailure("Incomplete percent escape in embedded URL") {
            _ = try MakerWorldLinkPolicy.parse(macLink("https://makerworld.com/model.3mf?version=%"))
        }
        let allowedHosts = ["makerworld.com", "www.makerworld.com", "makerworld.com.cn", "public-cdn.bblmw.com",
                            "public-cdn.bblmw.cn", "my-bucket.s3.amazonaws.com", "my-bucket.s3.ap-northeast-2.amazonaws.com",
                            "my-bucket.s3-us-west-2.amazonaws.com", "my-bucket.s3.dualstack.eu-central-1.amazonaws.com",
                            "my-bucket.s3.cn-north-1.amazonaws.com.cn", "my-bucket.oss-cn-hangzhou.aliyuncs.com"]
        for host in allowedHosts { try MakerWorldLinkPolicy.validateRemoteURL(URL(string: "https://" + host + "/a.3mf")!) }
        let badRemotes = [
            "http://makerworld.com/a.3mf", "https://makerworld.com.evil.test/a.3mf",
            "https://evil.test/amazonaws.com/a.3mf", "https://api.amazonaws.com/a.3mf",
            "https://s3.amazonaws.com/a.3mf", "https://my-bucket.s3.amazonaws.com.evil.test/a.3mf",
            "https://my-bucket.oss-cn-hangzhou.aliyuncs.com.evil.test/a.3mf",
            "https://my-bucket.oss-cn-hangzhou-internal.aliyuncs.com/a.3mf",
            "https://makerworld.com@evil.test/a.3mf", "https://user:secret@makerworld.com/a.3mf",
            "https://makerworld.com:8080/a.3mf", "https://makerworld.com./a.3mf",
            "https://127.0.0.1/a.3mf", "https://[::1]/a.3mf", "https://arbitrary.bblmw.com/a.3mf",
            "https://makerworld.com/a.3mf#fragment"
        ]
        for url in badRemotes {
            try expectFailure("Must reject untrusted source/redirect: \(url)") { try MakerWorldLinkPolicy.validateRemoteURL(URL(string: url)!) }
        }

        func identity(_ value: String) -> String { MakerWorldLinkPolicy.identityHash(for: URL(string: value)!) }
        let awsBase = "https://my-bucket.s3.ap-northeast-2.amazonaws.com/model.3mf?versionId=v1&profile=12"
        try expect(identity(awsBase + "&X-Amz-Signature=one&X-Amz-Date=first") == identity(awsBase + "&X-Amz-Signature=two&X-Amz-Date=second"), "AWS transport signatures may normalize")
        try expect(identity(awsBase) != identity(awsBase.replacingOccurrences(of: "v1", with: "v2")), "Version ID must remain in identity")
        try expect(identity(awsBase + "&unknown=one") != identity(awsBase + "&unknown=two"), "Unknown content parameters must remain")
        try expect(identity(remote + "&Signature=one") != identity(remote + "&Signature=two"), "Never strip provider-unknown signing parameters")
        let oss = "https://my-bucket.oss-cn-hangzhou.aliyuncs.com/model.3mf?versionId=1"
        try expect(identity(oss + "&OSSAccessKeyId=abc&Signature=one&Expires=1") == identity(oss + "&OSSAccessKeyId=def&Signature=two&Expires=2"), "OSS signature normalization")
        try expect(identity(oss) != identity(oss.replacingOccurrences(of: "versionId=1", with: "versionId=2")), "OSS version retained")
        try expect(MakerWorldLinkPolicy.strongETag("\"hash\"") == "\"hash\"", "Strong ETag accepted")
        for tag in ["W/\"hash\"", "*", "hash", "\"bad\r\nvalue\"", "\"one\", \"two\""] {
            try expect(MakerWorldLinkPolicy.strongETag(tag) == nil, "Weak or unsafe ETag rejected")
        }
    }

    static func cacheTests(_ root: URL) async throws {
        let cache = root.appendingPathComponent("cache")
        let mock = MockTransport([
            .init(status: 200, etag: "\"v1\"", data: zipA),
            .init(status: 304, etag: "\"v1\"", data: Data()),
            .init(status: 200, etag: "\"v2\"", data: zipB),
            .init(status: 200, etag: "\"v3\"", data: zipA),
            .init(status: 200, etag: "\"v4\"", data: zipB)
        ])
        let service = MakerWorldLinkService(cacheDirectory: cache, transport: mock)
        let initialRequests = await mock.requests
        try expect(initialRequests.isEmpty, "Initialization must not download")
        let first = try await service.resolve(macLink(remote, name: "Model.3mf"))
        try expect(!first.reused && (try Data(contentsOf: first.fileURL)) == zipA, "Initial download")
        let second = try await service.resolve(macLink(remote, name: "Model.3mf"))
        try expect(second.reused && second.fileURL == first.fileURL, "304 and SHA verified cache reused")
        let third = try await service.resolve(macLink(remote, name: "Model.3mf"))
        try expect(!third.reused && third.fileURL != first.fileURL && (try Data(contentsOf: third.fileURL)) == zipB, "Changed ETag/body produces a new immutable blob")
        try Data("locally corrupted".utf8).write(to: third.fileURL)
        let fourth = try await service.resolve(macLink(remote, name: "Model.3mf"))
        try expect(!fourth.reused && (try Data(contentsOf: fourth.fileURL)) == zipA, "Corrupted cached bytes must force a full download")
        let forced = try await service.resolve(macLink(remote), forceDownload: true)
        try expect(!forced.reused && (try Data(contentsOf: forced.fileURL)) == zipB, "Explicit refresh repairs an existing corrupt content path")
        let requests = await mock.requests
        try expect(requests.map { $0.value(forHTTPHeaderField: "If-None-Match") } == [nil, "\"v1\"", "\"v1\"", nil, nil], "Only verified cache sends a strong validator")
        try expect(requests.allSatisfy { $0.httpMethod == "GET" }, "Conditional GET needs only one request")
        try expect((try FileManager.default.contentsOfDirectory(atPath: cache.appendingPathComponent("temporary").path)).isEmpty, "Temporary files cleaned after success")

        for etag in [nil, "W/\"weak\""] as [String?] {
            let transport = MockTransport([.init(status: 200, etag: etag, data: zipA), .init(status: 200, etag: etag, data: zipA)])
            let client = MakerWorldLinkService(cacheDirectory: root.appendingPathComponent(UUID().uuidString), transport: transport)
            _ = try await client.resolve(macLink(remote))
            let result = try await client.resolve(macLink(remote))
            let observed = await transport.requests
            try expect(!result.reused && observed.last?.value(forHTTPHeaderField: "If-None-Match") == nil, "Missing/weak validator falls back to full transfer")
        }

        let signedCache = root.appendingPathComponent("signed")
        let signedTransport = MockTransport([.init(status: 200, etag: "\"stable\"", data: zipA), .init(status: 304, etag: nil, data: Data()), .init(status: 200, etag: "\"stable\"", data: zipB)])
        let signedService = MakerWorldLinkService(cacheDirectory: signedCache, transport: signedTransport)
        let signedBase = "https://my-bucket.s3.ap-northeast-2.amazonaws.com/a.3mf?versionId=1"
        _ = try await signedService.resolve(macLink(signedBase + "&X-Amz-Signature=TOP_SECRET_ONE"))
        let signedReuse = try await signedService.resolve(macLink(signedBase + "&X-Amz-Signature=TOP_SECRET_TWO"))
        try expect(signedReuse.reused, "Refreshed signed URL must still revalidate before reuse")
        _ = try await signedService.resolve(macLink(signedBase.replacingOccurrences(of: "versionId=1", with: "versionId=2") + "&X-Amz-Signature=TOP_SECRET_THREE"))
        let signedRequests = await signedTransport.requests
        try expect(signedRequests.last?.value(forHTTPHeaderField: "If-None-Match") == nil, "Different version must not reuse the previous validator")
        for file in try FileManager.default.contentsOfDirectory(at: signedCache.appendingPathComponent("records"), includingPropertiesForKeys: nil) {
            let persisted = try String(contentsOf: file, encoding: .utf8)
            try expect(!persisted.contains("TOP_SECRET") && !persisted.contains("https://") && !persisted.contains("X-Amz"), "No raw signed URL secrets in cache record")
        }

        let invalid304 = MockTransport([.init(status: 200, etag: "\"one\"", data: zipA), .init(status: 304, etag: "\"different\"", data: Data()), .init(status: 200, etag: "\"two\"", data: zipB)])
        let invalidClient = MakerWorldLinkService(cacheDirectory: root.appendingPathComponent("invalid304"), transport: invalid304)
        _ = try await invalidClient.resolve(macLink(remote))
        let recovered = try await invalidClient.resolve(macLink(remote))
        let fallbackRequests = await invalid304.requests
        try expect(!recovered.reused && fallbackRequests.last?.value(forHTTPHeaderField: "If-None-Match") == nil, "Inconsistent 304 triggers one unconditional retry")

        let failures: [MockTransport.Reply] = [
            .init(status: 403, etag: nil, data: Data()),
            .init(status: 200, etag: nil, data: Data("<html>Sign in</html>".utf8)),
            .init(status: 200, etag: nil, data: zipA, finalURL: URL(string: "https://evil.test/a.3mf")),
            .init(status: 200, etag: nil, data: zipA, reportedSize: MakerWorldLinkPolicy.maximumBytes + 1),
            .init(status: 200, etag: nil, data: zipA, reportedSize: 1)
        ]
        for failure in failures {
            let location = root.appendingPathComponent(UUID().uuidString)
            let bad = MakerWorldLinkService(cacheDirectory: location, transport: MockTransport([failure]))
            try await expectAsyncFailure("Invalid HTTP/archive/size response must fail") { _ = try await bad.resolve(macLink(remote)) }
            try expect((try FileManager.default.contentsOfDirectory(atPath: location.appendingPathComponent("records").path)).isEmpty, "Failures cannot commit cache records")
            try expect((try FileManager.default.contentsOfDirectory(atPath: location.appendingPathComponent("temporary").path)).isEmpty, "Temporary files cleaned after failure")
        }
    }

    static func provenanceTests() throws {
        let page = "https://makerworld.com/ko/models/1099461-sturdy-modular-filament-spool-rack-fully-printable"
        let profile = page + "#profileId-1791619"
        let snapshot = #"{"capturedAt":"2026-01-01T00:00:00.123Z","title":"필라멘트 랙","profileTitle":"Mega Pack","estimatedSeconds":42120,"plateCount":7}"#
        let incoming = "plateshelf://open?url=" + encoded(remote) + "&source=" + encoded(page + "?from=search&Signature=SECRET") + "&profile=" + encoded(profile) + "&snapshot=" + encoded(snapshot) + "&action=import"
        let parsed = try MakerWorldLinkPolicy.parse(URL(string: incoming)!)
        try expect(parsed.provenance?.pageURL == page, "Public model page removes tracking and signatures")
        try expect(parsed.provenance?.profileURL == profile, "Observed selected profile fragment retained")
        try expect(parsed.provenance?.estimatedSeconds == 42120 && parsed.provenance?.plateCount == 7, "Web profile totals remain separate from per-plate estimates")
        try expect(parsed.provenance?.plates == nil, "Never invent per-plate numbers from aggregate time")
        try expect(!parsed.openStudio, "Download intent imports without opening Studio")
        let legacyNested = URL(string: "bambustudio://open?file=" + encoded(remote + "&name=actual.3mf"))!
        try expect(try MakerWorldLinkPolicy.parse(legacyNested).downloadURL.absoluteString == remote, "Real current legacy Studio payload contains name inside file")
        let invalidSources = ["https://makerworld.com/ko/search/models?keyword=rack", "https://evil.test/en/models/123", "https://makerworld.com/api/v1/download/1", "https://public-cdn.bblmw.com/en/models/123", "file:///tmp/x.3mf"]
        for source in invalidSources {
            let url = URL(string: "plateshelf://open?url=" + encoded(remote) + "&source=" + encoded(source))!
            try expectFailure("Only actual public model-page provenance is allowed") { _ = try MakerWorldLinkPolicy.parse(url) }
        }
        let mismatch = URL(string: "plateshelf://open?url=" + encoded(remote) + "&source=" + encoded(page) + "&profile=" + encoded("https://makerworld.com/en/models/2-other#profileId-10"))!
        try expectFailure("A different model's profile cannot be attached") { _ = try MakerWorldLinkPolicy.parse(mismatch) }
        let unsigned = URL(string: "plateshelf://open?url=" + encoded(remote) + "&source=" + encoded(page) + "&snapshot=" + encoded(snapshot))!
        try expectFailure("Estimates require an identified selected profile") { _ = try MakerWorldLinkPolicy.parse(unsigned) }
        let invalidPlate = #"{"plates":[{"id":"1","estimatedSeconds":-10}]}"#
        let bad = URL(string: "plateshelf://open?url=" + encoded(remote) + "&source=" + encoded(page) + "&profile=" + encoded(profile) + "&snapshot=" + encoded(invalidPlate))!
        try expectFailure("Invalid web plate numbers rejected") { _ = try MakerWorldLinkPolicy.parse(bad) }
    }

    static func streamingTests(_ root: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let transport = MakerWorldStreamingTransport(configuration: configuration)
        let request = URLRequest(url: URL(string: remote)!)
        let target = root.appendingPathComponent("stream.part")
        StubURLProtocol.setReply(.init(status: 200, headers: ["ETag": "\"stream\"", "Content-Length": "8"], chunks: [Data("1234".utf8), Data("5678".utf8)]))
        let result = try await transport.fetch(request, to: target, maximumBytes: 10)
        try expect(result.byteCount == 8 && (try Data(contentsOf: target)).count == 8, "Streaming writes bounded chunks to disk")

        StubURLProtocol.setReply(.init(status: 200, headers: ["Content-Length": "11"], chunks: []))
        try await expectAsyncFailure("Reject oversized Content-Length before body") { _ = try await transport.fetch(request, to: target, maximumBytes: 10) }
        StubURLProtocol.setReply(.init(status: 200, headers: [:], chunks: [Data(repeating: 1, count: 4), Data(repeating: 2, count: 8)]))
        try await expectAsyncFailure("Reject oversized chunked body") { _ = try await transport.fetch(request, to: target, maximumBytes: 10) }
        try expect((try Data(contentsOf: target)).count <= 10, "Never writes bytes beyond transfer limit")
        StubURLProtocol.setReply(.init(status: 403, headers: [:], chunks: []))
        try await expectAsyncFailure("Reject error HTTP status") { _ = try await transport.fetch(request, to: target, maximumBytes: 10) }
        StubURLProtocol.setReply(.init(status: 200, headers: [:], chunks: [], responseURL: URL(string: "https://evil.test/a.3mf")))
        try await expectAsyncFailure("Recheck final response host") { _ = try await transport.fetch(request, to: target, maximumBytes: 10) }
    }
}
