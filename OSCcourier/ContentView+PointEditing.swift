import SwiftUI
import AppKit

extension ContentView {

    func refreshPointList() {
        var rows: [PointListRow] = []
        for (trackIndex, piste) in pistes.enumerated() {
            // Only markers and message tracks carry a meaningful label. Bang
            // and curve/step points don't — any label they hold is leftover
            // default state, so showing it (e.g. a stray "M") is just noise.
            let hasLabel = trackIndex == 0 || piste.type == .message
            let hasY = piste.type == .curve || piste.type == .step
            for event in piste.evenements {
                rows.append(PointListRow(
                    id: event.id,
                    trackName: piste.nom,
                    trackColor: piste.couleur,
                    time: event.time,
                    label: hasLabel ? event.label : "",
                    y: event.y,
                    comment: event.comment,
                    hasY: hasY,
                    hasLabel: hasLabel,
                    minAmplitude: piste.minAmplitude,
                    maxAmplitude: piste.maxAmplitude
                ))
            }
        }
        pointListStore.rows = rows.sorted { $0.time < $1.time }
        pointListStore.trackNames = pistes.map { $0.nom }
    }

    // Unlike deleteSelectedPoints (the lasso's version, scoped to a single
    // track since a lasso never spans more than one), the Point List shows
    // every track's points flattened into one list — so a batch of ids
    // selected there can legitimately span several tracks at once, and
    // every track needs checking.
    func deleteSpecificPoints(ids: [UUID]) {
        guard !tracksLocked, !ids.isEmpty else { return }
        let idSet = Set(ids)
        for i in pistes.indices {
            pistes[i].evenements.removeAll { idSet.contains($0.id) }
        }
        lastSentEvents.removeAll()
    }

    func applyPointEdit(_ edit: PointEdit) {
        guard !tracksLocked else { return }
        for trackIndex in pistes.indices {
            guard let eventIndex = pistes[trackIndex].evenements.firstIndex(where: { $0.id == edit.id }) else { continue }

            if let time = edit.time {
                pistes[trackIndex].evenements[eventIndex].time = min(max(time, 0), duree)
            }
            if let label = edit.label {
                pistes[trackIndex].evenements[eventIndex].label = label
            }
            if let y = edit.y {
                let piste = pistes[trackIndex]
                let clamped = min(max(y, piste.minAmplitude), piste.maxAmplitude)
                pistes[trackIndex].evenements[eventIndex].y = gateSnappedY(clamped, forTrackIndex: trackIndex)
            }
            if let comment = edit.comment {
                pistes[trackIndex].evenements[eventIndex].comment = comment
            }

            pistes[trackIndex].evenements.sort()
            lastSentEvents.removeAll()
            return
        }
    }

    func beginEditingPoint(eventId: UUID) {
        guard !tracksLocked else { return }
        for (trackIndex, piste) in pistes.enumerated() {
            guard let event = piste.evenements.first(where: { $0.id == eventId }) else { continue }
            pointAEditer = (trackIndex, eventId)
            nouvellePositionString = String(format: "%.2f", event.time)
            nouvelleYString = String(format: "%.2f", event.y)
            nouveauComment = event.comment
            if trackIndex == 0 || piste.type == .message {
                nouveauLabel = event.label
            }
            return
        }
    }

