import Foundation

public struct PlateRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var thumbnailPath: String?
    public var estimatedSeconds: Double?
    public var weightGrams: Double?

    public init(id: String, name: String, thumbnailPath: String? = nil,
                estimatedSeconds: Double? = nil, weightGrams: Double? = nil) {
        self.id = id; self.name = name; self.thumbnailPath = thumbnailPath
        self.estimatedSeconds = estimatedSeconds; self.weightGrams = weightGrams
    }
}

public struct PrintRun: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var date: Date
    public var status: String
    public var source: String
    public var note: String

    public init(id: String = UUID().uuidString, date: Date = Date(), status: String,
                source: String, note: String = "") {
        self.id = id; self.date = date; self.status = status; self.source = source; self.note = note
    }
}

public struct LibraryItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var filename: String
    /// Paths to managed archives and previews are relative to LibraryRepository.rootURL.
    public var filePath: String
    public var thumbnailPath: String?
    public var sourcePaths: [String]
    public var designer: String?
    public var modelID: String?
    public var profileID: String?
    public var profileTitle: String?
    public var materials: [String]
    public var printerModel: String?
    public var plates: [PlateRecord]
    public var hasGCode: Bool
    public var importedAt: Date
    public var tags: [String]
    public var favorite: Bool
    public var note: String
    public var printRuns: [PrintRun]
    /// Explicit browser provenance. Local archive estimates remain in `plates`.
    public var makerWorldSource: MakerWorldSource?

    public init(id: String, title: String, filename: String, filePath: String,
                thumbnailPath: String? = nil, sourcePaths: [String] = [], designer: String? = nil,
                modelID: String? = nil, profileID: String? = nil, profileTitle: String? = nil,
                materials: [String] = [], printerModel: String? = nil, plates: [PlateRecord] = [],
                hasGCode: Bool = false, importedAt: Date = Date(), tags: [String] = [],
                favorite: Bool = false, note: String = "", printRuns: [PrintRun] = [],
                makerWorldSource: MakerWorldSource? = nil) {
        self.id = id; self.title = title; self.filename = filename; self.filePath = filePath
        self.thumbnailPath = thumbnailPath; self.sourcePaths = sourcePaths; self.designer = designer
        self.modelID = modelID; self.profileID = profileID; self.profileTitle = profileTitle
        self.materials = materials; self.printerModel = printerModel; self.plates = plates
        self.hasGCode = hasGCode; self.importedAt = importedAt; self.tags = tags
        self.favorite = favorite; self.note = note; self.printRuns = printRuns
        self.makerWorldSource = makerWorldSource
    }

    /// A total is only available when every known plate has an estimate.
    public var estimatedSeconds: Double? { completeTotal(plates.map(\.estimatedSeconds)) }
    public var weightGrams: Double? { completeTotal(plates.map(\.weightGrams)) }

    private func completeTotal(_ values: [Double?]) -> Double? {
        guard !values.isEmpty, values.allSatisfy({ $0 != nil && $0!.isFinite && $0! > 0 }) else { return nil }
        let total = values.compactMap { $0 }.reduce(0, +)
        return total.isFinite ? total : nil
    }
}

public struct ImportResult: Sendable {
    public var item: LibraryItem
    public var isDuplicate: Bool
    public init(item: LibraryItem, isDuplicate: Bool) { self.item = item; self.isDuplicate = isDuplicate }
}

public enum LibraryError: Error, LocalizedError {
    case unsupportedFile
    case invalidArchive(String)
    case unsafePath(String)
    case limitExceeded(String)
    case invalidXML(String)
    case invalidSettings
    case corruptIndex
    case itemNotFound
    case sourceChanged
    case libraryChanged
    case invalidSource

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "일반 3MF 파일을 선택해 주세요. 폴더와 링크는 가져올 수 없습니다."
        case .invalidArchive(let detail): return "올바른 3MF 압축 파일이 아닙니다: \(detail)"
        case .unsafePath(let path): return "파일 안에 안전하지 않은 경로가 있습니다: \(path)"
        case .limitExceeded(let detail): return "파일의 안전한 처리 한도를 넘었습니다: \(detail)"
        case .invalidXML(let path): return "3MF 메타데이터를 읽을 수 없습니다: \(path)"
        case .invalidSettings: return "3MF 출력 설정의 JSON 형식이 올바르지 않습니다."
        case .corruptIndex: return "보관함 목록이 손상되었거나 지원하지 않는 형식입니다. 기존 목록을 보존했습니다."
        case .itemNotFound: return "보관함에서 해당 파일을 찾을 수 없습니다."
        case .sourceChanged: return "가져오는 동안 파일이 변경되었습니다. 저장을 완료한 뒤 다시 가져와 주세요."
        case .libraryChanged: return "다른 작업에서 보관함 목록이 변경되었습니다. 기존 목록을 보존했습니다. 앱을 다시 열어 주세요."
        case .invalidSource: return "MakerWorld 모델·프로필 페이지 주소 또는 웹 정보가 올바르지 않습니다. 다운로드 주소는 원본 페이지로 저장할 수 없습니다."
        }
    }
}
