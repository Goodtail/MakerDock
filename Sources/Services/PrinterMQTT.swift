import Foundation
import Network
import Security

struct PrinterConnectionConfiguration: Codable, Equatable {
    var host = ""
    var serial = ""
    var enabled = false
    var valid: Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part), (0...255).contains(value) else { return nil }
            return value
        }
        let local = octets.count == 4 && (octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 169 && octets[1] == 254))
        return local && (6...40).contains(serial.count) && serial.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) }
    }
}

enum PrinterConnectionError: Error, Equatable {
    case settings, certificate, authority, authentication, subscription, network, timeout, protocolError, keychain
    var message: String { L("printer.error." + String(describing: self)) }
}

/// MQTT 3.1.1 framing. Outgoing packets are limited to handshake, subscribe,
/// keepalive and acknowledgements. There is deliberately no publish/command API.
enum PrinterMQTTWire {
    static let maxPacketBytes = 1_048_576
    struct Packet { let header: UInt8; let body: Data }
    static func string(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        precondition(bytes.count <= 65_535)
        return Data([UInt8(bytes.count >> 8), UInt8(bytes.count & 255)]) + bytes
    }
    static func packet(_ header: UInt8, _ body: Data) -> Data {
        var length = body.count, bytes = Data([header])
        repeat { let digit = UInt8(length % 128); length /= 128; bytes.append(digit | (length > 0 ? 128 : 0)) } while length > 0
        return bytes + body
    }
    static func connect(clientID: String, code: String) -> Data {
        packet(0x10, string("MQTT") + Data([4, 0xc2, 0, 30]) + string(clientID) + string("bblp") + string(code))
    }
    static func subscribe(serial: String) -> Data {
        packet(0x82, Data([0, 1]) + string("device/\(serial)/report") + Data([0]))
    }
    static func extract(from buffer: inout Data) throws -> [Packet] {
        // Data slices can retain their original index. Normalize before indexing.
        var bytes = [UInt8](buffer), result: [Packet] = []
        while bytes.count >= 2 {
            var length = 0, multiplier = 1, offset = 1, complete = false
            for _ in 0..<4 {
                guard offset < bytes.count else { break }
                let digit = bytes[offset]; offset += 1
                length += Int(digit & 127) * multiplier
                guard length <= maxPacketBytes else { throw PrinterConnectionError.protocolError }
                if digit & 128 == 0 { complete = true; break }
                multiplier *= 128
            }
            if !complete {
                if offset == 5 { throw PrinterConnectionError.protocolError }
                break
            }
            guard bytes.count >= offset + length else { break }
            result.append(Packet(header: bytes[0], body: Data(bytes[offset..<(offset + length)])))
            bytes.removeFirst(offset + length)
        }
        guard bytes.count <= maxPacketBytes + 5 else { throw PrinterConnectionError.protocolError }
        buffer = Data(bytes); return result
    }
    static func publication(_ packet: Packet, serial: String) throws -> (payload: Data, ack: Data?, retained: Bool)? {
        guard packet.header >> 4 == 3 else { return nil }
        let body = [UInt8](packet.body), qos = (packet.header >> 1) & 3
        guard body.count >= 2, qos <= 1 else { throw PrinterConnectionError.protocolError }
        let length = Int(body[0]) * 256 + Int(body[1])
        var offset = 2 + length
        guard body.count >= offset else { throw PrinterConnectionError.protocolError }
        let topic = String(bytes: body[2..<offset], encoding: .utf8)
        var ack: Data?
        if qos == 1 {
            guard body.count >= offset + 2, body[offset] != 0 || body[offset + 1] != 0 else { throw PrinterConnectionError.protocolError }
            ack = Data([0x40, 2, body[offset], body[offset + 1]]); offset += 2
        }
        guard topic == "device/\(serial)/report" else { throw PrinterConnectionError.protocolError }
        return (Data(body[offset...]), ack, packet.header & 1 == 1)
    }
}

enum PrinterTrust {
    /// Public CA certificates are read from the separately installed official Studio.
    /// Neither the networking plugin nor account credentials are accessed.
    static func authorities(studioPath: String) throws -> [SecCertificate] {
        let bundle = Bundle(path: studioPath)
        guard bundle?.bundleIdentifier == "com.bambulab.bambu-studio",
              let url = bundle?.resourceURL?.appendingPathComponent("cert/printer.cer"),
              let text = try? String(contentsOf: url), text.utf8.count < 128_000 else { throw PrinterConnectionError.authority }
        let certificates = certificates(pem: text)
        guard !certificates.isEmpty else { throw PrinterConnectionError.authority }
        return certificates
    }
    static func certificates(pem: String) -> [SecCertificate] {
        pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().compactMap {
            guard let text = $0.components(separatedBy: "-----END CERTIFICATE-----").first,
                  let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
            return SecCertificateCreateWithData(nil, data as CFData)
        }
    }
    static func validate(_ trust: SecTrust, serial: String, authorities: [SecCertificate]) -> Bool {
        guard !authorities.isEmpty else { return false }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, serial as CFString))
        SecTrustSetAnchorCertificates(trust, authorities as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetNetworkFetchAllowed(trust, false)
        return SecTrustEvaluateWithError(trust, nil)
    }
}

