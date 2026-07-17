import SwiftUI
import AppKit

extension ContentView {

    func sendOSCMessage(_ message: String, color: Color = .primary) {
        let fullMessage = oscAddressPrefix + message
        oscManager.sendMessage(fullMessage)
        messageStore.addMessage(fullMessage, color: color)
        flashOSCIndicator()
    }

    func flashOSCIndicator() {
        isOSCFlashing = true
        oscFlashTimer?.invalidate()
        let t = Timer(timeInterval: 0.15, repeats: false) { _ in
            DispatchQueue.main.async {
                isOSCFlashing = false
            }
        }
        // .common so the flash still resets promptly even if the user is
        // mid-drag on something else when messages are sent.
        RunLoop.main.add(t, forMode: .common)
        oscFlashTimer = t
    }

    func sendOSCMessagesForPosition(_ pos: Double) {
        for piste in pistes where !piste.isMuted {
            if piste.type == .bang {
                let tol = 0.01
                for event in piste.evenements {
                    if abs(pos - event.time) < tol {
                        if piste.nom == "/markers" {
                            let label = event.label.isEmpty ? "marker" : event.label
                            sendOSCMessage(piste.nom + " " + label, color: piste.couleur)
                        } else {
                            sendOSCMessage(piste.nom + " bang", color: piste.couleur)
                        }
                    }
                }
            } else if piste.type == .message {
                let tol = 0.01
                for event in piste.evenements {
                    if abs(pos - event.time) < tol {
                        sendOSCMessage(piste.nom + " " + event.label, color: piste.couleur)
                    }
                }
            } else if piste.type == .curve {
                // Only speaks where the curve is actually drawn — strictly
                // between its first and last point. Before the first point
                // or after the last one, the track stays silent instead of
                // continuously repeating the nearest endpoint's value.
                let sortedEvents = piste.evenements.sorted { $0.time < $1.time }
                if sortedEvents.isEmpty { continue }

                let lastEventBefore = sortedEvents.last(where: { $0.time <= pos })
                let nextEvent = sortedEvents.first(where: { $0.time > pos })

                if let lastEventBefore = lastEventBefore, let nextEvent = nextEvent, lastEventBefore.segmentEnabled {
                    let ratio = (pos - lastEventBefore.time) / (nextEvent.time - lastEventBefore.time)
                    let curvedRatio = combinedProgress(ratio, curvature: lastEventBefore.segmentCurve, bulge: lastEventBefore.segmentBulge)
                    let interpolatedY = lastEventBefore.y + (nextEvent.y - lastEventBefore.y) * curvedRatio
                    sendOSCMessage(piste.nom + " " + String(format: "%.2f", interpolatedY), color: piste.couleur)
                }
            } else if piste.type == .step {
                // Zero-order hold: send the last event's value as-is, never interpolated.
                let sortedEvents = piste.evenements.sorted { $0.time < $1.time }
                if sortedEvents.isEmpty { continue }

                if let lastEventBefore = sortedEvents.last(where: { $0.time <= pos }) {
                    sendOSCMessage(piste.nom + " " + String(format: "%.2f", lastEventBefore.y), color: piste.couleur)
                } else if let firstEvent = sortedEvents.first {
                    sendOSCMessage(piste.nom + " " + String(format: "%.2f", firstEvent.y), color: piste.couleur)
                }
            }
        }
    }

    // Shared by the toolbar Play button and the Play/Pause menu command.
    func togglePlayback() {
        if !enLecture, enBoucle, let zoneStart = loopZoneStart, let zoneEnd = loopZoneEnd,
           position < zoneStart || position > zoneEnd {
            // Starting playback with an active loop zone: if the playhead
            // isn't already inside it, jump straight to its start instead
            // of playing through from wherever it currently sits until it
            // eventually wanders into the zone.
            position = zoneStart
            sendOSCMessagesForPosition(position)
        }
        enLecture.toggle()
    }

