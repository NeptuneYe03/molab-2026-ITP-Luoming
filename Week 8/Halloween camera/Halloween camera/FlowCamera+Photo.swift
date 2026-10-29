import Foundation
import UIKit
import Photos

// 拍照：保存当前带汽水和蝙蝠的合成帧。
extension FlowCamera {
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
                    self.keepPhoto(data, message: "Photos access is off. Use Share Photo to save to Files.")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = "BooSoda.png"
                    request.addResource(with: .photo, data: data, options: options)
                }) { saved, error in
                    if saved {
                        self.finishPhoto("Photo saved to Photos!")
                    } else {
                        self.keepPhoto(data, message: error?.localizedDescription
                            ?? "Could not save to Photos. Use Share Photo.")
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
            DispatchQueue.main.async { self.exportedPhoto = url }
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
}
