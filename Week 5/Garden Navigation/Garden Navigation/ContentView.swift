import SwiftUI
import Combine

private let gardenBackground = Color(red: 0.99, green: 0.96, blue: 0.89)
private let gardenGreen = Color(red: 0.36, green: 0.48, blue: 0.32)
private let flowerColors: [Color] = [
    Color(red: 0.91, green: 0.48, blue: 0.40),
    Color(red: 0.97, green: 0.66, blue: 0.45),
    Color(red: 0.96, green: 0.76, blue: 0.39),
    Color(red: 0.93, green: 0.63, blue: 0.60)
]
private let leafColors: [Color] = [gardenGreen, Color(red: 0.58, green: 0.66, blue: 0.43)]

private struct PlantData {
    var isFlower: Bool
    var color: Color
    var scale: Double
    var angle: Double
    var offsetX: Double
    var offsetY: Double
}

struct ContentView: View {
    @State private var showGarden = false

    var body: some View {
        ZStack {
            gardenBackground.ignoresSafeArea()
            if showGarden {
                CountdownGardenPage { showGarden = false }
            } else {
                VStack(spacing: 26) {
                    PulsingFlower()
                    Text("Time Garden").font(.largeTitle).bold()
                    Text("Flowers give you time. Leaves take a little away.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Text("Start with 20 seconds\nFlower +3s  ·  Leaf −1s")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(gardenGreen)
                    Button("Enter My Garden") { showGarden = true }
                        .buttonStyle(.borderedProminent)
                        .tint(gardenGreen)
                }
                .padding(24)
            }
        }
    }
}

// Animation。
private struct PulsingFlower: View {
    @State private var flowerPulse: CGFloat = 0.85

    var body: some View {
        Canvas { context, size in
            drawFlower(in: context,
                       center: CGPoint(x: size.width / 2, y: size.height / 2),
                       radius: 58, color: flowerColors[0], angle: 0)
        }
        .frame(width: 150, height: 150)
        .scaleEffect(flowerPulse)
        .onAppear {
            // 从 0.85 倍放大到 1.15 倍，再自动缩小，持续重复。
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                flowerPulse = 1.15
            }
        }
    }
}

private struct CountdownGardenPage: View {
    var onBack: () -> Void
    @State private var plants: [PlantData] = []
    @State private var timeRemaining = 20
    @State private var timerIsRunning = false

    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            Text("My Time Garden").font(.title2).bold()
            Text("Flower +3s  ·  Leaf −1s")
                .foregroundStyle(gardenGreen)

