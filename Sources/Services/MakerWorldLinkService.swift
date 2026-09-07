import Foundation
import CryptoKit

struct ResolvedModel: Sendable {
    let fileURL: URL
    let displayName: String
    let reused: Bool
    var source: CapturedMakerWorldSource? = nil
    var openStudio: Bool = true
}

struct CapturedWebPlateRecord: Codable, Sendable {
    let id: String
    let name: String?
    let estimatedSeconds: Double?
    let weightGrams: Double?
    let plateType: String?
}

struct CapturedMakerWorldSource: Codable, Sendable {
    let pageURL: String
    let profileURL: String?
    let capturedAt: Date
    let title: String?
    let profileTitle: String?
    let estimatedSeconds: Double?
    let plateCount: Int?
    let plates: [CapturedWebPlateRecord]?
}

enum MakerWorldLinkError: LocalizedError {
    case invalidLink
    case untrustedHost
    case invalidName
    case tooLarge
    case invalidResponse
    case httpStatus(Int)
    case invalidArchive
    case cannotWriteCache
    case tooManyRedirects
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidLink: return "올바른 MakerWorld 열기 링크가 아닙니다."
        case .untrustedHost: return "MakerWorld에서 사용하는 HTTPS 다운로드 주소만 열 수 있습니다."
        case .invalidName: return "링크에 포함된 파일 이름이 올바르지 않습니다."
        case .tooLarge: return "500 MB를 넘는 파일은 직접 다운로드한 뒤 보관함에 추가해 주세요."
        case .invalidResponse: return "다운로드 서버의 응답을 확인할 수 없습니다."
        case .httpStatus(let code): return "파일을 받지 못했습니다. 서버 응답: \(code). MakerWorld에서 새 열기 링크를 받아 주세요."
        case .invalidArchive: return "다운로드한 파일이 3MF 압축 파일 형식이 아닙니다."
        case .cannotWriteCache: return "다운로드 보관함에 파일을 저장하지 못했습니다."
        case .tooManyRedirects: return "다운로드 주소의 이동 횟수가 너무 많습니다."
        case .networkUnavailable: return "파일을 받는 중 연결이 끊겼습니다. 네트워크를 확인하고 다시 시도해 주세요."
        }
    }
}

/// URL parsing and trust checks are shared with the redirect delegate.
/// No URL or signed query string is persisted or included in an error message.
enum MakerWorldLinkPolicy {
    struct Source: Sendable {
        let downloadURL: URL
        let displayName: String
        let identityHash: String
        let provenance: CapturedMakerWorldSource?
        let openStudio: Bool
    }

    static let maximumBytes: Int64 = 500 * 1_000_000

    private static let exactHosts: Set<String> = [
        "makerworld.com", "www.makerworld.com", "makerworld.com.cn", "www.makerworld.com.cn",
        "public-cdn.bblmw.com", "public-cdn.bblmw.cn", "makerworld.bblmw.com", "makerworld.bblmw.cn"
    ]

