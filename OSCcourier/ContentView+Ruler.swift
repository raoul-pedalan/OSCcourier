import SwiftUI

// Thin adapter: builds the extracted `RulerBar` view, wiring it to the
// ruler gesture handlers that still live on ContentView (they reach
// across into snapping and track data, so they aren't a clean fit for
// LoopZoneState alone).
extension ContentView {
    func rulerBar(largeurTimeline: CGFloat, outerWidth: CGFloat, geometryWidth: CGFloat) -> some View {
        RulerBar(
            loopZone: loopZone,
            transport: transport,
            largeurTimeline: largeurTimeline,
            outerWidth: outerWidth,
            geometryWidth: geometryWidth,
            onHover: { phase in
                handleRulerHover(phase: phase, largeurTimeline: largeurTimeline)
            },
            onDragChanged: { value in
                handleRulerDragChanged(value, largeurTimeline: largeurTimeline)
            },
            onDragEnded: { value in
                handleRulerDragEnded(value, largeurTimeline: largeurTimeline)
            },
            onDoubleClick: {
                handleRulerDoubleClick()
            }
        )
    }
}
