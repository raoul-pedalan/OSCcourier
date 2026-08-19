import Combine
import SwiftUI
import AppKit

/// Owns the state for the most gesture-heavy interactions on a track:
/// dragging a point or a whole selection (with the per-point baselines
/// captured on the first tick of a drag), ⌥-dragging a curve segment
/// to bend it, modifier-aware hover/cursor tracking, and Cmd/grid
/// snap-zone proximity used both for the live cursor and for the snap
/// decision itself. Also owns the last-sent-events de-dup set (OSC
/// output) and the global key-down monitor, since both are driven by
/// the same point-editing gestures.
final class PointDragState: ObservableObject {
    @Published var lastSentEvents: Set<String> = []
    @Published var keyDownMonitor: Any?

    @Published var isHoveringPoint: Bool = false
    @Published var isNearCurveControlZone: Bool = false
    @Published var isOptionHeldForCursor: Bool = false
    @Published var isShiftHeldForCursor: Bool = false

    @Published var groupDragBaseline: [UUID: Double] = [:]
    @Published var groupDragAnchorOriginalTime: Double?
    @Published var groupDragYBaseline: [UUID: Double] = [:]
    @Published var groupDragAnchorOriginalY: Double?
    // Set once, on the first tick of a group drag: whether the selection
    // touches more than one track. Y is meaningless to move together
    // across tracks with different amplitude ranges/types, so it's
    // disabled entirely for the duration of such a drag — only time
    // moves.
    @Published var groupDragSpansMultipleTracks: Bool = false
    // Recomputed every tick during a group time-drag: which selected
    // points are currently sitting clamped at 0 or duree because their
    // *unclamped* target would have gone past it. Stacking them there is
    // just an in-progress visual (so the gesture stays predictable while
    // live), but on release (handlePointDragEnded) these get removed —
    // same "clip rather than stack" rule as nudgeSelection/Time Offset.
    @Published var groupDragOverflowingIDs: Set<UUID> = []

    @Published var curveDragSegmentID: UUID?
    @Published var curveDragBaseline: Double?
    @Published var curveDragBulgeBaseline: Double?

    @Published var isNearSnapZone: Bool = false
    @Published var isNearGridSnapZone: Bool = false
    @Published var isNearestSnapGrid: Bool = false

    /// Last OSC value actually sent for each step track, keyed by track
    /// name. A step track holds its value constant between two points, so
    /// without this every playhead-drag tick would re-send an identical
    /// message. Deliberately NOT @Published: no view reads it, and
    /// publishing it would invalidate the UI on every OSC send.
    var lastSentStepValues: [String: Double] = [:]

