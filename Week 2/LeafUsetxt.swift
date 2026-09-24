import Foundation
import Playgrounds

#Playground {
    let leafURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("leaf.txt")

    let leaf = try? String(contentsOf: leafURL, encoding: .utf8)

    print(leaf ?? "leaf 404.txt")
}
