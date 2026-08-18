import Combine
import SwiftUI
import AppKit

/// Owns the copy/paste-of-points state: the clipboard itself (with the
/// source track's type and amplitude range, so a same-type mismatch
/// can be detected and offered a rescale), paste-mode tracking, and
/// the bookkeeping ⌘D needs to repeat the last paste at a constant
/// offset.
final class PasteClipboardState: ObservableObject {
    @Published var pointClipboard: [PointClipboardEntry] = []
    @Published var pointClipboardTrackType: TrackType?
    @Published var isPasteModeActive: Bool = false
    @Published var showDifferentTypePasteAlert: Bool = false
    @Published var showPlayheadPositionChoice: Bool = false

    @Published var pointClipboardSourceMinAmplitude: Double?
    @Published var pointClipboardSourceMaxAmplitude: Double?
    @Published var pointClipboardOriginalEarliestTime: Double?

    @Published var lastPasteAnchorTime: Double?
    @Published var lastPasteTrackIndex: Int?
    @Published var lastPasteOffset: Double?

    @Published var pendingPasteAnchorTime: Double?
    @Published var pendingPasteTrackIndex: Int?
    @Published var showPasteScaleRangeAlert: Bool = false

    // While in paste mode, track snap proximity continuously (same
    // candidates as a point drag) so the cursor reflects where a
    // click-up would actually land, before the user even clicks.
    func handlePasteHover(phase: HoverPhase, largeurTimeline: CGFloat, markersTrack: TimelineTrack, showGrid: Bool, gridPeriod: Double, gridPhase: Double, duree: Double, magneticGridSnap: Bool, pointDrag: PointDragState) {
        guard isPasteModeActive else { return }
        switch phase {
        case .active(let location):
            let xPos = Double(location.x)
            let willSnapToMarker = NSEvent.modifierFlags.contains(.command)
                && isNearMarker(markersTrack: markersTrack, showGrid: showGrid, gridPeriod: gridPeriod, gridPhase: gridPhase, duree: duree, xPos: xPos, largeurTimeline: Double(largeurTimeline))
            let willSnapToGrid = magneticGridSnap
                && nearestGridTime(showGrid: showGrid, gridPeriod: gridPeriod, gridPhase: gridPhase, duree: duree, xPos: xPos, largeurTimeline: Double(largeurTimeline)) != nil
            if pointDrag.isNearSnapZone != willSnapToMarker { pointDrag.isNearSnapZone = willSnapToMarker }
            if pointDrag.isNearGridSnapZone != willSnapToGrid { pointDrag.isNearGridSnapZone = willSnapToGrid }
        case .ended:
            if pointDrag.isNearSnapZone { pointDrag.isNearSnapZone = false }
            if pointDrag.isNearGridSnapZone { pointDrag.isNearGridSnapZone = false }
        }
    }

    // Same reason as the lasso's onChanged: the tracking-area-based
    // CursorOverlay stops driving the cursor once the mouse is captured by
    // an active drag, so keep the crosshair asserted by hand for the whole
    // mouse-down-to-up window — including switching to the snap glyph as
    // it comes into range.
    func handlePasteDragChanged(_ value: DragGesture.Value, largeurTimeline: CGFloat, markersTrack: TimelineTrack, showGrid: Bool, gridPeriod: Double, gridPhase: Double, duree: Double, magneticGridSnap: Bool, pointDrag: PointDragState) {
        guard isPasteModeActive else { return }
        let xPos = Double(value.location.x)
        let willSnapToMarker = NSEvent.modifierFlags.contains(.command)
            && isNearMarker(markersTrack: markersTrack, showGrid: showGrid, gridPeriod: gridPeriod, gridPhase: gridPhase, duree: duree, xPos: xPos, largeurTimeline: Double(largeurTimeline))
        let willSnapToGrid = magneticGridSnap
            && nearestGridTime(showGrid: showGrid, gridPeriod: gridPeriod, gridPhase: gridPhase, duree: duree, xPos: xPos, largeurTimeline: Double(largeurTimeline)) != nil
        if pointDrag.isNearSnapZone != willSnapToMarker { pointDrag.isNearSnapZone = willSnapToMarker }
        if pointDrag.isNearGridSnapZone != willSnapToGrid { pointDrag.isNearGridSnapZone = willSnapToGrid }
        if willSnapToMarker || willSnapToGrid {
            cursor(fromSymbol: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left", color: .red).set()
        } else {
            cursor(fromSymbol: "dot.crosshair", color: .red).set()
        }
    }
}
