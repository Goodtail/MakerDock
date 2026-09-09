import Foundation
import Combine
import PlateShelfCore

struct PrinterSnapshot: Equatable {
    enum State: String, Codable { case running = "RUNNING", paused = "PAUSE", preparing = "PREPARE", finished = "FINISH", failed = "FAILED", idle = "IDLE", unknown = "UNKNOWN"
        var active: Bool { [.running, .paused, .preparing].contains(self) }
        var terminal: Bool { self == .finished || self == .failed }
        var label: String { L("printer.state." + rawValue) }
    }
    var state: State = .unknown
    var jobID = ""
    var jobName = ""
    var filename = ""
    var startedAt: Date?
    var progress: Double?
    var remainingSeconds: Double?
    var remainingUpdatedAt: Date?
    var receivedAt = Date.distantPast
    var usedFilaments: [FilamentRecord] = []
    // Delta reports must retain metadata for AMS slots, but never cross jobs.
    private var ams: [String: Any] = [:]
    private var external: [String: Any] = [:]
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.receivedAt == rhs.receivedAt && lhs.state == rhs.state && lhs.jobID == rhs.jobID && lhs.progress == rhs.progress }
    var identity: String? {
        if !jobID.isEmpty { return "job:" + jobID }
        return startedAt.map { "start:" + String(Int($0.timeIntervalSince1970)) }
    }
    func fresh(at now: Date) -> Bool { (0...90).contains(now.timeIntervalSince(receivedAt)) }
    func remaining(at now: Date) -> Double? {
        guard fresh(at: now), let value = remainingSeconds, let updated = remainingUpdatedAt,
              (0...90).contains(now.timeIntervalSince(updated)) else { return nil }
        guard state == .running || state == .preparing else { return nil }
        // A zero minute report is not a FINISH event; do not run the next job through it.
        let remaining = value - max(0, now.timeIntervalSince(updated))
        return remaining > 0 ? remaining : nil
    }
    mutating func ingest(_ data: Data, now: Date = Date()) throws -> Bool {
        guard data.count <= PrinterMQTTWire.maxPacketBytes,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PrinterConnectionError.protocolError }
        guard let print = root["print"] as? [String: Any] else { return false }
        let stateValue = (print["gcode_state"] as? String).map { State(rawValue: $0) ?? .unknown }
        let nextJob = Self.text(print["subtask_id"]).flatMap { $0 != "0" ? $0 : nil } ?? Self.text(print["task_id"]).flatMap { $0 != "0" ? $0 : nil }
        let unixStart = Self.number(print["gcode_start_time"]).flatMap { value -> Date? in
            guard value > 1_577_836_800, value <= now.timeIntervalSince1970 + 60 else { return nil }
            return Date(timeIntervalSince1970: value)
        }
        let changedJob = (nextJob != nil && !jobID.isEmpty && nextJob != jobID) || (unixStart != nil && startedAt != nil && unixStart != startedAt) || (state.terminal && stateValue?.active == true)
        if changedJob { self = PrinterSnapshot() }
        if let stateValue { state = stateValue }
        if let nextJob { jobID = nextJob }
        if let unixStart { startedAt = unixStart }
        if let value = print["subtask_name"] as? String { jobName = String(value.prefix(512)) }
        if let value = print["gcode_file"] as? String { filename = String(value.prefix(1024)) }
        if let percent = Self.number(print["mc_percent"]), (0...100).contains(percent) { progress = percent }
        if let minutes = Self.number(print["mc_remaining_time"]), (0...525_600).contains(minutes) {
            remainingSeconds = minutes * 60; remainingUpdatedAt = now
        }
        if let value = print["ams"] as? [String: Any] { ams = Self.merge(ams, value) }
        if let value = print["vt_tray"] as? [String: Any] { external = Self.merge(external, value) }
        usedFilaments = currentFilaments()
        receivedAt = now
        return true
    }
    private func currentFilaments() -> [FilamentRecord] {
        guard state.active, let index = Self.smallInteger(ams["tray_now"]) else { return [] }
        if index == 254 { return Self.filament(external, id: "external").map { [$0] } ?? [] }
        guard (0..<254).contains(index), let units = ams["ams"] as? [[String: Any]],
              let unit = units.first(where: { Self.smallInteger($0["id"]) == index / 4 }),
              let slots = unit["tray"] as? [[String: Any]],
              let slot = slots.first(where: { Self.smallInteger($0["id"]) == index % 4 }) else { return [] }
        return Self.filament(slot, id: "ams-\(index)").map { [$0] } ?? []
    }
    private static func filament(_ value: [String: Any], id: String) -> FilamentRecord? {
        guard let material = value["tray_type"] as? String, !material.isEmpty else { return nil }
        let name = (value["tray_sub_brands"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? material
        // tray_weight/remain describe the spool, not material consumed by this print.
        return FilamentRecord(id: id, name: String(name.prefix(100)), material: String(material.prefix(40)), color: (value["tray_color"] as? String).map { String($0.prefix(8)) })
    }
    private static func smallInteger(_ value: Any?) -> Int? {
        guard let value = number(value), (0...255).contains(value), value.rounded() == value else { return nil }
        return Int(value)
    }
    private static func text(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return String(text.prefix(128)) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
    private static func number(_ value: Any?) -> Double? {
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return number.flatMap { $0.isFinite ? $0 : nil }
    }
    private static func merge(_ old: [String: Any], _ new: [String: Any]) -> [String: Any] {
        var result = old
        for (key, value) in new {
            if let oldRows = old[key] as? [[String: Any]], let rows = value as? [[String: Any]] {
                var combined = oldRows
                for row in rows {
                    if let id = text(row["id"]), let index = combined.firstIndex(where: { text($0["id"]) == id }) { combined[index] = merge(combined[index], row) }
                    else { combined.append(row) }
                }
                result[key] = combined
            } else { result[key] = value }
        }
        return result
    }
}

struct PrinterPrintSession: Codable, Equatable {
    var serial: String
    var identity: String?
    var printerStartedAt: Date?
    var itemID: String?
    var jobName: String
    var startedAt: Date?
    var endedAt: Date?
    var endNeedsReview = false
    var terminalState: PrinterSnapshot.State?
    var filaments: [FilamentRecord] = []
    var recorded = false
    func matches(_ snapshot: PrinterSnapshot, serial: String) -> Bool {
        guard self.serial == serial else { return false }
        if let printerStartedAt, let start = snapshot.startedAt, printerStartedAt != start { return false }
        return identity != nil && identity == snapshot.identity || (printerStartedAt != nil && printerStartedAt == snapshot.startedAt)
    }
}

@MainActor final class PrinterMonitor: ObservableObject {
    enum ConnectionState { case disconnected, connecting, waiting, receiving, error(PrinterConnectionError) }
    @Published private(set) var configuration = PrinterConnectionConfiguration()
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var snapshot = PrinterSnapshot()
    @Published private(set) var session: PrinterPrintSession?
    var onUpdate: (() -> Void)?
    private let root: URL
    private let client = PrinterMQTTClient()
    private var connectionID = UUID()
    private var retry: Task<Void, Never>?
    private var attempt = 0
    private var studioPath = ""
    init(root: URL) {
        self.root = root
        configuration = (try? JSONDecoder().decode(PrinterConnectionConfiguration.self, from: Data(contentsOf: root.appendingPathComponent("printer-connection.json")))) ?? PrinterConnectionConfiguration()
        session = try? JSONDecoder().decode(PrinterPrintSession.self, from: Data(contentsOf: root.appendingPathComponent("printer-session.json")))
    }
    var label: String {
        switch connectionState {
        case .disconnected: return L("printer.disconnected")
        case .connecting: return L("printer.connecting")
        case .waiting: return L("printer.waiting")
        case .receiving: return snapshot.fresh(at: Date()) ? snapshot.state.label : L("printer.stale")
        case .error(let error): return error.message
        }
    }
    func saveAndConnect(_ configuration: PrinterConnectionConfiguration, code: String, studioPath: String) {
        do {
            guard configuration.valid else { throw PrinterConnectionError.settings }
            let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty {
                guard (8...64).contains(code.utf8.count), code.utf8.allSatisfy({ (33...126).contains($0) }) else { throw PrinterConnectionError.settings }
                try PrinterCredentialStore.save(code, serial: configuration.serial)
            } else { _ = try PrinterCredentialStore.load(serial: configuration.serial) }
            stop()
            if self.configuration.serial != configuration.serial || self.configuration.host != configuration.host { session = nil; try saveSession() }
            self.configuration = configuration; self.configuration.enabled = true
            try saveConfiguration()
            start(studioPath: studioPath)
        } catch { connectionState = .error((error as? PrinterConnectionError) ?? .settings) }
    }
    func start(studioPath: String) {
        guard configuration.enabled, configuration.valid else { return }
        self.studioPath = studioPath
        retry?.cancel(); retry = nil
        connectionID = UUID(); let id = connectionID
        snapshot = PrinterSnapshot(); connectionState = .connecting
        do {
            let code = try PrinterCredentialStore.load(serial: configuration.serial)
            let authorities = try PrinterTrust.authorities(studioPath: studioPath)
            client.connect(configuration: configuration, code: code, authorities: authorities) { [weak self] event in
                Task { @MainActor in guard let self, self.connectionID == id else { return }; self.handle(event) }
            }
        } catch { connectionState = .error((error as? PrinterConnectionError) ?? .network) }
    }
    func disconnect() {
        stop(); configuration.enabled = false
        do { try saveConfiguration() } catch { connectionState = .error(.settings) }
    }
    func forget() {
        do {
            try PrinterCredentialStore.remove(serial: configuration.serial)
            stop(); configuration = PrinterConnectionConfiguration(); session = nil
            try saveConfiguration(); try saveSession()
        } catch { connectionState = .error((error as? PrinterConnectionError) ?? .settings) }
    }
    func stop() {
        connectionID = UUID(); retry?.cancel(); retry = nil; attempt = 0
        client.disconnect(); connectionState = .disconnected; snapshot = PrinterSnapshot()
    }
    private func handle(_ event: PrinterMQTTClient.Event) {
        switch event {
        case .subscribed: connectionState = .waiting; attempt = 0
        case .report(let data, let retained):
            // A retained message can describe yesterday's completed job. Wait for live telemetry.
            guard !retained else { return }
            do { try receive(data) }
            catch { connectionState = .error(.protocolError) }
        case .failed(let error):
            connectionState = .error(error); snapshot.receivedAt = .distantPast
            if configuration.enabled && [.network, .timeout].contains(error) {
                attempt += 1; let delay = min(60, pow(2, Double(min(attempt, 6))))
                retry = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard !Task.isCancelled, let self else { return }
                    self.start(studioPath: self.studioPath)
                }
            }
        }
        onUpdate?()
    }
    // Also used by deterministic tests; no socket or credentials required.
    func receive(_ data: Data, at now: Date = Date()) throws {
        let previous = snapshot
        let previousSession = session
        guard try snapshot.ingest(data, now: now) else { return }
        connectionState = .receiving
        if snapshot.state.active || snapshot.state.terminal {
            let matches = session?.matches(snapshot, serial: configuration.serial) == true
            // Without a printer job identifier, keep a binding only within this live connection.
            let sameAnonymousJob = session?.identity == nil && session?.serial == configuration.serial && previous.fresh(at: now) && previous.state.active && !previous.jobName.isEmpty && previous.jobName == snapshot.jobName
            if (!matches && !sameAnonymousJob) || (previous.state.terminal && snapshot.state.active) || (session?.recorded == true && snapshot.state.active) {
                session = PrinterPrintSession(serial: configuration.serial, identity: snapshot.identity, printerStartedAt: snapshot.startedAt, jobName: snapshot.jobName, startedAt: snapshot.startedAt)
            }
            if var current = session {
                if current.startedAt == nil { current.startedAt = snapshot.startedAt }
                if current.identity == nil { current.identity = snapshot.identity }
                if current.printerStartedAt == nil { current.printerStartedAt = snapshot.startedAt }
                if snapshot.state.terminal, current.endedAt == nil {
                    current.endedAt = now; current.terminalState = snapshot.state
                    current.endNeedsReview = !previous.state.active || !previous.fresh(at: now)
                }
                for filament in snapshot.usedFilaments where !current.filaments.contains(where: { $0.id == filament.id && $0.material == filament.material && $0.color == filament.color }) {
                    var value = filament; value.id = UUID().uuidString
                    // Deduplicate by observed type/color rather than a reused AMS slot.
                    if current.filaments.count < 64, !current.filaments.contains(where: { $0.material == value.material && $0.color == value.color && $0.name == value.name }) { current.filaments.append(value) }
                }
                if current != session { session = current }
            }
            if previousSession != session { try saveSession() }
        }
        onUpdate?()
    }
    func bind(itemID: String, startedAt: Date) throws {
        guard snapshot.fresh(at: Date()), snapshot.state.active || snapshot.state.terminal,
              snapshot.identity != nil || !snapshot.jobName.isEmpty,
              startedAt <= (session?.endedAt ?? Date()), startedAt.timeIntervalSince1970 > 0,
              var value = session, !value.recorded else { throw PrinterConnectionError.settings }
        value.itemID = itemID; value.startedAt = startedAt; session = value; try saveSession(); onUpdate?()
    }
    func completionSession(itemID: String) -> PrinterPrintSession? {
        guard let session, session.itemID == itemID, !session.recorded else { return nil }
        return session
    }
    func markRecorded(itemID: String) {
        guard session?.itemID == itemID, session?.recorded == false else { return }
        session?.recorded = true
        do { try saveSession() } catch { connectionState = .error(.settings) }
    }
    func remaining(itemID: String, at now: Date) -> Double? {
        guard let session, session.itemID == itemID, !session.recorded,
              snapshot.fresh(at: now) else { return nil }
        let anonymousBinding = session.identity == nil && session.serial == configuration.serial && !session.jobName.isEmpty && session.jobName == snapshot.jobName
        guard session.matches(snapshot, serial: configuration.serial) || anonymousBinding else { return nil }
        return snapshot.remaining(at: now)
    }
    func ownsLiveJob(itemID: String) -> Bool {
        guard let session, session.itemID == itemID, !session.recorded else { return false }
        return true // A stale/disconnected bound job blocks planning until status returns or it is unlinked.
    }
    func unbind(itemID: String) {
        guard session?.itemID == itemID else { return }
        session?.itemID = nil
        do { try saveSession() } catch { connectionState = .error(.settings) }
    }
    private func saveConfiguration() throws { try write(configuration, to: "printer-connection.json") }
    private func saveSession() throws {
        if let session { try write(session, to: "printer-session.json") }
        else { let url = root.appendingPathComponent("printer-session.json"); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
    }
    private func write<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent(name), options: .atomic)
    }
}
