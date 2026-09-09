import XCTest
import PlateShelfCore
@testable import PlateShelf

final class PrintQueueTests: XCTestCase {
    func item(_ id: String, file: Double? = nil, web: Double? = nil) -> ShelfItem {
        ShelfItem(id: id, title: id, filename: id + ".3mf", filePath: "Files/\(id).3mf",
                  plates: [PlateRecord(id: "1", name: "Plate", estimatedSeconds: file)],
                  makerWorldSource: web.map { MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", estimatedSeconds: $0) })
    }
    func testDurationSortingUsesWebPriorityAndUnknownLastInBothDirections() {
        let values = [item("unknown"), item("short", file: 9000, web: 300), item("long", file: 3600), item("invalid", web: -1)]
        XCTAssertEqual(values.sorted { ShelfSort.shortest.precedes($0, $1) }.map(\.id), ["short", "long", "invalid", "unknown"])
        XCTAssertEqual(values.sorted { ShelfSort.longest.precedes($0, $1) }.map(\.id), ["long", "short", "invalid", "unknown"])
    }
    @MainActor func testQueueEstimateOverrideAndCompletionSurviveReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MakerDock-QueueTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = LibraryViewModel(rootOverride: root)
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        await vm.importFiles([fixture])
        let item = try XCTUnwrap(vm.items.first)
        let added = await vm.enqueue([item, item]); XCTAssertEqual(added, 1)
        let saved = await vm.setQueueDuration(item.id, seconds: 900); XCTAssertTrue(saved)
        let reopened = LibraryViewModel(rootOverride: root); await reopened.reload()
        XCTAssertEqual(reopened.queueSeconds(item), 900)
        reopened.filter = .queue; reopened.syncSelection()
        XCTAssertNil(reopened.selectionID)
        let completed = await reopened.recordPrint(item, status: "completed", note: "Queue record", moveFiles: false, durationSeconds: 840, durationSource: "manual")
        XCTAssertTrue(completed)
        let final = LibraryViewModel(rootOverride: root); await final.reload()
        XCTAssertTrue(final.printQueue.isEmpty)
        XCTAssertEqual(final.items.first?.printRuns.last?.durationSeconds, 840)
        XCTAssertEqual(final.items.first?.printRuns.last?.note, "Queue record")
    }
}
