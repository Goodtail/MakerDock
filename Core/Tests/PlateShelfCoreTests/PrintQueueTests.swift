import XCTest
@testable import PlateShelfCore

final class PrintQueuePlanTests: XCTestCase {
    func jobs(_ values: [Double?]) -> [PrintQueueJob] {
        values.enumerated().map { PrintQueueJob(id: String($0.offset), seconds: $0.element) }
    }
    func testSequentialWindowIncludesOnlyGapsBetweenPrints() {
        let plan = PrintQueuePlan(jobs: jobs([3600, 1800, 600]), availableSeconds: 5700, changeoverSeconds: 300)
        XCTAssertEqual(plan.rows.map(\.startOffset), [0, 3900, 6000])
        XCTAssertEqual(plan.rows.map(\.endOffset), [3600, 5700, 6600])
        XCTAssertEqual(plan.rows.map(\.fits), [true, true, false])
        XCTAssertEqual(plan.fitsCount, 2)
        XCTAssertEqual(plan.remainingSeconds, 0)
        XCTAssertEqual(plan.totalSeconds, 6600)
    }
    func testUnknownDurationBlocksFollowingTimeSlotsWithoutCountingAsZero() {
        let plan = PrintQueuePlan(jobs: jobs([600, nil, 300]), availableSeconds: 1800, changeoverSeconds: 60)
        XCTAssertEqual(plan.fitsCount, 1)
        XCTAssertEqual(plan.knownSeconds, 900)
        XCTAssertEqual(plan.unknownCount, 1)
        XCTAssertNil(plan.totalSeconds)
        XCTAssertNil(plan.rows[1].endOffset)
        XCTAssertNil(plan.rows[2].startOffset)
        XCTAssertEqual(plan.remainingSeconds, 1200)
    }
    func testFittingOrderPreservesPriorityAndEveryDeferredModel() {
        let input = jobs([5000, 600, nil, 300, 60])
        let order = PrintQueuePlan.fittingOrder(jobs: input, availableSeconds: 960, changeoverSeconds: 60)
        XCTAssertEqual(order, ["1", "3", "0", "2", "4"])
        XCTAssertEqual(Set(order), Set(input.map(\.id)))
        XCTAssertEqual(PrintQueuePlan.fittingOrder(jobs: input, availableSeconds: 0, changeoverSeconds: 60), input.map(\.id))
    }
    func testInvalidDurationsAndEmptyQueue() {
        for value in [Double.nan, .infinity, -1, 0, 31_536_001] { XCTAssertNil(PrintQueuePlan.duration(value)) }
        let empty = PrintQueuePlan(jobs: [], availableSeconds: 600)
        XCTAssertEqual(empty.totalSeconds, 0)
        XCTAssertEqual(empty.remainingSeconds, 600)
        XCTAssertEqual(PrintQueuePlan(jobs: jobs([600]), availableSeconds: .infinity).fitsCount, 0)
    }
}

extension LibraryRepositoryTests {
    func testQueuePersistenceDuplicatesOverridesAndRemovalKeepModels() async throws {
        let repo = try repository()
        let a = try await repo.importFile(at: fixture()).item
        let b = try await repo.importFile(at: fixture("B.3mf", changes: ["Metadata/plate_1.gcode": Data("G28\nG1 X2".utf8)])).item
        let count = try await repo.enqueue(itemIDs: [a.id, b.id, a.id])
        XCTAssertEqual(count, 2)
        try await repo.setQueueDuration(itemID: b.id, seconds: 900)
        try await repo.reorderQueue(itemIDs: [b.id, a.id])
        let reopened = try LibraryRepository(rootURL: repo.rootURL)
        let queue = await reopened.printQueue()
        XCTAssertEqual(queue.map(\.id), [b.id, a.id])
        XCTAssertEqual(queue.first?.durationSeconds, 900)
        do { try await reopened.reorderQueue(itemIDs: [a.id, a.id]); XCTFail("Invalid permutation accepted") } catch {}
        do { try await reopened.setQueueDuration(itemID: a.id, seconds: -1); XCTFail("Invalid time accepted") } catch {}
        try await reopened.removeFromQueue(itemIDs: [a.id])
        let models = await reopened.items(), pending = await reopened.printQueue()
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(pending.map(\.id), [b.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.rootURL.appendingPathComponent(a.filePath).path))
    }
    func testCompletedRunRemovesPendingButFailureAndReplayKeepIt() async throws {
        let repo = try repository(), item = try await repo.importFile(at: fixture()).item
        try await repo.enqueue(itemIDs: [item.id])
        try await repo.appendRun(itemID: item.id, run: PrintRun(id: "job", status: "failed", source: "manual"))
        var queue = await repo.printQueue(); XCTAssertEqual(queue.count, 1)
        let completed = PrintRun(id: "job", status: "completed", source: "manual")
        try await repo.appendRun(itemID: item.id, run: completed)
        queue = await repo.printQueue(); XCTAssertTrue(queue.isEmpty)
        try await repo.enqueue(itemIDs: [item.id])
        try await repo.appendRun(itemID: item.id, run: completed)
        queue = await repo.printQueue(); XCTAssertEqual(queue.count, 1)
        try await repo.trash(itemID: item.id)
        try await repo.restore(itemID: item.id)
        queue = await repo.printQueue(); XCTAssertTrue(queue.isEmpty)
    }
    func testOldIndexLoadsAndConflictingCompletionRollsBackQueueAndFiles() async throws {
        let repo = try repository(), item = try await repo.importFile(at: fixture()).item
        let index = repo.rootURL.appendingPathComponent("index.json")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
        old.removeValue(forKey: "printQueue")
        try JSONSerialization.data(withJSONObject: old).write(to: index, options: .atomic)
        let reopened = try LibraryRepository(rootURL: repo.rootURL)
        let initialQueue = await reopened.printQueue(); XCTAssertTrue(initialQueue.isEmpty)
        try await reopened.enqueue(itemIDs: [item.id])
        let competing = try Data(contentsOf: index) + Data("\n".utf8)
        try competing.write(to: index)
        do { _ = try await reopened.completePrint(itemID: item.id, note: "must roll back"); XCTFail("Conflict accepted") } catch {}
        let queue = await reopened.printQueue(), models = await reopened.items()
        XCTAssertEqual(queue.map(\.id), [item.id]); XCTAssertTrue(models[0].printRuns.isEmpty)
        XCTAssertEqual(try Data(contentsOf: index), competing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.rootURL.appendingPathComponent(item.filePath).path))
        let current = try LibraryRepository(rootURL: repo.rootURL)
        _ = try await current.completePrint(itemID: item.id, note: "done", durationSeconds: 1200)
        let final = try LibraryRepository(rootURL: repo.rootURL)
        let finalQueue = await final.printQueue(), finalModels = await final.items()
        XCTAssertTrue(finalQueue.isEmpty)
        XCTAssertEqual(finalModels[0].printRuns.last?.note, "done")
        XCTAssertEqual(finalModels[0].filePath, "Files/Printed/\(item.id).3mf")
    }
}
