import XCTest
import PlateShelfCore
@testable import PlateShelf

final class PrintEstimateTests: XCTestCase {
    func item(plates: [PlateRecord], web: MakerWorldSource? = nil) -> ShelfItem {
        ShelfItem(id: String(repeating: "a", count: 64), title: "Fixture", filename: "Fixture.3mf", filePath: "Files/fixture.3mf", plates: plates, makerWorldSource: web)
    }
    func testWebEstimateTakesPriorityAndSinglePlateUsesTheSameObservedTime() {
        let plate = PlateRecord(id: "1", name: "Clip", estimatedSeconds: 1200)
        let value = item(plates: [plate], web: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", estimatedSeconds: 1620, plateCount: 1))
        XCTAssertEqual(value.preferredEstimate, PrintEstimate(seconds: 1620, source: .makerWorld))
        XCTAssertEqual(value.preferredEstimate(for: plate), value.preferredEstimate)
        XCTAssertEqual(value.estimatedSeconds, 1200) // Presentation does not overwrite file metadata.
    }
    func testProfileTotalIsNeverDividedAmongMultiplePlates() {
        let plates = [PlateRecord(id: "1", name: "A"), PlateRecord(id: "2", name: "B", estimatedSeconds: 600)]
        let value = item(plates: plates, web: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", estimatedSeconds: 3600, plateCount: 2))
        XCTAssertEqual(value.preferredEstimate?.seconds, 3600)
        XCTAssertNil(value.preferredEstimate(for: plates[0]))
        XCTAssertEqual(value.preferredEstimate(for: plates[1]), PrintEstimate(seconds: 600, source: .file))
        let differentCount = item(plates: [plates[0]], web: value.makerWorldSource)
        XCTAssertNil(differentCount.preferredEstimate(for: plates[0]))
    }
    func testCompleteWebPlateDetailsAndLocalFallback() {
        let plates = [PlateRecord(id: "1", name: "A", estimatedSeconds: 100), PlateRecord(id: "2", name: "B", estimatedSeconds: 200)]
        let source = MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", plateCount: 2, plates: [WebPlateRecord(id: "1", estimatedSeconds: 300), WebPlateRecord(id: "2", estimatedSeconds: 400)])
        let value = item(plates: plates, web: source)
        XCTAssertEqual(value.preferredEstimate, PrintEstimate(seconds: 700, source: .makerWorld))
        XCTAssertEqual(value.preferredEstimate(for: plates[0])?.seconds, 300)
        XCTAssertEqual(item(plates: plates).preferredEstimate, PrintEstimate(seconds: 300, source: .file))
        XCTAssertNil(item(plates: [PlateRecord(id: "1", name: "No estimate")]).preferredEstimate)
    }
    func testInvalidOrIncompleteWebValuesDoNotHideUsableFileEstimate() {
        let plates = [PlateRecord(id: "1", name: "A", estimatedSeconds: 100)]
        for seconds in [Double.nan, Double.infinity, 0, -1] {
            let value = item(plates: plates, web: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", estimatedSeconds: seconds))
            XCTAssertEqual(value.preferredEstimate, PrintEstimate(seconds: 100, source: .file))
        }
        let partial = MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", plateCount: 2, plates: [WebPlateRecord(id: "1", estimatedSeconds: 400)])
        XCTAssertEqual(item(plates: plates, web: partial).preferredEstimate?.source, .file)
    }
}