    // Called from a track's paste gesture at the click-up location. Returns
    // false (and leaves paste mode active so the caller can show the
    // incompatible-track alert) if the track's type doesn't match the
    // clipboard's source type.
    func pasteClipboard(at anchorTime: Double, trackIndex: Int, scaleToRange: Bool) -> Bool {
        guard !tracksLocked, !pointClipboard.isEmpty,
              let clipboardType = pointClipboardTrackType else { return false }

        let piste = pistes[trackIndex]
        let destinationType = piste.type
        let typesDiffer = destinationType != clipboardType
        let srcMin = pointClipboardSourceMinAmplitude
        let srcMax = pointClipboardSourceMaxAmplitude
        var newSelection: Set<UUID> = []
        var pasted: [TimelineEvent] = []
        for entry in pointClipboard {
            var y = entry.y
            if scaleToRange, let srcMin, let srcMax, srcMax > srcMin {
                let normalized = (entry.y - srcMin) / (srcMax - srcMin)
                y = piste.minAmplitude + normalized * (piste.maxAmplitude - piste.minAmplitude)
            }
            // A label only means something on markers/message tracks, and
            // what it should default to differs by type — carrying the
            // source label over verbatim only makes sense between two
            // tracks of the same type.
            let label: String
            if !typesDiffer {
                label = entry.label
            } else {
                switch destinationType {
                case .bang: label = "M"
                case .message: label = entry.label.isEmpty ? "key" : entry.label
                case .curve, .step, .normal: label = ""
                }
            }
            let newEvent = TimelineEvent(
                time: min(max(anchorTime + entry.deltaTime, 0), duree),
                label: label,
                y: min(max(y, piste.minAmplitude), piste.maxAmplitude),
                segmentCurve: entry.segmentCurve,
                segmentBulge: entry.segmentBulge,
                segmentEnabled: entry.segmentEnabled,
                comment: entry.comment
            )
            pasted.append(newEvent)
            newSelection.insert(newEvent.id)
        }
        pistes[trackIndex].evenements.append(contentsOf: pasted)
        pistes[trackIndex].evenements.sort()
        lastSentEvents.removeAll()
        // The freshly pasted points become the new selection, so they can
        // immediately be nudged as a group if the placement needs tweaking.
        selectedPointIDs = newSelection
        // Remembered so ⌘D can repeat this exact paste at the same offset,
        // stepping forward again each time it's pressed.
        lastPasteAnchorTime = anchorTime
        lastPasteTrackIndex = trackIndex
        return true
    }

    // Whether the destination track's type differs from the clipboard's
    // source type — if so, paste needs the user to explicitly choose to
    // adapt (or cancel), rather than silently reinterpreting the data.
    func pasteNeedsTypeChoice(trackIndex: Int) -> Bool {
        guard let clipboardType = pointClipboardTrackType else { return false }
        return pistes[trackIndex].type != clipboardType
    }

    // Whether the destination track's amplitude range differs from the
    // clipboard's source range — only meaningful for curve/step tracks,
    // the only types where Y carries real information.
    func pasteNeedsRangeChoice(trackIndex: Int) -> Bool {
        guard pistes[trackIndex].type == .curve || pistes[trackIndex].type == .step else { return false }
        guard let srcMin = pointClipboardSourceMinAmplitude, let srcMax = pointClipboardSourceMaxAmplitude else { return false }
        return srcMin != pistes[trackIndex].minAmplitude || srcMax != pistes[trackIndex].maxAmplitude
    }

    // ⌘D: repeats the last paste at the exact same offset from wherever it
    // last landed — press it repeatedly to stamp out an evenly-spaced
    // series from a single copy. Requires at least one paste to have
    // happened since the last copy, since that's what establishes the
    // offset to repeat; does nothing before that.
    func duplicateSelectionWithSameOffset() {
        guard !tracksLocked, !pointClipboard.isEmpty,
              let prevAnchor = lastPasteAnchorTime,
              let trackIndex = lastPasteTrackIndex,
              pistes.indices.contains(trackIndex) else { return }

        let offset: Double
        if let fixedOffset = lastPasteOffset {
            offset = fixedOffset
        } else if let originalEarliest = pointClipboardOriginalEarliestTime {
            // First ⌘D since the last manual paste: derive the offset once
            // from how far that paste was from the original copy, then
            // remember it — every later ⌘D press reuses this exact value.
            offset = prevAnchor - originalEarliest
            lastPasteOffset = offset
        } else {
            return
        }

        let newAnchor = prevAnchor + offset
        _ = pasteClipboard(at: newAnchor, trackIndex: trackIndex, scaleToRange: false)
    }

