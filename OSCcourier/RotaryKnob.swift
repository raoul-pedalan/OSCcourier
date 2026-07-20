import SwiftUI

//Deliverer
// A circle with smooth rounded "teeth" around its edge, like a gear or a
// flower — used to give the RotaryKnob a notched/knurled look.
struct NotchedKnobShape: Shape {
    var lobes: Int = 8
    var lobeDepth: CGFloat = 0.22 // fraction of the base radius

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2
        let segments = 240
        for i in 0...segments {
            let theta = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            let r = baseRadius * (1 - lobeDepth / 2 + lobeDepth / 2 * cos(CGFloat(lobes) * theta))
            let point = CGPoint(x: center.x + r * cos(theta), y: center.y + r * sin(theta))
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

struct RotaryKnob: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onDoubleTap: () -> Void
    // Drag distance -> value change. Defaults to the value tuned for a 30s
    // track; callers with a range that scales with something else (like
    // zoomX, whose usable span grows with the track duration) should pass a
    // proportionally scaled sensitivity so the knob "feels" the same
    // regardless of how wide the range currently is.
    var sensitivity: Double = 0.05
    @State private var initialValue: Double?
    @State private var initialTranslation: CGFloat?

    var body: some View {
        ZStack {
            NotchedKnobShape()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 30, height: 30)

            NotchedKnobShape()
                .stroke(Color.gray, lineWidth: 2)
                .frame(width: 30, height: 30)
        }
        .rotationEffect(.degrees(valueToAngle(value: value)))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { gesture in
                    if initialValue == nil {
                        initialValue = value
                        initialTranslation = gesture.translation.height
                    } else {
                        let translationDiff = initialTranslation! - gesture.translation.height
                        let newValue = initialValue! + Double(translationDiff) * sensitivity
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                }
                .onEnded { _ in
                    initialValue = nil
                    initialTranslation = nil
                }
        )
        // Simultaneous (not exclusive) so it isn't swallowed by the drag
        // gesture above, which claims the interaction immediately since it
        // has minimumDistance: 0 — a plain .onTapGesture would never fire.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap()
            }
        )
    }

    private func valueToAngle(value: Double) -> Double {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return normalized * 270 - 135
    }
}
