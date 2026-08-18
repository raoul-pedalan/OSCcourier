import SwiftUI

/// One full track row (header + content columns), used by `body`'s
/// per-track ForEach.
///
/// A real `View` assembling the two extracted column views — mostly a
/// thin forwarding layer, since it needs every dependency either of
/// them needs. `@ViewBuilder` because the row is an `if`-guarded pair
/// of sibling views (the row itself, then a spacer).
struct TrackRow: View {
    @ObservedObject var timelineStore: TimelineStore
    @ObservedObject var pointDrag: PointDragState
    @ObservedObject var pointEditing: PointEditingState
    @ObservedObject var trackAmplitudeEdit: TrackAmplitudeEditState
    @ObservedObject var trackDragReorder: TrackDragReorderState
    @ObservedObject var autofill: AutofillState
    @ObservedObject var selection: SelectionState
    @ObservedObject var pasteClipboard: PasteClipboardState
    @ObservedObject var transport: TransportState
    @ObservedObject var uiChrome: UIChromeState

    let index: Int
    let largeurTimeline: CGFloat

    @AppStorage("showMarkersTrack") private var showMarkersTrack: Bool = true
    @AppStorage("magneticGridSnap") private var magneticGridSnap: Bool = false

    let onBeginCreatingPoint: (CGPoint, Int, CGFloat) -> Void
    let onUpdateCreatingPoint: (CGPoint, CGFloat) -> Void
    let onFinishCreatingPoint: () -> Void
    let onToggleSegmentEnabled: (Double, Int) -> Void
    let onBeginEditingPoint: (UUID) -> Void
    let onPasteDragEnded: (DragGesture.Value, Int, CGFloat) -> Void

    @ViewBuilder
    var body: some View {
        if index != 0 || showMarkersTrack {
            HStack(spacing: 0) {
                TrackHeaderColumn(
                    timelineStore: timelineStore,
                    pointDrag: pointDrag,
                    pointEditing: pointEditing,
                    trackAmplitudeEdit: trackAmplitudeEdit,
                    trackDragReorder: trackDragReorder,
                    autofill: autofill,
                    index: index
                )
                TrackContentColumn(
                    timelineStore: timelineStore,
                    pointDrag: pointDrag,
                    pointEditing: pointEditing,
                    selection: selection,
                    pasteClipboard: pasteClipboard,
                    transport: transport,
                    uiChrome: uiChrome,
                    index: index,
                    largeurTimeline: largeurTimeline,
                    onBeginCreatingPoint: onBeginCreatingPoint,
                    onUpdateCreatingPoint: onUpdateCreatingPoint,
                    onFinishCreatingPoint: onFinishCreatingPoint,
                    onToggleSegmentEnabled: onToggleSegmentEnabled,
                    onBeginEditingPoint: onBeginEditingPoint,
                    onPasteDragEnded: onPasteDragEnded
                )
            }
            .offset(y: trackDragReorder.reorderingIndex == index ? trackDragReorder.reorderDragTranslation : 0)
            .zIndex(trackDragReorder.reorderingIndex == index ? 1 : 0)
            .opacity(trackDragReorder.reorderingIndex == index ? 0.85 : 1.0)
            .onHover { hovering in
                // Belt-and-suspenders: if the mouse leaves this entire track
                // row (e.g. straight onto a different track) without passing
                // back through the curve area's own hover handler, make sure
                // the segment-erase cursor state doesn't stay stuck on.
                if !hovering && pointDrag.isNearCurveControlZone {
                    pointDrag.isNearCurveControlZone = false
                    pointDrag.updateCursor(pasteModeActive: pasteClipboard.isPasteModeActive, magneticGridSnap: magneticGridSnap)
                }
            }
            Rectangle().fill(Color.clear).frame(height: 5)
        }
    }
}