    // The lasso only ever selects points on a single track, so the first
    // track with a match is the source — its type is remembered so paste
    // can reject a mismatched destination.
    func copySelectedPoints() {
        guard !selectedPointIDs.isEmpty else { return }
        for piste in pistes {
            let matching = piste.evenements.filter { selectedPointIDs.contains($0.id) }
            guard !matching.isEmpty else { continue }
            let earliestTime = matching.map { $0.time }.min() ?? 0
            pointClipboard = matching.map { event in
                PointClipboardEntry(
                    deltaTime: event.time - earliestTime,
                    label: event.label,
                    y: event.y,
                    segmentCurve: event.segmentCurve,
                    segmentBulge: event.segmentBulge,
                    segmentEnabled: event.segmentEnabled,
                    comment: event.comment
                )
            }
            pointClipboardTrackType = piste.type
            pointClipboardSourceMinAmplitude = piste.minAmplitude
            pointClipboardSourceMaxAmplitude = piste.maxAmplitude
            pointClipboardOriginalEarliestTime = earliestTime
            // A new copy invalidates whatever offset ⌘D was tracking —
            // it needs a fresh paste before it has an offset to repeat.
            lastPasteAnchorTime = nil
            lastPasteTrackIndex = nil
            lastPasteOffset = nil
            return
        }
    }

    // Arrow keys: nudge the current selection by exactly one screen pixel,
    // in time (left/right) and/or value (up/down, curve/step only). Same
    // group-preserving clamp as a mouse drag: the delta itself shrinks
    // (rather than each point clamping independently) if it would push any
    // selected point out of range, so relative spacing is never distorted.
    func nudgeSelection(timePixels: Int, valuePixels: Int) {
        guard !tracksLocked, !selectedPointIDs.isEmpty else { return }
        for i in pistes.indices {
            let selected = pistes[i].evenements.filter { selectedPointIDs.contains($0.id) }
            guard !selected.isEmpty else { continue }

            if timePixels != 0 {
                // Mirrors largeurTimeline's own formula (geometry.size.width - 140,
                // where that geometry is the zoomed content width).
                let effectiveWidth = max((timelineAreaWidth * CGFloat(zoomX)) - 140, 1)
                let secondsPerPixel = duree / Double(effectiveWidth)
                let rawDelta = secondsPerPixel * Double(timePixels)
                var minAllowedDelta = -Double.infinity
                var maxAllowedDelta = Double.infinity
                for e in selected {
                    minAllowedDelta = max(minAllowedDelta, 0 - e.time)
                    maxAllowedDelta = min(maxAllowedDelta, duree - e.time)
                }
                let delta = min(max(rawDelta, minAllowedDelta), maxAllowedDelta)
                for id in selectedPointIDs {
                    guard let idx = pistes[i].evenements.firstIndex(where: { $0.id == id }) else { continue }
                    pistes[i].evenements[idx].time += delta
                }
            }

            if valuePixels != 0, pistes[i].type == .curve || pistes[i].type == .step {
                let goingUp = valuePixels > 0

                if pistes[i].type == .step && pistes[i].isGate {
                    // Only two levels exist — jump straight to the other one.
                    let target = goingUp ? pistes[i].maxAmplitude : pistes[i].minAmplitude
                    for id in selectedPointIDs {
                        guard let idx = pistes[i].evenements.firstIndex(where: { $0.id == id }) else { continue }
                        pistes[i].evenements[idx].y = target
                    }
                } else if pistes[i].quantizeActive {
                    // Quantization on: each keystroke jumps every selected point
                    // to the adjacent division above/below wherever it currently
                    // sits — not a pixel-sized nudge that quantizedY would then
                    // just round back down to nothing.
                    let step = pistes[i].quantizeStep
                    for id in selectedPointIDs {
                        guard let idx = pistes[i].evenements.firstIndex(where: { $0.id == id }) else { continue }
                        let currentY = pistes[i].evenements[idx].y
                        let currentDivision = ((currentY - pistes[i].minAmplitude) / step).rounded()
                        let newDivision = currentDivision + (goingUp ? 1 : -1)
                        let newY = pistes[i].minAmplitude + newDivision * step
                        pistes[i].evenements[idx].y = min(max(newY, pistes[i].minAmplitude), pistes[i].maxAmplitude)
                    }
                } else {
                    // No quantization: a plain one-pixel nudge, same
                    // group-preserving clamp as the time axis above.
                    let range = pistes[i].maxAmplitude - pistes[i].minAmplitude
                    let valuePerPixel = range / Double(max(pistes[i].height, 1))
                    let rawDelta = valuePerPixel * Double(valuePixels)
                    var minAllowedDelta = -Double.infinity
                    var maxAllowedDelta = Double.infinity
                    for e in selected {
                        minAllowedDelta = max(minAllowedDelta, pistes[i].minAmplitude - e.y)
                        maxAllowedDelta = min(maxAllowedDelta, pistes[i].maxAmplitude - e.y)
                    }
                    let delta = min(max(rawDelta, minAllowedDelta), maxAllowedDelta)
                    for id in selectedPointIDs {
                        guard let idx = pistes[i].evenements.firstIndex(where: { $0.id == id }) else { continue }
                        pistes[i].evenements[idx].y = pistes[i].evenements[idx].y + delta
                    }
                }
            }

            pistes[i].evenements.sort()
            lastSentEvents.removeAll()
            break // the lasso only ever selects points on a single track
        }
    }

