import XCTest
import PlateShelfCore
@testable import PlateShelf

final class OrganizationTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("plateshelf-organization-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }
    func source() throws -> URL {
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        let url = temp.appendingPathComponent("Model.3mf")
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }
    @MainActor func testTrashMovesArchiveAndSurvivesRestartAndWatchedFolderScan() async throws {
        let root = temp.appendingPathComponent("Library"), vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        let original = try source(), bytes = try Data(contentsOf: original)
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first), archived = vm.fileURL(item)
        await vm.saveMetadata(item, tags: "도구", note: "보존할 메모")
        try await vm.saveSource(item, page: "https://makerworld.com/en/models/123-model", profile: "https://makerworld.com/en/models/123-model#profileId-456")
        try await vm.saveCategory(CategoryEditRequest(itemID: item.id), name: "작업 도구")
        _ = await vm.recordPrint(item, status: "completed", note: "출력 메모")
        _ = try vm.workingCopy(for: item)
        let deleted = await vm.trash(item)
        XCTAssertTrue(deleted); XCTAssertTrue(vm.items.isEmpty); XCTAssertEqual(vm.trashedItems.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archived.path))
        XCTAssertEqual(try Data(contentsOf: vm.fileURL(vm.trashedItems[0])), bytes)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertNil(vm.savedProfile("https://makerworld.com/en/models/123-model#profileId-456"))
        let reopened = LibraryViewModel(rootOverride: root); reopened.preferences.folders = [temp.path]
        await reopened.reload(); await reopened.refresh()
        XCTAssertNil(reopened.errorMessage); XCTAssertTrue(reopened.items.isEmpty); XCTAssertEqual(reopened.trashedItems.count, 1)
        let restored = await reopened.restore(item.id)
        XCTAssertTrue(restored)
        let result = try XCTUnwrap(reopened.items.first)
        XCTAssertEqual(result.filePath, item.filePath); XCTAssertEqual(try Data(contentsOf: archived), bytes)
        XCTAssertEqual(result.note, "보존할 메모"); XCTAssertEqual(result.tags, ["도구"])
        XCTAssertEqual(result.printRuns.last?.note, "출력 메모"); XCTAssertNotNil(result.makerWorldSource)
        XCTAssertEqual(reopened.categoryName(result), "작업 도구")
        XCTAssertNil(result.deletedAt); XCTAssertNil(result.trashedFromPath)
    }
    @MainActor func testExplicitImportRestoresWithoutLosingMetadataOrDuplicatingFiles() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        await vm.saveMetadata(item, tags: "보관", note: "유지")
        _ = await vm.trash(item)
        await vm.importFiles([original])
        XCTAssertEqual(vm.items.count, 1); XCTAssertTrue(vm.trashedItems.isEmpty); XCTAssertNil(vm.lastTrashedID)
        XCTAssertEqual(vm.items.first?.note, "유지"); XCTAssertEqual(vm.items.first?.id, item.id)
    }
    @MainActor func testPrintedArchiveRestoresToItsPreviousLocation() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        _ = await vm.recordPrint(item, status: "completed", note: "출력 완료", moveFiles: true)
        let printed = try XCTUnwrap(vm.items.first)
        _ = await vm.trash(printed); _ = await vm.restore(item.id)
        XCTAssertEqual(vm.items.first?.filePath, "Files/Printed/\(item.id).3mf")
        XCTAssertEqual(vm.printedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vm.fileURL(printed).path))
    }
    @MainActor func testCategoryCreateAssignRenameDeletePreservesModelsIncludingTrash() async throws {
        let root = temp.appendingPathComponent("Library"), vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first), bytes = try Data(contentsOf: vm.fileURL(item))
        try await vm.saveCategory(CategoryEditRequest(itemID: item.id), name: "  생활용품  ")
        let category = try XCTUnwrap(vm.categories.first)
        XCTAssertEqual(category.name, "생활용품"); XCTAssertEqual(vm.items.first?.categoryID, category.id)
        vm.filter = .category(category.id); XCTAssertEqual(vm.visibleItems.count, 1)
        try await vm.saveCategory(CategoryEditRequest(category: category), name: "집에서 사용")
        XCTAssertEqual(vm.filterTitle, "집에서 사용"); XCTAssertEqual(vm.visibleItems.count, 1)
        do { try await vm.saveCategory(CategoryEditRequest(), name: "집에서 사용"); XCTFail("Duplicate category accepted") } catch {}
        do { try await vm.saveCategory(CategoryEditRequest(), name: "  "); XCTFail("Blank category accepted") } catch {}
        _ = await vm.trash(item)
        await vm.deleteCategory(category)
        XCTAssertTrue(vm.categories.isEmpty); XCTAssertNil(vm.trashedItems.first?.categoryID)
        _ = await vm.restore(item.id)
        let reopened = LibraryViewModel(rootOverride: root); await reopened.reload(); reopened.filter = .uncategorized
        XCTAssertEqual(reopened.visibleItems.count, 1); XCTAssertEqual(try Data(contentsOf: reopened.fileURL(item)), bytes)
    }
    @MainActor func testIndexConflictRollsTrashBackWithoutOverwritingOtherWriter() async throws {
        let root = temp.appendingPathComponent("Library"), vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        let index = root.appendingPathComponent("index.json"), changed = try Data(contentsOf: root.appendingPathComponent("index.json")) + Data("\n".utf8)
        try changed.write(to: index)
        let deleted = await vm.trash(item)
        XCTAssertFalse(deleted); XCTAssertEqual(vm.items.count, 1); XCTAssertTrue(vm.trashedItems.isEmpty)
        XCTAssertEqual(try Data(contentsOf: index), changed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vm.fileURL(item).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".archive-move.json").path))
    }
    @MainActor func testInterruptedTrashRollsBackAndCommittedMoveStaysDeleted() async throws {
        let root = temp.appendingPathComponent("Library"), vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        let target = "Files/Trash/\(item.id).3mf", moved = root.appendingPathComponent(target)
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        let journal = try JSONSerialization.data(withJSONObject: ["itemID": item.id, "from": item.filePath, "to": target])
        try journal.write(to: root.appendingPathComponent(".archive-move.json"))
        try FileManager.default.moveItem(at: vm.fileURL(item), to: moved)
        let recovered = LibraryViewModel(rootOverride: root); await recovered.reload()
        XCTAssertNil(recovered.errorMessage); XCTAssertEqual(recovered.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.fileURL(item).path))
        _ = await recovered.trash(item)
        try journal.write(to: root.appendingPathComponent(".archive-move.json"))
        let committed = LibraryViewModel(rootOverride: root); await committed.reload()
        XCTAssertNil(committed.errorMessage); XCTAssertTrue(committed.items.isEmpty); XCTAssertEqual(committed.trashedItems.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    }
    @MainActor func testRestoreCollisionPreservesBothFilesAndDeletedState() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        _ = await vm.trash(item)
        let collision = Data("keep this unrelated file".utf8); try collision.write(to: vm.fileURL(item))
        let restored = await vm.restore(item.id)
        XCTAssertFalse(restored); XCTAssertTrue(vm.items.isEmpty); XCTAssertEqual(vm.trashedItems.count, 1)
        XCTAssertEqual(try Data(contentsOf: vm.fileURL(item)), collision)
        XCTAssertEqual(try Data(contentsOf: vm.fileURL(vm.trashedItems[0])), try Data(contentsOf: original))
    }
    @MainActor func testFilterSynchronizationKeepsExplicitBrowserSelection() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        let first = ShelfItem(id: String(repeating: "a", count: 64), title: "First", filename: "A.3mf", filePath: "Files/a.3mf")
        let target = ShelfItem(id: String(repeating: "b", count: 64), title: "Target", filename: "B.3mf", filePath: "Files/b.3mf")
        vm.items = [first, target]; vm.sort = .name
        vm.filter = .makerWorld; vm.showLibraryItem(target.id); vm.syncSelection()
        XCTAssertEqual(vm.selected?.id, target.id)
        vm.filter = .trash; vm.syncSelection(); XCTAssertNil(vm.selected)
    }
    @MainActor func testCategoryCreationAndAssignmentIsAtomicForMissingItem() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        do { try await vm.saveCategory(CategoryEditRequest(itemID: "missing"), name: "도구"); XCTFail("Missing model accepted") } catch {}
        await vm.reload(); XCTAssertTrue(vm.categories.isEmpty)
    }
}
