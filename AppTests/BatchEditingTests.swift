import XCTest
import PlateShelfCore
@testable import PlateShelf

final class BatchEditingTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("MakerDock-Batch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }
    @MainActor func models() async throws -> LibraryViewModel {
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        let original = try Data(contentsOf: fixture)
        let a = temp.appendingPathComponent("A.3mf"), b = temp.appendingPathComponent("B.3mf")
        try original.write(to: a); try (original + Data("second archive".utf8)).write(to: b)
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        await vm.importFiles([a,b]); XCTAssertEqual(vm.items.count, 2); return vm
    }
    @MainActor func testMultiSelectionCategoryTrashRestoreAndFavoritesPreserveOriginals() async throws {
        let vm = try await models(); let ids = Set(vm.items.map(\.id))
        vm.selectionMode = true; vm.selectAllVisible(); XCTAssertEqual(vm.selectedIDs, ids)
        vm.selectItem(vm.items[0]); XCTAssertEqual(vm.selectedItems.count, 1)
        vm.selectAllVisible()
        try await vm.saveCategory(CategoryEditRequest(), name: "Tools")
        let category = try XCTUnwrap(vm.categories.first)
        _ = await vm.applyBatch(.category(category.id), ids: ids)
        XCTAssertTrue(vm.items.allSatisfy { $0.categoryID == category.id }); XCTAssertTrue(vm.selectedIDs.isEmpty)
        _ = await vm.applyBatch(.favorite(true), ids: ids)
        _ = await vm.applyBatch(.favorite(true), ids: ids)
        XCTAssertTrue(vm.items.allSatisfy(\.favorite))
        _ = await vm.applyBatch(.trash, ids: ids)
        XCTAssertEqual(vm.trashedItems.count, 2); XCTAssertTrue(vm.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.appendingPathComponent("A.3mf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.appendingPathComponent("B.3mf").path))
        _ = await vm.applyBatch(.restore, ids: ids)
        let reopened = LibraryViewModel(rootOverride: vm.rootURL); await reopened.reload()
        XCTAssertEqual(reopened.items.count, 2); XCTAssertTrue(reopened.items.allSatisfy { $0.categoryID == category.id && $0.favorite })
        reopened.selectionMode = true; reopened.selectAllVisible(); reopened.search = "no match"; reopened.pruneSelection()
        XCTAssertTrue(reopened.selectedIDs.isEmpty)
    }
    @MainActor func testCompletionKeepsEachModelsTimeAndFilamentsAcrossRestartAndMovesArchives() async throws {
        let vm = try await models()
        let drafts = vm.items.enumerated().map { i,item in
            BatchPrintDraft(item: item, details: PrintDetailsDraft(estimate: PrintEstimate(seconds: i == 0 ? 1620 : 600, source: .makerWorld), filaments: [FilamentRecord(name: "PLA Basic", material: "PLA", grams: i == 0 ? 5.74 : 20)]))
        }
        let result = await vm.completeBatch(drafts, note: "Batch notes", moveFiles: true)
        XCTAssertEqual(result.succeeded.count, 2); XCTAssertTrue(result.errors.isEmpty)
        let reopened = LibraryViewModel(rootOverride: vm.rootURL); await reopened.reload()
        for draft in drafts {
            let item = try XCTUnwrap(reopened.items.first { $0.id == draft.id }), run = try XCTUnwrap(item.printRuns.last)
            XCTAssertEqual(run.durationSeconds, draft.details.seconds); XCTAssertEqual(run.durationSource, "makerWorld")
            XCTAssertEqual(run.filaments?.first?.grams, draft.details.records.first?.grams)
            XCTAssertEqual(run.note, "Batch notes"); XCTAssertEqual(item.printRuns.count, 1)
            XCTAssertEqual(item.filePath, "Files/Printed/\(item.id).3mf")
            XCTAssertEqual(try Data(contentsOf: reopened.fileURL(item)), try Data(contentsOf: URL(fileURLWithPath: item.sourcePaths[0])))
        }
    }
    @MainActor func testPartialCompletionReportsFailedItemAndRetryDoesNotDuplicateSuccess() async throws {
        let vm = try await models(); let first = vm.items[0], second = vm.items[1]
        let original = try Data(contentsOf: vm.fileURL(second))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: vm.fileURL(second).path)
        try Data("changed archive".utf8).write(to: vm.fileURL(second))
        let drafts = [first,second].map { BatchPrintDraft(item: $0, details: PrintDetailsDraft(estimate: PrintEstimate(seconds: 60, source: .file))) }
        vm.selectionMode = true; vm.selectAllVisible()
        let result = await vm.completeBatch(drafts, note: "Test", moveFiles: true)
        XCTAssertEqual(result.succeeded, [first.id]); XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(vm.selectedIDs, [second.id]); XCTAssertFalse(vm.isWorking)
        try original.write(to: vm.fileURL(second))
        let retry = await vm.completeBatch(drafts.filter { !result.succeeded.contains($0.id) }, note: "Test", moveFiles: true)
        XCTAssertEqual(retry.succeeded, [second.id]); XCTAssertTrue(vm.items.allSatisfy { $0.printRuns.count == 1 })
    }
}
