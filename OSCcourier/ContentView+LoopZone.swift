import SwiftUI
import AppKit

extension ContentView {

    // The strip just above the ruler shows a live proximity cursor near an
    // existing zone's edges, so the chevron cursor appears even before a
    // drag starts.
    func handleRulerHover(phase: HoverPhase, largeurTimeline: CGFloat) {
        switch phase {
        case .active(let location):
            guard loopZone.resizingLoopZoneEdge == nil,
                  let zoneStart = loopZone.loopZoneStart, let zoneEnd = loopZone.loopZoneEnd else {
                if loopZone.isNearLoopZoneEdge { loopZone.isNearLoopZoneEdge = false }
                return
            }
            let startX = 140 + CGFloat(zoneStart / transport.duree) * largeurTimeline
            let endX = 140 + CGFloat(zoneEnd / transport.duree) * largeurTimeline
            let near = abs(location.x - startX) < 6 || abs(location.x - endX) < 6
            if loopZone.isNearLoopZoneEdge != near { loopZone.isNearLoopZoneEdge = near }
        case .ended:
            if loopZone.isNearLoopZoneEdge { loopZone.isNearLoopZoneEdge = false }
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
        if loopZone.resizingLoopZoneEdge == nil, !loopZone.isDraggingLoopZoneBody, loopZone.rulerDragStartTime == nil,
           let zoneStart = loopZone.loopZoneStart, let zoneEnd = loopZone.loopZoneEnd {
            let startX = 140 + CGFloat(zoneStart / transport.duree) * largeurTimeline
            let endX = 140 + CGFloat(zoneEnd / transport.duree) * largeurTimeline
            if abs(value.startLocation.x - startX) < 6 {
                loopZone.resizingLoopZoneEdge = .start
            } else if abs(value.startLocation.x - endX) < 6 {
                loopZone.resizingLoopZoneEdge = .end
            } else {
                let startTime = min(max((startXPos / Double(largeurTimeline)) * transport.duree, 0), transport.duree)
                if startTime > zoneStart && startTime < zoneEnd {
                    loopZone.isDraggingLoopZoneBody = true
                    loopZone.loopZoneDragOriginalStart = zoneStart
                    loopZone.loopZoneDragOriginalEnd = zoneEnd
                    loopZone.loopZoneDragAnchorTime = startTime
                }
            }
        }

        if let edge = loopZone.resizingLoopZoneEdge {
            // Same reason as the lasso/paste cursors: onContinuousHover
            // stops firing once the mouse is captured by this active
            // drag, so reassert the cursor by hand for its duration.
            cursor(fromSymbol: "chevron.left.chevron.right").set()
            let xPos = Double(value.location.x - 140)
            var newTime = (xPos / Double(largeurTimeline)) * transport.duree
            if NSEvent.modifierFlags.contains(.command),
               let snapped = nearestSnapTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
                newTime = snapped
            } else if magneticGridSnap,
                      let snapped = nearestGridTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
                newTime = snapped
            }
            newTime = min(max(newTime, 0), transport.duree)
            switch edge {
            case .start:
                loopZone.loopZoneStart = min(newTime, (loopZone.loopZoneEnd ?? newTime) - 0.01)
            case .end:
                loopZone.loopZoneEnd = max(newTime, (loopZone.loopZoneStart ?? newTime) + 0.01)
            }
            return
        }

        if loopZone.isDraggingLoopZoneBody,
           let origStart = loopZone.loopZoneDragOriginalStart,
           let origEnd = loopZone.loopZoneDragOriginalEnd,
           let anchor = loopZone.loopZoneDragAnchorTime {
            let currentTime = min(max((Double(value.location.x - 140) / Double(largeurTimeline)) * transport.duree, 0), transport.duree)
            let delta = currentTime - anchor
            let zoneLength = origEnd - origStart
            var newStart = origStart + delta
            var newEnd = origEnd + delta

            // Snap the zone's start (not the cursor) to the nearest
            // marker/grid line — the whole zone jumps into place as
            // one piece, keeping its length exactly.
            let startXPos = (newStart / transport.duree) * Double(largeurTimeline)
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
            if newEnd > transport.duree {
                newEnd = transport.duree
                newStart = transport.duree - zoneLength
            }
            loopZone.loopZoneStart = newStart
            loopZone.loopZoneEnd = newEnd
            return
        }

        let startTime = min(max((startXPos / Double(largeurTimeline)) * transport.duree, 0), transport.duree)
        let currentTime = min(max((Double(value.location.x - 140) / Double(largeurTimeline)) * transport.duree, 0), transport.duree)
        loopZone.rulerDragStartTime = startTime
        loopZone.rulerDragCurrentTime = currentTime
    }

    func handleRulerDragEnded(_ value: DragGesture.Value, largeurTimeline: CGFloat) {
        defer {
            loopZone.rulerDragStartTime = nil
            loopZone.rulerDragCurrentTime = nil
            loopZone.resizingLoopZoneEdge = nil
            loopZone.isDraggingLoopZoneBody = false
            loopZone.loopZoneDragOriginalStart = nil
            loopZone.loopZoneDragOriginalEnd = nil
            loopZone.loopZoneDragAnchorTime = nil
        }
        guard value.startLocation.x > 140 else { return }
        if loopZone.resizingLoopZoneEdge != nil || loopZone.isDraggingLoopZoneBody {
            // Already applied live in onChanged — nothing more to do.
            return
        }
        // A negligible drag is just a click on the ruler now that
        // moving the playhead lives in the strip above: Shift+click
        // erases the zone, a plain click does nothing.
        let dragDistance = abs(value.location.x - value.startLocation.x)
        if dragDistance < 3 {
            if NSEvent.modifierFlags.contains(.shift) {
                loopZone.loopZoneStart = nil
                loopZone.loopZoneEnd = nil
            }
            return
        }
        let startTime = min(max((Double(value.startLocation.x - 140) / Double(largeurTimeline)) * transport.duree, 0), transport.duree)
        let endTime = min(max((Double(value.location.x - 140) / Double(largeurTimeline)) * transport.duree, 0), transport.duree)
        loopZone.loopZoneStart = min(startTime, endTime)
        loopZone.loopZoneEnd = max(startTime, endTime)
        // A freshly drawn zone is active right away.
        enBoucle = true
    }

    func handleRulerDoubleClick() {
        // Double-click opens the precise editor — never conflicts with
        // the single-click-moves-the-playhead behavior above, since
        // .simultaneousGesture lets both coexist without either
        // blocking the other's recognition.
        guard loopZone.loopZoneStart != nil, loopZone.loopZoneEnd != nil else { return }
        loopZone.loopZoneEditStartString = formattedDuration(loopZone.loopZoneStart ?? 0)
        loopZone.loopZoneEditEndString = formattedDuration(loopZone.loopZoneEnd ?? 0)
        loopZone.showLoopZoneEditor = true
    }

}