    func advancePlaybackTick() {
        guard enLecture else {
            // Reset so that resuming later doesn't compute a delta spanning
            // the whole time playback was paused/stopped.
            lastTickTimestamp = nil
            return
        }

        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        // First tick after starting/resuming: fall back to the nominal 0.05
        // since there's no previous timestamp yet to compute a real delta from.
        let delta = lastTickTimestamp.map { now - $0 } ?? 0.05
        lastTickTimestamp = now

        let prev = position
        position += delta
        var justLooped = false
        var wrapTarget = 0.0
        if let zoneStart = loopZoneStart, let zoneEnd = loopZoneEnd, enBoucle, position >= zoneEnd {
            // A loop zone exists and Loop is on: wrap within the zone
            // instead of the whole timeline.
            position = zoneStart
            wrapTarget = zoneStart
            lastSentEvents.removeAll()
            justLooped = true
        } else if position >= duree {
            position = 0.0
            wrapTarget = 0.0
            if !enBoucle { enLecture = false }
            lastSentEvents.removeAll()
            justLooped = true
        }
        // Right on the tick where playback wraps back to 0 (or to the loop
        // zone's start), `prev` still holds the old (pre-wrap) position —
        // comparing it directly against early event times would make the
        // crossing check (prev < event.time <= position) fail for anything
        // near the wrap target, since prev is much larger than those times.
        // Substitute a value just below the wrap target for that one tick
        // so events right at the start of the loop are correctly treated
        // as freshly crossed.
        let effectivePrev = justLooped ? wrapTarget - 1.0 : prev

        for piste in pistes {
            guard piste.type == .bang, !piste.isMuted else { continue }
            let tol = 0.001
            for event in piste.evenements {
                guard effectivePrev < event.time - tol && position >= event.time - tol else { continue }
                let key = piste.nom + "-" + String(event.time)
                guard !lastSentEvents.contains(key) else { continue }
                lastSentEvents.insert(key)
                if piste.nom == "/markers" {
                    let label = event.label.isEmpty ? "marker" : event.label
                    sendOSCMessage(piste.nom + " " + label, color: piste.couleur)
                } else {
                    sendOSCMessage(piste.nom + " bang", color: piste.couleur)
                }
            }
        }

        for piste in pistes {
            guard piste.type == .message, !piste.isMuted else { continue }
            let tol = 0.001
            for event in piste.evenements {
                guard effectivePrev < event.time - tol && position >= event.time - tol else { continue }
                let key = piste.nom + "-message-" + String(event.time)
                guard !lastSentEvents.contains(key) else { continue }
                lastSentEvents.insert(key)
                sendOSCMessage(piste.nom + " " + event.label, color: piste.couleur)
            }
        }

        for piste in pistes {
            guard piste.type == .curve, !piste.isMuted else { continue }
            // Only speaks where the curve is actually drawn — see the same
            // comment in sendOSCMessagesForPosition.
            let sortedEvents = piste.evenements.sorted { $0.time < $1.time }
            if sortedEvents.isEmpty { continue }

            let lastEventBefore = sortedEvents.last(where: { $0.time <= position })
            let nextEvent = sortedEvents.first(where: { $0.time > position })

            if let lastEventBefore = lastEventBefore, let nextEvent = nextEvent, lastEventBefore.segmentEnabled {
                let ratio = (position - lastEventBefore.time) / (nextEvent.time - lastEventBefore.time)
                let curvedRatio = combinedProgress(ratio, curvature: lastEventBefore.segmentCurve, bulge: lastEventBefore.segmentBulge)
                let interpolatedY = lastEventBefore.y + (nextEvent.y - lastEventBefore.y) * curvedRatio
                sendOSCMessage(piste.nom + " " + String(format: "%.2f", interpolatedY), color: piste.couleur)
            }
        }

        for piste in pistes {
            guard piste.type == .step, !piste.isMuted else { continue }
            // Zero-order hold, but only send OSC when a new point is crossed —
            // the value doesn't change between two points, so continuous sending
            // (like every 50ms tick) would just flood the system uselessly.
            let tol = 0.001
            for event in piste.evenements {
                guard effectivePrev < event.time - tol && position >= event.time - tol else { continue }
                let key = piste.nom + "-step-" + String(event.time)
                guard !lastSentEvents.contains(key) else { continue }
                lastSentEvents.insert(key)
                sendOSCMessage(piste.nom + " " + String(format: "%.2f", event.y), color: piste.couleur)
            }
        }
    }

