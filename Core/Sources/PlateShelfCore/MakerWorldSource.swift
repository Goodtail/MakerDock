import Foundation

/// Values actually observed on the selected MakerWorld profile, separate from a 3MF's saved slice data.
public struct WebPlateRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let estimatedSeconds: Double?
    public let weightGrams: Double?
    public let plateType: String?

    public init(id: String, name: String? = nil, estimatedSeconds: Double? = nil,
                weightGrams: Double? = nil, plateType: String? = nil) {
        self.id = id; self.name = name; self.estimatedSeconds = estimatedSeconds
        self.weightGrams = weightGrams; self.plateType = plateType
    }
}

/// A captured web snapshot. Importing a local 3MF never fabricates or refreshes these values.
public struct MakerWorldSource: Codable, Sendable, Hashable {
    public let pageURL: String
    public let profileURL: String?
    public let capturedAt: Date
    public let title: String?
    public let profileTitle: String?
    /// Profile totals shown on the web card, never represented as a fictional plate.
    public let estimatedSeconds: Double?
    public let plateCount: Int?
    /// nil: not observed; []: explicitly observed no plate details.
    public let plates: [WebPlateRecord]?

    public init(pageURL: String, profileURL: String? = nil, capturedAt: Date = Date(),
                title: String? = nil, profileTitle: String? = nil, estimatedSeconds: Double? = nil,
                plateCount: Int? = nil, plates: [WebPlateRecord]? = nil) {
        self.pageURL = pageURL; self.profileURL = profileURL; self.capturedAt = capturedAt
        self.title = title; self.profileTitle = profileTitle; self.plates = plates
        self.estimatedSeconds = estimatedSeconds; self.plateCount = plateCount
    }

    public var knownPlateEstimatedSeconds: Double? { total(plates?.map(\.estimatedSeconds)) }
    public var weightGrams: Double? { total(plates?.map(\.weightGrams)) }
    private func total(_ values: [Double?]?) -> Double? {
        guard let values, !values.isEmpty,
              plateCount == nil || plateCount == values.count,
              values.allSatisfy({ $0 != nil && $0!.isFinite && $0! > 0 }) else { return nil }
        let total = values.compactMap { $0 }.reduce(0, +)
        return total.isFinite ? total : nil
    }

    func validated() throws -> MakerWorldSource {
        let page = try MakerWorldPage(pageURL)
        let profile = try profileURL.map(MakerWorldPage.init) ?? (page.profileID == nil ? nil : page)
        guard profile == nil || (profile?.modelID == page.modelID && profile?.profileID != nil),
              capturedAt.timeIntervalSince1970.isFinite,
              estimatedSeconds.map({ $0.isFinite && $0 > 0 }) ?? true,
              plateCount.map({ $0 >= 0 && $0 <= 1_000 }) ?? true,
              plateCount == nil || plates == nil || plates!.count <= plateCount!,
              (title?.count ?? 0) <= 2_000, (profileTitle?.count ?? 0) <= 2_000,
              (plates?.count ?? 0) <= 1_000 else { throw LibraryError.invalidSource }
        var ids = Set<String>()
        for plate in plates ?? [] {
            guard !plate.id.isEmpty, plate.id.count <= 200, ids.insert(plate.id).inserted,
                  (plate.name?.count ?? 0) <= 2_000, (plate.plateType?.count ?? 0) <= 500,
                  plate.estimatedSeconds.map({ $0.isFinite && $0 > 0 }) ?? true,
                  plate.weightGrams.map({ $0.isFinite && $0 > 0 }) ?? true else { throw LibraryError.invalidSource }
        }
        return MakerWorldSource(pageURL: page.pageURL, profileURL: profile?.profileURL,
                                capturedAt: capturedAt, title: title?.nonEmpty,
                                profileTitle: profileTitle?.nonEmpty, estimatedSeconds: estimatedSeconds,
                                plateCount: plateCount, plates: plates)
    }

