import SwiftUI
import Network
import ApplicationServices
import CoreImage.CIFilterBuiltins
import Darwin

final class Receiver: ObservableObject {
    @Published var status = "正在启动"
    @Published var connected = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var key = PairingKeychain.load("receiver") ?? TouchWire.newKey()
    @Published var pairingSaved = true
    @Published var addresses: [String] = []
    @Published var selectedAddress = ""
    private let serviceName: String = {
        if let saved = UserDefaults.standard.string(forKey: "receiverService") { return saved }
        let value = "Touchpad-" + UUID().uuidString
        UserDefaults.standard.set(value, forKey: "receiverService")
        return value
    }()
    private var listener: NWListener?
    private var channels: [UUID: Channel] = [:]
    private var activeID: UUID?
    private var dragging = false
    private var zoomRemainder = 0.0 // Compatibility with older phones.
    private let gestures = GestureOutput()
    private let acceleration = PointerAcceleration()
    private var displayBounds = DesktopBounds.screens()
    private var manualDrag = false
    private var gestureDrag = false
    private var pendingRightTap: DispatchWorkItem?
    private var lastTwoFingerTap = -100.0
    private var pendingTapPoint = CGPoint.zero
    private var lastSettingsRefresh = 0.0
    private var lastClickTime = 0.0
    private var lastClickPoint = CGPoint.zero
    private var clickCount: Int64 = 0
    private var lastInput = Date()
    private var lastPeerActivity = Date()
    private var pointer: CGPoint?
    private var timer: Timer?
    init() {
        pairingSaved = PairingKeychain.save(key, account: "receiver")
        refreshAddresses()
        gestures.settings.nativeAcceleration=acceleration.available
        gestures.settings.continuousDock=gestures.continuousDock
        start()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshPermission()
            self.refreshSettings()
            if self.dragging && Date().timeIntervalSince(self.lastInput) > 3 { self.release() }
            if self.gestures.dockActive && Date().timeIntervalSince(self.lastPeerActivity) > 6 { self.gestures.cancel() }
        }
    }
    var pairingURL: String {
        var c = URLComponents()
        c.scheme = "touchpad"
        c.host = "pair"
        c.queryItems = [URLQueryItem(name: "host", value: selectedAddress), URLQueryItem(name: "key", value: key), URLQueryItem(name: "service", value: serviceName), URLQueryItem(name: "name", value: Host.current().localizedName ?? "我的 Mac")]
        return c.string ?? ""
    }
    var qr: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(pairingURL.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 7, y: 7)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    func refreshAddresses() {
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0 else { return }
        defer { freeifaddrs(ptr) }
        var result: [String] = []
        var current = ptr
        while let p = current {
            defer { current = p.pointee.ifa_next }
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  p.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  p.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        addresses = result
        if !result.contains(selectedAddress) { selectedAddress = result.first ?? "" }
    }
    func start() {
        do {
            let server = try NWListener(using: TouchWire.parameters(key: key), on: NWEndpoint.Port(rawValue: TouchWire.port)!)
            listener = server
            server.service = NWListener.Service(name: serviceName, type: "_touchpad._tcp")
            server.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.status = "等待 iPhone 连接"
                case .failed(let error): self?.status = error.localizedDescription
                default: break
                }
            }
            server.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            server.start(queue: .main)
        } catch { status = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection) {
        guard channels.count < 4 else { connection.cancel(); return }
        let id = UUID()
        let channel = Channel(connection)
        channels[id] = channel
        channel.onState = { [weak self, weak channel] ready, message in
            guard let self else { return }
            if ready {
                guard self.activeID == nil else { channel?.close("已有手机连接"); return }
                self.activeID = id
                self.connected = true
                self.status = "iPhone 已连接"
                channel?.send(InputEvent(kind: "status", action: self.trusted ? "ready" : "permission"))
                self.sendSettings(channel)
            } else {
                self.channels.removeValue(forKey: id)
                if self.activeID == id {
                    self.activeID = nil
                    self.connected = false
                    self.status = "等待 iPhone 连接"
                    self.release()
                }
            }
        }
        channel.onEvent = { [weak self, weak channel] event in
            guard let self, self.activeID == id else { return }
            self.lastPeerActivity=Date()
            if event.kind == "ping" {
                self.refreshPermission()
                channel?.send(InputEvent(kind: "status", action: self.trusted ? "ready" : "permission"))
                channel?.send(InputEvent(kind: "pong", x: event.x))
                return
            }
            self.handle(event)
        }
        channel.start()
    }
    private func sendSettings(_ channel: Channel?) {
        guard let data = try? JSONEncoder().encode(gestures.settings), let text = String(data: data, encoding: .utf8) else { return }
        channel?.send(InputEvent(kind: "settings", text: text))
    }
    private func refreshSettings() {
        let now=ProcessInfo.processInfo.systemUptime
        guard now-lastSettingsRefresh > 2 else { return }
        lastSettingsRefresh=now
        var settings=MacTrackpadPreferences.read()
        acceleration.refresh(index:settings.trackingSpeed)
        settings.nativeAcceleration=acceleration.available
        settings.continuousDock=gestures.continuousDock
        displayBounds=DesktopBounds.screens()
        if gestures.settings != settings {
            gestures.settings=settings
            for channel in channels.values { sendSettings(channel) }
        }
    }
    func disconnect() {
        Array(channels.values).forEach { $0.close() }
        release()
        pointer = nil
    }
    func rotateKey() {
        disconnect()
        listener?.cancel()
        key = TouchWire.newKey()
        pairingSaved = PairingKeychain.save(key, account: "receiver")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.start() }
    }
    func refreshPermission() {
        let permission = AXIsProcessTrusted()
        guard trusted != permission else { return }
        trusted = permission
        Array(channels.values).forEach { $0.send(InputEvent(kind: "status", action: permission ? "ready" : "permission")) }
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermission()
    }
    #if TOUCHPAD_INPUT_CHECK
    var nativeInputReady:Bool { acceleration.available && gestures.continuousDock }
    // Opt-in visual acceptance build. Never included in the normal app.
    func visualCheck(axis:Int) {
        release()
        let windowID=UInt32(NSApp.windows.first(where: { $0.title == "Pocket Touchpad · Mac" })?.windowNumber ?? 0)
        let library=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_NOW)
        typealias Connection = @convention(c) () -> Int32
        typealias Transform = @convention(c) (Int32,UInt32,UnsafeMutablePointer<CGAffineTransform>) -> Int32
        var observations=[String]()
        func sample(_ phase:String) {
            guard let library,let c=dlsym(library,"SLSMainConnectionID"),let t=dlsym(library,"SLSGetWindowTransform") else { return }
            var value=CGAffineTransform.identity
            let result=unsafeBitCast(t,to:Transform.self)(unsafeBitCast(c,to:Connection.self)(),windowID,&value)
            let windows=CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] ?? []
            let dockPID=NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.dock" }?.processIdentifier
            let dock=windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == dockPID }.map { $0[kCGWindowBounds as String] ?? "" }
            observations.append("\(phase): result=\(result) transform=\(value) Dock=\(dock)")
            try? observations.joined(separator:"\n").write(toFile:"/private/tmp/touchpad-visual-check.txt",atomically:true,encoding:.utf8)
        }
        sample("before")
        for delay in 0...16 {
            DispatchQueue.main.asyncAfter(deadline:.now()+Double(delay)) { [weak self] in self?.lastPeerActivity=Date() }
        }
        handle(InputEvent(kind:"dock",x:-0.001,y:Double(axis),action:"begin"))
        for (delay,progress,action) in [(0.2,-0.15,"change"),(0.5,-0.4,"change"),(8.0,-0.1,"change"),(14.0,0.0,"cancel")] {
            DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
                self?.handle(InputEvent(kind:"dock",x:progress,y:Double(axis),action:action,velocity:0))
            }
        }
        for (delay,label) in [(2.0,"40%"),(5.0,"hold40%"),(10.0,"return10%"),(15.5,"cancelled")] {
            DispatchQueue.main.asyncAfter(deadline:.now()+delay) { sample(label) }
        }
    }
    #endif
    private var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }
    private func mouse(_ type: CGEventType, button: CGMouseButton = .left, point: CGPoint? = nil) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point ?? pointer ?? location, mouseButton: button)?.post(tap: .cghidEventTap)
    }
    func release() {
        if dragging { mouse(.leftMouseUp); dragging = false }
        manualDrag=false; gestureDrag=false
        pendingRightTap?.cancel(); pendingRightTap=nil
        gestures.cancel()
    }
    private func updateDrag() {
        let wanted=manualDrag || gestureDrag
        if wanted != dragging { mouse(wanted ? .leftMouseDown : .leftMouseUp); dragging=wanted }
    }
    private func tap(_ event: InputEvent) {
        let p=gestures.settings
        if event.x == 1, p.tapToClick {
            let right=event.action == "bottom" && (p.secondaryCorner == 1 && event.y>0.8 || p.secondaryCorner == 2 && event.y<0.2)
            handle(InputEvent(kind:"click",action:right ? "right" : "left"))
        } else if event.x == 2 {
            let now=ProcessInfo.processInfo.systemUptime
            if p.smartZoom && pendingRightTap != nil && now-lastTwoFingerTap <= p.doubleClickInterval {
                pendingRightTap?.cancel(); pendingRightTap=nil; lastTwoFingerTap = -100
                gestures.smartZoom()
            } else {
                pendingRightTap?.cancel(); lastTwoFingerTap=now; pendingTapPoint=pointer ?? location
                let task=DispatchWorkItem { [weak self] in
                    guard let self else { return }; self.pendingRightTap=nil
                    if p.secondaryClick { self.mouse(.rightMouseDown,button:.right,point:self.pendingTapPoint); self.mouse(.rightMouseUp,button:.right,point:self.pendingTapPoint) }
                }
                pendingRightTap=task
                DispatchQueue.main.asyncAfter(deadline:.now()+(p.smartZoom ? p.doubleClickInterval : 0),execute:task)
            }
        } else if event.x == 3, p.lookup { gestures.system("lookup") }
    }
    private func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
    private func handle(_ event: InputEvent) {
        guard trusted else { return }
        if Date().timeIntervalSince(lastInput) > 0.1 { pointer = nil }
        lastInput = Date()
        switch event.kind {
        case "gesture":
            pointer = nil; gestures.interruptMomentum(); displayBounds=DesktopBounds.screens()
        case "tap": if !manualDrag { tap(event) }
        case "magnify", "rotate", "dock", "inertia", "page": gestures.handle(event)
        case "system": gestures.system(event.action)
        case "absolute", "move", "pointer":
            let point: CGPoint
            if event.kind == "absolute" {
                let bounds=CGDisplayBounds(CGMainDisplayID()) // Legacy phone compatibility only.
                point = CGPoint(x: bounds.minX + min(1, max(0, event.x)) * max(0, bounds.width - 1), y: bounds.minY + min(1, max(0, event.y)) * max(0, bounds.height - 1))
            } else {
                let origin = pointer ?? location
                let dx=max(-2000,min(2000,event.x)), dy=max(-2000,min(2000,event.y))
                let delta=event.kind == "pointer" ? acceleration.apply(x:dx,y:dy,dt:event.dt ?? 1/120) : CGPoint(x:dx,y:dy)
                point=DesktopBounds.constrain(CGPoint(x:origin.x+delta.x,y:origin.y+delta.y),from:origin,to:displayBounds)
            }
            pointer = point
            mouse(dragging ? .leftMouseDragged : .mouseMoved, point: point)
        case "click":
            guard !manualDrag else { return }
            if event.action == "right" { mouse(.rightMouseDown, button: .right); mouse(.rightMouseUp, button: .right) }
            else {
                let point = pointer ?? location
                let now = ProcessInfo.processInfo.systemUptime
                clickCount = now - lastClickTime < NSEvent.doubleClickInterval && hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < 6 ? min(3, clickCount + 1) : 1
                lastClickTime = now; lastClickPoint = point
                for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
                    let click = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                    click?.setIntegerValueField(.mouseEventClickState, value: clickCount)
                    click?.post(tap: .cghidEventTap)
                }
            }
        case "drag":
            if event.action == "manualBegin" { manualDrag=true; gestureDrag=false }
            else if event.action == "manualEnd" { manualDrag=false }
            else if event.action == "begin" { gestureDrag=true }
            else if event.action == "end" { gestureDrag=false }
            updateDrag()
        case "scroll":
            gestures.handle(event)
        case "zoom":
            zoomRemainder += max(-0.5, min(0.5, event.x))
            while abs(zoomRemainder) >= 0.10 {
                let zoomIn = zoomRemainder > 0
                press(zoomIn ? 24 : 27, flags: .maskCommand)
                zoomRemainder += zoomIn ? -0.10 : 0.10
            }
        case "text":
            // Split by Character, preserving surrogate pairs and combining sequences.
            var chunk = ""
            func emit(_ text: String) {
                let units = Array(text.utf16)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                    units.withUnsafeBufferPointer { p in e?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: p.baseAddress!) }
                    e?.post(tap: .cghidEventTap)
                }
            }
            for ch in event.text {
                if !chunk.isEmpty && (chunk + String(ch)).utf16.count > 20 { emit(chunk); chunk = "" }
                chunk.append(ch)
            }
            if !chunk.isEmpty { emit(chunk) }
        case "key":
            let mapping: [String: (CGKeyCode, CGEventFlags)] = ["return": (36, []), "delete": (51, []), "escape": (53, []), "tab": (48, []), "copy": (8, .maskCommand), "paste": (9, .maskCommand), "undo": (6, .maskCommand), "selectAll": (0, .maskCommand), "space": (49, [])]
            if let (code, flags) = mapping[event.action] { press(code, flags: flags) }
        default: break
        }
    }
}

