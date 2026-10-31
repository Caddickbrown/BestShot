import SwiftUI

/// Hand-drawn grease-pencil marks, traced from the same SVG paths the Linux
/// and web apps use, so every BestShot marks photos the same way.
struct GreasePencilShape: Shape {
    let pathData: String
    let viewBox: CGSize

    /// Keep: a loose circle around a print.
    static let circle = GreasePencilShape(
        pathData: "M26 104 C18 44 80 12 118 14 C172 18 192 62 184 110 C176 158 122 188 84 184 C40 180 14 146 18 100 C20 74 40 52 64 40",
        viewBox: CGSize(width: 200, height: 200))

    /// Reject: a cross through a print.
    static let cross = GreasePencilShape(
        pathData: "M22 22 C70 70 130 126 180 178 M178 20 C128 66 72 124 20 180",
        viewBox: CGSize(width: 200, height: 200))

    /// Full-stage keep ring for the viewfinder.
    static let stageCircle = GreasePencilShape(
        pathData: "M210 470 C190 210 520 92 760 96 C1060 102 1270 250 1236 480 C1204 700 940 806 690 800 C420 794 214 690 200 500 C192 380 280 270 380 220",
        viewBox: CGSize(width: 1440, height: 900))

    /// Full-stage reject cross for the viewfinder.
    static let stageCross = GreasePencilShape(
        pathData: "M240 150 C520 380 900 560 1210 770 M1190 130 C930 330 560 600 250 790",
        viewBox: CGSize(width: 1440, height: 900))

    /// An underline stroke, for the active tab or a heading.
    static let underline = GreasePencilShape(
        pathData: "M2 6 C30 2 70 9 98 4",
        viewBox: CGSize(width: 100, height: 10))

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / viewBox.width
        let sy = rect.height / viewBox.height
        let point = { (x: Double, y: Double) in CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }

        var path = Path()
        var command: Character = "M"
        var numbers: [Double] = []

        func flush() {
            switch command {
            case "M" where numbers.count >= 2:
                path.move(to: point(numbers[0], numbers[1]))
            case "C":
                var i = 0
                while i + 5 < numbers.count {
                    path.addCurve(
                        to: point(numbers[i + 4], numbers[i + 5]),
                        control1: point(numbers[i], numbers[i + 1]),
                        control2: point(numbers[i + 2], numbers[i + 3]))
                    i += 6
                }
            default:
                break
            }
            numbers.removeAll()
        }

        for token in pathData.split(separator: " ") {
            if let first = token.first, first.isLetter {
                flush()
                command = first
                if token.count > 1, let n = Double(token.dropFirst()) { numbers.append(n) }
            } else if let n = Double(token) {
                numbers.append(n)
            }
        }
        flush()
        return path
    }
}

/// A grease-pencil stroke in the accent colour.
struct GreasePencilMark: View {
    let shape: GreasePencilShape
    var color: Color = Theme.accent
    var lineWidth: CGFloat = 4

    var body: some View {
        shape
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .allowsHitTesting(false)
    }
}
