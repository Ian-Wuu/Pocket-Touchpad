import SwiftUI

// Available only in Debug simulator builds; the captured views are the real UI.
enum ScreenshotPreview {
    static var enabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--screenshot-preview")
        #else
        false
        #endif
    }
    static func has(_ flag: String) -> Bool { enabled && ProcessInfo.processInfo.arguments.contains(flag) }
}

@main
struct TouchpadApp: App {
    @StateObject private var connection = PhoneConnection()
    @StateObject private var preferences = Preferences()
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RemoteView(connection: connection, preferences: preferences)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { connection.background() }
                    if phase == .active { connection.resume() }
                    UIApplication.shared.isIdleTimerDisabled = phase == .active && connection.connected
                }
                .onAppear { connection.resume() }
                .onChange(of: connection.connected) { _, connected in UIApplication.shared.isIdleTimerDisabled = connected }
        }
    }
}

struct RemoteView: View {
    @ObservedObject var connection: PhoneConnection
    @ObservedObject var preferences: Preferences
    @State private var scrolling = false
    @AppStorage("sensitivity") private var sensitivity = 1.5
    @AppStorage("haptics") private var haptics = true
    @State private var showConnection = false
    @State private var showSettings = false
    @State private var showKeyboard = false
    @State private var editing = false
    @State private var landscape = false
    @State private var dragOrigins: [Int: CGPoint] = [:]
    @State private var resizeOrigin: CGSize?
    private func tick() { if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) } }
    var body: some View {
        VStack(spacing: landscape ? 6 : 16) {
            if !landscape { header }
            GeometryReader { geometry in
                let size = geometry.size
                let rowOneY: CGFloat = landscape ? size.height / 2 - 10 : 34
                let rowTwoY: CGFloat = landscape ? size.height / 2 + 58 : 120
                let padTop: CGFloat = landscape ? 0 : 177
                let controlWidth = landscape ? size.width * 0.36 - 24 : size.width
                let buttonSize: CGFloat = landscape ? 48 : 60
                let controlLeft = (size.width - controlWidth) / 2
                let space = max(80, size.height - padTop)
                let padWidth = size.width * preferences.width
                let padHeight = space * preferences.height
                let padY = padTop + padHeight / 2 + (space - padHeight) * preferences.centerY
                ZStack {
                    if landscape {
                        HStack(spacing: 0) {
                            padBackground.frame(width: size.width * 0.30)
                            Spacer(minLength: 0)
                            padBackground.frame(width: size.width * 0.30)
                        }
                        .overlay {
                            TouchSurface(scrolling: scrolling, dragLocked: connection.dragLocked, dualHand: true, settings: connection.trackpadSettings, sensitivity: sensitivity, haptics: haptics, enabled: connection.canControl && !editing, send: connection.send)
                        }
                        .frame(width: size.width, height: size.height)
                        .position(x: size.width / 2, y: size.height / 2)
                        ConcentricRectangle(corners: .fixed(28))
                            .fill(Color(uiColor: .secondarySystemBackground).opacity(0.55))
                            .frame(width: size.width * 0.36, height: 232)
                            .position(x: size.width / 2, y: size.height / 2)
                            .allowsHitTesting(false)
                        Rectangle().fill(.primary.opacity(0.07)).frame(width: controlWidth, height: 0.5)
                            .position(x: size.width / 2, y: size.height / 2 + 24).allowsHitTesting(false)
                        header.frame(width: controlWidth).position(x: size.width / 2, y: size.height / 2 - 78)
                    } else {
                        padBackground
                            .overlay {
                                TouchSurface(scrolling: scrolling, dragLocked: connection.dragLocked, dualHand: false, settings: connection.trackpadSettings, sensitivity: sensitivity, haptics: haptics, enabled: connection.canControl && !editing, send: connection.send)
                            }
                            .clipShape(padShape)
                            .frame(width: padWidth, height: padHeight)
                            .position(x: size.width / 2, y: padY)
                    }
                    if editing {
                        padShape.stroke(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                            .frame(width: padWidth, height: padHeight).position(x: size.width / 2, y: padY).allowsHitTesting(false)
                        Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 48, height: 48).glassEffect(.regular, in: .circle)
                            .position(x: (size.width + padWidth) / 2 - 24, y: padY + padHeight / 2 - 24)
                            .gesture(DragGesture().onChanged { value in
                                if resizeOrigin == nil { resizeOrigin = CGSize(width: preferences.width, height: preferences.height) }
                                preferences.width = min(1, max(0.55, (resizeOrigin?.width ?? 0.98) + value.translation.width * 2 / size.width))
                                preferences.height = min(1, max(0.4, (resizeOrigin?.height ?? 0.98) + value.translation.height / space))
                            }.onEnded { _ in resizeOrigin = nil; tick() })
                            .accessibilityLabel("调整触摸区大小")
                    }
                    HStack(spacing: 0) {
                        functionButton("单击", icon: "cursorarrow", enabled: connection.canControl && !connection.dragLocked) { connection.send(InputEvent(kind: "click", action: "left")); tick() }
                        Spacer(minLength: 8)
                        functionButton("右键", icon: "computermouse", enabled: connection.canControl && !connection.dragLocked) { connection.send(InputEvent(kind: "click", action: "right")); tick() }
                        Spacer(minLength: 8)
                        functionButton(connection.dragLocked ? "放开" : "拖移", icon: connection.dragLocked ? "hand.point.up.left.fill" : "hand.point.up.left", enabled: connection.canControl, selected: connection.dragLocked) { connection.toggleDrag(); tick() }
                        Spacer(minLength: 8)
                        functionButton("键盘", icon: "keyboard", enabled: true) { connection.releaseDrag(); showKeyboard = true; tick() }
                    }.frame(width: controlWidth).position(x: size.width / 2, y: rowOneY).disabled(editing)
                    ForEach(Array(preferences.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                        VStack(spacing: 7) {
                            Button {
                                guard !editing else { return }
                                if shortcut.action == "scroll" { connection.releaseDrag(); scrolling.toggle() }
                                else { connection.send(InputEvent(kind: "key", action: shortcut.action)) }; tick()
                            } label: {
                                Image(systemName: Shortcut.icon(shortcut.action)).font(.system(size: landscape ? 22 : 25, weight: .regular))
                                    .frame(width: buttonSize, height: buttonSize)
                                    .modifier(ControlSurface(landscape: landscape, secondary: true, selected: shortcut.action == "scroll" && scrolling))
                            }.buttonStyle(.plain).disabled(!editing && !connection.canControl)
                            if !landscape { Text(Shortcut.label(shortcut.action)).font(.caption).foregroundStyle(.secondary) }
                        }
                        .frame(width: 68, height: landscape ? 48 : 82)
                        .overlay { if editing { RoundedRectangle(cornerRadius: 20).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) } }
                        .position(x: controlLeft + buttonSize / 2 + (controlWidth - buttonSize) * (landscape ? Double(index) / 3 : shortcut.x), y: min(size.height - 42, max(42, rowTwoY + size.height * (landscape ? 0 : shortcut.y))))
                        .gesture(DragGesture(minimumDistance: editing ? 0 : 10000).onChanged { value in
                            guard editing else { return }
                            if dragOrigins[shortcut.id] == nil { dragOrigins[shortcut.id] = CGPoint(x: shortcut.x, y: shortcut.y) }
                            let origin = dragOrigins[shortcut.id]!
                            preferences.shortcuts[index].x = min(1, max(0, origin.x + value.translation.width / max(1, size.width - buttonSize)))
                            preferences.shortcuts[index].y = min((size.height - rowTwoY - 42) / size.height, max((42 - rowTwoY) / size.height, origin.y + value.translation.height / size.height))
                        }.onEnded { _ in dragOrigins[shortcut.id] = nil; if editing { tick() } })
                        .accessibilityLabel(Shortcut.label(shortcut.action))
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, landscape ? 12 : 6).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { landscape = $0; editing = false; connection.releaseDrag() }
        .background(Color(uiColor: .systemBackground))
        .persistentSystemOverlays(.hidden)
        .ignoresSafeArea(.container, edges: landscape ? .all : .bottom)
        .sheet(isPresented: $showConnection) { PairingView(connection: connection) }
        .sheet(isPresented: $showSettings) { SettingsView(preferences: preferences, connection: connection) }
        .sheet(isPresented: $showKeyboard) { KeyboardView(connection: connection, haptics: haptics) }
        .task {
            guard ScreenshotPreview.enabled else { return }
            preferences.reset()
            // Let the window attach before requesting the same native layout as rotation.
            try? await Task.sleep(for: .milliseconds(500))
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: ScreenshotPreview.has("--landscape") ? .landscapeRight : .portrait))
            }
            try? await Task.sleep(for: .milliseconds(500))
            if ScreenshotPreview.has("--drag") { connection.toggleDrag() }
            if ScreenshotPreview.has("--edit-layout") {
                preferences.width = 0.9
                preferences.height = 0.78
                preferences.centerY = 0.9
                editing = true
            }
            if ScreenshotPreview.has("--keyboard") { showKeyboard = true }
            if ScreenshotPreview.has("--settings") || ScreenshotPreview.has("--layout-settings") { showSettings = true }
            if ScreenshotPreview.has("--pairing") { showConnection = true }
        }
    }
    // Resolve the device-concentric corners first, then apply the largest to all four.
    private var padShape: ConcentricRectangle { ConcentricRectangle(corners: .concentric, isUniform: true) }
    private var padBackground: some View {
        padShape
            .fill(Color(uiColor: .secondarySystemBackground))
            .overlay {
                Canvas { context, size in
                    for x in stride(from: 16.0, through: size.width, by: 18) {
                        for y in stride(from: 16.0, through: size.height, by: 18) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.primary.opacity(0.10)))
                        }
                    }
                }.clipShape(padShape).allowsHitTesting(false)
            }
    }
    private func functionButton(_ title: String, icon: String, enabled: Bool, selected: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 7) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: landscape ? 23 : 27, weight: .medium))
                    .frame(width: landscape ? 48 : 60, height: landscape ? 48 : 60)
                    .modifier(ControlSurface(landscape: landscape, selected: selected))
            }.buttonStyle(.plain).disabled(!enabled)
            if !landscape { Text(title).font(.caption.weight(.medium)) }
        }.frame(width: landscape ? 48 : 60).accessibilityLabel(title).accessibilityValue(selected ? "已按住，再点放开" : "").accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var header: some View {
        HStack {
            Button { connection.releaseDrag(); showConnection = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                    Text(connection.connected ? "我的 Mac" : landscape ? "连接" : "连接 Mac").font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }.padding(.horizontal, 14).frame(height: 42).modifier(HeaderSurface(landscape: landscape))
            }.buttonStyle(.plain)
            Spacer()
            if editing {
                Button("完成") { editing = false; tick() }.buttonStyle(.glass)
            } else {
                Menu {
                    Toggle("单指滚动", isOn: $scrolling)
                    if let latency = connection.latency { Text("网络往返 \(latency) ms") }
                    Divider()
                    Button("编辑布局", systemImage: "slider.horizontal.3") { connection.releaseDrag(); editing = true }.disabled(landscape)
                    Button("设置与手势", systemImage: "gearshape") { connection.releaseDrag(); showSettings = true }
                } label: {
                    Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 42).modifier(HeaderSurface(landscape: landscape))
                }.buttonStyle(.plain).accessibilityLabel("更多选项")
                    .onChange(of: scrolling) { _, _ in connection.releaseDrag(); tick() }
            }
        }
    }
}