    static func parse(_ incoming: URL) throws -> Source {
        let scheme = incoming.scheme?.lowercased()
        let remoteString: String
        let requestedName: String?
        var provenance: CapturedMakerWorldSource?
        var openStudio = true
        guard incoming.absoluteString.utf8.count <= 65_536 else { throw MakerWorldLinkError.invalidLink }
        if scheme == "bambustudioopen" {
            let raw = incoming.absoluteString
            guard let separator = raw.range(of: "://") else { throw MakerWorldLinkError.invalidLink }
            let payload = String(raw[separator.upperBound...])
            guard !payload.isEmpty, validPercentEscapes(payload) else { throw MakerWorldLinkError.invalidLink }
            // MakerWorld has used both a separately encoded URL and an encoded whole payload.
            if let nameRange = payload.range(of: "&name=") {
                remoteString = try decode(String(payload[..<nameRange.lowerBound]))
                requestedName = try decode(String(payload[nameRange.upperBound...]))
            } else {
                let decoded = try decode(payload)
                if let nameRange = decoded.range(of: "&name=") {
                    remoteString = String(decoded[..<nameRange.lowerBound])
                    requestedName = String(decoded[nameRange.upperBound...])
                } else {
                    remoteString = decoded
                    requestedName = nil
                }
            }
        } else if scheme == "bambustudio" || ["makerdock", "plateshelf"].contains(scheme) {
            guard var parts = URLComponents(url: incoming, resolvingAgainstBaseURL: false),
                  parts.host?.lowercased() == "open", parts.path.isEmpty || parts.path == "/",
                  parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
                  validPercentEscapes(incoming.absoluteString) else { throw MakerWorldLinkError.invalidLink }
            if ["makerdock", "plateshelf"].contains(scheme) {
                // Chrome URLSearchParams uses form encoding: + is a space, %2B is a literal +.
                // Normalize before percent decoding so nested URLs/signatures retain their bytes.
                parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
            }
            let key = scheme == "bambustudio" ? "file" : "url"
            let values = (parts.queryItems ?? []).filter { $0.name == key }
            let names = (parts.queryItems ?? []).filter { $0.name == "name" }
            guard values.count == 1, let value = values.first?.value, !value.isEmpty,
                  names.count <= 1 else { throw MakerWorldLinkError.invalidLink }
            if scheme == "bambustudio", names.isEmpty, let trailer = value.range(of: "&name=") {
                remoteString = String(value[..<trailer.lowerBound])
                requestedName = String(value[trailer.upperBound...])
            } else {
                remoteString = value
                requestedName = names.first?.value
            }
            if ["makerdock", "plateshelf"].contains(scheme) {
                provenance = try parseProvenance(parts.queryItems ?? [])
                let actions = (parts.queryItems ?? []).filter { $0.name == "action" }
                guard actions.count <= 1, actions.isEmpty || ["open", "import"].contains(actions.first?.value ?? "") else { throw MakerWorldLinkError.invalidLink }
                openStudio = actions.first?.value != "import"
            }
        } else {
            throw MakerWorldLinkError.invalidLink
        }
        // URL(string:) silently repairs malformed percent sequences. Validate before constructing it.
        guard validPercentEscapes(remoteString),
              !remoteString.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let remote = URL(string: remoteString) else { throw MakerWorldLinkError.invalidLink }
        try validateRemoteURL(remote)
        let name: String
        if let requestedName {
            name = try validateName(requestedName)
        } else if remote.pathExtension.lowercased() == "3mf" {
            name = try validateName(remote.lastPathComponent)
        } else {
            name = "MakerWorld 모델.3mf"
        }
        return Source(downloadURL: remote, displayName: name, identityHash: identityHash(for: remote), provenance: provenance, openStudio: openStudio)
    }

