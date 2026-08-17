import SwiftUI
import AppKit

extension ContentView {

    // While in paste mode, track snap proximity continuously (same
    // candidates as a point drag) so the cursor reflects where a
    // click-up would actually land, before the user even clicks.
    func handlePasteHover(phase: HoverPhase, largeurTimeline: CGFloat) {
        guard pasteClipboard.isPasteModeActive else { return }
        switch phase {
        case .active(let location):
            let xPos = Double(location.x)
            let willSnapToMarker = NSEvent.modifierFlags.contains(.command)
                && isNearMarker(xPos: xPos, largeurTimeline: Double(largeurTimeline))
            let willSnapToGrid = magneticGridSnap
                && nearestGridTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) != nil
            if pointDrag.isNearSnapZone != willSnapToMarker { pointDrag.isNearSnapZone = willSnapToMarker }
            if pointDrag.isNearGridSnapZone != willSnapToGrid { pointDrag.isNearGridSnapZone = willSnapToGrid }
        case .ended:
            if pointDrag.isNearSnapZone { pointDrag.isNearSnapZone = false }
            if pointDrag.isNearGridSnapZone { pointDrag.isNearGridSnapZone = false }
        }
    }

    // ⌥⇧-drag lassos points on THIS track only — attached as
    // .simultaneousGesture (not .gesture) so it never blocks the
    // ordinary click-to-create-point / drag-to-move-point gestures
    // underneath; it only actually does anything once both modifiers
    // are held.
    func handleLassoDragChanged(_ value: DragGesture.Value, trackIndex index: Int, largeurTimeline: CGFloat) {
        guard !tracksLocked, !pasteClipboard.isPasteModeActive,
              NSEvent.modifierFlags.contains(.shift),
              NSEvent.modifierFlags.contains(.option) else { return }
        // onContinuousHover (used for the idle-hover cursor) stops firing
        // once a real drag begins, so reassert the cursor manually for the
        // duration of the lasso drag itself — same pattern as the
        // curve-bend cursor.
        cursor(fromSymbol: "dot.crosshair").set()
        if selection.lassoTrackIndex == nil {
            selection.lassoTrackIndex = index
            selection.lassoStartLocation = value.startLocation
        }
        guard selection.lassoTrackIndex == index else { return }
        selection.lassoCurrentLocation = value.location
    }

    func handleLassoDragEnded(_ value: DragGesture.Value, trackIndex index: Int, largeurTimeline: CGFloat) {
        guard selection.lassoTrackIndex == index, let start = selection.lassoStartLocation else {
            selection.lassoTrackIndex = nil
            selection.lassoStartLocation = nil
            selection.lassoCurrentLocation = nil
            return
        }
        let rect = CGRect(
            x: min(start.x, value.location.x),
            y: min(start.y, value.location.y),
            width: abs(value.location.x - start.x),
            height: abs(value.location.y - start.y)
        )
        let trackHeight = rowHeight(for: pistes[index])
        var newSelection: Set<UUID> = []
        for event in pistes[index].evenements {
            let xPos = CGFloat(event.time / transport.duree) * largeurTimeline
            let pointY: CGFloat
            if pistes[index].type == .curve || pistes[index].type == .step {
                let amplitudeRange = pistes[index].maxAmplitude - pistes[index].minAmplitude
                let normalizedY = amplitudeRange > 0 ? (event.y - pistes[index].minAmplitude) / amplitudeRange : 0.5
                pointY = curveMargin + (trackHeight - 2 * curveMargin) * (1 - normalizedY)
            } else {
                pointY = index == 0 ? 22 : 15
            }
            if rect.contains(CGPoint(x: xPos, y: pointY)) {
                newSelection.insert(event.id)
            }
        }
        selection.selectedPointIDs = newSelection
        selection.lassoTrackIndex = nil
        selection.lassoStartLocation = nil
        selection.lassoCurrentLocation = nil
    }

    // Same reason as the lasso's onChanged: the tracking-area-based
    // CursorOverlay stops driving the cursor once the mouse is captured by
    // an active drag, so keep the crosshair asserted by hand for the whole
    // mouse-down-to-up window — including switching to the snap glyph as
    // it comes into range.
    func handlePasteDragChanged(_ value: DragGesture.Value, largeurTimeline: CGFloat) {
        guard pasteClipboard.isPasteModeActive else { return }
        let xPos = Double(value.location.x)
        let willSnapToMarker = NSEvent.modifierFlags.contains(.command)
            && isNearMarker(xPos: xPos, largeurTimeline: Double(largeurTimeline))
        let willSnapToGrid = magneticGridSnap
            && nearestGridTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) != nil
        if pointDrag.isNearSnapZone != willSnapToMarker { pointDrag.isNearSnapZone = willSnapToMarker }
        if pointDrag.isNearGridSnapZone != willSnapToGrid { pointDrag.isNearGridSnapZone = willSnapToGrid }
        if willSnapToMarker || willSnapToGrid {
            cursor(fromSymbol: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left", color: .red).set()
        } else {
            cursor(fromSymbol: "dot.crosshair", color: .red).set()
        }
    }

    // Paste-mode click: minimumDistance 0 so a plain click and a
    // click-drag both land here, using the release location either
    // way — a plain click pastes right there, a click-drag pastes
    // wherever it ended (with the same Cmd/grid snap as a point drag).
    func handlePasteDragEnded(_ value: DragGesture.Value, trackIndex index: Int, largeurTimeline: CGFloat) {
        guard pasteClipboard.isPasteModeActive, pasteClipboard.pointClipboardTrackType != nil else { return }
        let xPos = Double(value.location.x)
        var anchorTime = (xPos / Double(largeurTimeline)) * transport.duree
        if NSEvent.modifierFlags.contains(.command),
           let snapped = nearestSnapTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
            anchorTime = snapped
        } else if magneticGridSnap,
                  let snapped = nearestGridTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
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
