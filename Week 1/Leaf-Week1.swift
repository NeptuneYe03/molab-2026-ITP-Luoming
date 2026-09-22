import Playgrounds

#Playground {
    let leafRadius = 6
    let stemLength = 3

    func drawLeaf(radius: Int, stem: Int) -> String {
        var lines: [String] = []

        // 从叶尖画到叶片底部
        for row in 0..<(radius * 2 + 1) {
            let halfWidth = min(row, radius * 2 - row)
            let spaces = String(repeating: " ", count: radius - halfWidth)

            if halfWidth == 0 {
                lines.append(spaces + "*")
            } else {
                let filling = String(repeating: ".", count: halfWidth - 1)
                lines.append(spaces + "*" + filling + "|" + filling + "*")
            }
        }

        // 画叶柄
        for _ in 0..<stem {
            lines.append(String(repeating: " ", count: radius) + "|")
        }

        return lines.joined(separator: "\n")
    }

    let leaf = drawLeaf(radius: leafRadius, stem: stemLength)
    print(leaf)
}
