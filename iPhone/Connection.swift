import SwiftUI
import Network

struct PairedMac: Codable, Identifiable {
    var id: String
    var name: String
    var host: String
    var service: String?
}

final class PhoneConnection: ObservableObject {
    @Published var connected = false
    @Published var canControl = false
    @Published var status = "未连接"
    @Published var latency: Int?
    @Published var host = ""
    @Published var name = "我的 Mac"
    @Published var dragLocked = false
    @Published var trackpadSettings = TrackpadSettings()
    @Published var settingsSynced = false
    @Published var savedMacs: [PairedMac] = UserDefaults.standard.data(forKey: "pairedMacs").flatMap { try? JSONDecoder().decode([PairedMac].self, from: $0) } ?? []
    private var channel: Channel?
    private var timer: Timer?
    private var retry: DispatchWorkItem?
    private var target: (mac: PairedMac, key: String)?
    private var foreground = true
    private var generation = UUID()
    private var retryCount = 0
    private var lastPong = 0.0
    private var automatic = (UserDefaults.standard.object(forKey: "autoReconnect") as? Bool) ?? true

    init() {
        // Screenshot fixtures never open a channel or access pairing credentials.
        if ScreenshotPreview.enabled {
            connected = true
            canControl = true
            status = "已连接"
            savedMacs = []
            if ScreenshotPreview.has("--pairing") {
                connected = false
                canControl = false
                status = "未连接"
                savedMacs = [PairedMac(id: "preview-mac", name: "我的 Mac", host: "", service: nil)]
            }
        }
    }

