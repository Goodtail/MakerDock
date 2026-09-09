import XCTest
import Security
import PlateShelfCore
@testable import PlateShelf

final class PrinterMonitorTests: XCTestCase {
    func report(_ fields: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: ["print": fields]) }
    func testLocalConfigurationRejectsRemoteHostsAndTopicInjection() {
        XCTAssertTrue(PrinterConnectionConfiguration(host: "192.168.1.2", serial: "TEST123").valid)
        for host in ["8.8.8.8", "printer.example.com", "127.0.0.1", "192.168.1.256", "192.168.1.2/path", "192.168.1"] {
            XCTAssertFalse(PrinterConnectionConfiguration(host: host, serial: "TEST123").valid, host)
        }
        XCTAssertFalse(PrinterConnectionConfiguration(host: "192.168.1.2", serial: "TEST/#").valid)
    }
    func testMQTTFragmentationMultiplePacketsQOSAndWrongTopic() throws {
        let topic = PrinterMQTTWire.string("device/TEST123/report")
        let payload = try report(["gcode_state": "RUNNING", "mc_percent": 30])
        let published = PrinterMQTTWire.packet(0x32, topic + Data([0, 7]) + payload)
        var buffer = Data(published.prefix(3))
        XCTAssertTrue(try PrinterMQTTWire.extract(from: &buffer).isEmpty)
        buffer.append(published.dropFirst(3)); buffer.append(Data([0xd0, 0]))
        let packets = try PrinterMQTTWire.extract(from: &buffer)
        XCTAssertEqual(packets.count, 2); XCTAssertTrue(buffer.isEmpty)
        let value = try XCTUnwrap(PrinterMQTTWire.publication(packets[0], serial: "TEST123"))
        XCTAssertEqual(value.payload, payload); XCTAssertEqual(value.ack, Data([0x40, 2, 0, 7])); XCTAssertFalse(value.retained)
        XCTAssertThrowsError(try PrinterMQTTWire.publication(packets[0], serial: "OTHER123"))
        var malformed = Data([0x30, 255, 255, 255, 255])
        XCTAssertThrowsError(try PrinterMQTTWire.extract(from: &malformed))
        var truncated = Data([0x30, 0x81])
        XCTAssertTrue(try PrinterMQTTWire.extract(from: &truncated).isEmpty)
        let connection = PrinterMQTTWire.connect(clientID: "TEST-CLIENT", code: "DUMMY123")
        XCTAssertEqual(connection.first, 0x10)
        XCTAssertFalse(String(decoding: PrinterMQTTWire.subscribe(serial: "TEST123"), as: UTF8.self).contains("/request"))
    }
    func testDeltaReportsDoNotConfuseStaleRemainingTimeOrSpoolWeightWithUsage() throws {
        let now = Date()
        var value = PrinterSnapshot()
        _ = try value.ingest(report(["gcode_state":"RUNNING", "subtask_id":"42", "mc_remaining_time":30, "mc_percent": 10,
            "ams": ["tray_now":"0", "ams":[["id":"0", "tray":[["id":"0", "tray_type":"PLA", "tray_color":"000000FF", "tray_weight":1000]]]]]]), now: now)
        XCTAssertEqual(value.remaining(at: now.addingTimeInterval(60)), 1740)
        XCTAssertEqual(value.usedFilaments.first?.material, "PLA"); XCTAssertNil(value.usedFilaments.first?.grams)
        _ = try value.ingest(report(["mc_percent":11]), now: now.addingTimeInterval(100))
        XCTAssertNil(value.remaining(at: now.addingTimeInterval(100)))
        _ = try value.ingest(report(["gcode_state":"PAUSE", "mc_remaining_time":25]), now: now.addingTimeInterval(110))
        XCTAssertNil(value.remaining(at: now.addingTimeInterval(110)))
        _ = try value.ingest(report(["gcode_state":"RUNNING", "subtask_id":"43", "mc_remaining_time":5]), now: now.addingTimeInterval(120))
        XCTAssertTrue(value.usedFilaments.isEmpty); XCTAssertNil(value.progress)
        XCTAssertEqual(value.remaining(at: now.addingTimeInterval(120)), 300)
        _ = try value.ingest(report(["mc_remaining_time":0]), now: now.addingTimeInterval(121))
        XCTAssertEqual(value.state, .running); XCTAssertNil(value.remaining(at: now.addingTimeInterval(121)))
    }
    @MainActor func testBoundJobStoresFinishOnceAndNeverMatchesAnotherJobOrAutoCompletesLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = LibraryViewModel(rootOverride: root)
        let fixture = try XCTUnwrap(Bundle(for: IntegrationTests.self).url(forResource: "Fixture", withExtension: "3mf"))
        await vm.importFiles([fixture]); let item = try XCTUnwrap(vm.items.first); await vm.enqueue([item])
        let now = Date(), start = now.addingTimeInterval(-14_400)
        let monitor = vm.printerMonitor
        try monitor.receive(report(["gcode_state":"RUNNING", "subtask_id":"42", "subtask_name":"Test print", "gcode_start_time":start.timeIntervalSince1970, "mc_remaining_time":12]), at: now)
        XCTAssertNil(monitor.session?.itemID)
        let bound = await vm.bindPrinterJob(item, startedAt: start)
        XCTAssertTrue(bound); XCTAssertEqual(vm.queueJobs(at: now).first?.seconds, 720)
        try monitor.receive(report(["gcode_state":"PAUSE"]), at: now.addingTimeInterval(1))
        XCTAssertNil(vm.queueJobs(at: now.addingTimeInterval(1)).first?.seconds)
        let end = now.addingTimeInterval(2)
        try monitor.receive(report(["gcode_state":"FINISH", "mc_percent":100, "mc_remaining_time":0]), at: end)
        XCTAssertEqual(monitor.session?.endedAt, end); XCTAssertFalse(monitor.session!.endNeedsReview)
        try monitor.receive(report(["gcode_state":"FINISH"]), at: end.addingTimeInterval(30))
        XCTAssertEqual(monitor.session?.endedAt, end)
        XCTAssertEqual(vm.items.first?.printRuns.count, 0); XCTAssertEqual(vm.printQueue.count, 1)
        let draft = vm.printDetails(item)
        XCTAssertEqual(try XCTUnwrap(draft.seconds), 14_402, accuracy: 1)
        XCTAssertEqual(draft.completedAt, end); XCTAssertEqual(draft.durationSource, "elapsed")
        let restored = PrinterMonitor(root: root)
        XCTAssertEqual(restored.session?.endedAt, end)
        try monitor.receive(report(["gcode_state":"RUNNING", "subtask_id":"43", "subtask_name":"Next print"]), at: now.addingTimeInterval(40))
        XCTAssertNil(monitor.session?.itemID); XCTAssertNil(monitor.session?.endedAt)
    }
    @MainActor func testReconnectDoesNotInventExactFinishTimeAndLateStartMetadataKeepsBinding() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(), start = now.addingTimeInterval(-3600), monitor = PrinterMonitor(root: root)
        try monitor.receive(report(["gcode_state":"RUNNING", "subtask_id":"42", "subtask_name":"Model"]), at: now)
        try monitor.bind(itemID: "model", startedAt: start)
        try monitor.receive(report(["gcode_start_time":start.timeIntervalSince1970]), at: now.addingTimeInterval(1))
        XCTAssertEqual(monitor.session?.itemID, "model")
        let restored = PrinterMonitor(root: root)
        try restored.receive(report(["gcode_state":"FINISH", "subtask_id":"42", "gcode_start_time":start.timeIntervalSince1970]), at: now.addingTimeInterval(600))
        XCTAssertEqual(restored.session?.itemID, "model"); XCTAssertTrue(restored.session!.endNeedsReview)
    }
    func testReadsOnlyPublicAuthoritiesFromOfficialStudio() throws {
        guard FileManager.default.fileExists(atPath: "/Applications/BambuStudio.app") else { throw XCTSkip("Official Studio is not installed") }
        let certificates = try PrinterTrust.authorities(studioPath: "/Applications/BambuStudio.app")
        XCTAssertGreaterThanOrEqual(certificates.count, 1)
        XCTAssertThrowsError(try PrinterTrust.authorities(studioPath: "/Applications/Safari.app"))
    }
}
