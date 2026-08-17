import SwiftUI

// One full track row (header + content columns), used by body's per-track
// ForEach. @ViewBuilder because the row is an `if`-guarded pair of sibling
// views (the row itself, then a spacer) — the same shape the original
// inline ForEach closure had.
extension ContentView {
    @ViewBuilder
    func trackRow(index: Int, largeurTimeline: CGFloat) -> some View {
        if index != 0 || showMarkersTrack {
            HStack(spacing: 0) {
                trackHeaderColumn(index: index)
                trackContentColumn(index: index, largeurTimeline: largeurTimeline)
            }
            .offset(y: reorderingIndex == index ? reorderDragTranslation : 0)
            .zIndex(reorderingIndex == index ? 1 : 0)
            .opacity(reorderingIndex == index ? 0.85 : 1.0)
            .onHover { hovering in
                // Belt-and-suspenders: if the mouse leaves this entire track
                // row (e.g. straight onto a different track) without passing
                // back through the curve area's own hover handler, make sure
                // the segment-erase cursor state doesn't stay stuck on.
                if !hovering && isNearCurveControlZone {
                    isNearCurveControlZone = false
                    updatePointCursor()
                }
            }
            Rectangle().fill(Color.clear).frame(height: 5)
        }
    }
}