    /// Link-only observations cannot erase richer profile details or falsely re-date old estimates.
    func merging(previous: MakerWorldSource?) throws -> MakerWorldSource {
        let incoming = try validated()
        guard let previous, let old = try? previous.validated(),
              try MakerWorldPage(old.pageURL).modelID == MakerWorldPage(incoming.pageURL).modelID else { return incoming }
        let oldProfileID = try old.profileURL.flatMap { try MakerWorldPage($0).profileID }
        let newProfileID = try incoming.profileURL.flatMap { try MakerWorldPage($0).profileID }
        let compatibleProfile = newProfileID == nil || oldProfileID == newProfileID
        guard compatibleProfile else {
            return MakerWorldSource(pageURL: incoming.pageURL, profileURL: incoming.profileURL,
                                    capturedAt: incoming.capturedAt, title: incoming.title ?? old.title,
                                    profileTitle: incoming.profileTitle, estimatedSeconds: incoming.estimatedSeconds,
                                    plateCount: incoming.plateCount, plates: incoming.plates)
        }
        let changedPlateCount = incoming.plateCount.map { count in
            (old.plateCount != nil && old.plateCount != count) || (old.plates?.count ?? 0) > count
        } ?? false
        let mergedPlates = incoming.plates ?? (changedPlateCount ? nil : old.plates)
        let mergedEstimate = incoming.estimatedSeconds ?? (changedPlateCount ? nil : old.estimatedSeconds)
        let preservedEstimate = incoming.plates == nil && incoming.estimatedSeconds == nil &&
            (mergedPlates != nil || mergedEstimate != nil)
        let linkOnly = incoming.title == nil && incoming.profileTitle == nil && incoming.plates == nil &&
            incoming.estimatedSeconds == nil && incoming.plateCount == nil
        return try MakerWorldSource(pageURL: incoming.pageURL, profileURL: incoming.profileURL ?? old.profileURL,
                                capturedAt: preservedEstimate || linkOnly ? old.capturedAt : incoming.capturedAt,
                                title: incoming.title ?? old.title, profileTitle: incoming.profileTitle ?? old.profileTitle,
                                estimatedSeconds: mergedEstimate,
                                plateCount: incoming.plateCount ?? old.plateCount,
                                plates: mergedPlates).validated()
    }
}

/// Only IDs literally present in public page URLs are used here. Studio's DesignModelId is unrelated.
private struct MakerWorldPage {
    let modelID: String
    let profileID: String?
    let pageURL: String
    let profileURL: String?

    init(_ raw: String) throws {
        guard raw.count <= 8_192, var parts = URLComponents(string: raw),
              parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "makerworld.com",
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443 else {
            throw LibraryError.invalidSource
        }
        let path = parts.path
        let pattern = #"^/(?:[A-Za-z]{2}(?:-[A-Za-z]{2})?/)?models/([1-9][0-9]*)(?:-[^/\\?#\s]+)?/?$"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range(at: 1), in: path) else { throw LibraryError.invalidSource }
        modelID = String(path[range])
        let selectors = (parts.queryItems ?? []).filter { ["profileid", "printprofileid"].contains($0.name.lowercased()) }
        var explicitIDs = selectors.compactMap(\.value)
        if let fragment = parts.fragment, fragment.hasPrefix("profileId-") { explicitIDs.append(String(fragment.dropFirst("profileId-".count))) }
        guard explicitIDs.allSatisfy({ $0.range(of: #"^[1-9][0-9]*$"#, options: .regularExpression) != nil }),
              Set(explicitIDs).count <= 1 else { throw LibraryError.invalidSource }
        profileID = explicitIDs.first
        parts.scheme = "https"; parts.host = "makerworld.com"; parts.port = nil
        // No query parameter or arbitrary fragment is persisted, including signed download URLs.
        parts.queryItems = nil; parts.fragment = nil
        guard let page = parts.url?.absoluteString else { throw LibraryError.invalidSource }
        pageURL = page
        if let profileID { parts.fragment = "profileId-\(profileID)"; profileURL = parts.url?.absoluteString }
        else { profileURL = nil }
    }
}
