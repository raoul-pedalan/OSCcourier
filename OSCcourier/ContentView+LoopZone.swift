import SwiftUI
import AppKit

extension ContentView {

    // The strip just above the ruler shows a live proximity cursor near an
    // existing zone's edges, so the chevron cursor appears even before a
    // drag starts.
    func handleRulerHover(phase: HoverPhase, largeurTimeline: CGFloat) {
        switch phase {
        case .active(let location):
            guard resizingLoopZoneEdge == nil,
                  let zoneStart = loopZoneStart, let zoneEnd = loopZoneEnd else {
                if isNearLoopZoneEdge { isNearLoopZoneEdge = false }
                return
            }
            let startX = 140 + CGFloat(zoneStart / duree) * largeurTimeline
            let endX = 140 + CGFloat(zoneEnd / duree) * largeurTimeline
            let near = abs(location.x - startX) < 6 || abs(location.x - endX) < 6
            if isNearLoopZoneEdge != near { isNearLoopZoneEdge = near }
        case .ended:
            if isNearLoopZoneEdge { isNearLoopZoneEdge = false }
        }
    }

    func handleRulerDragChanged(_ value: DragGesture.Value, largeurTimeline: CGFloat) {
        guard value.startLocation.x > 140 else { return }
        let startXPos = Double(value.startLocation.x - 140)

        // First tick of this drag: decide once whether it's grabbing
        // an existing zone's edge, moving its body, or starting a
        // brand new zone — checked against the drag's start point
        // only, never re-evaluated mid-drag (so crossing the other
        // edge or leaving the zone mid-drag doesn't change what's
        // being manipulated).
        if resizingLoopZoneEdge == nil, !isDraggingLoopZoneBody, rulerDragStartTime == nil,
           let zoneStart = loopZoneStart, let zoneEnd = loopZoneEnd {
            let startX = 140 + CGFloat(zoneStart / duree) * largeurTimeline
            let endX = 140 + CGFloat(zoneEnd / duree) * largeurTimeline
            if abs(value.startLocation.x - startX) < 6 {
                resizingLoopZoneEdge = .start
            } else if abs(value.startLocation.x - endX) < 6 {
                resizingLoopZoneEdge = .end
            } else {
                let startTime = min(max((startXPos / Double(largeurTimeline)) * duree, 0), duree)
                if startTime > zoneStart && startTime < zoneEnd {
                    isDraggingLoopZoneBody = true
                    loopZoneDragOriginalStart = zoneStart
                    loopZoneDragOriginalEnd = zoneEnd
                    loopZoneDragAnchorTime = startTime
                }
            }
        }

        if let edge = resizingLoopZoneEdge {
            // Same reason as the lasso/paste cursors: onContinuousHover
            // stops firing once the mouse is captured by this active
            // drag, so reassert the cursor by hand for its duration.
            cursor(fromSymbol: "chevron.left.chevron.right").set()
            let xPos = Double(value.location.x - 140)
            var newTime = (xPos / Double(largeurTimeline)) * duree
            if NSEvent.modifierFlags.contains(.command),
               let snapped = nearestSnapTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
                newTime = snapped
            } else if magneticGridSnap,
                      let snapped = nearestGridTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
                newTime = snapped
            }
            newTime = min(max(newTime, 0), duree)
            switch edge {
            case .start:
                loopZoneStart = min(newTime, (loopZoneEnd ?? newTime) - 0.01)
            case .end:
                loopZoneEnd = max(newTime, (loopZoneStart ?? newTime) + 0.01)
            }
            return
        }

        if isDraggingLoopZoneBody,
           let origStart = loopZoneDragOriginalStart,
           let origEnd = loopZoneDragOriginalEnd,
           let anchor = loopZoneDragAnchorTime {
            let currentTime = min(max((Double(value.location.x - 140) / Double(largeurTimeline)) * duree, 0), duree)
            let delta = currentTime - anchor
            let zoneLength = origEnd - origStart
            var newStart = origStart + delta
            var newEnd = origEnd + delta

            // Snap the zone's start (not the cursor) to the nearest
            // marker/grid line — the whole zone jumps into place as
            // one piece, keeping its length exactly.
            let startXPos = (newStart / duree) * Double(largeurTimeline)
            if NSEvent.modifierFlags.contains(.command),
               let snapped = nearestSnapTime(xPos: startXPos, largeurTimeline: Double(largeurTimeline)) {
                let snapDelta = snapped - newStart
                newStart += snapDelta
                newEnd += snapDelta
            } else if magneticGridSnap,
                      let snapped = nearestGridTime(xPos: startXPos, largeurTimeline: Double(largeurTimeline)) {
                let snapDelta = snapped - newStart
                newStart += snapDelta
                newEnd += snapDelta
            }

            if newStart < 0 {
                newStart = 0
                newEnd = zoneLength
            }
            if newEnd > duree {
                newEnd = duree
                newStart = duree - zoneLength
            }
            loopZoneStart = newStart
            loopZoneEnd = newEnd
            return
        }

        let startTime = min(max((startXPos / Double(largeurTimeline)) * duree, 0), duree)
        let currentTime = min(max((Double(value.location.x - 140) / Double(largeurTimeline)) * duree, 0), duree)
        rulerDragStartTime = startTime
        rulerDragCurrentTime = currentTime
    }

    func handleRulerDragEnded(_ value: DragGesture.Value, largeurTimeline: CGFloat) {
        defer {
            rulerDragStartTime = nil
            rulerDragCurrentTime = nil
            resizingLoopZoneEdge = nil
            isDraggingLoopZoneBody = false
            loopZoneDragOriginalStart = nil
            loopZoneDragOriginalEnd = nil
            loopZoneDragAnchorTime = nil
        }
        guard value.startLocation.x > 140 else { return }
        if resizingLoopZoneEdge != nil || isDraggingLoopZoneBody {
            // Already applied live in onChanged — nothing more to do.
            return
        }
        // A negligible drag is just a click on the ruler now that
        // moving the playhead lives in the strip above: Shift+click
        // erases the zone, a plain click does nothing.
        let dragDistance = abs(value.location.x - value.startLocation.x)
        if dragDistance < 3 {
            if NSEvent.modifierFlags.contains(.shift) {
                loopZoneStart = nil
                loopZoneEnd = nil
            }
            return
        }
        let startTime = min(max((Double(value.startLocation.x - 140) / Double(largeurTimeline)) * duree, 0), duree)
        let endTime = min(max((Double(value.location.x - 140) / Double(largeurTimeline)) * duree, 0), duree)
        loopZoneStart = min(startTime, endTime)
        loopZoneEnd = max(startTime, endTime)
        // A freshly drawn zone is active right away.
        enBoucle = true
    }

    func handleRulerDoubleClick() {
        // Double-click opens the precise editor — never conflicts with
        // the single-click-moves-the-playhead behavior above, since
        // .simultaneousGesture lets both coexist without either
        // blocking the other's recognition.
        guard loopZoneStart != nil, loopZoneEnd != nil else { return }
        loopZoneEditStartString = formattedDuration(loopZoneStart ?? 0)
        loopZoneEditEndString = formattedDuration(loopZoneEnd ?? 0)
        showLoopZoneEditor = true
    }

}
