import SwiftUI
import UIKit
import Combine
import AVFoundation
import CoreMotion
import CoreImage
import Photos

// ContentView.swift
// iOS 17+ / Swift 5

final class FlowCamera: NSObject, ObservableObject,
                        AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var preview: CGImage?
    @Published var takingPhoto = false
    @Published var exportedPhoto: URL?
    @Published var exportedVideo: URL?
    @Published var ready = false
    @Published var recording = false
    @Published var saving = false
    @Published var message = "Starting camera…"
    @Published var alertText = ""
    @Published var showAlert = false

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(
        label: "BooSoda.camera",
        qos: .userInitiated
    )

    private let motion = CMMotionManager()
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let previewSlot = DispatchSemaphore(value: 1)

    private let bounds = CGRect(
        x: 0,
        y: 0,
        width: 720,
        height: 1280
    )

    private var configured = false
    private var active = false
    private var recordingOnQueue = false
    private var savingOnQueue = false

    private var gravityX = 0.0
    private var gravityY = -1.0
    private var neutralX = 0.0

    private var slope = 0.0
    private var slopeVelocity = 0.0
    private var waveEnergy = 0.0

    private var lastFrameTime: Double?
    private var animationTime = 0.0
    private var lastBatTime = -10.0

    private var bats: [SodaBat] = []

    private let overlayContext = CGContext(
        data: nil,
        width: 720,
        height: 1280,
        bitsPerComponent: 8,
        bytesPerRow: 720 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )

    private struct SodaBat {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var age = 0.0
        var size: Double
        var phase: Double
    }

    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var firstTime: CMTime?
    private var fileURL: URL?
    private var frameCount = 0

    // MARK: - 启动相机

    func start() {
        #if targetEnvironment(simulator)
        message = "Use a real iPhone for camera + tilt."
        return
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            activate()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.activate()
                    } else {
                        self?.report(
                            "Camera access is off. Enable it in Settings."
                        )
                    }
                }
            }

        default:
            report("Camera access is off. Enable it in Settings.")
        }
        #endif
    }

    private func activate() {
        queue.async { [weak self] in
            guard let self, !self.active else { return }

            do {
                if !self.configured {
                    try self.configure()
                }

                self.active = true
                self.lastFrameTime = nil
                self.session.startRunning()

                DispatchQueue.main.async {
                    self.ready = true
                    self.message = "Tilt to slosh · Shake for bats"
                }
            } catch {
                self.report(error.localizedDescription)
            }
        }

        guard motion.isDeviceMotionAvailable,
              !motion.isDeviceMotionActive else {
            return
        }

        motion.deviceMotionUpdateInterval = 1.0 / 30.0

        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            let x = data.gravity.x
            let y = data.gravity.y
            let acceleration = data.userAcceleration

            // userAcceleration 已移除重力。
            let shake = sqrt(
                acceleration.x * acceleration.x
                + acceleration.y * acceleration.y
                + acceleration.z * acceleration.z
            )

            let kickX = acceleration.x

            self.queue.async {
                self.gravityX = x
                self.gravityY = y

                guard self.active else { return }

                // 摇动阈值，单位为 g；数值越小越容易触发。
                if shake > 1.0,
                   self.animationTime - self.lastBatTime > 0.8 {

                    self.lastBatTime = self.animationTime
                    self.waveEnergy = min(self.waveEnergy + 0.8, 1.5)
                    self.slopeVelocity += max(-2.0, min(kickX, 2.0))

                    self.spawnBats()
                }
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw FlowError("No rear camera found.")
        }

        let input = try AVCaptureDeviceInput(device: device)

        guard session.canAddInput(input) else {
            throw FlowError("Camera input unavailable.")
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_32BGRA
        ]

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

            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async {
                self.ready = false
            }
        }
    }

    // MARK: - 校准

    func recenter() {
        queue.async {
            self.neutralX = self.gravityX
            self.slope = 0
            self.slopeVelocity = 0
            self.waveEnergy = 0
        }
    }

    // MARK: - 拍照

    // 保存当前合成帧，不包含按钮和界面文字。
    // 照片为 720 × 1280 PNG。
    func takePhoto() {
        guard ready, !takingPhoto, let image = preview else { return }

        takingPhoto = true

        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = UIImage(cgImage: image).pngData() else {
                self.finishPhoto("Could not create photo.")
                return
            }

            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    self.keepPhoto(
                        data,
                        message: "Photos access is off. Use Share Photo to save to Files."
                    )
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()

                    options.originalFilename = "BooSoda.png"

                    request.addResource(
                        with: .photo,
                        data: data,
                        options: options
                    )
                }) { saved, error in
                    if saved {
                        self.finishPhoto("Photo saved to Photos!")
                    } else {
                        self.keepPhoto(
                            data,
                            message: error?.localizedDescription
                                ?? "Could not save to Photos. Use Share Photo."
                        )
                    }
                }
            }
        }
    }

    private func keepPhoto(_ data: Data, message: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BooSoda-\(UUID().uuidString).png")

        do {
            try data.write(to: url, options: .atomic)

            DispatchQueue.main.async {
                self.exportedPhoto = url
            }

            finishPhoto(message)
        } catch {
            finishPhoto("Could not save photo: \(error.localizedDescription)")
        }
    }

    private func finishPhoto(_ text: String) {
        DispatchQueue.main.async {
            self.takingPhoto = false
            self.alertText = text
            self.showAlert = true
        }
    }

    // MARK: - 录像控制

    func toggleRecording() {
        queue.async {
            guard self.active, !self.savingOnQueue else { return }

            if self.recordingOnQueue {
                self.finishRecording()
            } else {
                self.recordingOnQueue = true
                self.frameCount = 0
                self.firstTime = nil

                DispatchQueue.main.async {
                    self.recording = true
                    self.message = "Recording · silent video"
                }
            }
        }
    }

    // MARK: - 逐帧处理

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard active,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        autoreleasepool {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let now = CMTimeGetSeconds(timestamp)

            let dt = min(
                max(now - (lastFrameTime ?? now - 1.0 / 30.0), 0.001),
                0.05
            )

            lastFrameTime = now
            animationTime += dt

            // 液面跟随重力，弹簧阻尼产生滞后和回弹。
            let target = max(
                -0.72,
                min(
                    (gravityX - neutralX) / max(abs(gravityY), 0.45),
                    0.72
                )
            )

            slopeVelocity += (
                (target - slope) * 22 - slopeVelocity * 3.4
            ) * dt

            slope += slopeVelocity * dt
            slope = max(-0.90, min(slope, 0.90))

            waveEnergy *= exp(-dt * 1.8)

            for index in bats.indices {
                bats[index].age += dt
                bats[index].x += bats[index].vx * dt
                bats[index].y += bats[index].vy * dt
            }

            bats.removeAll {
                $0.age > 3.2 || $0.y > 1450
            }

            let base = fit(CIImage(cvPixelBuffer: pixelBuffer))
            let result = soda(over: base)

            // 同一个合成结果用于预览、拍照和录像。
            if previewSlot.wait(timeout: .now()) == .success {
                if let image = ci.createCGImage(result, from: bounds) {
                    DispatchQueue.main.async {
                        self.preview = image
                        self.previewSlot.signal()
                    }
                } else {
                    previewSlot.signal()
                }
            }

            if recordingOnQueue {
                do {
                    if writer == nil {
                        try prepareWriter()
                    }

                    try writeFrame(result, at: timestamp)
                } catch {
                    abortRecording(error.localizedDescription)
                }
            }
        }
    }

    private func fit(_ image: CIImage) -> CIImage {
        let rect = image.extent

        let scale = max(
            bounds.width / rect.width,
            bounds.height / rect.height
        )

        let scaled = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        let dx = (bounds.width - scaled.extent.width) / 2
            - scaled.extent.minX

        let dy = (bounds.height - scaled.extent.height) / 2
            - scaled.extent.minY

        return scaled
            .transformed(
                by: CGAffineTransform(translationX: dx, y: dy)
            )
            .cropped(to: bounds)
    }

    // MARK: - 液面

    private func surfaceY(_ x: Double) -> Double {
        let amplitude = 3.0
            + min(abs(slopeVelocity) * 15.0, 32.0)
            + waveEnergy * 24.0

        // 平均水位为画面高度的三分之一。
        return 1280.0 / 3.0
            + slope * (x - 360)
            + sin(x / 720 * .pi * 2 + animationTime * 4.2) * amplitude
            + sin(x / 720 * .pi * 4 - animationTime * 3.1)
                * amplitude * 0.22
    }

    private func spawnBats() {
        guard bats.count < 16 else { return }

        for index in 0..<5 {
            let x = Double.random(in: 100...620)

            bats.append(
                SodaBat(
                    x: x,
                    y: surfaceY(x) + 16,
                    vx: Double.random(in: -95...95),
                    vy: Double.random(in: 190...320),
                    size: Double.random(in: 18...29),
                    phase: Double(index) * 1.7
                )
            )
        }
    }

    private func soda(over base: CIImage) -> CIImage {
        guard let ctx = overlayContext else { return base }

        ctx.clear(bounds)

        // 绘图坐标原点在左下角。
        let liquid = CGMutablePath()
        liquid.move(to: CGPoint(x: 0, y: 0))
        liquid.addLine(to: CGPoint(x: 720, y: 0))

        for x in stride(from: 720.0, through: 0.0, by: -8.0) {
            liquid.addLine(to: CGPoint(x: x, y: surfaceY(x)))
        }

        liquid.closeSubpath()

        ctx.saveGState()
        ctx.addPath(liquid)
        ctx.clip()

        // 橙汽水：底部深橙，上方浅橙，保留透明度。
        let colors = [
            CGColor(red: 1.0, green: 0.25, blue: 0.0, alpha: 0.78),
            CGColor(red: 1.0, green: 0.62, blue: 0.02, alpha: 0.55)
        ] as CFArray

        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: [0, 1]
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: 750),
                options: [
                    .drawsBeforeStartLocation,
                    .drawsAfterEndLocation
                ]
            )
        }

        // 气泡只绘制在液体内部。
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(
            CGColor(red: 1, green: 0.93, blue: 0.69, alpha: 0.55)
        )

        for index in 0..<23 {
            let seed = Double(index)

            let x = (seed * 137.7 + 45)
                .truncatingRemainder(dividingBy: 720)
                + sin(animationTime * 1.6 + seed)
                    * (3 + waveEnergy * 8)

            let y = (
                seed * 83
                + animationTime
                    * (19 + seed.truncatingRemainder(dividingBy: 5) * 4)
            )
            .truncatingRemainder(dividingBy: 750) - 15

            let r = 2.5
                + seed.truncatingRemainder(dividingBy: 4) * 1.2

            ctx.strokeEllipse(
                in: CGRect(
                    x: x - r,
                    y: y - r,
                    width: r * 2,
                    height: r * 2
                )
            )
        }

        ctx.restoreGState()

        // 液面细亮边。
        let rim = CGMutablePath()
        rim.move(to: CGPoint(x: 0, y: surfaceY(0)))

        for x in stride(from: 8.0, through: 720.0, by: 8.0) {
            rim.addLine(to: CGPoint(x: x, y: surfaceY(x)))
        }

        ctx.addPath(rim)
        ctx.setLineWidth(3)
        ctx.setStrokeColor(
            CGColor(red: 1, green: 0.82, blue: 0.30, alpha: 0.90)
        )
        ctx.strokePath()

        for bat in bats {
            drawBat(bat, in: ctx)
        }

        guard let overlay = ctx.makeImage() else { return base }

        return CIImage(cgImage: overlay)
            .composited(over: base)
            .cropped(to: bounds)
    }

    // MARK: - 蝙蝠

    private func drawBat(_ bat: SodaBat, in ctx: CGContext) {
        ctx.saveGState()

        let flutter = 0.65 + 0.35 * sin(bat.age * 22 + bat.phase)

        ctx.translateBy(
            x: bat.x + sin(bat.age * 5 + bat.phase) * 24,
            y: bat.y
        )
        ctx.rotate(by: -bat.vx / 650)
        ctx.scaleBy(x: bat.size, y: bat.size)

        let alpha = min(1.0, bat.age * 8)
            * min(1.0, max(0, (3.2 - bat.age) * 2))

        ctx.setFillColor(CGColor(gray: 0.015, alpha: alpha))

        // 两侧翅膀。
        for sign in [-1.0, 1.0] {
            ctx.saveGState()
            ctx.scaleBy(x: sign, y: 1)

            let wing = CGMutablePath()
            wing.move(to: CGPoint(x: 0, y: 0.10))

            wing.addCurve(
                to: CGPoint(x: 1.45, y: flutter),
                control1: CGPoint(x: 0.42, y: 0.85 * flutter),
                control2: CGPoint(x: 0.90, y: 1.15 * flutter)
            )

            wing.addQuadCurve(
                to: CGPoint(x: 1.02, y: -0.14),
                control: CGPoint(x: 1.15, y: 0.04)
            )

            wing.addQuadCurve(
                to: CGPoint(x: 0.63, y: -0.30),
                control: CGPoint(x: 0.84, y: 0.17)
            )

            wing.addQuadCurve(
                to: CGPoint(x: 0.12, y: -0.43),
                control: CGPoint(x: 0.40, y: -0.02)
            )

            wing.closeSubpath()

            ctx.addPath(wing)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 身体。
        ctx.fillEllipse(
            in: CGRect(
                x: -0.20,
                y: -0.42,
                width: 0.40,
                height: 0.76
            )
        )

        // 耳朵。
        let ears = CGMutablePath()
        ears.move(to: CGPoint(x: -0.20, y: 0.16))
        ears.addLine(to: CGPoint(x: -0.21, y: 0.59))
        ears.addLine(to: CGPoint(x: 0, y: 0.35))
        ears.addLine(to: CGPoint(x: 0.21, y: 0.59))
        ears.addLine(to: CGPoint(x: 0.20, y: 0.16))
        ears.closeSubpath()

        ctx.addPath(ears)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - 视频写入

    private func prepareWriter() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BooSoda-\(UUID().uuidString).mp4")

        fileURL = url

        let newWriter = try AVAssetWriter(
            outputURL: url,
            fileType: .mp4
        )

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 720,
                AVVideoHeightKey: 1280,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000
                ]
            ]
        )

        input.expectsMediaDataInRealTime = true

        let newAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 720,
                kCVPixelBufferHeightKey as String: 1280,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard newWriter.canAdd(input) else {
            throw FlowError("Cannot create video writer.")
        }

        newWriter.add(input)

        guard newWriter.startWriting() else {
            throw newWriter.error
                ?? FlowError("Cannot start recording.")
        }

        newWriter.startSession(atSourceTime: .zero)

        writer = newWriter
        writerInput = input
        adaptor = newAdaptor
    }

    private func writeFrame(
        _ image: CIImage,
        at timestamp: CMTime
    ) throws {
        guard let writer,
              let input = writerInput,
              let adaptor else {
            return
        }

        guard writer.status == .writing else {
            throw writer.error
                ?? FlowError("Recording stopped unexpectedly.")
        }

        guard input.isReadyForMoreMediaData else { return }

        guard let pool = adaptor.pixelBufferPool else {
            throw FlowError("Video buffer unavailable.")
        }

        var buffer: CVPixelBuffer?

        guard CVPixelBufferPoolCreatePixelBuffer(
            nil,
            pool,
            &buffer
        ) == kCVReturnSuccess,
              let buffer else {
            throw FlowError("Cannot allocate video frame.")
        }

        ci.render(
            image,
            to: buffer,
            bounds: bounds,
            colorSpace: colorSpace
        )

        if firstTime == nil {
            firstTime = timestamp
        }

        let relativeTime = CMTimeSubtract(
            timestamp,
            firstTime ?? timestamp
        )

        guard adaptor.append(
            buffer,
            withPresentationTime: relativeTime
        ) else {
            throw writer.error
                ?? FlowError("Cannot write video frame.")
        }

        frameCount += 1
    }

    private func finishRecording() {
        guard recordingOnQueue else { return }

        recordingOnQueue = false

        guard let completedWriter = writer,
              let input = writerInput,
              let url = fileURL,
              frameCount > 0 else {
            abortRecording("No frames recorded. Please try a longer clip.")
            return
        }

        savingOnQueue = true

        writer = nil
        writerInput = nil
        adaptor = nil
        fileURL = nil
        firstTime = nil

        DispatchQueue.main.async {
            self.recording = false
            self.saving = true
            self.message = "Saving video…"
        }

        input.markAsFinished()

        completedWriter.finishWriting { [weak self] in
            guard let self else { return }

            if completedWriter.status == .completed {
                self.saveToPhotos(url)
            } else {
                try? FileManager.default.removeItem(at: url)

                self.finishSaving(
                    completedWriter.error?.localizedDescription
                        ?? "Video export failed."
                )
            }
        }
    }

    // MARK: - 保存视频

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }

            guard status == .authorized || status == .limited else {
                self.keepExport(
                    url,
                    message: "Photos access is off. Use Share Video to save this clip to Files."
                )
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(
                    atFileURL: url
                )
            }) { saved, error in
                if saved {
                    try? FileManager.default.removeItem(at: url)
                    self.finishSaving("Video saved to Photos!")
                } else {
                    self.keepExport(
                        url,
                        message: error?.localizedDescription
                            ?? "Could not save to Photos. Use Share Video."
                    )
                }
            }
        }
    }

    private func keepExport(_ url: URL, message: String) {
        DispatchQueue.main.async {
            self.exportedVideo = url
        }

        finishSaving(message)
    }

    private func finishSaving(_ text: String) {
        queue.async {
            self.savingOnQueue = false
        }

        DispatchQueue.main.async {
            self.saving = false
            self.message = "Tilt to slosh · Shake for bats"
            self.alertText = text
            self.showAlert = true
        }
    }

    private func abortRecording(_ text: String) {
        recordingOnQueue = false
        writer?.cancelWriting()

        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }

        writer = nil
        writerInput = nil
        adaptor = nil
        fileURL = nil
        firstTime = nil

        DispatchQueue.main.async {
            self.recording = false
        }

        report(text)
    }

    private func report(_ text: String) {
        DispatchQueue.main.async {
            self.message = text
            self.alertText = text
            self.showAlert = true
        }
    }
}

