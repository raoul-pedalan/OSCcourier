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
           let snapped = nearestSnapTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
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