/// All mutable transport state and callbacks are confined to one serial queue.
final class PrinterMQTTClient {
    enum Event { case subscribed, report(Data, retained: Bool), failed(PrinterConnectionError) }
    private let queue = DispatchQueue(label: "app.makerdock.printer.mqtt")
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var buffer = Data()
    private var generation = UUID()
    private var lastReceived = Date()
    private var began = Date()
    private var phase = 0
    private var failure: PrinterConnectionError?
    private var handler: ((Event) -> Void)?

    func connect(configuration: PrinterConnectionConfiguration, code: String, authorities: [SecCertificate], port: UInt16 = 8883, handler: @escaping (Event) -> Void) {
        queue.async {
            self.close(); self.handler = handler
            let generation = self.generation
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, configuration.serial)
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] _, value, complete in
                guard let self, self.generation == generation else { complete(false); return }
                let trust = sec_trust_copy_ref(value).takeRetainedValue()
                let valid = PrinterTrust.validate(trust, serial: configuration.serial, authorities: authorities)
                if !valid { self.failure = .certificate }
                complete(valid)
            }, self.queue)
            let connection = NWConnection(host: NWEndpoint.Host(configuration.host), port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: tls))
            self.connection = connection; self.began = Date(); self.lastReceived = Date()
            connection.stateUpdateHandler = { [weak self] state in
                guard let self, self.generation == generation else { return }
                switch state {
                case .ready:
                    self.send(PrinterMQTTWire.connect(clientID: "md-" + String(UUID().uuidString.prefix(18)), code: code))
                    self.receive(serial: configuration.serial, generation: generation)
                case .failed: self.fail(self.failure ?? .network)
                case .waiting: self.fail(self.failure ?? .network)
                default: break
                }
            }
            connection.start(queue: self.queue)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 10, repeating: 10)
            timer.setEventHandler { [weak self] in
                guard let self, self.generation == generation else { return }
                if self.phase < 2, Date().timeIntervalSince(self.began) > 20 { self.fail(.timeout) }
                else if Date().timeIntervalSince(self.lastReceived) > 65 { self.fail(.timeout) }
                else if self.phase == 2 { self.send(Data([0xc0, 0])) }
            }
            self.timer = timer; timer.resume()
        }
    }
    func disconnect() { queue.async { self.close() } }
    private func send(_ data: Data) {
        let generation = generation
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, self.generation == generation else { return }
            if error != nil { self.fail(self.failure ?? .network) }
        })
    }
    private func receive(serial: String, generation: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, self.generation == generation else { return }
            do {
                if let data, !data.isEmpty {
                    self.buffer.append(data); self.lastReceived = Date()
                    for packet in try PrinterMQTTWire.extract(from: &self.buffer) {
                        switch packet.header {
                        case 0x20:
                            guard self.phase == 0, packet.body.count == 2, packet.body.first == 0 else { throw PrinterConnectionError.protocolError }
                            guard packet.body.last == 0 else { throw PrinterConnectionError.authentication }
                            self.phase = 1; self.send(PrinterMQTTWire.subscribe(serial: serial))
                        case 0x90:
                            guard self.phase == 1, packet.body == Data([0, 1, 0]) else { throw PrinterConnectionError.subscription }
                            self.phase = 2; self.handler?(.subscribed)
                        case 0xd0:
                            guard self.phase == 2, packet.body.isEmpty else { throw PrinterConnectionError.protocolError }
                        default:
                            guard self.phase == 2, let publication = try PrinterMQTTWire.publication(packet, serial: serial) else { throw PrinterConnectionError.protocolError }
                            if let ack = publication.ack { self.send(ack) }
                            self.handler?(.report(publication.payload, retained: publication.retained))
                        }
                    }
                }
                if complete || error != nil { self.fail(.network) }
                else { self.receive(serial: serial, generation: generation) }
            } catch { self.fail((error as? PrinterConnectionError) ?? .protocolError) }
        }
    }
    private func fail(_ error: PrinterConnectionError) { let callback = handler; close(); callback?(.failed(error)) }
    private func close() {
        generation = UUID(); timer?.cancel(); timer = nil
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        buffer = Data(); phase = 0; failure = nil; handler = nil
    }
}

enum PrinterCredentialStore {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "com.ninepiece.app.mac.makerdock.dev") + ".printer" }
    private static func query(_ serial: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: serial]
    }
    static func save(_ code: String, serial: String) throws {
        let value = Data(code.utf8), query = query(serial)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var added = query; added[kSecValueData as String] = value
            added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else { throw PrinterConnectionError.keychain }
        } else if status != errSecSuccess { throw PrinterConnectionError.keychain }
    }
    static func load(serial: String) throws -> String {
        var request = query(serial); request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, let code = String(data: data, encoding: .utf8) else { throw PrinterConnectionError.keychain }
        return code
    }
    static func remove(serial: String) throws {
        let status = SecItemDelete(query(serial) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PrinterConnectionError.keychain }
    }
}
