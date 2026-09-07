import XCTest
import PlateShelfCore
@testable import PlateShelf

final class PrintCompletionTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("plateshelf-completion-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }
    func source(_ name: String = "Model.3mf") throws -> URL {
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        let file = temp.appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixture, to: file)
        return file
    }
    @MainActor func testCompletionMovesSelectedSourceAndArchiveAndPreservesMetadataAfterRescan() async throws {
        let root = temp.appendingPathComponent("Library"), vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        let original = try source(), duplicate = try source("Duplicate.3mf"), bytes = try Data(contentsOf: original)
        await vm.importFiles([original, duplicate])
        let item = try XCTUnwrap(vm.items.first), oldArchive = vm.fileURL(item)
        await vm.saveMetadata(item, tags: "실사용", note: "모델 메모 유지")
        try await vm.saveSource(item, page: "https://makerworld.com/en/models/123-model", profile: "https://makerworld.com/en/models/123-model#profileId-456")
        let destination = temp.appendingPathComponent("출력 완료")
        let success = await vm.recordPrint(item, status: "completed", note: "PLA, 서포트 제거 후 정상", moveFiles: true, sourceURL: original, directoryURL: destination)
        XCTAssertTrue(success); XCTAssertNil(vm.errorMessage); XCTAssertEqual(vm.printedCount, 1)
        let marked = try XCTUnwrap(vm.items.first), moved = destination.appendingPathComponent(original.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: oldArchive.path))
        XCTAssertEqual(try Data(contentsOf: moved), bytes); XCTAssertEqual(try Data(contentsOf: duplicate), bytes)
        XCTAssertEqual(try Data(contentsOf: vm.fileURL(marked)), bytes)
        XCTAssertEqual(marked.filePath, "Files/Printed/\(item.id).3mf")
        XCTAssertEqual(marked.printRuns.last?.note, "PLA, 서포트 제거 후 정상")
        XCTAssertEqual(marked.printRuns.last?.movedTo, moved.path)
        XCTAssertEqual(Set(marked.sourcePaths), Set([moved.path, duplicate.path]))
        let reopened = LibraryViewModel(rootOverride: root); await reopened.reload()
        await reopened.importFiles([moved, duplicate])
        let reloaded = try XCTUnwrap(reopened.items.first)
        XCTAssertEqual(reopened.items.count, 1); XCTAssertEqual(reopened.printedCount, 1)
        XCTAssertEqual(reloaded.tags, ["실사용"]); XCTAssertEqual(reloaded.note, "모델 메모 유지")
        XCTAssertEqual(reloaded.makerWorldSource?.profileURL, "https://makerworld.com/en/models/123-model#profileId-456")
        XCTAssertEqual(reloaded.filePath, marked.filePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldArchive.path))
        XCTAssertEqual(try Data(contentsOf: reopened.workingCopy(for: reloaded)), bytes)
    }
    @MainActor func testCollisionRenamesWithoutOverwritingAndRepeatDoesNotNestFolder() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        let destination = vm.printDestination(for: original)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let occupied = destination.appendingPathComponent(original.lastPathComponent), otherBytes = Data("keep existing file".utf8)
        try otherBytes.write(to: occupied)
        let success = await vm.recordPrint(item, status: "completed", note: "첫 출력", moveFiles: true, sourceURL: original, directoryURL: destination)
        XCTAssertTrue(success); XCTAssertEqual(try Data(contentsOf: occupied), otherBytes)
        let marked = try XCTUnwrap(vm.items.first), moved = try XCTUnwrap(marked.printRuns.last?.movedTo).asFileURL
        XCTAssertEqual(moved.lastPathComponent, "Model (2).3mf")
        XCTAssertEqual(vm.printDestination(for: moved), destination)
        let repeated = await vm.recordPrint(marked, status: "completed", note: "재출력", moveFiles: true, sourceURL: moved, directoryURL: destination)
        XCTAssertTrue(repeated); XCTAssertEqual(vm.items.first?.printRuns.count, 2)
        XCTAssertEqual(try Data(contentsOf: occupied), otherBytes)
    }
    @MainActor func testEditedSourceIsNotMovedOrMarkedAndFailedRecordDoesNotMove() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        let changed = Data("saved user edits".utf8); try changed.write(to: original)
        let result = await vm.recordPrint(item, status: "completed", note: "must fail", moveFiles: true, sourceURL: original, directoryURL: temp.appendingPathComponent("Completed"))
        XCTAssertFalse(result); XCTAssertEqual(vm.printedCount, 0); XCTAssertEqual(vm.items.first?.printRuns.count, 0)
        XCTAssertEqual(try Data(contentsOf: original), changed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vm.fileURL(item).path))
        let failed = await vm.recordPrint(item, status: "failed", note: "첫 레이어 실패", moveFiles: true)
        XCTAssertTrue(failed); XCTAssertEqual(vm.printedCount, 0); XCTAssertEqual(vm.items.first?.filePath, item.filePath)
    }
    @MainActor func testIndexConflictRollsBackMovesAndDoesNotOverwriteOtherWriter() async throws {
        let root = temp.appendingPathComponent("Library"), vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        let index = root.appendingPathComponent("index.json")
        let updated = try Data(contentsOf: index) + Data("\n".utf8)
        try updated.write(to: index)
        let result = await vm.recordPrint(item, status: "completed", note: "not committed", moveFiles: true, sourceURL: original, directoryURL: temp.appendingPathComponent("Completed"))
        XCTAssertFalse(result); XCTAssertEqual(try Data(contentsOf: index), updated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vm.fileURL(item).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".print-move.json").path))
    }
    @MainActor func testInterruptedMoveRecoversBeforeOpeningLibrary() async throws {
        let root = temp.appendingPathComponent("Library"), vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library")), original = try source()
        await vm.importFiles([original]); let item = try XCTUnwrap(vm.items.first)
        let archived = vm.fileURL(item), moved = root.appendingPathComponent("Files/Printed/\(item.id).3mf")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        let journal: [String: Any] = ["itemID": item.id, "runID": UUID().uuidString,
                                      "moves": [["from": archived.path, "to": moved.path]]]
        try JSONSerialization.data(withJSONObject: journal).write(to: root.appendingPathComponent(".print-move.json"))
        try FileManager.default.moveItem(at: archived, to: moved)
        let reopened = LibraryViewModel(rootOverride: root); await reopened.reload()
        XCTAssertNil(reopened.errorMessage); XCTAssertEqual(reopened.printedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
    }
}
private extension String { var asFileURL: URL { URL(fileURLWithPath: self) } }
