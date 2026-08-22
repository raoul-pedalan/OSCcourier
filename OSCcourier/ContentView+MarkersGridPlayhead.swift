import SwiftUI
import AppKit

// Everything drawn in the tracks ZStack besides the tracks VStack itself:
// the gray marker lines, the optional grid overlay, and the playhead's
// vertical line through the tracks. The ruler, loop zone, the
// click-to-scrub strip, and the playhead's draggable triangle now live in
// their own pinned strip above the scroll view (see RulerBar / ContentView
// body) — they're no longer part of this scrollable content, so they stay
// visible however far you've scrolled down through the tracks.
//
// Deliberately NOT extracted into a `struct ... : View` like RulerBar was:
// the marker lines and the playhead position themselves with `.position()`
// and `.offset()`, which resolve against the coordinate space of their
// direct parent — the outer ZStack in `body`. Wrapping them in their own
// View would insert an intermediate container that sizes to its content
// rather than filling that same space, silently shifting where every one
// of these lands. Kept as a @ViewBuilder function so they stay direct
// children of that ZStack.
extension ContentView {
    @ViewBuilder
    func markersGridAndPlayhead(largeurTimeline: CGFloat, totalHeight: CGFloat) -> some View {
        // Gray vertical lines for each marker on the "markers" track,
        // drawn here (outside the .clipped() area of each individual track)
        // so they can span through all the tracks below.
        ForEach(pistes[0].evenements) { event in
            let xPos = CGFloat(event.time / transport.duree) * largeurTimeline + 140
            Rectangle()
                .fill(pistes[0].couleur)
                .frame(width: 1, height: CGFloat(totalHeight))
                .position(x: xPos, y: CGFloat(totalHeight) / 2)
                .opacity(0.5)
                .allowsHitTesting(false)
        }

        // Grid overlay: evenly spaced dashed vertical lines across all
        // tracks (period/phase set via double-clicking the grid button),
        // same span as the marker lines above but dashed and purely visual.
        if showGrid {
            ForEach(visibleGridLineTimes(gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, largeurTimeline: largeurTimeline), id: \.self) { time in
                let xPos = CGFloat(time / transport.duree) * largeurTimeline + 140
                Path { path in
                    path.move(to: CGPoint(x: xPos, y: 0))
                    path.addLine(to: CGPoint(x: xPos, y: CGFloat(totalHeight)))
                }
                .stroke(Color.gray.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .allowsHitTesting(false)
            }
        }

        // The playhead's vertical line through the tracks. No longer
        // draggable here (or topped with the triangle) — both moved to the
        // pinned ruler strip above (see RulerBar), which is now always
        // visible instead of scrolling away, so that's a strictly better
        // place to grab the playhead than a line buried among the tracks.
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: CGFloat(totalHeight))
            .offset(x: CGFloat(transport.position / transport.duree) * largeurTimeline + 140)
            .allowsHitTesting(false)
    }
}