    /// Called whenever something changes what *should* be on the wire —
    /// an edit, a load, a track removal — as opposed to the playhead
    /// merely moving. Position changes alone must not reset the step
    /// cache, since suppressing those repeats is the whole point of it.
    // Paste mode owns the cursor entirely while active — don't let a
    // stray modifier-key change (e.g. releasing ⌘ right after ⌘V) clobber
    // the red crosshair with the arrow just because the mouse isn't
    // currently over a point.
    // suppressShiftEraser: true while a point is actively being dragged —
    // Shift during a drag means "constrain to one axis", not "delete on
    // release" (that's only a plain Shift *click*, a separate gesture), so
    // the delete-cursor would be misleading there.
    func updateCursor(pasteModeActive: Bool, magneticGridSnap: Bool, suppressShiftEraser: Bool = false) {
        guard !pasteModeActive else { return }
        guard isHoveringPoint else {
            NSCursor.arrow.set()
            return
        }
        if NSEvent.modifierFlags.contains(.shift) && !suppressShiftEraser {
            cursor(fromSymbol: "eraser.badge.xmark").set()
        } else if NSEvent.modifierFlags.contains(.command) && isNearSnapZone {
            let color: NSColor = isNearestSnapGrid ? .gray : .black
            cursor(fromSymbol: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left", color: color).set()
        } else if magneticGridSnap && isNearGridSnapZone {
            cursor(fromSymbol: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left", color: .gray).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // Dragging an existing point: moves the whole current selection
    // together (X, and Y on curve/step) if the dragged point is part of
    // it, or just this one point otherwise (which also clears whatever
    // was selected, since dragging a non-selected point is a fresh,
    // unrelated action).
    func handlePointDragChanged(_ value: DragGesture.Value, eventID: UUID, trackIndex index: Int, largeurTimeline: CGFloat, pistes: inout [TimelineTrack], selection: SelectionState, pasteClipboard: PasteClipboardState, uiChrome: UIChromeState, transport: TransportState, showGrid: Bool, magneticGridSnap: Bool, tracksLocked: Bool) {
        guard !tracksLocked else { return }
        // ⇧⌥ starting directly on top of a point means the
        // lasso started there — don't also move the point out
        // from under it via this gesture.
        guard !(NSEvent.modifierFlags.contains(.shift) && NSEvent.modifierFlags.contains(.option)), !pasteClipboard.isPasteModeActive else { return }

        let isGroupDrag = selection.selectedPointIDs.contains(eventID)
        if !isGroupDrag && !selection.selectedPointIDs.isEmpty {
            selection.selectedPointIDs.removeAll()
        }

        // Shift (without Option, which is reserved for starting the lasso)
        // constrains the drag to whichever axis has moved further from the
        // drag's start — X-only (time) or Y-only (value) — recomputed every
        // tick rather than locked once, so it stays forgiving if the
        // dominant axis changes mid-drag.
        var location = value.location
        if NSEvent.modifierFlags.contains(.shift), !NSEvent.modifierFlags.contains(.option) {
            let dx = abs(value.location.x - value.startLocation.x)
            let dy = abs(value.location.y - value.startLocation.y)
            if dx >= dy {
                location.y = value.startLocation.y
            } else {
                location.x = value.startLocation.x
            }
        }

        var newPosition = (Double(location.x) / Double(largeurTimeline)) * transport.duree
        isHoveringPoint = true

        // Cmd + within 7px of a marker or grid line: snap to it.
        // Without Cmd, if "magnetic grid" is on, still snap onto
        // the nearest grid line alone (never a marker).
        let dragXPos = (newPosition / transport.duree) * Double(largeurTimeline)
        isNearSnapZone = isNearMarker(markersTrack: pistes[0], showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: dragXPos, largeurTimeline: Double(largeurTimeline), excluding: eventID)
        isNearGridSnapZone = nearestGridTime(showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: dragXPos, largeurTimeline: Double(largeurTimeline)) != nil
        isNearestSnapGrid = isNearestSnapAGridLine(markersTrack: pistes[0], showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: dragXPos, largeurTimeline: Double(largeurTimeline), excluding: eventID)
        if NSEvent.modifierFlags.contains(.command),
           let snapTime = nearestSnapTime(markersTrack: pistes[0], showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: dragXPos, largeurTimeline: Double(largeurTimeline), excluding: eventID) {
            newPosition = snapTime
        } else if magneticGridSnap,
                  let gridSnapTime = nearestGridTime(showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: dragXPos, largeurTimeline: Double(largeurTimeline)) {
            newPosition = gridSnapTime
        }
        updateCursor(pasteModeActive: pasteClipboard.isPasteModeActive, magneticGridSnap: magneticGridSnap, suppressShiftEraser: true)

        let clampedNewTime = min(max(newPosition, 0), transport.duree)

        if isGroupDrag {
            // Captured once, on the first tick — re-deriving from
            // a moving baseline each frame would compound
            // snapping/rounding error across the drag. Scans every
            // track (not just this one), so a selection spanning
            // multiple tracks (e.g. via "Select Points in Time Range")
            // drags together in time, staying in sync.
            if groupDragBaseline.isEmpty {
                var baseline: [UUID: Double] = [:]
                var touchedTracks: Set<Int> = []
                for (trackIndex, piste) in pistes.enumerated() {
                    // The markers track is a navigation aid, not data — it
                    // never moves along with the rest of a group drag, even
                    // if a marker got swept into the selection (e.g. via
                    // Select All). Same rule as nudgeSelection.
                    guard trackIndex != 0 else { continue }
                    for event in piste.evenements where selection.selectedPointIDs.contains(event.id) {
                        baseline[event.id] = event.time
                        touchedTracks.insert(trackIndex)
                    }
                }
                groupDragBaseline = baseline
                groupDragAnchorOriginalTime = groupDragBaseline[eventID]
                groupDragSpansMultipleTracks = touchedTracks.count > 1
            }
            guard let anchorOriginal = groupDragAnchorOriginalTime else { return }
            let delta = clampedNewTime - anchorOriginal
            var overflowing: Set<UUID> = []
            for (id, originalTime) in groupDragBaseline {
                let rawTime = originalTime + delta
                if rawTime < 0 || rawTime > transport.duree {
                    overflowing.insert(id)
                }
                for trackIndex in pistes.indices {
                    guard let idx = pistes[trackIndex].evenements.firstIndex(where: { $0.id == id }) else { continue }
                    pistes[trackIndex].evenements[idx].time = min(max(rawTime, 0), transport.duree)
                    break
                }
            }
            groupDragOverflowingIDs = overflowing

            // Y moves too, but only where it means something — and only
            // when the whole selection lives on this one track. Across
            // tracks with different amplitude ranges/types, a shared Y
            // delta wouldn't mean anything consistent.
            if !groupDragSpansMultipleTracks, pistes[index].type == .curve || pistes[index].type == .step {
                if groupDragYBaseline.isEmpty {
                    groupDragYBaseline = Dictionary(uniqueKeysWithValues: pistes[index].evenements
                        .filter { selection.selectedPointIDs.contains($0.id) }
                        .map { ($0.id, $0.y) })
                    groupDragAnchorOriginalY = groupDragYBaseline[eventID]
                }
                if let anchorOriginalY = groupDragAnchorOriginalY {
                    let normalizedY = min(max(1 - (Double(location.y) / Double(pistes[index].height)), 0), 1)
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
                        pistes[index].evenements[idx].y = gateSnappedY(originalY + clampedYDelta, forTrack: pistes[index])
                    }
                }
            }
        } else if let eventIndex = pistes[index].evenements.firstIndex(where: { $0.id == eventID }) {
            pistes[index].evenements[eventIndex].time = clampedNewTime
            if pistes[index].type == .curve || pistes[index].type == .step {
                let normalizedY = min(max(1 - (Double(location.y) / Double(pistes[index].height)), 0), 1)
                let yValue = pistes[index].minAmplitude + (normalizedY * (pistes[index].maxAmplitude - pistes[index].minAmplitude))
                pistes[index].evenements[eventIndex].y = gateSnappedY(yValue, forTrack: pistes[index])
            }
        }
    }

    func handlePointDragEnded(trackIndex index: Int, pistes: inout [TimelineTrack], selection: SelectionState) {
        // A group drag can have touched points on other tracks too (see
        // handlePointDragChanged) — re-sort every track that had a
        // selected point, not just the one the gesture started on.
        if groupDragBaseline.isEmpty {
            pistes[index].evenements.sort()
        } else {
            for trackIndex in pistes.indices {
                pistes[trackIndex].evenements.sort()
            }
        }
        // Points that spent the drag clamped at 0/duree (their unclamped
        // target was past it) get removed now that the gesture is over —
        // stacking was just an in-progress visual, not a useful end state.
        // A single-point drag never populates this set (only isGroupDrag
        // does), so a lone point dragged to the edge still just clamps,
        // same as before.
        if !groupDragOverflowingIDs.isEmpty {
            let overflowing = groupDragOverflowingIDs
            for trackIndex in pistes.indices {
                pistes[trackIndex].evenements.removeAll { overflowing.contains($0.id) }
            }
            selection.selectedPointIDs.subtract(overflowing)
        }
        invalidateSentCache()
        groupDragBaseline.removeAll()
        groupDragAnchorOriginalTime = nil
        groupDragYBaseline.removeAll()
        groupDragAnchorOriginalY = nil
        groupDragSpansMultipleTracks = false
        groupDragOverflowingIDs.removeAll()
    }

    // A plain click: Shift (without Option) removes the point; otherwise a
    // click anywhere just clears whatever the lasso had selected.
    func handlePointTap(eventID: UUID, trackIndex index: Int, pistes: inout [TimelineTrack], selection: SelectionState, tracksLocked: Bool) {
        guard !tracksLocked else { return }
        if NSEvent.modifierFlags.contains(.shift) && !NSEvent.modifierFlags.contains(.option) {
            if let eventIndex = pistes[index].evenements.firstIndex(where: { $0.id == eventID }) {
                pistes[index].evenements.remove(at: eventIndex)
                invalidateSentCache()
            }
        } else if !selection.selectedPointIDs.isEmpty {
            selection.selectedPointIDs.removeAll()
        }
    }

    // ⌥-drag on a curve segment bends it: horizontal movement adds
    // S-shaped curvature, vertical movement adds a simple bow — both
    // combine together. Attached as .simultaneousGesture so it never blocks
    // the plain tap-to-add-point gesture; it only does anything once
    // Option (without Shift) is held and the drag exceeds the threshold.
    func handleCurveBendDragChanged(_ value: DragGesture.Value, trackIndex index: Int, largeurTimeline: CGFloat, pistes: inout [TimelineTrack], duree: Double) {
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

    func invalidateSentCache() {
        lastSentEvents.removeAll()
        lastSentStepValues.removeAll()
    }
}