    func connect(link: String) -> Bool {
        guard !ScreenshotPreview.enabled else { return false }
        guard let url = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "touchpad", url.host == "pair",
              let host = url.queryItems?.first(where: { $0.name == "host" })?.value, !host.isEmpty,
              let key = url.queryItems?.first(where: { $0.name == "key" })?.value, TouchWire.validKey(key) else {
            status = "配对链接无效，请从 Mac 复制或扫码"; return false
        }
        let service = url.queryItems?.first(where: { $0.name == "service" })?.value
        let name = url.queryItems?.first(where: { $0.name == "name" })?.value ?? "我的 Mac"
        target = (PairedMac(id: service ?? host, name: name, host: host, service: service), key)
        automatic = true
        UserDefaults.standard.set(true, forKey: "autoReconnect")
        retryCount = 0
        begin()
        return true
    }
    func connectSaved(_ mac: PairedMac) {
        guard !ScreenshotPreview.enabled else { return }
        guard let key = PairingKeychain.load(mac.id) else { status = "这台 Mac 的配对已失效，请重新扫码"; return }
        target = (mac, key)
        automatic = true
        UserDefaults.standard.set(true, forKey: "autoReconnect")
        retryCount = 0
        begin()
    }
    private func begin() {
        guard !ScreenshotPreview.enabled else { return }
        guard let target else { return }
        releaseDrag()
        generation = UUID()
        let attempt = generation
        retry?.cancel(); timer?.invalidate()
        channel?.close()
        connected = false; canControl = false; latency = nil
        host = target.mac.host; name = target.mac.name
        status = retryCount == 0 ? "正在连接…" : "正在自动重连…"
        let endpoint: NWEndpoint
        if let service = target.mac.service, !service.isEmpty {
            endpoint = .service(name: service, type: "_touchpad._tcp", domain: "local.", interface: nil)
        } else {
            endpoint = .hostPort(host: NWEndpoint.Host(target.mac.host), port: NWEndpoint.Port(rawValue: TouchWire.port)!)
        }
        let channel = Channel(NWConnection(to: endpoint, using: TouchWire.parameters(key: target.key)))
        self.channel = channel
        channel.onState = { [weak self] ready, message in
            guard let self, self.generation == attempt else { return }
            self.connected = ready
            if ready {
                self.retryCount = 0
                self.status = "正在检查 Mac 权限…"
                self.remember(target.mac, key: target.key)
                self.startHeartbeat()
            } else {
                self.canControl = false; self.dragLocked = false; self.latency = nil
                self.timer?.invalidate()
                self.status = message
                self.scheduleReconnect()
            }
        }
        channel.onEvent = { [weak self] event in
            guard let self, self.generation == attempt else { return }
            if event.kind == "settings", let data = event.text.data(using: .utf8), let settings = try? JSONDecoder().decode(TrackpadSettings.self, from: data) {
                self.trackpadSettings = settings; self.settingsSynced = true
            }
            if event.kind == "status" {
                let ready = event.action == "ready"
                if self.canControl != ready { self.canControl = ready }
                let status = ready ? "已连接 Mac" : "请在 Mac 允许辅助功能权限"
                if self.status != status { self.status = status }
            }
            if event.kind == "pong" {
                self.lastPong = ProcessInfo.processInfo.systemUptime
                let latency = max(0, Int((self.lastPong - event.x) * 1000))
                if self.latency != latency { self.latency = latency }
            }
        }
        channel.start()
    }
    private func remember(_ mac: PairedMac, key: String) {
        guard PairingKeychain.save(key, account: mac.id) else { status = "已连接，但配对记录保存失败"; return }
        savedMacs.removeAll { $0.id == mac.id }
        savedMacs.insert(mac, at: 0)
        persistRecords()
        UserDefaults.standard.set(mac.id, forKey: "lastMac")
    }
    private func persistRecords() {
        if let data = try? JSONEncoder().encode(savedMacs) { UserDefaults.standard.set(data, forKey: "pairedMacs") }
    }
    func forget(_ mac: PairedMac) {
        if target?.mac.id == mac.id { disconnect() }
        savedMacs.removeAll { $0.id == mac.id }
        PairingKeychain.delete(mac.id)
        persistRecords()
    }
    private func startHeartbeat() {
        timer?.invalidate()
        guard foreground else { return }
        lastPong = ProcessInfo.processInfo.systemUptime
        channel?.send(InputEvent(kind: "ping", x: lastPong))
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastPong > 5 { self.channel?.close("连接暂时中断"); return }
            self.channel?.send(InputEvent(kind: "ping", x: now))
            if self.dragLocked { self.send(InputEvent(kind: "hold")) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func scheduleReconnect() {
        guard foreground, automatic, target != nil else { return }
        retry?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.begin() }
        retry = task
        let delay = min(8.0, pow(2.0, Double(retryCount)))
        retryCount = min(4, retryCount + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    func resume() {
        guard !ScreenshotPreview.enabled else { return }
        foreground = true
        retryCount = 0
        if connected {
            startHeartbeat()
            let resumed = lastPong
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.foreground, self.connected, self.lastPong <= resumed else { return }
                self.channel?.close("正在恢复连接…")
            }
            return
        }
        guard automatic else { return }
        if target != nil { begin() }
        else if let mac = savedMacs.first(where: { $0.id == UserDefaults.standard.string(forKey: "lastMac") }) ?? savedMacs.first {
            connectSaved(mac)
        }
    }
    func background() {
        foreground = false
        releaseDrag()
        retry?.cancel(); timer?.invalidate()
        // Do not deliberately close the socket. iOS may still suspend it;
        // resume() probes it and recovers with the saved pairing if needed.
    }
    func send(_ event: InputEvent) {
        guard canControl else { return }

        channel?.send(event)
    }
    func toggleDrag() {
        guard canControl else { return }
        dragLocked.toggle()
        channel?.send(InputEvent(kind: "drag", action: dragLocked ? "manualBegin" : "manualEnd"))
    }
    func releaseDrag() {
        if dragLocked { channel?.send(InputEvent(kind: "drag", action: "manualEnd")); dragLocked = false }
    }
    func disconnect() {
        automatic = false
        UserDefaults.standard.set(false, forKey: "autoReconnect")
        retry?.cancel(); timer?.invalidate()
        releaseDrag()
        generation = UUID()
        channel?.close(); channel = nil; target = nil
        connected = false; canControl = false; latency = nil
        status = "未连接"
    }
}

struct Shortcut: Codable, Identifiable {
    var id: Int
    var action: String
    var x: Double
    var y: Double
    static let defaults = [Shortcut(id: 0, action: "escape", x: 0, y: 0), Shortcut(id: 1, action: "undo", x: 1.0 / 3, y: 0), Shortcut(id: 2, action: "copy", x: 2.0 / 3, y: 0), Shortcut(id: 3, action: "paste", x: 1, y: 0)]
    static let actions = ["escape", "undo", "copy", "paste", "selectAll", "tab", "return", "delete", "space", "scroll"]
    static func label(_ action: String) -> String {
        ["scroll": "滚动", "escape": "退出", "undo": "撤销", "copy": "复制", "paste": "粘贴", "selectAll": "全选", "tab": "Tab", "return": "回车", "delete": "退格", "space": "空格"][action] ?? action
    }
    static func icon(_ action: String) -> String {
        ["scroll": "arrow.up.arrow.down", "escape": "escape", "undo": "arrow.uturn.backward", "copy": "doc.on.doc", "paste": "document.on.clipboard", "selectAll": "selection.pin.in.out", "tab": "arrow.right.to.line", "return": "return", "delete": "delete.left", "space": "space"][action] ?? "circle"
    }
}

final class Preferences: ObservableObject {
    @Published var shortcuts: [Shortcut] { didSet { if let data = try? JSONEncoder().encode(shortcuts) { UserDefaults.standard.set(data, forKey: "shortcuts") } } }
    @Published var width: Double { didSet { UserDefaults.standard.set(width, forKey: "padWidth") } }
    @Published var height: Double { didSet { UserDefaults.standard.set(height, forKey: "padHeight") } }
    @Published var centerY: Double { didSet { UserDefaults.standard.set(centerY, forKey: "padY") } }
    init() {
        shortcuts = UserDefaults.standard.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([Shortcut].self, from: $0) } ?? Shortcut.defaults
        width = (UserDefaults.standard.object(forKey: "padWidth") as? Double) ?? 1
        height = (UserDefaults.standard.object(forKey: "padHeight") as? Double) ?? 1
        centerY = (UserDefaults.standard.object(forKey: "padY") as? Double) ?? 0.5
        if !UserDefaults.standard.bool(forKey: "alignedLayoutV2") {
            if UserDefaults.standard.data(forKey: "shortcuts") != nil {
                for i in shortcuts.indices { shortcuts[i].x = min(1, max(0, (shortcuts[i].x - 0.125) / 0.75)) }
            }
            if width == 0.98 { width = 1 }
            if height == 0.98 { height = 1 }
            if let data = try? JSONEncoder().encode(shortcuts) { UserDefaults.standard.set(data, forKey: "shortcuts") }
            UserDefaults.standard.set(width, forKey: "padWidth")
            UserDefaults.standard.set(height, forKey: "padHeight")
            UserDefaults.standard.set(true, forKey: "alignedLayoutV2")
        }
    }
    func reset() { shortcuts = Shortcut.defaults; width = 1; height = 1; centerY = 0.5 }
}