            GeometryReader { geometry in
                let cellWidth = geometry.size.width / 4
                let cellHeight = geometry.size.height / 5
                let radius = min(cellWidth, cellHeight) * 0.30

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.45))

                    ForEach(plants.indices, id: \.self) { index in
                        // Leave the middle six cells empty for the countdown.
                        if isBorderCell(index) {
                            let plant = plants[index]
                            Button {
                                tapPlant(plant)
                            } label: {
                                Canvas { context, size in
                                    let center = CGPoint(
                                        x: size.width * (0.5 + plant.offsetX),
                                        y: size.height * (0.5 + plant.offsetY)
                                    )
                                    if plant.isFlower {
                                        drawFlower(in: context, center: center,
                                                   radius: radius * plant.scale,
                                                   color: plant.color, angle: plant.angle)
                                    } else {
                                        drawLeaves(in: context, center: center,
                                                   radius: radius * plant.scale,
                                                   color: plant.color, angle: plant.angle)
                                    }
                                }
                                .frame(width: cellWidth, height: cellHeight)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!timerIsRunning)
                            .accessibilityLabel(plant.isFlower ? "Flower, add 3 seconds" : "Leaf, subtract 1 second")
                            .position(
                                x: (Double(index % 4) + 0.5) * cellWidth,
                                y: (Double(index / 4) + 0.5) * cellHeight
                            )
                        }
                    }

                    VStack(spacing: 12) {
                        Text("\(timeRemaining)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundStyle(gardenGreen)
                        Text(timeRemaining > 0 ? "seconds left" : "Time is up!")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        if timeRemaining == 0 {
                            Button("Back Home", action: onBack)
                                .buttonStyle(.borderedProminent)
                                .tint(gardenGreen)
                        }
                    }
                    .frame(width: geometry.size.width * 0.46)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            Text(timeRemaining > 0 ? "Tap a plant to grow a new garden." : "Your garden is resting.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear {
            timeRemaining = 20
            growGarden()
            timerIsRunning = true
        }
        .onReceive(timer) { _ in
            if timerIsRunning && timeRemaining > 0 {
                timeRemaining -= 1
                if timeRemaining == 0 { timerIsRunning = false }
            }
        }
        .onDisappear { timerIsRunning = false }
    }

    private func isBorderCell(_ index: Int) -> Bool {
        let row = index / 4
        let column = index % 4
        return row == 0 || row == 4 || column == 0 || column == 3
    }

    private func tapPlant(_ plant: PlantData) {
        guard timerIsRunning && timeRemaining > 0 else { return }
        timeRemaining = max(0, timeRemaining + (plant.isFlower ? 3 : -1))
        growGarden()
        if timeRemaining == 0 { timerIsRunning = false }
    }

    private func growGarden() {
        var newPlants: [PlantData] = []
        for _ in 0..<20 {
            let isFlower = Int.random(in: 0..<100) < 65
            let colors = isFlower ? flowerColors : leafColors
            newPlants.append(PlantData(
                isFlower: isFlower,
                color: colors.randomElement()!,
                scale: Double.random(in: 0.78...1.05),
                angle: Double.random(in: -0.5...0.5),
                offsetX: Double.random(in: -0.08...0.08),
                offsetY: Double.random(in: -0.08...0.08)
            ))
        }
        // Ensure each garden has flowers and leaves available to tap.
        newPlants[0].isFlower = true
        newPlants[0].color = flowerColors.randomElement()!
        newPlants[3].isFlower = false
        newPlants[3].color = leafColors.randomElement()!
        plants = newPlants
    }
}


private func drawFlower(in context: GraphicsContext, center: CGPoint,
                        radius: Double, color: Color, angle: Double) {
    var local = context
    local.translateBy(x: center.x, y: center.y)
    local.rotate(by: .radians(angle))

    for petal in 0..<4 {
        var petalContext = local
        petalContext.rotate(by: .degrees(Double(petal) * 90))
        let rect = CGRect(x: -radius * 0.34, y: -radius,
                          width: radius * 0.68, height: radius * 1.05)
        let path = Path(ellipseIn: rect)
        petalContext.fill(path, with: .color(color))
    }
    let centerRect = CGRect(x: -radius * 0.22, y: -radius * 0.22,
                            width: radius * 0.44, height: radius * 0.44)
    local.fill(Path(ellipseIn: centerRect),
               with: .color(Color(red: 1, green: 0.86, blue: 0.48)))
}

// A line for the stem and two rotated ellipse paths for the leaves.
private func drawLeaves(in context: GraphicsContext, center: CGPoint,
                        radius: Double, color: Color, angle: Double) {
    var local = context
    local.translateBy(x: center.x, y: center.y)
    local.rotate(by: .radians(angle))

    var stem = Path()
    stem.move(to: CGPoint(x: 0, y: -radius * 0.25))
    stem.addLine(to: CGPoint(x: 0, y: radius * 0.75))
    local.stroke(stem, with: .color(color),
                 style: StrokeStyle(lineWidth: radius * 0.07, lineCap: .round))

    for direction in [-1.0, 1.0] {
        var leafContext = local
        leafContext.rotate(by: .degrees(direction * 45))
        let rect = CGRect(x: -radius * 0.27, y: -radius,
                          width: radius * 0.54, height: radius)
        leafContext.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

#Preview {
    ContentView()
}
