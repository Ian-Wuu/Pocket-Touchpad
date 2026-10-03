import Foundation
import Network
import Security

struct InputEvent: Codable {
    var kind: String
    var x: Double = 0
    var y: Double = 0
    var text: String = ""
    var action: String = ""
    // Source sampling interval and release velocity, independent of Wi-Fi jitter.
    var dt: Double? = nil
    var velocity: Double? = nil
}

enum TouchWire {
    static let port: UInt16 = 49732
    static func parameters(key: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let secret = Array(key.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Array("Touchpad-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, secret as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.disableAckStretching = true
        let params = NWParameters(tls: tls, tcp: tcp)
        params.includePeerToPeer = true
        params.serviceClass = .interactiveVideo
        return params
    }
    static func newKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func validKey(_ key: String) -> Bool {
        key.count == 32 && key.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

// All channel state and callbacks are confined to the main queue.
final class Channel {
    let connection: NWConnection
    var onEvent: (InputEvent) -> Void = { _ in }
    var onState: (Bool, String) -> Void = { _, _ in }
    private var buffer = Data()
    private var closed = false
    private var ready = false
    private var inFlight = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pending: [InputEvent] = []
    init(_ connection: NWConnection) { self.connection = connection }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready:
                self.ready = true
                self.onState(true, "已连接")
                self.receive()
            case .failed(let error): self.close(error.localizedDescription)
            case .waiting(let error): self.close(error.localizedDescription)
            case .cancelled: self.close("已断开")
            default: break
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, !self.ready else { return }
            self.close("连接超时，请检查网络与配对码")
        }
    }
    func send(_ event: InputEvent) {
        guard ready, !closed else { return }
        // Coalesce only adjacent movement packets; never drop button/key ordering.
        if let last = pending.last, event.kind == last.kind, event.action == last.action, (event.action.isEmpty || event.action == "change"), ["move", "absolute", "scroll"].contains(event.kind) {
            if event.kind == "absolute" { pending[pending.count - 1] = event }
            else {
                pending[pending.count - 1].x += event.x
                pending[pending.count - 1].y += event.y
            }
        } else { pending.append(event) }
        guard pending.count < 256 else { close("连接拥堵，请重新连接"); return }
        flush()
    }
    private func flush() {
        // Small bounded pipeline: do not serialize every sample behind its send callback.
        while inFlight < 4, !pending.isEmpty, !closed {
            let event = pending.removeFirst()
            guard var data = try? encoder.encode(event), data.count < 65536 else { continue }
            data.append(10)
            inFlight += 1
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.inFlight -= 1
                if let error { self.close(error.localizedDescription) } else { self.flush() }
            })
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            if let data { self.buffer.append(data) }
            while let end = self.buffer.firstIndex(of: 10) {
                let line = self.buffer[..<end]
                guard line.count < 65536,
                      let event = try? self.decoder.decode(InputEvent.self, from: line),
                      event.x.isFinite, event.y.isFinite,
                      event.dt?.isFinite != false, event.velocity?.isFinite != false,
                      event.text.utf8.count <= 16384 else { self.close("无效数据"); return }
                self.buffer.removeSubrange(...end)
                self.onEvent(event)
            }
            if self.buffer.count >= 65536 { self.close("数据超出限制"); return }
            if complete || error != nil { self.close("连接已断开"); return }
            self.receive()
        }
    }
    func close(_ reason: String = "已断开") {
        guard !closed else { return }
        closed = true
        ready = false
        pending.removeAll()
        connection.cancel()
        onState(false, reason)
    }
}

// Pairing secrets live in the app's Keychain, never in UserDefaults or logs.
enum PairingKeychain {
    static func load(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "art.dongheng.touchpad.pairing", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    @discardableResult static func save(_ key: String, account: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "art.dongheng.touchpad.pairing", kSecAttrAccount as String: account]
        let value: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let result = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var item = query.merging(value) { _, new in new }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func delete(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "art.dongheng.touchpad.pairing", kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
