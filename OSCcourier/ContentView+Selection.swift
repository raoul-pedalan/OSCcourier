import SwiftUI
import AppKit

extension ContentView {

    // Paste-mode click: minimumDistance 0 so a plain click and a
    // click-drag both land here, using the release location either
    // way — a plain click pastes right there, a click-drag pastes
    // wherever it ended (with the same Cmd/grid snap as a point drag).
    // Kept on ContentView (unlike the lasso/paste-hover handlers, which
    // now live on SelectionState/PasteClipboardState): it calls straight
    // into the point-editing/undo logic in ContentView+PointEditing.swift,
    // which stays together as one unit.
    func handlePasteDragEnded(_ value: DragGesture.Value, trackIndex index: Int, largeurTimeline: CGFloat) {
        guard pasteClipboard.isPasteModeActive, pasteClipboard.pointClipboardTrackType != nil else { return }
        let xPos = Double(value.location.x)
        var anchorTime = (xPos / Double(largeurTimeline)) * transport.duree
        if NSEvent.modifierFlags.contains(.command),
           let snapped = nearestSnapTime(markersTrack: pistes[0], showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
            anchorTime = snapped
        } else if magneticGridSnap,
                  let snapped = nearestGridTime(showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
            anchorTime = snapped
        }
        anchorTime = min(max(anchorTime, 0), transport.duree)
        if pasteNeedsTypeChoice(trackIndex: index) {
            pasteClipboard.pendingPasteAnchorTime = anchorTime
            pasteClipboard.pendingPasteTrackIndex = index
            pasteClipboard.showDifferentTypePasteAlert = true
        } else if pasteNeedsRangeChoice(trackIndex: index) {
            pasteClipboard.pendingPasteAnchorTime = anchorTime
            pasteClipboard.pendingPasteTrackIndex = index
            pasteClipboard.showPasteScaleRangeAlert = true
        } else if pasteClipboard(at: anchorTime, trackIndex: index, scaleToRange: false) {
            pasteClipboard.lastPasteOffset = nil
            pasteClipboard.isPasteModeActive = false
        }
    }

}
