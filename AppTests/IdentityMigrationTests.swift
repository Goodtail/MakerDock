import XCTest
import PlateShelfCore
@testable import PlateShelf

final class IdentityMigrationTests: XCTestCase {
    var temp: URL!
    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("makerdock-upgrade-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }

    @MainActor func testUpgradePreservesTrashPrintsMetadataPreviewsAndCachedFiles() async throws {
        let old = temp.appendingPathComponent("com.ninepiece.app.mac.plateshelf")
        let new = temp.appendingPathComponent("com.ninepiece.app.mac.makerdock")
        let vm = LibraryViewModel(rootOverride: old)
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        let downloads = old.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let local = downloads.appendingPathComponent("Cached.3mf")
        try FileManager.default.copyItem(at: fixture, to: local)
        await vm.importFiles([local])
        let item = try XCTUnwrap(vm.items.first), note = "Do not rewrite this note: " + old.path
        await vm.saveMetadata(item, tags: "도구, 보관", note: note)
        try await vm.saveSource(item, page: "https://makerworld.com/en/models/123-model", profile: "https://makerworld.com/en/models/123-model#profileId-456")
        try await vm.saveCategory(CategoryEditRequest(itemID: item.id), name: "작업 도구")
        _ = await vm.recordPrint(item, status: "completed", note: "완료 메모", moveFiles: true)
        let printed = try XCTUnwrap(vm.items.first)
        let working = try vm.workingCopy(for: printed)
        let didTrash = await vm.trash(printed); XCTAssertTrue(didTrash)
        vm.preferences.archivePath = old.appendingPathComponent("StudioInbox").path
        vm.preferences.folders = ["/external/models", old.path + "-unrelated", downloads.path]
        vm.savePreferences()
        let originalIndex = try Data(contentsOf: old.appendingPathComponent("index.json"))
        let originalPreferences = try Data(contentsOf: old.appendingPathComponent("preferences.json"))
        let bytes = try Data(contentsOf: fixture)
        try LibraryMigration.copyIfNeeded(from: old, to: new)
        let reopened = LibraryViewModel(rootOverride: new); await reopened.reload()
        XCTAssertNil(reopened.errorMessage); XCTAssertTrue(reopened.items.isEmpty)
        let migrated = try XCTUnwrap(reopened.trashedItems.first)
        XCTAssertEqual(migrated.id, item.id); XCTAssertEqual(migrated.note, note)
        XCTAssertEqual(migrated.printRuns.last?.note, "완료 메모")
        XCTAssertEqual(migrated.makerWorldSource?.profileURL, "https://makerworld.com/en/models/123-model#profileId-456")
        XCTAssertEqual(reopened.categoryName(migrated), "작업 도구")
        XCTAssertEqual(migrated.sourcePaths, [new.appendingPathComponent("Downloads/Cached.3mf").path])
        XCTAssertEqual(reopened.preferences.archivePath, new.appendingPathComponent("StudioInbox").path)
        XCTAssertEqual(reopened.preferences.folders, ["/external/models", old.path + "-unrelated", new.appendingPathComponent("Downloads").path])
        XCTAssertEqual(try Data(contentsOf: reopened.fileURL(migrated)), bytes)
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("Downloads/Cached.3mf")), bytes)
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent(String(working.path.dropFirst(old.path.count + 1)))), bytes)
        if let preview = migrated.thumbnailPath {
            XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent(preview)), try Data(contentsOf: old.appendingPathComponent(preview)))
        }
        XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("index.json")), originalIndex)
        XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("preferences.json")), originalPreferences)
        let restored = await reopened.restore(item.id); XCTAssertTrue(restored)
        XCTAssertEqual(reopened.items.first?.filePath, "Files/Printed/\(item.id).3mf")
        XCTAssertEqual(reopened.printedCount, 1)
    }

    func testMigrationNeverOverwritesExistingDestinationOrPublishesCorruptCopy() throws {
        let old = temp.appendingPathComponent("old"), new = temp.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: old.appendingPathComponent("index.json"))
        XCTAssertThrowsError(try LibraryMigration.copyIfNeeded(from: old, to: new))
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: temp.path).contains { $0.hasPrefix(".makerdock-upgrade-") })
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        let sentinel = new.appendingPathComponent("index.json"), bytes = Data("keep newer library".utf8)
        try bytes.write(to: sentinel)
        try LibraryMigration.copyIfNeeded(from: old, to: new)
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
        let missing = temp.appendingPathComponent("missing")
        try LibraryMigration.copyIfNeeded(from: missing, to: temp.appendingPathComponent("unused"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("unused").path))
    }

    func testPendingFileMoveIsLeftForOldAppToRecover() throws {
        let old = temp.appendingPathComponent("old"), new = temp.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let journal = old.appendingPathComponent(".print-move.json"), bytes = Data("pending".utf8)
        try bytes.write(to: journal)
        XCTAssertThrowsError(try LibraryMigration.copyIfNeeded(from: old, to: new))
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
        XCTAssertEqual(try Data(contentsOf: journal), bytes)
    }

    func testVariantsAndPreferencesRemainSeparateAndMigrationIsOneTime() throws {
        XCTAssertEqual(AppIdentity.legacyIdentifier(for: "com.ninepiece.app.mac.makerdock"), "com.ninepiece.app.mac.plateshelf")
        XCTAssertEqual(AppIdentity.legacyIdentifier(for: "com.ninepiece.app.mac.makerdock.dev"), "com.ninepiece.app.mac.plateshelf.dev")
        XCTAssertNil(AppIdentity.legacyIdentifier(for: "com.other.app"))
        let legacy = "migration-old-" + UUID().uuidString, current = "migration-new-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: current))
        defer { defaults.removePersistentDomain(forName: legacy); defaults.removePersistentDomain(forName: current) }
        defaults.setPersistentDomain(["browser.preferStored": true, "browser.lastModel": "https://makerworld.com/ko/models/123"], forName: legacy)
        defaults.setPersistentDomain(["browser.preferStored": false], forName: current)
        AppIdentity.migrateDefaults(from: legacy, to: current, defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: "browser.preferStored"))
        XCTAssertEqual(defaults.string(forKey: "browser.lastModel"), "https://makerworld.com/ko/models/123")
        defaults.removeObject(forKey: "browser.lastModel")
        AppIdentity.migrateDefaults(from: legacy, to: current, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "browser.lastModel"))
    }

    func testOldAndNewLinksPreserveSignedURLAndProvenanceIdentically() throws {
        let raw = "plateshelf://open?url=https%3A%2F%2Fpublic-cdn.bblmw.com%2Fmodel.3mf%3FSignature%3DA%2BB%252BC&name=Cube+%2B+Dock.3mf&action=import&source=https%3A%2F%2Fmakerworld.com%2Fen%2Fmodels%2F123-model"
        let old = try MakerWorldLinkPolicy.parse(XCTUnwrap(URL(string: raw)))
        let new = try MakerWorldLinkPolicy.parse(XCTUnwrap(URL(string: raw.replacingOccurrences(of: "plateshelf://", with: "makerdock://"))))
        XCTAssertEqual(new.downloadURL, old.downloadURL); XCTAssertEqual(new.displayName, "Cube + Dock.3mf")
        XCTAssertEqual(new.provenance?.pageURL, old.provenance?.pageURL)
        XCTAssertEqual(new.openStudio, old.openStudio); XCTAssertFalse(new.openStudio)
    }

    func testHandlerMigrationPreservesOfficialStudioAndOtherVariant() {
        let production = "com.ninepiece.app.mac.makerdock", development = production + ".dev"
        XCTAssertTrue(AppIdentity.shouldMigrateLink(owner: "com.ninepiece.app.mac.plateshelf", to: production))
        XCTAssertTrue(AppIdentity.shouldMigrateLink(owner: "com.ninepiece.app.mac.plateshelf.dev", to: development))
        XCTAssertFalse(AppIdentity.shouldMigrateLink(owner: "com.ninepiece.app.mac.plateshelf.dev", to: production))
        XCTAssertFalse(AppIdentity.shouldMigrateLink(owner: "com.ninepiece.app.mac.plateshelf", to: development))
        XCTAssertFalse(AppIdentity.shouldMigrateLink(owner: "com.bambulab.bambu-studio", to: production))
        XCTAssertFalse(AppIdentity.shouldMigrateLink(owner: nil, to: production))
        XCTAssertFalse(AppIdentity.shouldMigrateLink(owner: development, to: production))
    }
}
