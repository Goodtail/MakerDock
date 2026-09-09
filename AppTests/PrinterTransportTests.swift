import XCTest
import Security
@testable import PlateShelf

final class PrinterTransportTests: XCTestCase {
    private func command(_ executable: String, _ arguments: [String], in root: URL) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments; process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }
    private func mock() async throws -> (URL, Process, UInt16, [SecCertificate]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("makerdock-mqtt-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = """
        [req]
        distinguished_name = dn
        x509_extensions = ext
        prompt = no
        [dn]
        CN = TEST123
        [ext]
        basicConstraints = critical,CA:TRUE
        keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign
        extendedKeyUsage = serverAuth
        subjectAltName = DNS:TEST123
        """
        try config.write(to: root.appendingPathComponent("cert.cnf"), atomically: true, encoding: .utf8)
        try command("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "server.key", "-out", "server.pem", "-days", "1", "-config", "cert.cnf"], in: root)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "mock-printer", withExtension: "py"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = [fixture.path, root.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: root.appendingPathComponent("port").path) { try await Task.sleep(nanoseconds: 50_000_000) }
        let port = try XCTUnwrap(UInt16(String(contentsOf: root.appendingPathComponent("port"))))
        let authorities = PrinterTrust.certificates(pem: try String(contentsOf: root.appendingPathComponent("server.pem")))
        return (root, process, port, authorities)
    }
    func testNativeTLSSubscriptionReceivesStatusAndAcknowledgesWithoutPrinterCommands() async throws {
        let (root, server, port, authorities) = try await mock()
        defer { if server.isRunning { server.terminate() }; try? FileManager.default.removeItem(at: root) }
        let client = PrinterMQTTClient(); defer { client.disconnect() }
        let received = expectation(description: "Received the mock printer status")
        client.connect(configuration: PrinterConnectionConfiguration(host: "127.0.0.1", serial: "TEST123"), code: "DUMMY123", authorities: authorities, port: port) { event in
            if case .report(let data, let retained) = event {
                XCTAssertFalse(retained)
                var status = PrinterSnapshot(); XCTAssertTrue((try? status.ingest(data)) == true)
                XCTAssertEqual(status.state, .running); XCTAssertEqual(status.remainingSeconds, 1800)
                received.fulfill()
            }
        }
        await fulfillment(of: [received], timeout: 10)
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: root.appendingPathComponent("result").path) { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("result")), "subscribed-and-acknowledged-without-commands")
    }
    func testWrongSerialRejectsTLSBeforeSendingAccessCode() async throws {
        let (root, server, port, authorities) = try await mock()
        defer { if server.isRunning { server.terminate() }; try? FileManager.default.removeItem(at: root) }
        let client = PrinterMQTTClient(); defer { client.disconnect() }
        let rejected = expectation(description: "Rejected mismatched printer certificate")
        client.connect(configuration: PrinterConnectionConfiguration(host: "127.0.0.1", serial: "WRONG123"), code: "DUMMY123", authorities: authorities, port: port) { event in
            if case .failed(let error) = event { XCTAssertEqual(error, .certificate); rejected.fulfill() }
            if case .subscribed = event { XCTFail("Subscribed to the wrong printer") }
        }
        await fulfillment(of: [rejected], timeout: 10)
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: root.appendingPathComponent("result").path) { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("result")), "tls-rejected-before-credentials")
    }
}
