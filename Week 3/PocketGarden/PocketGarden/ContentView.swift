import SwiftUI

private let gardenBackground = Color(red: 0.99, green: 0.96, blue: 0.89)
private let gardenGreen = Color(red: 0.36, green: 0.48, blue: 0.32)
private let flowerColors: [Color] = [
    Color(red: 0.91, green: 0.48, blue: 0.40),
    Color(red: 0.97, green: 0.66, blue: 0.45),
    Color(red: 0.96, green: 0.76, blue: 0.39),
    Color(red: 0.93, green: 0.63, blue: 0.60)
]
private let leafColors: [Color] = [gardenGreen, Color(red: 0.58, green: 0.66, blue: 0.43)]

// Save random data in an array, like the teacher's PathData array.
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
                GardenPage {
                    showGarden = false
                }
            } else {
                WelcomePage {
                    showGarden = true
                }
            }
        }
        .frame(minWidth: 300, minHeight: 450)
    }
}

private struct WelcomePage: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            Canvas { context, size in
                drawFlower(in: context,
                           center: CGPoint(x: size.width / 2, y: size.height / 2),
                           radius: 58, color: flowerColors[0], angle: 0)
            }
            .frame(width: 150, height: 150)

            Text("Pocket Garden").font(.largeTitle).bold()
            Text("A little garden, different every time.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Grow My Garden", action: onStart)
                .buttonStyle(.borderedProminent)
                .tint(gardenGreen)
        }
        .padding(24)
    }
}

private struct GardenPage: View {
    var onBack: () -> Void
    @State private var plants: [PlantData] = []

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Back", action: onBack)
                Spacer()
                Text("My Garden").font(.headline)
                Spacer()
                // Balance the title without adding another button.
                Text("Back").hidden()
            }
            .tint(gardenGreen)

            Text("Your little patch of sunshine.")
                .foregroundStyle(.secondary)

            // Same drawing structure as the teacher: Canvas + Path + loop.
            Canvas { context, size in
                let cellWidth = size.width / 4
                let cellHeight = size.height / 5
                let radius = min(cellWidth, cellHeight) * 0.34

                for (index, plant) in plants.enumerated() {
                    let center = CGPoint(
                        x: (Double(index % 4) + 0.5 + plant.offsetX) * cellWidth,
                        y: (Double(index / 4) + 0.5 + plant.offsetY) * cellHeight
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
            }
            .background(Color.white.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 24))

            Button("Grow Again", action: growGarden)
                .buttonStyle(.borderedProminent)
                .tint(gardenGreen)
        }
        .padding(20)
        .onAppear {
            if plants.isEmpty { growGarden() }
        }
    }

    private func growGarden() {
        var newPlants: [PlantData] = []
        for _ in 0..<20 {
            let isFlower = Int.random(in: 0..<100) < 65
            let colors = isFlower ? flowerColors : leafColors
            let plant = PlantData(
                isFlower: isFlower,
                color: colors.randomElement()!,
                scale: Double.random(in: 0.78...1.05),
                angle: Double.random(in: -0.5...0.5),
                offsetX: Double.random(in: -0.08...0.08),
                offsetY: Double.random(in: -0.08...0.08)
            )
            newPlants.append(plant)
        }
        plants = newPlants
    }
}

// Four ellipse paths around a central circle.
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
