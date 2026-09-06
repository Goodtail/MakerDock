import XCTest
import PlateShelfCore
@testable import PlateShelf

final class IntegrationTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws { temp = FileManager.default.temporaryDirectory.appendingPathComponent("plateshelf-app-tests-" + UUID().uuidString); try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }
    func fixture() throws -> URL {
        let bundle = Bundle(for: IntegrationTests.self)
        let source = try XCTUnwrap(bundle.url(forResource: "Fixture", withExtension: "3mf"))
        let copy = temp.appendingPathComponent("Fixture.3mf")
        if !FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.copyItem(at: source, to: copy) }
        return copy
    }
    @MainActor func testImportSaveReopenAndWorkingCopy() async throws {
        let root = temp.appendingPathComponent("Library")
        let vm = LibraryViewModel(rootOverride: root)
        let original = try fixture(), originalData = try Data(contentsOf: original)
        await vm.importFiles([original])
        XCTAssertNil(vm.errorMessage); XCTAssertEqual(vm.items.count, 1)
        let item = try XCTUnwrap(vm.items.first)
        await vm.saveMetadata(item, tags: "AMS, test, AMS", note: "remember this")
        let working = try vm.workingCopy(for: item)
        XCTAssertNotEqual(working, vm.fileURL(item))
        let attrs = try FileManager.default.attributesOfItem(atPath: working.path)
        XCTAssertNotEqual(((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o200, 0)
        try Data("edited working bytes".utf8).write(to: working)
        XCTAssertEqual(try Data(contentsOf: vm.fileURL(item)), originalData)
        XCTAssertEqual(try Data(contentsOf: original), originalData)
        XCTAssertEqual(try vm.workingCopy(for: item), working)
        XCTAssertEqual(try Data(contentsOf: working), Data("edited working bytes".utf8))
        let reopened = LibraryViewModel(rootOverride: root); await reopened.reload()
        XCTAssertEqual(reopened.items.first?.tags, ["AMS", "test"])
        XCTAssertEqual(reopened.items.first?.note, "remember this")
        await reopened.importFiles([original]); XCTAssertEqual(reopened.items.count, 1)
    }
    @MainActor func testInboxTransitionsDoNotClaimCompletion() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        let source = try fixture(); await vm.importFiles([source])
        let item = try XCTUnwrap(vm.items.first), eventID = UUID().uuidString
        let inbox = temp.appendingPathComponent("Inbox"), event = inbox.appendingPathComponent(eventID)
        try FileManager.default.createDirectory(at: event, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: event.appendingPathComponent("print.3mf"))
        vm.preferences.archivePath = inbox.path
        func write(_ state: String, hash: String) throws {
            let manifest: [String: Any] = ["schema_version":1,"event_type":"studio_submission","event_id":eventID,"created_at":"2026-09-07T00:00:00Z","submission_state":state,"project_name":"fixture", "artifacts":[["role":"gcode_3mf","relative_path":"print.3mf","sha256":hash]]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: event.appendingPathComponent("manifest.json"), options:.atomic)
        }
        try write("prepared", hash: item.id); await vm.scanStudioInbox()
        XCTAssertEqual(vm.items.first?.printRuns.count, 1)
        XCTAssertEqual(vm.items.first?.printRuns.first?.status, "prepared")
        try write("submitted", hash: item.id); await vm.scanStudioInbox()
        XCTAssertEqual(vm.items.first?.printRuns.count, 1)
        XCTAssertEqual(vm.items.first?.printRuns.first?.status, "submitted")
        XCTAssertEqual(vm.printedCount, 0)
        await vm.recordPrint(item, status: "completed", note: "manually verified")
        XCTAssertEqual(vm.printedCount, 1)
        try write("completed", hash: item.id); await vm.scanStudioInbox()
        XCTAssertEqual(vm.items.first?.printRuns.count, 2)
        XCTAssertTrue(vm.archiveStatus.contains("상태"))
        try write("submitted", hash: String(repeating: "0", count:64)); await vm.scanStudioInbox()
        XCTAssertEqual(vm.items.first?.printRuns.count, 2)
        XCTAssertTrue(vm.archiveStatus.contains("해시"))
    }
    @MainActor func testOldPreferencesDecodeAndSearch() async throws {
        let root=temp.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{\"folders\":[],\"studioPath\":\"/Applications/BambuStudio.app\",\"archivePath\":\"\",\"automaticScan\":false}".utf8).write(to: root.appendingPathComponent("preferences.json"))
        let vm=LibraryViewModel(rootOverride: root)
        XCTAssertNil(vm.errorMessage)
        await vm.importFiles([try fixture()])
        vm.search="Integration"; XCTAssertEqual(vm.visibleItems.count,1)
        vm.search="no match"; XCTAssertEqual(vm.visibleItems.count,0)
        vm.search=""; vm.filter = .printed; XCTAssertEqual(vm.visibleItems.count,0)
    }
    @MainActor func testConcurrentImportsQueueWithoutDroppingFiles() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        let a = try fixture(), b = temp.appendingPathComponent("Second.3mf")
        try FileManager.default.copyItem(at: a, to: b)
        async let first: Void = vm.importFiles([a])
        async let second: Void = vm.importFiles([b])
        _ = await (first, second)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(Set(vm.items.first?.sourcePaths ?? []), Set([a.path, b.path]))
        XCTAssertFalse(vm.isWorking)
    }
    @MainActor func testSourceLinkPersistsAndRejectsDownloadAddress() async throws {
        let root = temp.appendingPathComponent("Library"), vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        await vm.importFiles([try fixture()])
        let item = try XCTUnwrap(vm.items.first)
        try await vm.saveSource(item, page: "https://makerworld.com/en/models/123-example?utm_source=test", profile: "https://makerworld.com/en/models/123-example#profileId-456")
        let reopened = LibraryViewModel(rootOverride: root); await reopened.reload()
        XCTAssertEqual(reopened.items.first?.makerWorldSource?.pageURL, "https://makerworld.com/en/models/123-example")
        XCTAssertEqual(reopened.items.first?.makerWorldSource?.profileURL, "https://makerworld.com/en/models/123-example#profileId-456")
        do { try await vm.saveSource(item, page: "https://makerworld.com/assets/secret.3mf?token=secret", profile: ""); XCTFail("Asset URL must not become source link") } catch {}
        XCTAssertEqual(vm.items.first?.makerWorldSource?.profileURL, "https://makerworld.com/en/models/123-example#profileId-456")
    }
    @MainActor func testBrowserSnapshotKeepsProfileTotalsSeparateFromFile() async throws {
        let vm = LibraryViewModel(rootOverride: temp.appendingPathComponent("Library"))
        await vm.importFiles([try fixture()])
        let item = try XCTUnwrap(vm.items.first)
        let source = CapturedMakerWorldSource(pageURL: "https://makerworld.com/en/models/123-example", profileURL: "https://makerworld.com/en/models/123-example#profileId-456", capturedAt: Date(), title: "Observed model", profileTitle: "Observed profile", estimatedSeconds: 42_120, plateCount: 7, plates: nil)
        try await vm.applyCapturedSource(source, itemID: item.id)
        await vm.reload()
        XCTAssertEqual(vm.items.first?.makerWorldSource?.estimatedSeconds, 42_120)
        XCTAssertEqual(vm.items.first?.makerWorldSource?.plateCount, 7)
        XCTAssertNil(vm.items.first?.makerWorldSource?.plates)
        XCTAssertEqual(vm.items.first?.estimatedSeconds, 3_600)
        await vm.importFiles([try fixture()])
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.makerWorldSource?.estimatedSeconds, 42_120)
    }
}
