import SwiftUI
import AppKit

extension ContentView {

    // Dragging an existing point: moves the whole current selection
    // together (X, and Y on curve/step) if the dragged point is part of
    // it, or just this one point otherwise (which also clears whatever
    // was selected, since dragging a non-selected point is a fresh,
    // unrelated action).
    func handlePointDragChanged(_ value: DragGesture.Value, eventID: UUID, trackIndex index: Int, largeurTimeline: CGFloat) {
        guard !tracksLocked else { return }
        // ⇧⌥ starting directly on top of a point means the
        // lasso started there — don't also move the point out
        // from under it via this gesture.
        guard !(NSEvent.modifierFlags.contains(.shift) && NSEvent.modifierFlags.contains(.option)), !isPasteModeActive else { return }

        let isGroupDrag = selectedPointIDs.contains(eventID)
        if !isGroupDrag && !selectedPointIDs.isEmpty {
            selectedPointIDs.removeAll()
        }

        var newPosition = (Double(value.location.x) / Double(largeurTimeline)) * duree
        isHoveringPoint = true

        // Cmd + within 7px of a marker or grid line: snap to it.
        // Without Cmd, if "magnetic grid" is on, still snap onto
        // the nearest grid line alone (never a marker).
        let dragXPos = (newPosition / duree) * Double(largeurTimeline)
        isNearSnapZone = isNearMarker(xPos: dragXPos, largeurTimeline: Double(largeurTimeline), excluding: eventID)
        isNearGridSnapZone = nearestGridTime(xPos: dragXPos, largeurTimeline: Double(largeurTimeline)) != nil
        isNearestSnapGrid = isNearestSnapAGridLine(xPos: dragXPos, largeurTimeline: Double(largeurTimeline), excluding: eventID)
        if NSEvent.modifierFlags.contains(.command),
           let snapTime = nearestSnapTime(xPos: dragXPos, largeurTimeline: Double(largeurTimeline), excluding: eventID) {
            newPosition = snapTime
        } else if magneticGridSnap,
                  let gridSnapTime = nearestGridTime(xPos: dragXPos, largeurTimeline: Double(largeurTimeline)) {
            newPosition = gridSnapTime
        }
        updatePointCursor()

        let clampedNewTime = min(max(newPosition, 0), duree)

        if isGroupDrag {
            // Captured once, on the first tick — re-deriving from
            // a moving baseline each frame would compound
            // snapping/rounding error across the drag.
            if groupDragBaseline.isEmpty {
                groupDragBaseline = Dictionary(uniqueKeysWithValues: pistes[index].evenements
                    .filter { selectedPointIDs.contains($0.id) }
                    .map { ($0.id, $0.time) })
                groupDragAnchorOriginalTime = groupDragBaseline[eventID]
            }
            guard let anchorOriginal = groupDragAnchorOriginalTime else { return }
            let delta = clampedNewTime - anchorOriginal
            for (id, originalTime) in groupDragBaseline {
                guard let idx = pistes[index].evenements.firstIndex(where: { $0.id == id }) else { continue }
                pistes[index].evenements[idx].time = min(max(originalTime + delta, 0), duree)
            }

            // Y moves too, but only where it means something.
            if pistes[index].type == .curve || pistes[index].type == .step {
                if groupDragYBaseline.isEmpty {
                    groupDragYBaseline = Dictionary(uniqueKeysWithValues: pistes[index].evenements
                        .filter { selectedPointIDs.contains($0.id) }
                        .map { ($0.id, $0.y) })
                    groupDragAnchorOriginalY = groupDragYBaseline[eventID]
                }
                if let anchorOriginalY = groupDragAnchorOriginalY {
                    let normalizedY = min(max(1 - (Double(value.location.y) / Double(pistes[index].height)), 0), 1)
                    let rawY = pistes[index].minAmplitude + normalizedY * (pistes[index].maxAmplitude - pistes[index].minAmplitude)
                    let rawYDelta = rawY - anchorOriginalY
                    // Group-preserving clamp: shrink the delta itself
                    // (rather than clamping each point separately)
                    // so the whole group stays in range without
                    // distorting the spacing between their values.
                    var minAllowedDelta = -Double.infinity
                    var maxAllowedDelta = Double.infinity
                    for (_, originalY) in groupDragYBaseline {
                        minAllowedDelta = max(minAllowedDelta, pistes[index].minAmplitude - originalY)
                        maxAllowedDelta = min(maxAllowedDelta, pistes[index].maxAmplitude - originalY)
                    }
                    let clampedYDelta = min(max(rawYDelta, minAllowedDelta), maxAllowedDelta)
                    for (id, originalY) in groupDragYBaseline {
                        guard let idx = pistes[index].evenements.firstIndex(where: { $0.id == id }) else { continue }
                        pistes[index].evenements[idx].y = gateSnappedY(originalY + clampedYDelta, forTrackIndex: index)
                    }
                }
            }
        } else if let eventIndex = pistes[index].evenements.firstIndex(where: { $0.id == eventID }) {
            pistes[index].evenements[eventIndex].time = clampedNewTime
            if pistes[index].type == .curve || pistes[index].type == .step {
                let normalizedY = min(max(1 - (Double(value.location.y) / Double(pistes[index].height)), 0), 1)
                let yValue = pistes[index].minAmplitude + (normalizedY * (pistes[index].maxAmplitude - pistes[index].minAmplitude))
                pistes[index].evenements[eventIndex].y = gateSnappedY(yValue, forTrackIndex: index)
            }
        }
    }

