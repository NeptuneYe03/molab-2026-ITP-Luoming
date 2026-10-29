import Foundation
import CoreGraphics
import CoreImage

// 只负责液面物理、气泡、蝙蝠和透明绘图层。
// 由 FlowCamera 的串行队列调用，无需独立计时器。
final class SodaRenderer {
    private let bounds = CGRect(x: 0, y: 0, width: 720, height: 1280)
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var gravityX = 0.0
    private var gravityY = -1.0
    private var neutralX = 0.0
    private var slope = 0.0
    private var slopeVelocity = 0.0
    private var waveEnergy = 0.0
    private var animationTime = 0.0
    private var lastBatTime = -10.0
    private var bats: [SodaBat] = []
    private let overlayContext = CGContext(data: nil, width: 720, height: 1280,
        bitsPerComponent: 8, bytesPerRow: 720 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)

    private struct SodaBat {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var age = 0.0
        var size: Double
        var phase: Double
    }


    func updateMotion(x: Double, y: Double, shake: Double, kickX: Double) {
        gravityX = x
        gravityY = y
        // userAcceleration 已移除重力，只有明显摇动时触发。
        if shake > 1.0 && animationTime - lastBatTime > 0.8 {
            lastBatTime = animationTime
            waveEnergy = min(waveEnergy + 0.8, 1.5)
            slopeVelocity += max(-2.0, min(kickX, 2.0))
            spawnBats()
        }
    }

    func recenter() {
        neutralX = gravityX
        slope = 0
        slopeVelocity = 0
        waveEnergy = 0
    }

    func step(dt: Double) {
        animationTime += dt
        // 自由液面跟随重力，弹簧阻尼产生滞后和停下后的来回晃动。
        let target = max(-0.72, min((gravityX - neutralX) / max(abs(gravityY), 0.45), 0.72))
        slopeVelocity += ((target - slope) * 22 - slopeVelocity * 3.4) * dt
        slope += slopeVelocity * dt
        // 适度限制斜率，保证橙汽水始终留在屏幕下方。
        slope = max(-0.90, min(slope, 0.90))
        waveEnergy *= exp(-dt * 1.8)
        for index in bats.indices {
            bats[index].age += dt
            bats[index].x += bats[index].vx * dt
            bats[index].y += bats[index].vy * dt
    }
    bats.removeAll { $0.age > 3.2 || $0.y > 1450 }
    }

    private func surfaceY(_ x: Double) -> Double {
        let amplitude = 3.0 + min(abs(slopeVelocity) * 15.0, 32.0) + waveEnergy * 24.0
        return 1280.0 / 3.0 + slope * (x - 360)
             + sin(x / 720 * .pi * 2 + animationTime * 4.2) * amplitude
             + sin(x / 720 * .pi * 4 - animationTime * 3.1) * amplitude * 0.22
    }

    private func spawnBats() {
        guard bats.count < 16 else { return }
        for index in 0..<5 {
            let x = Double.random(in: 100...620)
            bats.append(SodaBat(x: x, y: surfaceY(x) + 16,
                vx: Double.random(in: -95...95), vy: Double.random(in: 190...320),
                size: Double.random(in: 18...29), phase: Double(index) * 1.7))
        }
    }

    func composite(over base: CIImage) -> CIImage {
        guard let ctx = overlayContext else { return base }
        ctx.clear(bounds)
        // Core Graphics 原点在左下角；这里的水位是画面底部的三分之一。
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
        let colors = [CGColor(red: 1.0, green: 0.25, blue: 0.0, alpha: 0.78),
                      CGColor(red: 1.0, green: 0.62, blue: 0.02, alpha: 0.55)] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: 750), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // 少量细气泡，限定在液体内；摇动后横向扰动短暂增加。
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.93, blue: 0.69, alpha: 0.55))
        for index in 0..<23 {
            let seed = Double(index)
            let x = (seed * 137.7 + 45).truncatingRemainder(dividingBy: 720)
                  + sin(animationTime * 1.6 + seed) * (3 + waveEnergy * 8)
            let y = (seed * 83 + animationTime * (19 + seed.truncatingRemainder(dividingBy: 5) * 4))
                .truncatingRemainder(dividingBy: 750) - 15
            let r = 2.5 + seed.truncatingRemainder(dividingBy: 4) * 1.2
            ctx.strokeEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))
        }
        ctx.restoreGState()
        // 水面上只有一条细亮边，不铺满整屏。
        let rim = CGMutablePath()
        rim.move(to: CGPoint(x: 0, y: surfaceY(0)))
        for x in stride(from: 8.0, through: 720.0, by: 8.0) {
            rim.addLine(to: CGPoint(x: x, y: surfaceY(x)))
        }
        ctx.addPath(rim)
        ctx.setLineWidth(3)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.82, blue: 0.30, alpha: 0.90))
        ctx.strokePath()
        for bat in bats { drawBat(bat, in: ctx) }
        guard let overlay = ctx.makeImage() else { return base }
        return CIImage(cgImage: overlay).composited(over: base).cropped(to: bounds)
    }

    private func drawBat(_ bat: SodaBat, in ctx: CGContext) {
        ctx.saveGState()
        let flutter = 0.65 + 0.35 * sin(bat.age * 22 + bat.phase)
        ctx.translateBy(x: bat.x + sin(bat.age * 5 + bat.phase) * 24, y: bat.y)
        ctx.rotate(by: -bat.vx / 650)
        ctx.scaleBy(x: bat.size, y: bat.size)
        let alpha = min(1.0, bat.age * 8) * min(1.0, max(0, (3.2 - bat.age) * 2))
        ctx.setFillColor(CGColor(gray: 0.015, alpha: alpha))
        // 左右翼用两段弧线和锯齿下缘组成，翅膀振幅随时间变化。
        for sign in [-1.0, 1.0] {
            ctx.saveGState()
            ctx.scaleBy(x: sign, y: 1)
            let wing = CGMutablePath()
            wing.move(to: CGPoint(x: 0, y: 0.10))
            wing.addCurve(to: CGPoint(x: 1.45, y: flutter),
                          control1: CGPoint(x: 0.42, y: 0.85 * flutter),
                          control2: CGPoint(x: 0.90, y: 1.15 * flutter))
            wing.addQuadCurve(to: CGPoint(x: 1.02, y: -0.14), control: CGPoint(x: 1.15, y: 0.04))
            wing.addQuadCurve(to: CGPoint(x: 0.63, y: -0.30), control: CGPoint(x: 0.84, y: 0.17))
            wing.addQuadCurve(to: CGPoint(x: 0.12, y: -0.43), control: CGPoint(x: 0.40, y: -0.02))
            wing.closeSubpath()
            ctx.addPath(wing); ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.fillEllipse(in: CGRect(x: -0.20, y: -0.42, width: 0.40, height: 0.76))
        let ears = CGMutablePath()
        ears.move(to: CGPoint(x: -0.20, y: 0.16))
        ears.addLine(to: CGPoint(x: -0.21, y: 0.59))
        ears.addLine(to: CGPoint(x: 0, y: 0.35))
        ears.addLine(to: CGPoint(x: 0.21, y: 0.59))
        ears.addLine(to: CGPoint(x: 0.20, y: 0.16))
        ears.closeSubpath()
        ctx.addPath(ears); ctx.fillPath()
        ctx.restoreGState()
    }
}