    /// Canonical public provenance has a model-page path, never a signed asset/search URL.
    static func canonicalPage(_ raw: String, includeProfile: Bool) throws -> URL {
        guard raw.utf8.count <= 4096, let url = URL(string: raw),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host?.lowercased(),
              ["makerworld.com", "www.makerworld.com", "makerworld.com.cn", "www.makerworld.com.cn"].contains(host),
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              parts.path.range(of: #"^/(?:[a-z]{2}(?:-[A-Za-z]{2})?/)?models/[1-9][0-9]*(?:-[^/]+)?/?$"#, options: .regularExpression) != nil,
              !parts.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw MakerWorldLinkError.invalidLink }
        let fragmentID = parts.fragment?.range(of: #"^profileId-[1-9][0-9]*$"#, options: .regularExpression) != nil ? parts.fragment : nil
        let queryIDs = (parts.queryItems ?? []).filter { $0.name == "printProfileId" || $0.name == "profileId" }
        guard queryIDs.count <= 1 else { throw MakerWorldLinkError.invalidLink }
        var queryProfile: URLQueryItem?
        if let item = queryIDs.first {
            guard let value = item.value, value.range(of: #"^[1-9][0-9]*$"#, options: .regularExpression) != nil else { throw MakerWorldLinkError.invalidLink }
            queryProfile = item
        }
        if let fragmentID, let queryProfile, fragmentID != "profileId-" + (queryProfile.value ?? "") { throw MakerWorldLinkError.invalidLink }
        parts.scheme = "https"
        parts.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        parts.port = nil
        parts.queryItems = includeProfile && fragmentID == nil ? queryProfile.map { [$0] } : nil
        parts.fragment = includeProfile ? fragmentID : nil
        guard !includeProfile || fragmentID != nil || queryProfile != nil, let result = parts.url else { throw MakerWorldLinkError.invalidLink }
        return result
    }

    private struct WebSnapshot: Decodable {
        let capturedAt: String?
        let title: String?
        let profileTitle: String?
        let estimatedSeconds: Double?
        let plateCount: Int?
        let plates: [CapturedWebPlateRecord]?
    }

    static func parseProvenance(_ items: [URLQueryItem]) throws -> CapturedMakerWorldSource? {
        func value(_ name: String) throws -> String? {
            let matches = items.filter { $0.name == name }
            guard matches.count <= 1 else { throw MakerWorldLinkError.invalidLink }
            return matches.first?.value
        }
        guard let rawPage = try value("source") else {
            guard try value("profile") == nil, try value("snapshot") == nil else { throw MakerWorldLinkError.invalidLink }
            return nil
        }
        let page = try canonicalPage(rawPage, includeProfile: false)
        var profile: URL?
        if let rawProfile = try value("profile") {
            let checked = try canonicalPage(rawProfile, includeProfile: true)
            guard try canonicalPage(checked.absoluteString, includeProfile: false) == page else { throw MakerWorldLinkError.invalidLink }
            profile = checked
        }
        var snapshot: WebSnapshot?
        if let json = try value("snapshot") {
            guard json.utf8.count <= 24_000, let data = json.data(using: .utf8) else { throw MakerWorldLinkError.invalidLink }
            snapshot = try JSONDecoder().decode(WebSnapshot.self, from: data)
        }
        func text(_ value: String?, limit: Int) throws -> String? {
            guard let value else { return nil }
            guard value.utf8.count <= limit,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }) else { throw MakerWorldLinkError.invalidLink }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func number(_ value: Double?, maximum: Double) throws -> Double? {
            guard let value else { return nil }
            guard value.isFinite, value >= 0, value <= maximum else { throw MakerWorldLinkError.invalidLink }
            return value
        }
        var capturedAt = Date()
        if let rawDate = snapshot?.capturedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: rawDate)
            if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: rawDate) }
            guard let date, date.timeIntervalSinceNow <= 300 else { throw MakerWorldLinkError.invalidLink }
            capturedAt = date
        }
        let count = snapshot?.plateCount
        guard count == nil || (1...256).contains(count!) else { throw MakerWorldLinkError.invalidLink }
        let records = snapshot?.plates
        guard records == nil || records!.count <= 256 else { throw MakerWorldLinkError.invalidLink }
        var ids = Set<String>()
        let plates = try records?.map { record in
            guard record.id.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil,
                  ids.insert(record.id).inserted else { throw MakerWorldLinkError.invalidLink }
            return CapturedWebPlateRecord(id: record.id, name: try text(record.name, limit: 512),
                estimatedSeconds: try number(record.estimatedSeconds, maximum: 31_536_000),
                weightGrams: try number(record.weightGrams, maximum: 1_000_000), plateType: try text(record.plateType, limit: 256))
        }
        // Without an identified selected profile, web estimates cannot be attributed to this download.
        guard profile != nil || (snapshot?.profileTitle == nil && snapshot?.estimatedSeconds == nil && count == nil && plates == nil) else { throw MakerWorldLinkError.invalidLink }
        return CapturedMakerWorldSource(pageURL: page.absoluteString, profileURL: profile?.absoluteString,
            capturedAt: capturedAt, title: try text(snapshot?.title, limit: 1024), profileTitle: try text(snapshot?.profileTitle, limit: 1024),
            estimatedSeconds: try number(snapshot?.estimatedSeconds, maximum: 31_536_000), plateCount: count, plates: plates)
    }

    static func validateRemoteURL(_ url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.port == nil || parts.port == 443,
              !host.hasSuffix("."), !host.contains("%"),
              validPercentEscapes(url.absoluteString),
              exactHosts.contains(host) || isAWSBucket(host) || isOSSBucket(host) else {
            throw MakerWorldLinkError.untrustedHost
        }
    }

    static func identityHash(for url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return sha256(Data(url.absoluteString.utf8))
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if parts.port == 443 { parts.port = nil }
        let host = parts.host ?? ""
        // Only transport authentication fields are removed, and only on their known hosts.
        // Keep raw encodings, duplicate parameters, their order, and all content/version fields.
        let awsFields: Set<String> = ["X-Amz-Algorithm", "X-Amz-Credential", "X-Amz-Date", "X-Amz-Expires",
                                      "X-Amz-SignedHeaders", "X-Amz-Signature", "X-Amz-Security-Token",
                                      "AWSAccessKeyId", "Signature", "Expires"]
        let ossFields: Set<String> = ["OSSAccessKeyId", "Signature", "Expires", "security-token",
                                      "x-oss-signature-version", "x-oss-credential", "x-oss-date",
                                      "x-oss-expires", "x-oss-signature", "x-oss-additional-headers",
                                      "x-oss-security-token"]
        let removable = isAWSBucket(host) ? awsFields : (isOSSBucket(host) ? ossFields : [])
        if let query = parts.percentEncodedQuery, !removable.isEmpty {
            let retained = query.components(separatedBy: "&").filter { field in
                let key = String(field.prefix { $0 != "=" }).removingPercentEncoding ?? ""
                return !removable.contains(key)
            }
            parts.percentEncodedQuery = retained.isEmpty ? nil : retained.joined(separator: "&")
        }
        return sha256(Data((parts.string ?? url.absoluteString).utf8))
    }

    static func strongETag(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.utf8.count >= 2, trimmed.utf8.count <= 1024,
              trimmed.first == "\"", trimmed.last == "\"",
              !trimmed.dropFirst().dropLast().contains("\""),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return trimmed
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fileSHA256(_ file: URL) throws -> (hash: String, size: Int64) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        var count: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            count += Int64(chunk.count)
            guard count <= maximumBytes else { throw MakerWorldLinkError.tooLarge }
            hash.update(data: chunk)
        }
        return (hash.finalize().map { String(format: "%02x", $0) }.joined(), count)
    }

    private static func validateName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 240,
              !trimmed.contains("/"), !trimmed.contains("\\"), !trimmed.contains(":"),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (trimmed as NSString).pathExtension.lowercased() == "3mf",
              !(trimmed as NSString).deletingPathExtension.isEmpty else { throw MakerWorldLinkError.invalidName }
        return trimmed
    }

    private static func decode(_ text: String) throws -> String {
        guard validPercentEscapes(text), let decoded = text.removingPercentEncoding else {
            throw MakerWorldLinkError.invalidLink
        }
        return decoded
    }

    private static func validPercentEscapes(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var index = 0
        func hex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
        while index < bytes.count {
            if bytes[index] == 37 {
                guard index + 2 < bytes.count, hex(bytes[index + 1]), hex(bytes[index + 2]) else { return false }
                index += 3
            } else { index += 1 }
        }
        return true
    }

    private static func isAWSBucket(_ host: String) -> Bool {
        // Virtual-hosted S3 bucket endpoints; never an arbitrary *.amazonaws.com service.
        let pattern = #"^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\.s3(?:(?:[.-](?:[a-z]{2}(?:-[a-z]+){1,2}-[0-9]))|(?:\.dualstack\.[a-z]{2}(?:-[a-z]+){1,2}-[0-9])|(?:-accelerate(?:\.dualstack)?))?\.amazonaws\.com(?:\.cn)?$"#
        return host.range(of: pattern, options: .regularExpression) != nil && !host.contains("..")
    }

    private static func isOSSBucket(_ host: String) -> Bool {
        let pattern = #"^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\.oss-[a-z0-9]+(?:-[a-z0-9]+)*\.aliyuncs\.com$"#
        return host.range(of: pattern, options: .regularExpression) != nil && !host.contains("-internal.")
    }
}