    func handlePointDragEnded(trackIndex index: Int) {
        pistes[index].evenements.sort()
        lastSentEvents.removeAll()
        groupDragBaseline.removeAll()
        groupDragAnchorOriginalTime = nil
        groupDragYBaseline.removeAll()
        groupDragAnchorOriginalY = nil
    }

    // A plain click: Shift (without Option) removes the point; otherwise a
    // click anywhere just clears whatever the lasso had selected.
    func handlePointTap(eventID: UUID, trackIndex index: Int) {
        guard !tracksLocked else { return }
        if NSEvent.modifierFlags.contains(.shift) && !NSEvent.modifierFlags.contains(.option) {
            if let eventIndex = pistes[index].evenements.firstIndex(where: { $0.id == eventID }) {
                pistes[index].evenements.remove(at: eventIndex)
                lastSentEvents.removeAll()
            }
        } else if !selectedPointIDs.isEmpty {
            selectedPointIDs.removeAll()
        }
    }

    // ⌥-drag on a curve segment bends it: horizontal movement adds
    // S-shaped curvature, vertical movement adds a simple bow — both
    // combine together. Attached as .simultaneousGesture so it never blocks
    // the plain tap-to-add-point gesture; it only does anything once
    // Option (without Shift) is held and the drag exceeds the threshold.
    func handleCurveBendDragChanged(_ value: DragGesture.Value, trackIndex index: Int, largeurTimeline: CGFloat) {
        guard NSEvent.modifierFlags.contains(.option),
              !NSEvent.modifierFlags.contains(.shift) else { return }
        // onContinuousHover stops firing once a real drag begins (the mouse
        // is "captured" by the gesture), so the CursorOverlay's isActive
        // state would otherwise freeze or drop — keep reasserting the
        // cursor manually for the duration of the drag itself.
        cursor(fromSymbol: "point.bottomleft.forward.to.point.topright.filled.scurvepath").set()

        let sorted = pistes[index].evenements.sorted { $0.time < $1.time }
        guard sorted.count > 1 else { return }

        if curveDragSegmentID == nil {
            let startTime = (Double(value.startLocation.x) / Double(largeurTimeline)) * duree
            var chosenID = sorted[0].id
            for i in 0..<(sorted.count - 1) {
                if startTime >= sorted[i].time && startTime <= sorted[i + 1].time {
                    chosenID = sorted[i].id
                    break
                }
            }
            curveDragSegmentID = chosenID
            let chosenEvent = sorted.first(where: { $0.id == chosenID })
            curveDragBaseline = chosenEvent?.segmentCurve ?? 0
            curveDragBulgeBaseline = chosenEvent?.segmentBulge ?? 0
        }

        if let segmentID = curveDragSegmentID,
           let baseline = curveDragBaseline,
           let bulgeBaseline = curveDragBulgeBaseline,
           let eventIndex = pistes[index].evenements.firstIndex(where: { $0.id == segmentID }) {
            let newCurvature = min(max(baseline + Double(value.translation.width) * 0.0075, -6), 6)
            let newBulge = min(max(bulgeBaseline - Double(value.translation.height) * 0.0075, -6), 6)
            pistes[index].evenements[eventIndex].segmentCurve = newCurvature
            pistes[index].evenements[eventIndex].segmentBulge = newBulge
        }
    }

    func handleCurveBendDragEnded() {
        curveDragSegmentID = nil
        curveDragBaseline = nil
        curveDragBulgeBaseline = nil
    }

}
