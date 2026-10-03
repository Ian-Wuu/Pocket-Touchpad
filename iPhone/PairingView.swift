import SwiftUI
import AVFoundation

struct PairingView: View {
    @ObservedObject var connection: PhoneConnection
    @State private var link = ""
    @State private var scanning = false
    @State private var cameraError: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 24) {
                if !connection.savedMacs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("已配对的 Mac").font(.headline)
                        ForEach(connection.savedMacs) { mac in
                            HStack {
                                Button { connection.connectSaved(mac) } label: {
                                    Label(mac.name, systemImage: "desktopcomputer").frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.glass)
                                Menu { Button("忘记这台 Mac", role: .destructive) { connection.forget(mac) } } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            }
                        }
                    }
                }
                Image(systemName: "iphone.and.arrow.right.inward").font(.system(size: 48, weight: .light)).padding(.top, 28)
                Text("把 Mac，放进手心。").font(.title2.weight(.semibold))
                Text("在 Mac 打开 Pocket Touchpad Mac，\n连接同一 Wi-Fi，然后扫描配对二维码。")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button { scanning = true } label: { Label("扫描 Mac 二维码", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity).padding(.vertical, 8) }
                    .buttonStyle(.glassProminent)
                TextField("或粘贴 Mac 的配对链接", text: $link, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...4)
                    .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                Button("连接") { _ = connection.connect(link: link) }.buttonStyle(.glass).disabled(link.isEmpty)
                Text(connection.status).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let error = cameraError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                if connection.connected { Button("断开连接", role: .destructive) { connection.disconnect() } }
                Spacer()
                Label("配对加密直连，输入内容不经过云端", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
            }.padding(24) }.background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("连接 Mac").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onChange(of: connection.canControl) { _, ready in if ready { dismiss() } }
                .sheet(isPresented: $scanning) {
                    ZStack(alignment: .topTrailing) {
                        QRScanner { value in
                            scanning = false
                            link = value
                            _ = connection.connect(link: value)
                        } failure: { message in cameraError = message; scanning = false }
                        Button("取消") { scanning = false }.buttonStyle(.glass).padding(24)
                    }.ignoresSafeArea(edges: .bottom)
                }
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    var found: (String) -> Void
    var failure: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.found = found; controller.failure = failure
        return controller
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}
final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var found: (String) -> Void = { _ in }
    var failure: (String) -> Void = { _ in }
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "touchpad.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                if allowed { self.configure() }
                else { self.failure("相机权限未开启，可在系统设置中允许，或使用配对链接。") }
            }
        }
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            failure("相机不可用，请粘贴配对链接。"); return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { failure("无法启动扫码。"); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        queue.async { [session] in session.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished, let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, value.hasPrefix("touchpad://pair?") else { return }
        stop(); found(value)
    }
    func stop() { finished = true; queue.async { [session] in if session.isRunning { session.stopRunning() } } }
}