struct MakerWorldHTTPResult: Sendable {
    let statusCode: Int
    let finalURL: URL
    let etag: String?
    let byteCount: Int64
}

protocol MakerWorldHTTPTransport: Sendable {
    func fetch(_ request: URLRequest, to destination: URL, maximumBytes: Int64) async throws -> MakerWorldHTTPResult
}

actor MakerWorldLinkService {
    private struct CacheRecord: Codable {
        let schema: Int
        let identityHash: String
        let contentHash: String
        let byteCount: Int64
        let displayName: String
        let etag: String?
        let checkedAt: Date
    }

    private let cacheDirectory: URL
    private let transport: any MakerWorldHTTPTransport
    // Coalesces repeated clicks on the same source while its request is in flight.
    private var pending: [String: Task<ResolvedModel, Error>] = [:]

    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        self.transport = MakerWorldStreamingTransport()
    }

    // Internal injection seam: the test suite performs no real network requests.
    init(cacheDirectory: URL, transport: any MakerWorldHTTPTransport) {
        self.cacheDirectory = cacheDirectory
        self.transport = transport
    }

    func resolve(_ incoming: URL, forceDownload: Bool = false) async throws -> ResolvedModel {
        let source = try MakerWorldLinkPolicy.parse(incoming)
        let operationKey = source.identityHash + (forceDownload ? ":force" : ":normal")
        if let existing = pending[operationKey] {
            var result = try await existing.value
            result.source = source.provenance
            result.openStudio = source.openStudio
            return result
        }
        let task = Task { try await self.performResolve(source, forceDownload: forceDownload) }
        pending[operationKey] = task
        defer { pending[operationKey] = nil }
        var result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        result.source = source.provenance
        result.openStudio = source.openStudio
        return result
    }

    private func performResolve(_ source: MakerWorldLinkPolicy.Source, forceDownload: Bool) async throws -> ResolvedModel {
        try Task.checkCancellation()
        try prepareDirectories()
        let recordURL = cacheDirectory.appendingPathComponent("records").appendingPathComponent(source.identityHash + ".json")
        let prior: CacheRecord? = forceDownload ? nil : readVerifiedRecord(recordURL, identityHash: source.identityHash)
        var request = URLRequest(url: source.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.setValue("application/vnd.ms-package.3dmanufacturing-3dmodel+xml, application/zip, application/octet-stream", forHTTPHeaderField: "Accept")
        // Avoid transparent compression changing the byte-level representation associated with an ETag.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let etag = prior?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let temporary = cacheDirectory.appendingPathComponent("temporary").appendingPathComponent(UUID().uuidString + ".part")
        defer { try? FileManager.default.removeItem(at: temporary) }
        var response = try await transport.fetch(request, to: temporary, maximumBytes: MakerWorldLinkPolicy.maximumBytes)
        try Task.checkCancellation()
        try MakerWorldLinkPolicy.validateRemoteURL(response.finalURL)
        if response.statusCode == 304 {
            // A 304 response is meaningful only for the strong validator we actually sent.
            if let prior, let expectedETag = prior.etag,
                  response.etag == nil || MakerWorldLinkPolicy.strongETag(response.etag) == expectedETag,
                  let stillValid = readVerifiedRecord(recordURL, identityHash: source.identityHash),
                  stillValid.contentHash == prior.contentHash {
                let refreshed = CacheRecord(schema: 1, identityHash: source.identityHash, contentHash: prior.contentHash,
                                        byteCount: prior.byteCount, displayName: source.displayName, etag: expectedETag, checkedAt: Date())
                try writeRecord(refreshed, to: recordURL)
                return ResolvedModel(fileURL: blobURL(prior.contentHash), displayName: source.displayName, reused: true)
            }
            // A broken/missing validator or a locally changed cache must never open stale bytes.
            // Retry once without a condition; a second 304 is an invalid server response.
            request.setValue(nil, forHTTPHeaderField: "If-None-Match")
            response = try await transport.fetch(request, to: temporary, maximumBytes: MakerWorldLinkPolicy.maximumBytes)
            try Task.checkCancellation()
            try MakerWorldLinkPolicy.validateRemoteURL(response.finalURL)
        }
        guard response.statusCode == 200 else { throw MakerWorldLinkError.httpStatus(response.statusCode) }
        guard response.byteCount <= MakerWorldLinkPolicy.maximumBytes else { throw MakerWorldLinkError.tooLarge }
        try validateArchiveHeader(temporary)
        let content = try MakerWorldLinkPolicy.fileSHA256(temporary)
        guard content.size == response.byteCount else { throw MakerWorldLinkError.invalidResponse }
        let target = blobURL(content.hash)
        if FileManager.default.fileExists(atPath: target.path) {
            let existing = try? MakerWorldLinkPolicy.fileSHA256(target)
            if existing?.hash != content.hash {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            }
        } else {
            try FileManager.default.moveItem(at: temporary, to: target)
        }
        let record = CacheRecord(schema: 1, identityHash: source.identityHash, contentHash: content.hash,
                                 byteCount: content.size, displayName: source.displayName,
                                 etag: MakerWorldLinkPolicy.strongETag(response.etag), checkedAt: Date())
        try writeRecord(record, to: recordURL)
        return ResolvedModel(fileURL: target, displayName: source.displayName, reused: false)
    }

    private func prepareDirectories() throws {
        for path in [cacheDirectory, cacheDirectory.appendingPathComponent("records"),
                     cacheDirectory.appendingPathComponent("blobs"), cacheDirectory.appendingPathComponent("temporary")] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    private func blobURL(_ contentHash: String) -> URL {
        cacheDirectory.appendingPathComponent("blobs").appendingPathComponent(contentHash + ".3mf")
    }

    private func readVerifiedRecord(_ url: URL, identityHash: String) -> CacheRecord? {
        guard let data = try? Data(contentsOf: url), data.count <= 16_384,
              let record = try? JSONDecoder().decode(CacheRecord.self, from: data),
              record.schema == 1, record.identityHash == identityHash,
              record.contentHash.count == 64, record.contentHash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              record.byteCount > 0, record.byteCount <= MakerWorldLinkPolicy.maximumBytes,
              let etag = MakerWorldLinkPolicy.strongETag(record.etag), etag == record.etag,
              let actual = try? MakerWorldLinkPolicy.fileSHA256(blobURL(record.contentHash)),
              actual.hash == record.contentHash, actual.size == record.byteCount else { return nil }
        return record
    }

    private func writeRecord(_ record: CacheRecord, to url: URL) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: .atomic)
    }

    private func validateArchiveHeader(_ file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        // 3MF is a ZIP package. MIME types vary across CDNs, so require actual ZIP bytes.
        guard try handle.read(upToCount: 4) == Data([0x50, 0x4b, 0x03, 0x04]) else {
            throw MakerWorldLinkError.invalidArchive
        }
    }
}