private struct HeaderSurface: ViewModifier {
    var landscape: Bool
    func body(content: Content) -> some View {
        if landscape { content.contentShape(Capsule()) }
        else { content.glassEffect(.regular.interactive(), in: .capsule) }
    }
}

private struct ControlSurface: ViewModifier {
    var landscape: Bool
    var secondary = false
    var selected = false
    func body(content: Content) -> some View {
        if selected {
            content.foregroundStyle(Color(uiColor: .systemBackground))
                .background(Color.primary, in: landscape ? AnyShape(RoundedRectangle(cornerRadius: 16)) : AnyShape(Circle()))
        } else if landscape {
            content.foregroundStyle(secondary ? .secondary : .primary)
                .contentShape(RoundedRectangle(cornerRadius: 16))
        } else if secondary {
            content.foregroundStyle(.secondary)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.65), in: .circle)
        } else { content.foregroundStyle(.primary).glassEffect(.regular.interactive(), in: .circle) }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var connection: PhoneConnection
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("sensitivity") private var sensitivity = 1.5
    @AppStorage("haptics") private var haptics = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    Section("手势") {
                        Label(connection.settingsSynced ? "已读取 Mac 触控板设置" : "连接 Mac 后读取手势设置", systemImage: "checkmark.circle")
                        Text("默认支持多指操作，无需切换姿势。单指移动；双指滚动、缩放、旋转；轻点和多指操作跟随 Mac 上的开关。")
                        Text(connection.trackpadSettings.threeFingerDrag ? "三指移动：拖移。四指左右滑动：切换桌面；上下滑动：调度中心 / 应用窗口。" : "三指或四指切换桌面、调度中心和应用窗口，取决于 Mac 的设置。")
                        Text("拖移按钮亮起后持续按住左键，抬手不会放开；再点按钮结束。也可长按后拖动，松手结束。")
                        Text("横屏两侧都支持手势；两拇指各占一侧时，同向移动光标、张合缩放。")
                        if connection.trackpadSettings.continuousDock == true {
                            Text("桌面切换跟随滑动进度；可以中途停住或反向退回，松手时由系统完成或取消。")
                        }
                    }.font(.subheadline)
                    Section("兼容说明") {
                        Text("这是手势桥接，尚未注册为硬件触控板。自然滚动、轻点、三指拖移等读取 Mac 设置；缩放、旋转和桌面切换依赖系统事件兼容，效果因 macOS 与应用而异。")
                        Text("手机不能提供 Magic Trackpad 的力度感应。通知中心手势需要 Mac 已设置对应键盘快捷键。")
                    }.font(.footnote).foregroundStyle(.secondary)
                    Section("外观") {
                        Picker("显示模式", selection: $appearance) {
                            Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                        }
                    }
                    Section {
                        Toggle("触觉反馈", isOn: $haptics)
                        LabeledContent("滑动灵敏度", value: String(format: "%.1f×", sensitivity))
                        Slider(value: $sensitivity, in: 0.5...3, step: 0.1).accessibilityLabel("滑动灵敏度")
                    } header: { Text("触控手感") } footer: {
                        Text(connection.trackpadSettings.nativeAcceleration == true ? "已接入此 Mac 的原生加速曲线，跟随系统跟踪速度。这里调整手机滑动距离，横竖屏都生效。" : "调整手机滑动距离。此 Mac 暂未提供可用的原生加速曲线，使用线性移动。")
                    }
                    Section("触摸区域") {
                        LabeledContent("宽度", value: "\(Int(preferences.width * 100))%")
                        Slider(value: $preferences.width, in: 0.55...1).accessibilityLabel("触摸区宽度")
                        LabeledContent("高度", value: "\(Int(preferences.height * 100))%")
                        Slider(value: $preferences.height, in: 0.4...1).accessibilityLabel("触摸区高度")
                        Slider(value: $preferences.centerY, in: 0...1) { Text("垂直位置") }.accessibilityLabel("触摸区垂直位置")
                    }.id("touch-area")
                    Section("自定义按钮") {
                        ForEach(preferences.shortcuts.indices, id: \.self) { index in
                            Picker("按钮 \(index + 1)", selection: $preferences.shortcuts[index].action) {
                                ForEach(Shortcut.actions, id: \.self) { Text(Shortcut.label($0)).tag($0) }
                            }
                        }
                        Button("恢复默认布局") { preferences.reset() }
                    }
                }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                    .task {
                        if ScreenshotPreview.has("--layout-settings") {
                            try? await Task.sleep(for: .milliseconds(500))
                            scroll.scrollTo("touch-area", anchor: .top)
                        }
                    }
            }
        }
    }
}