    // The lasso only ever selects points on the single track it started on,
    // so removing by id across every track's evenements is safe — at most
    // one track actually has any matches.
    func deleteSelectedPoints() {
        guard !tracksLocked, !selectedPointIDs.isEmpty else { return }
        for i in pistes.indices {
            pistes[i].evenements.removeAll { selectedPointIDs.contains($0.id) }
        }
        selectedPointIDs.removeAll()
        lastSentEvents.removeAll()
    }

    func beginCreatingPoint(at location: CGPoint, trackIndex: Int, largeurTimeline: CGFloat) {
        guard !tracksLocked else { return }
        if !selectedPointIDs.isEmpty {
            selectedPointIDs.removeAll()
        }
        let piste = pistes[trackIndex]
        let rawTime = (Double(location.x) / Double(largeurTimeline)) * duree
        let time = min(max(rawTime, 0), duree)

        let label: String
        let y: Double
        switch piste.type {
        case .bang:
            label = "M"
            y = 0.5
        case .message:
            label = "key"
            y = 0.5
        case .curve, .step:
            label = ""
            let normalizedY = min(max(1 - (Double(location.y) / Double(piste.height)), 0), 1)
            let raw = piste.minAmplitude + normalizedY * (piste.maxAmplitude - piste.minAmplitude)
            y = gateSnappedY(raw, forTrackIndex: trackIndex)
        case .normal:
            label = ""
            y = 0.5
        }

        let event = TimelineEvent(time: time, label: label, y: y)
        pistes[trackIndex].evenements.append(event)
        pistes[trackIndex].evenements.sort()
        lastSentEvents.removeAll()

        creatingPointId = event.id
        creatingPointTrackIndex = trackIndex
    }

    func updateCreatingPoint(at location: CGPoint, largeurTimeline: CGFloat) {
        guard !tracksLocked,
              let id = creatingPointId,
              let trackIndex = creatingPointTrackIndex,
              pistes.indices.contains(trackIndex),
              let eventIndex = pistes[trackIndex].evenements.firstIndex(where: { $0.id == id })
        else { return }

        let xPos = Double(location.x)
        var newTime = (xPos / Double(largeurTimeline)) * duree

        if NSEvent.modifierFlags.contains(.command),
           let snapped = nearestSnapTime(xPos: xPos, largeurTimeline: Double(largeurTimeline), excluding: id) {
            newTime = snapped
        } else if magneticGridSnap,
                  let snapped = nearestGridTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
            newTime = snapped
        }
        pistes[trackIndex].evenements[eventIndex].time = min(max(newTime, 0), duree)

