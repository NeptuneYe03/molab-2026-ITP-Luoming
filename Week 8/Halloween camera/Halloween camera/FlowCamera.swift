import SwiftUI
import Combine
import AVFoundation
import CoreMotion
import CoreImage

// 相机采集、Core Motion 输入和逐帧调度。
// 串行队列上的状态仅在 queue 中访问；界面状态在主线程更新。
final class FlowCamera: NSObject, ObservableObject,
                        AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var preview: CGImage?
    @Published var takingPhoto = false
    @Published var exportedPhoto: URL?
    @Published var ready = false
    @Published var recording = false
    @Published var saving = false
    @Published var message = "Starting camera…"
    @Published var alertText = ""
    @Published var showAlert = false

    @Published var exportedVideo: URL?
    private let session = AVCaptureSession()
    let queue = DispatchQueue(label: "ColorFlow.camera", qos: .userInitiated)
    private let motion = CMMotionManager()
    let ci = CIContext(options: [.cacheIntermediates: false])
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let previewSlot = DispatchSemaphore(value: 1)
    let bounds = CGRect(x: 0, y: 0, width: 720, height: 1280)

    private var configured = false
    var active = false
    var recordingOnQueue = false
    var savingOnQueue = false
    private let renderer = SodaRenderer()
    private var lastFrameTime: Double?

    // 存储属性放在主体中，供录像 extension 使用。
    var writer: AVAssetWriter?
    var writerInput: AVAssetWriterInput?
    var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    var firstTime: CMTime?
    var fileURL: URL?
    var frameCount = 0


    func start() {
        #if targetEnvironment(simulator)
        message = "Use a real iPhone for camera + tilt."
        return
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            activate()
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.activate() }
                    else { self?.report("Camera access is off. Enable it in Settings.") }
                }
            }
        } else {
            report("Camera access is off. Enable it in Settings.")
        }
        #endif
    }

    private func activate() {
        queue.async { [weak self] in
            guard let self, !self.active else { return }
            do {
                if !self.configured { try self.configure() }
                self.active = true
                self.lastFrameTime = nil
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.ready = true
                    self.message = "Tilt to slosh · Shake for bats"
                }
            } catch { self.report(error.localizedDescription) }
        }
        if motion.isDeviceMotionAvailable && !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 30.0
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                let x = data.gravity.x
                let y = data.gravity.y
                let acceleration = data.userAcceleration
                let shake = sqrt(acceleration.x * acceleration.x
                               + acceleration.y * acceleration.y
                               + acceleration.z * acceleration.z)
                let kickX = acceleration.x
                self.queue.async {
                    guard self.active else { return }
                    self.renderer.updateMotion(x: x, y: y, shake: shake, kickX: kickX)
                }
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 后置相机，竖屏。输出降低到 720p 档，减少实时处理负担。
        session.sessionPreset = .hd1280x720
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back) else {
            throw FlowError("No rear camera found.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw FlowError("Camera input unavailable.") }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw FlowError("Camera output unavailable.")
        }
        session.addOutput(output)
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        configured = true
    }

    func pause() {
        motion.stopDeviceMotionUpdates()
        queue.async { [weak self] in
            guard let self else { return }
            self.active = false
            self.finishRecording()
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.ready = false }
        }
    }

    func recenter() {
        queue.async { self.renderer.recenter() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard active, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let now = CMTimeGetSeconds(timestamp)
            let dt = min(max(now - (lastFrameTime ?? now - 1.0 / 30.0), 0.001), 0.05)
            lastFrameTime = now

            renderer.step(dt: dt)
            let base = fit(CIImage(cvPixelBuffer: pixelBuffer))
            let result = renderer.composite(over: base)

            // 预览与录像共用 result，保证保存的画面也有颜色。
            if previewSlot.wait(timeout: .now()) == .success {
                if let image = ci.createCGImage(result, from: bounds) {
                    DispatchQueue.main.async {
                        self.preview = image
                        self.previewSlot.signal()
                    }
                } else { previewSlot.signal() }
            }
            if recordingOnQueue {
                do {
                    if writer == nil { try prepareWriter() }
                    try writeFrame(result, at: timestamp)
                } catch { abortRecording(error.localizedDescription) }
            }
        }
    }

    private func fit(_ image: CIImage) -> CIImage {
        let rect = image.extent
        let scale = max(bounds.width / rect.width, bounds.height / rect.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (bounds.width - scaled.extent.width) / 2 - scaled.extent.minX
        let dy = (bounds.height - scaled.extent.height) / 2 - scaled.extent.minY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: bounds)
    }

    func report(_ text: String) {
        DispatchQueue.main.async {
            self.message = text
            self.alertText = text
            self.showAlert = true
        }
    }
}

struct FlowError: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

