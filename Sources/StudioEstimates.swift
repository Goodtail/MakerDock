import Foundation
import CryptoKit
import PlateShelfCore

struct StudioPreset: Identifiable, Equatable {
    let name: String
    let printerModel: String
    let compatiblePrinters: [String]
    var id: String { name }
}

struct StudioPresetCatalog {
    let directory: URL
    let version: String
    let machines: [StudioPreset]
    let processes: [StudioPreset]

    init(studioURL: URL) throws {
        guard let bundle = Bundle(url: studioURL), bundle.bundleIdentifier == "com.bambulab.bambu-studio" else {
            throw ShelfError.message(L("공식 Bambu Studio 앱을 설정에서 선택해 주세요."))
        }
        let presetDirectory = studioURL.appendingPathComponent("Contents/Resources/profiles/BBL")
        directory = presetDirectory
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        func scan(_ kind: String) -> [StudioPreset] {
            let urls = (try? FileManager.default.contentsOfDirectory(at: presetDirectory.appendingPathComponent(kind), includingPropertiesForKeys: nil)) ?? []
            return urls.compactMap { url -> StudioPreset? in
                guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["instantiation"] as? String == "true", let name = json["name"] as? String else { return nil }
                return StudioPreset(name: name, printerModel: json["printer_model"] as? String ?? "", compatiblePrinters: json["compatible_printers"] as? [String] ?? [])
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        machines = scan("machine").filter { !$0.printerModel.isEmpty }
        processes = scan("process")
    }

    func compatibleProcesses(machine: String) -> [StudioPreset] {
        processes.filter { $0.compatiblePrinters.contains(machine) }
    }

    static func resolvePreset(in directory: URL, name: String, visited: Set<String> = []) throws -> [String: Any] {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !visited.contains(name), visited.count < 32 else {
            throw ShelfError.message(L("Studio 프린터 설정을 읽을 수 없습니다."))
        }
        let data = try Data(contentsOf: directory.appendingPathComponent(name + ".json"))
        guard data.count <= 4 * 1_024 * 1_024, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShelfError.message(L("Studio 설정 형식이 올바르지 않습니다."))
        }
        var full: [String: Any] = [:]
        if let parent = json["inherits"] as? String, !parent.isEmpty {
            full = try resolvePreset(in: directory, name: parent, visited: visited.union([name]))
        }
        full.merge(json) { _, value in value }; full.removeValue(forKey: "inherits")
        return full
    }

    func configuration(machine: String, process: String) throws -> StudioEstimateConfiguration {
        guard let preset = machines.first(where: { $0.name == machine }),
              process.isEmpty || compatibleProcesses(machine: machine).contains(where: { $0.name == process }) else {
            throw ShelfError.message(L("내 프린터와 호환되는 출력 품질을 설정에서 선택해 주세요."))
        }
        let machineData = try JSONSerialization.data(withJSONObject: Self.resolvePreset(in: directory.appendingPathComponent("machine"), name: machine), options: [.sortedKeys])
        let processData = try process.isEmpty ? nil : JSONSerialization.data(withJSONObject: Self.resolvePreset(in: directory.appendingPathComponent("process"), name: process), options: [.sortedKeys])
        return StudioEstimateConfiguration(machine: machine, printerModel: preset.printerModel, process: process,
                                           studioVersion: version, machineData: machineData, processData: processData)
    }

    static func selectedPrinter(at preferencesURL: URL) -> String? {
        guard let data = try? Data(contentsOf: preferencesURL), data.count < 4 * 1_024 * 1_024,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let presets = json["presets"] as? [String: Any] else { return nil }
        return (presets["machine"] ?? presets["printer"]) as? String
    }
}

struct StudioEstimateConfiguration {
    let machine: String
    let printerModel: String
    let process: String
    let studioVersion: String
    let machineData: Data
    let processData: Data?
    var key: String {
        var data = Data("MakerDock-estimate-v1\n\(studioVersion)\n\(machine)\n\(process)\n".utf8)
        data.append(machineData); data.append(processData ?? Data())
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct StudioEstimateRecord: Codable, Equatable {
    let itemID: String
    let configurationKey: String
    let machine: String
    let process: String
    let studioVersion: String
    let calculatedAt: Date
    let plates: [PlateRecord]
    var total: Double? {
        guard !plates.isEmpty, plates.allSatisfy({ PrintEstimate.valid($0.estimatedSeconds) != nil }) else { return nil }
        let result = plates.reduce(0) { $0 + ($1.estimatedSeconds ?? 0) }
        return PrintEstimate.valid(result)
    }
}

private final class StudioProcessSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    func set(_ value: Process?) { lock.lock(); defer { lock.unlock() }; process = value }
    func stop() {
        lock.lock(); defer { lock.unlock() }
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}

actor StudioEstimateService {
    private nonisolated let slot = StudioProcessSlot()
    nonisolated func stop() { slot.stop() }
    func calculate(item: ShelfItem, inputURL: URL, studioURL: URL, configuration: StudioEstimateConfiguration) async throws -> StudioEstimateRecord {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("MakerDock-Estimate-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary.appendingPathComponent("settings"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let input = temporary.appendingPathComponent("input.3mf")
        try fm.copyItem(at: inputURL, to: input)
        let machine = temporary.appendingPathComponent("machine.json")
        try configuration.machineData.write(to: machine)
        var settings = machine.path
        if let data = configuration.processData {
            let process = temporary.appendingPathComponent("process.json")
            try data.write(to: process); settings += ";" + process.path
        }
        guard Bundle(url: studioURL)?.bundleIdentifier == "com.bambulab.bambu-studio" else { throw ShelfError.message(L("공식 Bambu Studio가 필요합니다.")) }
        let process = Process()
        process.executableURL = studioURL.appendingPathComponent("Contents/MacOS/BambuStudio")
        process.currentDirectoryURL = temporary
        // Separate preferences and working copy; no printer or network commands.
        process.arguments = ["--datadir", temporary.appendingPathComponent("settings").path,
                             "--debug", "1", "--load-settings", settings, "--slice", "0", "--mstpp", "90",
                             "--outputdir", temporary.path, "--export-3mf", "sliced.3mf", input.path]
        let logURL = temporary.appendingPathComponent("studio.log")
        fm.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        process.standardOutput = log; process.standardError = log; process.standardInput = FileHandle.nullDevice
        try Task.checkCancellation()
        try process.run()
        slot.set(process)
        defer { slot.set(nil) }
        let deadline = Date().addingTimeInterval(300)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw ShelfError.message(L("계산이 5분을 넘었습니다. Studio에서 직접 슬라이싱해 주세요.")) }
                let size = (try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size < 8 * 1_024 * 1_024 else { throw ShelfError.message(L("Studio 계산을 중단했습니다. Studio에서 파일의 설정을 확인해 주세요.")) }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
        } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw error
        }
        try Task.checkCancellation()
        let output = temporary.appendingPathComponent("sliced.3mf")
        guard process.terminationStatus == 0, fm.fileExists(atPath: output.path) else {
            throw ShelfError.message(L("이 파일을 선택한 프린터로 계산하지 못했습니다. Studio에서 프린터·재료·플레이트 배치를 확인해 주세요."))
        }
        let summary = try ArchivePrintSummary.read(at: output)
        guard summary.printerModel == configuration.printerModel,
              Set(summary.plates.map(\.id)) == Set(item.plates.map(\.id)),
              summary.plates.count == item.plates.count,
              summary.plates.contains(where: { PrintEstimate.valid($0.estimatedSeconds) != nil }) else {
            throw ShelfError.message(L("계산 결과의 프린터 또는 플레이트가 원본과 일치하지 않습니다. Studio에서 확인해 주세요."))
        }
        return StudioEstimateRecord(itemID: item.id, configurationKey: configuration.key, machine: configuration.machine,
                                    process: configuration.process, studioVersion: configuration.studioVersion,
                                    calculatedAt: Date(), plates: summary.plates)
    }
}

@MainActor extension LibraryViewModel {
    var compatiblePrinterProcesses: [StudioPreset] { printerCatalog?.compatibleProcesses(machine: preferences.printerPreset) ?? [] }
    func configurePrinter(importFromStudio: Bool = false) {
        do {
            printerCatalog = try StudioPresetCatalog(studioURL: URL(fileURLWithPath: preferences.studioPath))
            if importFromStudio {
                let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BambuStudio/BambuStudio.conf")
                guard let selected = StudioPresetCatalog.selectedPrinter(at: path), printerCatalog?.machines.contains(where: { $0.name == selected }) == true else {
                    throw ShelfError.message(L("Studio에서 선택한 프린터를 찾지 못했습니다. 목록에서 직접 선택해 주세요."))
                }
                preferences.printerPreset = selected
                preferences.printerProcess = ""
            }
            if !compatiblePrinterProcesses.contains(where: { $0.name == preferences.printerProcess }) {
                preferences.printerProcess = compatiblePrinterProcesses.first(where: { $0.name.hasPrefix("0.20mm Standard") })?.name ?? compatiblePrinterProcesses.first?.name ?? ""
            }
            estimateConfiguration = preferences.printerPreset.isEmpty || preferences.printerProcess.isEmpty ? nil : try printerCatalog?.configuration(machine: preferences.printerPreset, process: preferences.printerProcess)
            savePreferences()
        } catch { estimateConfiguration = nil; errorMessage = error.localizedDescription }
    }
    func savedEstimate(_ item: ShelfItem) -> StudioEstimateRecord? {
        guard let key = estimateConfiguration?.key else { return nil }
        return calculatedEstimates.first { $0.itemID == item.id && $0.configurationKey == key }
    }
    func displayedEstimate(_ item: ShelfItem, plate: PlateRecord? = nil) -> PrintEstimate? {
        let saved = plate != nil ? item.preferredEstimate(for: plate!) : item.preferredEstimate
        // MakerWorld remains the primary display requested by the user.
        if let saved { return saved }
        guard let record = savedEstimate(item) else { return nil }
        let value = plate == nil ? record.total : record.plates.first { $0.id == plate?.id }?.estimatedSeconds
        return PrintEstimate.valid(value).map { PrintEstimate(seconds: $0, source: .myPrinter) }
    }
    func calculateEstimate(_ item: ShelfItem) {
        guard calculatingItemID == nil else { return }
        guard let configuration = estimateConfiguration else { showSettings = true; return }
        let input = fileURL(item), studio = URL(fileURLWithPath: preferences.studioPath)
        calculatingItemID = item.id
        estimateTask = Task {
            defer { calculatingItemID = nil; estimateTask = nil }
            do {
                let result = try await estimateService.calculate(item: item, inputURL: input, studioURL: studio, configuration: configuration)
                try Task.checkCancellation()
                var records = calculatedEstimates.filter { !($0.itemID == result.itemID && $0.configurationKey == result.configurationKey) }
                records.append(result)
                try JSONEncoder().encode(records).write(to: rootURL.appendingPathComponent("estimates.json"), options: .atomic)
                calculatedEstimates = records
                statusMessage = L("내 프린터 예상 시간을 저장했습니다.")
            } catch is CancellationError { statusMessage = L("시간 계산을 취소했습니다.") }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