        let piste = pistes[trackIndex]
        if piste.type == .curve || piste.type == .step {
            let normalizedY = min(max(1 - (Double(location.y) / Double(piste.height)), 0), 1)
            let raw = piste.minAmplitude + normalizedY * (piste.maxAmplitude - piste.minAmplitude)
            pistes[trackIndex].evenements[eventIndex].y = gateSnappedY(raw, forTrackIndex: trackIndex)
        }
        lastSentEvents.removeAll()
    }

    func finishCreatingPoint() {
        if let trackIndex = creatingPointTrackIndex, pistes.indices.contains(trackIndex) {
            pistes[trackIndex].evenements.sort()
        }
        creatingPointId = nil
        creatingPointTrackIndex = nil
    }

    func commitPointEdit() {
        if let (trackIndex, eventId) = pointAEditer,
           let newPosition = Double(nouvellePositionString),
           let eventIndex = pistes[trackIndex].evenements.firstIndex(where: { $0.id == eventId }) {
            pistes[trackIndex].evenements[eventIndex].time = min(max(newPosition, 0), duree)
            if (pistes[trackIndex].type == .curve || pistes[trackIndex].type == .step), let newY = Double(nouvelleYString) {
                let constrainedY = min(max(newY, pistes[trackIndex].minAmplitude), pistes[trackIndex].maxAmplitude)
                pistes[trackIndex].evenements[eventIndex].y = gateSnappedY(constrainedY, forTrackIndex: trackIndex)
            }
            if trackIndex == 0 || pistes[trackIndex].type == .message {
                pistes[trackIndex].evenements[eventIndex].label = nouveauLabel
            }
            pistes[trackIndex].evenements[eventIndex].comment = nouveauComment
            pistes[trackIndex].evenements.sort()
            lastSentEvents.removeAll()
        }
        pointAEditer = nil
    }

    func openPointListWindow() {
        refreshPointList()

        // Wired every time (cheap, and the closure captures fresh state) so
        // the list window can hand its edits back to us.
        pointListStore.onCommitEdit = { edit in
            applyPointEdit(edit)
        }
        pointListStore.onDeletePoints = { ids in
            deleteSpecificPoints(ids: ids)
        }

        if let controller = pointListWindowController {
            if isPointListWindowVisible {
                controller.window?.close()
                isPointListWindowVisible = false
            } else {
                controller.showWindow(nil)
                isPointListWindowVisible = true
            }
            return
        }

        // The view observes pointListStore, so no need to rebuild the hosting
        // view on reopen — it re-renders on its own whenever the store changes.
        let hostingView = NSHostingView(rootView: PointListView(store: pointListStore))
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 380)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Point List"
        window.setFrameAutosaveName("PointListWindow")
        window.contentView = hostingView
        window.minSize = NSSize(width: 520, height: 300)
        window.isReleasedWhenClosed = false
        // Deliberately NOT a floating window: a floating list parked in the
        // middle of the screen would sit on top of every sheet the main window
        // opens (point editor, autofill, grid settings...), hiding them.

        let delegate = OSCWindowCloseDelegate()
        delegate.onClose = {
            isPointListWindowVisible = false
        }
        delegate.sharedUndoManager = timelineStore.undoManager
        window.delegate = delegate
        pointListCloseDelegate = delegate

        window.center()

        pointListWindowController = NSWindowController(window: window)
        pointListWindowController?.showWindow(nil)
        isPointListWindowVisible = true
    }

}
