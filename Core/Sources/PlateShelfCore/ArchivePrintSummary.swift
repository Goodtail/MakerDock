import Foundation

/// Reads saved slicing results without importing or modifying the archive.
public struct ArchivePrintSummary {
    public let plates: [PlateRecord]
    public let printerModel: String?
    public static func read(at url: URL) throws -> Self {
        let parsed = try ThreeMFReader(url: url).parse()
        return Self(plates: parsed.plates, printerModel: parsed.printerModel)
    }
}
