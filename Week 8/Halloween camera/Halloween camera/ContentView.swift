import SwiftUI

// 只负责界面布局和用户操作。
struct ContentView: View {
    @StateObject private var camera = FlowCamera()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = camera.preview {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Color.orange.opacity(0.12)
                    Text(camera.message).multilineTextAlignment(.center).padding(30)
                }
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("BOO SODA").font(.system(size: 26, weight: .heavy, design: .rounded))
                            Text("Tilt to slosh · Shake for bats").font(.caption)
                        }
                        .padding(12)
                        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 16))
                        Spacer()
                        Button { camera.recenter() } label: {
                            Image(systemName: "scope").font(.title2).padding(12)
                                .background(.black.opacity(0.38), in: Circle())
                        }.accessibilityLabel("Recenter liquid")
                    }
                    .padding(.horizontal, 18).padding(.top, 12)
                    Spacer()
                    if camera.recording {
                        Label("REC", systemImage: "record.circle.fill")
                            .font(.caption.bold()).foregroundStyle(.white)
                    }
                    HStack(spacing: 28) {
                        Button { camera.takePhoto() } label: {
                            ZStack {
                                Circle().fill(.black.opacity(0.30)).frame(width: 54, height: 54)
                                Circle().stroke(.white.opacity(0.9), lineWidth: 1.5).frame(width: 54, height: 54)
                                if camera.takingPhoto {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "camera.fill").font(.title2)
                                }
                            }
                        }
                        .disabled(!camera.ready || camera.takingPhoto || camera.saving)
                        .accessibilityLabel("Take photo")
                        Button { camera.toggleRecording() } label: {
                            ZStack {
                                Circle().fill(.black.opacity(0.18)).frame(width: 78, height: 78)
                                Circle().stroke(.white, lineWidth: 3).frame(width: 74, height: 74)
                                if camera.saving {
                                    ProgressView().tint(.white)
                                } else if camera.recording {
                                    RoundedRectangle(cornerRadius: 5).fill(.red).frame(width: 28, height: 28)
                                } else {
                                    Circle().fill(.white).frame(width: 60, height: 60)
                                }
                            }
                        }
                        .disabled(!camera.ready || camera.saving)
                        .accessibilityLabel(camera.recording ? "Stop recording" : "Start recording")
                        Color.clear.frame(width: 54, height: 54)
                    }
                    if camera.saving { Text("Saving…").font(.caption) }
                    if let url = camera.exportedPhoto {
                        ShareLink(item: url) { Label("Share Photo", systemImage: "square.and.arrow.up") }
                            .font(.caption).padding(8).background(.black.opacity(0.3), in: Capsule())
                    }
                    if let url = camera.exportedVideo {
                        ShareLink(item: url) { Label("Share Video", systemImage: "square.and.arrow.up") }
                            .font(.caption).padding(8).background(.black.opacity(0.3), in: Capsule())
                    }
                }
                .padding(.bottom, 12)
                .foregroundStyle(.white)
            }
        }
        .background(.black)
        .task { camera.start() }
        .onDisappear { camera.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() }
            else { camera.pause() }
        }
        .alert("Boo Soda", isPresented: $camera.showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(camera.alertText) }
        .preferredColorScheme(.dark)
    }
}