private struct FlowError: LocalizedError {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var errorDescription: String? {
        text
    }
}

// MARK: - 界面

struct ContentView: View {
    @StateObject private var camera = FlowCamera()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let image = camera.preview {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                } else {
                    Color.orange.opacity(0.12)

                    Text(camera.message)
                        .multilineTextAlignment(.center)
                        .padding(30)
                }

                VStack {
                    header

                    Spacer()

                    if camera.recording {
                        Label("REC", systemImage: "record.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 28) {
                        photoButton
                        recordButton

                        // 保持录像按钮位于中间。
                        Color.clear
                            .frame(width: 54, height: 54)
                    }

                    if camera.saving {
                        Text("Saving…")
                            .font(.caption)
                    }

                    if let url = camera.exportedPhoto {
                        ShareLink(item: url) {
                            Label(
                                "Share Photo",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .font(.caption)
                        .padding(8)
                        .background(
                            .black.opacity(0.3),
                            in: Capsule()
                        )
                    }

                    if let url = camera.exportedVideo {
                        ShareLink(item: url) {
                            Label(
                                "Share Video",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .font(.caption)
                        .padding(8)
                        .background(
                            .black.opacity(0.3),
                            in: Capsule()
                        )
                    }
                }
                .padding(.bottom, 12)
                .foregroundStyle(.white)
            }
        }
        .background(.black)
        .task {
            camera.start()
        }
        .onDisappear {
            camera.pause()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                camera.start()
            } else {
                camera.pause()
            }
        }
        .alert("Boo Soda", isPresented: $camera.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(camera.alertText)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("BOO SODA")
                    .font(
                        .system(
                            size: 26,
                            weight: .heavy,
                            design: .rounded
                        )
                    )

                Text("Tilt to slosh · Shake for bats")
                    .font(.caption)
            }
            .padding(12)
            .background(
                .black.opacity(0.38),
                in: RoundedRectangle(cornerRadius: 16)
            )

            Spacer()

            Button {
                camera.recenter()
            } label: {
                Image(systemName: "scope")
                    .font(.title2)
                    .padding(12)
                    .background(
                        .black.opacity(0.38),
                        in: Circle()
                    )
            }
            .accessibilityLabel("Recenter liquid")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var photoButton: some View {
        Button {
            camera.takePhoto()
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.30))
                    .frame(width: 54, height: 54)

                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: 54, height: 54)

                if camera.takingPhoto {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                }
            }
        }
        .disabled(
            !camera.ready
            || camera.takingPhoto
            || camera.saving
        )
        .accessibilityLabel("Take photo")
    }

    private var recordButton: some View {
        Button {
            camera.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.18))
                    .frame(width: 78, height: 78)

                Circle()
                    .stroke(.white, lineWidth: 3)
                    .frame(width: 74, height: 74)

                if camera.saving {
                    ProgressView()
                        .tint(.white)
                } else if camera.recording {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(!camera.ready || camera.saving)
        .accessibilityLabel(
            camera.recording
            ? "Stop recording"
            : "Start recording"
        )
    }
}
