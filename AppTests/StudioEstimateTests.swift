import XCTest
import PlateShelfCore
@testable import PlateShelf

final class StudioEstimateTests: XCTestCase {
    @MainActor func testQueueAutomaticallyCalculatesSeriallyAndPersistsGlobalEstimates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let a = ShelfItem(id: "a", title: "A", filename: "a.3mf", filePath: "Files/a.3mf", plates: [PlateRecord(id: "1", name: "Plate")])
        let b = ShelfItem(id: "b", title: "B", filename: "b.3mf", filePath: "Files/b.3mf", plates: a.plates)
        let known = ShelfItem(id: "known", title: "Known", filename: "known.3mf", filePath: "Files/known.3mf", plates: a.plates, makerWorldSource: MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", estimatedSeconds: 400))
        model.items = [a, b, known]
        model.printQueue = [a, b, known].map { PrintQueueEntry(id: $0.id) }
        var calls: [String] = [], active = 0, maximum = 0
        model.estimateRunnerOverride = { item, _, _, config in
            active += 1; maximum = max(maximum, active); calls.append(item.id)
            await Task.yield()
            active -= 1
            return StudioEstimateRecord(itemID: item.id, configurationKey: config.key, machine: config.machine, process: config.process, studioVersion: config.studioVersion, calculatedAt: Date(), plates: [PlateRecord(id: "1", name: "Plate", estimatedSeconds: 1200)])
        }
        model.estimateConfiguration = config()
        model.scheduleQueueEstimates(); model.scheduleQueueEstimates()
        await model.estimateTask?.value
        XCTAssertEqual(calls, ["a", "b"]); XCTAssertEqual(maximum, 1)
        XCTAssertEqual(model.displayedEstimate(a)?.seconds, 1200)
        XCTAssertEqual(model.displayedEstimate(a, plate: a.plates[0])?.seconds, 1200)
        XCTAssertEqual(model.queueSeconds(a), 1200)
        let reopened = LibraryViewModel(rootOverride: root); reopened.estimateConfiguration = config()
        XCTAssertEqual(reopened.displayedEstimate(b)?.seconds, 1200)
        model.scheduleQueueEstimates(); XCTAssertNil(model.estimateTask)
    }
    @MainActor func testFailedAutomaticEstimateWaitsForExplicitRetryAndConfigChangeInvalidatesCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let a = ShelfItem(id: "a", title: "A", filename: "a.3mf", filePath: "Files/a.3mf", plates: [PlateRecord(id: "1", name: "Plate")])
        model.items = [a]; model.printQueue = [PrintQueueEntry(id: a.id)]
        var calls = 0
        model.estimateRunnerOverride = { item, _, _, config in
            calls += 1
            if calls == 1 { throw NSError(domain: "test", code: 1) }
            return StudioEstimateRecord(itemID: item.id, configurationKey: config.key, machine: config.machine, process: config.process, studioVersion: config.studioVersion, calculatedAt: Date(), plates: [PlateRecord(id: "1", name: "Plate", estimatedSeconds: 100)])
        }
        model.estimateConfiguration = config(); await model.estimateTask?.value
        XCTAssertNotNil(model.estimateErrors[a.id])
        model.scheduleQueueEstimates(); await model.estimateTask?.value
        XCTAssertEqual(calls, 1)
        model.calculateEstimate(a); await model.estimateTask?.value
        XCTAssertEqual(calls, 2); XCTAssertNil(model.estimateErrors[a.id])
        model.estimateConfiguration = config(machine: "B"); XCTAssertNil(model.savedEstimate(a))
        await model.estimateTask?.value
        XCTAssertEqual(calls, 3); XCTAssertEqual(model.savedEstimate(a)?.machine, "B")
    }
    func testInheritedPresetResolutionAndCycles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"name":"base","speed":"100","height":"0.2"}"#.utf8).write(to: root.appendingPathComponent("base.json"))
        try Data(#"{"name":"child","inherits":"base","speed":"200"}"#.utf8).write(to: root.appendingPathComponent("child.json"))
        let result = try StudioPresetCatalog.resolvePreset(in: root, name: "child")
        XCTAssertEqual(result["speed"] as? String, "200")
        XCTAssertEqual(result["height"] as? String, "0.2")
        XCTAssertNil(result["inherits"])
        try Data(#"{"inherits":"child"}"#.utf8).write(to: root.appendingPathComponent("base.json"))
        XCTAssertThrowsError(try StudioPresetCatalog.resolvePreset(in: root, name: "child"))
        XCTAssertThrowsError(try StudioPresetCatalog.resolvePreset(in: root, name: "../escape"))
    }
    func config(machine: String = "A", process: String = "", version: String = "1", data: Data = Data("a".utf8)) -> StudioEstimateConfiguration {
        StudioEstimateConfiguration(machine: machine, printerModel: machine, process: process, studioVersion: version, machineData: data, processData: nil)
    }
    func testCacheChangesWithPrinterProcessStudioAndFullPresetContent() {
        let original = config().key
        XCTAssertNotEqual(original, config(machine: "B").key)
        XCTAssertNotEqual(original, config(process: "Fine").key)
        XCTAssertNotEqual(original, config(version: "2").key)
        XCTAssertNotEqual(original, config(data: Data("b".utf8)).key)
        XCTAssertEqual(original, config().key)
    }
    @MainActor func testSavedCalculationIsIsolatedAndNeverReplacesWebProfileOrGuessesPlateTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let configuration = config()
        model.estimateConfiguration = configuration
        let plates = [PlateRecord(id: "1", name: "A"), PlateRecord(id: "2", name: "B")]
        let item = ShelfItem(id: "fixture", title: "Test", filename: "Test.3mf", filePath: "Files/test.3mf", plates: plates)
        let record = StudioEstimateRecord(itemID: item.id, configurationKey: configuration.key, machine: "A", process: "", studioVersion: "1", calculatedAt: Date(), plates: [PlateRecord(id: "1", name: "A", estimatedSeconds: 600), PlateRecord(id: "2", name: "B", estimatedSeconds: 900)])
        model.calculatedEstimates = [record]
        XCTAssertEqual(model.displayedEstimate(item), PrintEstimate(seconds: 1500, source: .myPrinter))
        XCTAssertEqual(model.displayedEstimate(item, plate: plates[0])?.seconds, 600)
        var web = item
        web.makerWorldSource = MakerWorldSource(pageURL: "https://makerworld.com/en/models/123", estimatedSeconds: 3600, plateCount: 2)
        XCTAssertEqual(model.displayedEstimate(web)?.seconds, 3600)
        XCTAssertEqual(model.displayedEstimate(web, plate: plates[0])?.seconds, 600)
        model.estimateConfiguration = config(machine: "B")
        XCTAssertNil(model.savedEstimate(item))
        XCTAssertNil(model.displayedEstimate(item))
        XCTAssertNil(model.displayedEstimate(web, plate: plates[0]))
        XCTAssertEqual(try JSONDecoder().decode(StudioEstimateRecord.self, from: JSONEncoder().encode(record)), record)
    }
    func testLegacyPreferencesKeepTheirDataAndGetEmptyPrinterSettings() throws {
        let prefs = try JSONDecoder().decode(ShelfPreferences.self, from: Data(#"{"folders":["/tmp/models"],"completedFolder":"/tmp/printed"}"#.utf8))
        XCTAssertEqual(prefs.folders, ["/tmp/models"])
        XCTAssertEqual(prefs.completedFolder, "/tmp/printed")
        XCTAssertEqual(prefs.printerPreset, "")
        XCTAssertFalse(prefs.printerSetupInitialized)
    }
    func testReadsOnlyTheSelectedMachineFromStudioPreferences() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"presets":{"machine":"Bambu Lab X2D 0.4 nozzle","process":"Fine"},"access_code":"DO_NOT_IMPORT"}"#.utf8).write(to: file)
        XCTAssertEqual(StudioPresetCatalog.selectedPrinter(at: file), "Bambu Lab X2D 0.4 nozzle")
    }
    func testOfficialInstalledCatalogResolvesCompatibleMachineAndProcess() throws {
        let studio = URL(fileURLWithPath: "/Applications/BambuStudio.app")
        guard FileManager.default.fileExists(atPath: studio.path) else { throw XCTSkip("Official Studio is not installed") }
        let catalog = try StudioPresetCatalog(studioURL: studio)
        XCTAssertFalse(catalog.machines.isEmpty)
        for machine in catalog.machines {
            let full = try catalog.configuration(machine: machine.name, process: "")
            XCTAssertFalse(full.machineData.isEmpty)
        }
        let machine = try XCTUnwrap(catalog.machines.first { !catalog.compatibleProcesses(machine: $0.name).isEmpty })
        let process = try XCTUnwrap(catalog.compatibleProcesses(machine: machine.name).first)
        XCTAssertNotNil(try catalog.configuration(machine: machine.name, process: process.name).processData)
    }
    @MainActor func testChoosingPrinterAlsoResolvesFullCompatibleProcessForCLI() throws {
        guard FileManager.default.fileExists(atPath: "/Applications/BambuStudio.app") else { throw XCTSkip("Official Studio is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryViewModel(rootOverride: root)
        let catalog = try StudioPresetCatalog(studioURL: URL(fileURLWithPath: model.preferences.studioPath))
        let machine = try XCTUnwrap(catalog.machines.first { !catalog.compatibleProcesses(machine: $0.name).isEmpty })
        model.preferences.printerPreset = machine.name
        model.configurePrinter()
        let config = try XCTUnwrap(model.estimateConfiguration)
        XCTAssertNotNil(config.processData) // Machine-only overrides fail with official macOS resource presets.
        XCTAssertTrue(catalog.compatibleProcesses(machine: machine.name).contains { $0.name == config.process })
        let persisted = try JSONDecoder().decode(ShelfPreferences.self, from: Data(contentsOf: root.appendingPathComponent("preferences.json")))
        XCTAssertEqual(persisted.printerPreset, machine.name)
        XCTAssertEqual(persisted.printerProcess, config.process)
    }
}