@main
struct TouchpadMacApp: App {
    @StateObject private var receiver = Receiver()
    var body: some Scene {
        WindowGroup("Pocket Touchpad · Mac") {
            ReceiverView(receiver: receiver)
                .onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)) { _ in receiver.disconnect() }
        }
            .defaultSize(width: 440, height: 650)
            .windowResizability(.contentSize)
        MenuBarExtra("Pocket Touchpad", systemImage: "rectangle.and.hand.point.up.left") {
            Text(receiver.status)
            Button("断开手机") { receiver.disconnect() }.disabled(!receiver.connected)
            Divider()
            Button("退出") { receiver.disconnect(); NSApplication.shared.terminate(nil) }
        }
    }
}

struct ReceiverView: View {
    @ObservedObject var receiver: Receiver
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.and.hand.point.up.left").font(.system(size: 30, weight: .light))
            Text("Pocket Touchpad").font(.system(size: 28, weight: .semibold))
            Label(receiver.status, systemImage: receiver.connected ? "link" : "iphone").foregroundStyle(.secondary)
            if !receiver.trusted {
                Button("允许控制此 Mac") { receiver.requestPermission() }.buttonStyle(.borderedProminent).tint(.black)
                Text("在系统设置 → 隐私与安全性 → 辅助功能中开启 Pocket Touchpad Mac。")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let qr = receiver.qr {
                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 190, height: 190).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
            Text("用 iPhone 的 Pocket Touchpad 扫码连接\n两台设备需连接同一 Wi-Fi")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Picker("Mac 地址", selection: $receiver.selectedAddress) {
                ForEach(receiver.addresses, id: \.self) { Text($0).tag($0) }
            }
            HStack {
                Button("复制配对链接") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(receiver.pairingURL, forType: .string) }
                Button("刷新地址") { receiver.refreshAddresses() }
                Button("重新配对") { receiver.rotateKey() }
            }.controlSize(.small)
            if !receiver.pairingSaved { Text("无法保存配对，下次启动需重新扫码").font(.caption).foregroundStyle(.orange) }
            Text("加密直连 · 无云端 · 不记录输入内容").font(.caption).foregroundStyle(.tertiary)
            #if TOUCHPAD_INPUT_CHECK
            Text("验证：原生曲线 \(receiver.nativeInputReady ? "✓" : "×")")
            HStack {
                Button("验证调度中心跟手") { receiver.visualCheck(axis:2) }
                Button("验证桌面跟手") { receiver.visualCheck(axis:1) }
            }
            #endif
        }.padding(32).frame(width: 440).background(Color(nsColor: .windowBackgroundColor))
    }
}