/// Downloads in URLSession delegate chunks, writing directly to disk and cancelling at 500 MB.
/// URLSession's normal TLS trust validation stays enabled; credentials and browser cookies are not shared.
struct MakerWorldStreamingTransport: MakerWorldHTTPTransport {
    private let configuration: URLSessionConfiguration?

    init(configuration: URLSessionConfiguration? = nil) {
        self.configuration = configuration
    }

    func fetch(_ request: URLRequest, to destination: URL, maximumBytes: Int64) async throws -> MakerWorldHTTPResult {
        let transfer = MakerWorldStreamingTransfer(destination: destination, maximumBytes: maximumBytes, configuration: configuration)
        return try await withTaskCancellationHandler {
            try await transfer.start(request)
        } onCancel: {
            transfer.cancel()
        }
    }
}

private final class MakerWorldStreamingTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destination: URL
    private let maximumBytes: Int64
    private let configuration: URLSessionConfiguration?
    private let stateLock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<MakerWorldHTTPResult, Error>?
    private var handle: FileHandle?
    // These fields are only accessed by URLSession's serial delegate queue after start().
    private var response: HTTPURLResponse?
    private var received: Int64 = 0
    private var redirectCount = 0
    private var failure: Error?

    init(destination: URL, maximumBytes: Int64, configuration: URLSessionConfiguration?) {
        self.destination = destination
        self.maximumBytes = maximumBytes
        self.configuration = configuration
    }

    func start(_ request: URLRequest) async throws -> MakerWorldHTTPResult {
        guard let url = request.url else { throw MakerWorldLinkError.invalidLink }
        try MakerWorldLinkPolicy.validateRemoteURL(url)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw MakerWorldLinkError.cannotWriteCache
        }
        handle = try FileHandle(forWritingTo: destination)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = (self.configuration?.copy() as? URLSessionConfiguration) ?? URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.urlCredentialStorage = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForResource = 300
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            let task = session.dataTask(with: request)
            stateLock.lock()
            self.task = task
            let shouldCancel = cancelled
            stateLock.unlock()
            task.resume()
            if shouldCancel { task.cancel() }
        }
    }

    func cancel() {
        stateLock.lock()
        cancelled = true
        let task = self.task
        stateLock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        do {
            redirectCount += 1
            guard redirectCount <= 8 else { throw MakerWorldLinkError.tooManyRedirects }
            guard let url = request.url else { throw MakerWorldLinkError.invalidResponse }
            try MakerWorldLinkPolicy.validateRemoteURL(url)
            completionHandler(request)
        } catch {
            failure = error
            completionHandler(nil)
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse, let url = http.url else { throw MakerWorldLinkError.invalidResponse }
            try MakerWorldLinkPolicy.validateRemoteURL(url)
            guard http.statusCode == 200 || http.statusCode == 304 else { throw MakerWorldLinkError.httpStatus(http.statusCode) }
            guard response.expectedContentLength <= maximumBytes else { throw MakerWorldLinkError.tooLarge }
            self.response = http
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        do {
            guard Int64(data.count) <= maximumBytes - received else { throw MakerWorldLinkError.tooLarge }
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            self.session?.finishTasksAndInvalidate()
            self.session = nil
            stateLock.lock()
            self.task = nil
            stateLock.unlock()
            continuation = nil
        }
        do {
            try handle?.close()
            handle = nil
            if let failure { throw failure }
            if let error {
                if (error as? URLError)?.code == .cancelled { throw CancellationError() }
                // URLError userInfo can include signed URLs; expose a clean error to the UI.
                throw MakerWorldLinkError.networkUnavailable
            }
            guard let response, let url = response.url else { throw MakerWorldLinkError.invalidResponse }
            continuation?.resume(returning: MakerWorldHTTPResult(statusCode: response.statusCode, finalURL: url,
                etag: response.value(forHTTPHeaderField: "ETag"), byteCount: received))
        } catch {
            continuation?.resume(throwing: error)
        }
    }
}
