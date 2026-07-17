import SwiftUI

// Small upward-pointing triangle used as the "tail" of the duration tooltip
// bubble, so the bubble visually points up at the drag handle above it.
struct UpPointingTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// Diagonal hazard-stripe pattern, used for the track resize handles at the
// bottom of curve/step headers. Draws a set of parallel 45° lines; stroking
// this shape over a colored background gives the classic striped look.
// The path is drawn wider than the frame (and clipped) so the slanted lines
// reach the edges cleanly instead of leaving triangular gaps at the corners.
struct DiagonalStripes: Shape {
    var stripeWidth: CGFloat = 4
    var spacing: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = stripeWidth + spacing
        // Start far enough left that the slanted lines still cover the top-left
        // corner, and run past the right edge for the same reason.
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return path
    }
}

struct Polygon: Shape {
    let sides: Int
    let size: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = size / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = (2 * .pi) / CGFloat(sides)
        for i in 0..<sides {
            let point = CGPoint(
                x: center.x + radius * cos(angle * CGFloat(i) - .pi / 2),
                y: center.y + radius * sin(angle * CGFloat(i) - .pi / 2)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