    func startPlaybackTimer() {
        timer?.invalidate()
        let rate = max(1, oscMessagesPerSecond)
        let interval = 1.0 / Double(rate)
        let playbackTimer = Timer(timeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                advancePlaybackTick()
            }
        }
        // .common (not just .default) so playback keeps ticking even while
        // some other drag (a point, a track resize, the duration handle...)
        // is actively being tracked elsewhere in the app.
        RunLoop.main.add(playbackTimer, forMode: .common)
        timer = playbackTimer
    }

    func handleReceivedOSCMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        switch normalized {
        case "play":
            enLecture = true
        case "pause":
            enLecture = false
        case "stop":
            enLecture = false
            position = 0
            lastSentEvents.removeAll()
        default:
            break
        }
    }

    func centerOnPlayhead() {
        let outerWidth = max(timelineAreaWidth, 1)
        // timelineAreaWidth already excludes the duration handle (the whole
        // timeline area is padded by its width), so no extra subtraction here
        // — this must mirror the largeurTimeline used for drawing exactly.
        let largeurTimeline = outerWidth * CGFloat(zoomX) - 140
        guard largeurTimeline > 0 else { return }
        let playheadX = 140 + CGFloat(position / duree) * largeurTimeline
        scrollOffsetX = max(0, playheadX - outerWidth / 2)
    }

    func goToNextMarker() {
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return }
        let target = sorted.first(where: { $0.time > position + 0.001 })?.time ?? sorted[0].time
        position = target
        sendOSCMessagesForPosition(position)
        centerOnPlayhead()
    }

    func goToPreviousMarker() {
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return }
        let target = sorted.last(where: { $0.time < position - 0.001 })?.time ?? sorted[sorted.count - 1].time
        position = target
        sendOSCMessagesForPosition(position)
        centerOnPlayhead()
    }

    @discardableResult
    func goToMarkerByName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showGoToMarkerNoMatch = true
            return false
        }
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        let exactMatch = sorted.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })
        let partialMatch = sorted.first(where: { $0.label.range(of: trimmed, options: .caseInsensitive) != nil })
        guard let match = exactMatch ?? partialMatch else {
            showGoToMarkerNoMatch = true
            return false
        }
        position = match.time
        sendOSCMessagesForPosition(position)
        centerOnPlayhead()
        return true
    }

    func goToTime(_ text: String) {
        guard let parsed = parseDuration(text) else { return }
        position = min(max(parsed, 0), duree)
        sendOSCMessagesForPosition(position)
        centerOnPlayhead()
    }

    // Used by the "Go to Position" sheet's single Go button (and Return in
    // either field): acts on whichever field currently has focus, falling
    // back to the time field if focus was lost some other way (e.g. the
    // user clicked directly on the Go button without tabbing through).
    func goToChosenPlayheadPosition() {
        // Decided by field *content*, not focus: clicking the "Go" button
        // transiently moves keyboard focus away from whichever TextField
        // had it, so a focus-based decision was unreliable. If a marker
        // name was typed, that's an unambiguous signal to search by marker;
        // otherwise fall back to the time field.
        let trimmedMarker = goToMarkerNameString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMarker.isEmpty {
            // Presenting the "No match" alert while this sheet is
            // simultaneously dismissing doesn't reliably show in SwiftUI —
            // so on failure, keep the sheet open and surface it inline
            // instead of dismissing blindly.
            if goToMarkerByName(goToMarkerNameString) {
                playheadMarkerNotFound = false
                showPlayheadPositionChoice = false
            } else {
                playheadMarkerNotFound = true
            }
        } else {
            goToTime(goToTimeString)
            showPlayheadPositionChoice = false
        }
    }

    func recenterOnZoomChange(oldZoom: Double, newZoom: Double, outerWidth: CGFloat) {
        guard !isPinchZooming else { return }
        let largeurAvant = outerWidth * CGFloat(oldZoom) - 140
        guard largeurAvant > 0 else { return }

        let anchorTime = min(max(position, 0), duree)
        let absoluteContentXBefore = 140 + CGFloat(anchorTime / duree) * largeurAvant
        let locationXInViewport = absoluteContentXBefore - scrollOffsetX

        let largeurApres = outerWidth * CGFloat(newZoom) - 140
        guard largeurApres > 0 else { return }
        let absoluteContentXAfter = 140 + CGFloat(anchorTime / duree) * largeurApres
        let maxX = max(0, outerWidth * CGFloat(newZoom) - outerWidth)
        let newOffsetX = max(0, min(absoluteContentXAfter - locationXInViewport, maxX))
        scrollOffsetX = newOffsetX
    }

    func commitDureeEdit() {
        if let parsed = parseDuration(dureeText) {
            duree = max(parsed.rounded(), 1)
        }
        dureeText = formattedDuration(duree)
    }

    func startDurationDragTimer() {
        durationDragTimer?.invalidate()
        let tickInterval = 0.02
        let newTimer = Timer(timeInterval: tickInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                let dx = Double(durationDragCurrentDeltaX)
                let magnitude = pow(abs(dx), durationDragVelocityExponent) * durationDragVelocityScale
                let ratePerSecond = dx < 0 ? -magnitude : magnitude
                let rawDuree = duree + ratePerSecond * tickInterval
                let quantized = (rawDuree * 100).rounded() / 100
                duree = max(0.1, quantized)
                dureeText = formattedDuration(duree)
            }
        }
        // Timer.scheduledTimer only runs in the .default run loop mode,
        // which AppKit suspends while actively tracking a mouse drag (the
        // run loop switches to .eventTracking mode during that time) — so
        // the timer would silently never fire while the drag is held.
        // Adding it in .common mode instead keeps it running throughout.
        RunLoop.main.add(newTimer, forMode: .common)
        durationDragTimer = newTimer
    }

    func stopDurationDragTimer() {
        durationDragTimer?.invalidate()
        durationDragTimer = nil
    }

}