struct KeyboardView: View {
    @ObservedObject var connection: PhoneConnection
    var haptics: Bool
    @State private var text = ScreenshotPreview.enabled ? "Hello from iPhone." : ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    private func tick() { if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("在手机上输入，在 Mac 上继续。")
                    .font(.title2.weight(.semibold))
                Text("先在 Mac 选中输入框。中文选词完成后，点击发送。")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text).focused($focused).frame(minHeight: 110, maxHeight: 180)
                    .padding(12).scrollContentBackground(.hidden).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityLabel("发送到 Mac 的文字")
                HStack(spacing: 12) {
                    Button("Tab") { connection.send(InputEvent(kind: "key", action: "tab")); tick() }
                    Button { connection.send(InputEvent(kind: "key", action: "delete")); tick() } label: { Image(systemName: "delete.left") }.accessibilityLabel("Mac 退格")
                    Button { connection.send(InputEvent(kind: "key", action: "return")); tick() } label: { Image(systemName: "return") }.accessibilityLabel("Mac 回车")
                    Spacer()
                    Button { connection.send(InputEvent(kind: "text", text: text)); text = ""; tick() } label: { Label("发送", systemImage: "arrow.up") }
                        .buttonStyle(.glassProminent).disabled(text.isEmpty || text.utf8.count > 16384)
                }.buttonStyle(.glass).controlSize(.large).disabled(!connection.canControl)
                if !connection.canControl { Text(connection.status).font(.footnote).foregroundStyle(.secondary) }
                if text.utf8.count > 16384 { Text("文字过长，请分段发送。").font(.footnote).foregroundStyle(.red) }
                Spacer(minLength: 0)
            }.padding(24).background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("键盘").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onAppear { focused = true }
        }
    }
}

#Preview("浅色") { RemoteView(connection: PhoneConnection(), preferences: Preferences()).preferredColorScheme(.light) }
#Preview("深色") { RemoteView(connection: PhoneConnection(), preferences: Preferences()).preferredColorScheme(.dark) }
