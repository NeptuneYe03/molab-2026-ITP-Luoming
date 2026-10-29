import Foundation
import AVFoundation
import CoreImage
import Photos

// 录像编码、结束录像和保存视频。
extension FlowCamera {
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

    func prepareWriter() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColorFlow-\(UUID().uuidString).mp4")
        fileURL = url
        let newWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 720,
            AVVideoHeightKey: 1280,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000]
        ])
        input.expectsMediaDataInRealTime = true
        let newAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 720,
                kCVPixelBufferHeightKey as String: 1280,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ])
        guard newWriter.canAdd(input) else { throw FlowError("Cannot create video writer.") }
        newWriter.add(input)
        guard newWriter.startWriting() else {
            throw newWriter.error ?? FlowError("Cannot start recording.")
        }
        newWriter.startSession(atSourceTime: .zero)
        writer = newWriter
        writerInput = input
        adaptor = newAdaptor
    }

    func writeFrame(_ image: CIImage, at timestamp: CMTime) throws {
        guard let writer, let input = writerInput, let adaptor else { return }
        guard writer.status == .writing else {
            throw writer.error ?? FlowError("Recording stopped unexpectedly.")
        }
        guard input.isReadyForMoreMediaData else { return }
        guard let pool = adaptor.pixelBufferPool else { throw FlowError("Video buffer unavailable.") }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { throw FlowError("Cannot allocate video frame.") }
        ci.render(image, to: buffer, bounds: bounds, colorSpace: colorSpace)
        if firstTime == nil { firstTime = timestamp }
        let relativeTime = CMTimeSubtract(timestamp, firstTime ?? timestamp)
        guard adaptor.append(buffer, withPresentationTime: relativeTime) else {
            throw writer.error ?? FlowError("Cannot write video frame.")
        }
        frameCount += 1
    }

    func finishRecording() {
        guard recordingOnQueue else { return }
        recordingOnQueue = false
        guard let completedWriter = writer, let input = writerInput,
              let url = fileURL, frameCount > 0 else {
            abortRecording("No frames recorded. Please try a longer clip.")
            return
        }
        savingOnQueue = true
        writer = nil; writerInput = nil; adaptor = nil; fileURL = nil; firstTime = nil
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
                self.finishSaving(completedWriter.error?.localizedDescription ?? "Video export failed.")
            }
        }
    }

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                // 拒绝照片权限时保留 MP4，并提供分享/保存到“文件”的出口。
                self.keepExport(url, message: "Photos access is off. Use Share Video to save this clip to Files.")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { saved, error in
                if saved {
                    try? FileManager.default.removeItem(at: url)
                    self.finishSaving("Video saved to Photos!")
                } else {
                    self.keepExport(url, message: error?.localizedDescription ?? "Could not save to Photos. Use Share Video.")
                }
            }
        }
    }

    private func keepExport(_ url: URL, message: String) {
        DispatchQueue.main.async { self.exportedVideo = url }
        finishSaving(message)
    }

    private func finishSaving(_ text: String) {
        queue.async { self.savingOnQueue = false }
        DispatchQueue.main.async {
            self.saving = false
            self.message = "Tilt to slosh · Shake for bats"
            self.alertText = text
            self.showAlert = true
        }
    }

    func abortRecording(_ text: String) {
        recordingOnQueue = false
        writer?.cancelWriting()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        writer = nil; writerInput = nil; adaptor = nil; fileURL = nil; firstTime = nil
        DispatchQueue.main.async { self.recording = false }
        report(text)
    }
}
