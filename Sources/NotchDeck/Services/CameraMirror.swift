import AVFoundation
import SwiftUI

/// The front camera as a mirror. Runs only while the Mirror tab is on screen.
final class CameraMirror: ObservableObject {
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isRunning = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "notchdeck.camera")
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
            queue.async { [weak self] in self?.run() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorization = granted ? .authorized : .denied
                    if granted { self?.start() }
                }
            }
        default:
            authorization = .denied
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    private func run() {
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .high
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video)
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            configured = true
        }
        guard !session.isRunning else { return }
        session.startRunning()
        DispatchQueue.main.async { self.isRunning = true }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
