import XCTest
import PlateShelfCore
@testable import PlateShelf

final class PrintRecordDetailsTests: XCTestCase {
    func testPrefillPreservesExactEstimateAndManualEditsAreSeparateFromNotes() {
        var d = PrintDetailsDraft(estimate: PrintEstimate(seconds: 1627, source: .makerWorld))
        XCTAssertEqual(d.hours, "0"); XCTAssertEqual(d.minutes, "27")
        XCTAssertEqual(d.seconds, 1627); XCTAssertEqual(d.durationSource, "makerWorld")
        d.hours = "1"; d.minutes = " 5 "
        XCTAssertTrue(d.valid); XCTAssertEqual(d.seconds, 3900); XCTAssertEqual(d.durationSource, "manual")
        d.minutes = "60"; XCTAssertFalse(d.valid)
        d.minutes = "5"; d.hours = "-1"; XCTAssertFalse(d.valid)
        d.hours = "many"; XCTAssertFalse(d.valid)
        d.hours = ""; d.minutes = ""; XCTAssertTrue(d.valid); XCTAssertNil(d.seconds)
        d.filaments = [FilamentDraft(FilamentRecord(material: "PLA", grams: 4.2))]
        d.filaments[0].grams = "4x"; XCTAssertFalse(d.valid)
        d.filaments[0].grams = "-2"; XCTAssertFalse(d.valid)
        d.filaments[0].grams = ""; XCTAssertTrue(d.valid); XCTAssertNil(d.records[0].grams)
    }
    @MainActor func testWebPrefillAndFilamentTotalsDoNotGuessMissingPlateUsage() throws {
        let vm = LibraryViewModel(rootOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: vm.rootURL) }
        let f = FilamentRecord(id: "1", name: "Bambu PLA", material: "PLA", color: "#F5CF00", grams: 2)
        var item = ShelfItem(id: "a", title: "Model", filename: "A.3mf", filePath: "Files/a.3mf",
            plates: [PlateRecord(id: "1", name: "A", estimatedSeconds: 120, filaments: [f]), PlateRecord(id: "2", name: "B", estimatedSeconds: 60, filaments: [f])],
            makerWorldSource: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", estimatedSeconds: 600, plateCount: 2))
        var d = vm.printDetails(item)
        XCTAssertEqual(d.seconds, 600); XCTAssertEqual(d.durationSource, "makerWorld")
        XCTAssertEqual(d.records.count, 1); XCTAssertEqual(d.records[0].grams, 4)
        item.plates[1].filaments = nil
        d = vm.printDetails(item); XCTAssertNil(d.records[0].grams)
    }
    func testLegacyPrintRunDecodesWithoutNewFields() throws {
        let old = Data(#"{"id":"old","date":0,"status":"completed","source":"manual","note":"Keep my note"}"#.utf8)
        let run = try JSONDecoder().decode(PrintRun.self, from: old)
        XCTAssertEqual(run.note, "Keep my note"); XCTAssertNil(run.durationSeconds); XCTAssertNil(run.filaments)
    }
}
