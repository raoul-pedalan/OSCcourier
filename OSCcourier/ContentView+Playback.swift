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
        transport.isOSCFlashing = true
        transport.oscFlashTimer?.invalidate()
        let t = Timer(timeInterval: 0.15, repeats: false) { _ in
            DispatchQueue.main.async {
                transport.isOSCFlashing = false
            }
        }
        // .common so the flash still resets promptly even if the user is
        // mid-drag on something else when messages are sent.
        RunLoop.main.add(t, forMode: .common)
        transport.oscFlashTimer = t
    }

    func sendOSCMessagesForPosition(_ pos: Double) {
        // Called whenever the playhead jumps to an arbitrary transport.position
        // (click, drag, Go to Time/Marker, next/previous marker, the OSC
        // /goto command, a loop zone's start...) — never from the
        // continuous per-tick playback loop, which tracks its own
        // crossings separately. Clearing here means replaying back over
        // points already sent earlier (e.g. play, pause, drag the playhead
        // back, play again) re-sends them instead of silently treating
        // them as "already sent" from a previous, unrelated pass.
        pointDrag.lastSentEvents.removeAll()
        // A muted step track forgets its last sent value, so unmuting makes
        // it speak again immediately rather than being suppressed by an
        // entry cached from before it was silenced.
        for piste in pistes where piste.isMuted && piste.type == .step {
            pointDrag.lastSentStepValues.removeValue(forKey: piste.nom)
        }
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
                // Zero-order hold: send the last event's value as-is, never
                // interpolated — and only when that held value actually
                // changes. A step track is constant between two points, so
                // dragging the playhead across a single step would otherwise
                // emit the same message on every drag tick. Matches what the
                // playback loop already does via its crossing check.
                let sortedEvents = piste.evenements.sorted { $0.time < $1.time }
                if sortedEvents.isEmpty { continue }

                let heldValue: Double
                if let lastEventBefore = sortedEvents.last(where: { $0.time <= pos }) {
                    heldValue = lastEventBefore.y
                } else if let firstEvent = sortedEvents.first {
                    heldValue = firstEvent.y
                } else {
                    continue
                }
                guard pointDrag.lastSentStepValues[piste.nom] != heldValue else { continue }
                pointDrag.lastSentStepValues[piste.nom] = heldValue
                sendOSCMessage(piste.nom + " " + String(format: "%.2f", heldValue), color: piste.couleur)
            }
        }
    }

    // Shared by the toolbar Play button and the Play/Pause menu command.
    // Shared by togglePlayback (local Play button/menu/spacebar) and the
    // OSC "/play" handler: if a loop zone is active and the playhead isn't
    // currently inside it, jump straight to its start instead of playing
    // through from wherever it currently sits until it eventually wanders
    // into the zone.
    private func jumpToLoopZoneStartIfNeeded() {
        if enBoucle, let zoneStart = loopZone.loopZoneStart, let zoneEnd = loopZone.loopZoneEnd,
           transport.position < zoneStart || transport.position > zoneEnd {
            transport.position = zoneStart
            sendOSCMessagesForPosition(transport.position)
        }
    }

    func togglePlayback() {
        if !transport.enLecture {
            jumpToLoopZoneStartIfNeeded()
        }
        transport.enLecture.toggle()
    }

    func advancePlaybackTick() {
        guard transport.enLecture else {
            // Reset so that resuming later doesn't compute a delta spanning
            // the whole time playback was paused/stopped.
            transport.lastTickTimestamp = nil
            return
        }

        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        // First tick after starting/resuming: fall back to the nominal 0.05
        // since there's no previous timestamp yet to compute a real delta from.
        let delta = transport.lastTickTimestamp.map { now - $0 } ?? 0.05
        transport.lastTickTimestamp = now

        let prev = transport.position
        transport.position += delta
        var justLooped = false
        var wrapTarget = 0.0
        if let zoneStart = loopZone.loopZoneStart, let zoneEnd = loopZone.loopZoneEnd, enBoucle, transport.position >= zoneEnd {
            // A loop zone exists and Loop is on: wrap within the zone
            // instead of the whole timeline.
            transport.position = zoneStart
            wrapTarget = zoneStart
            pointDrag.lastSentEvents.removeAll()
            justLooped = true
        } else if transport.position >= transport.duree {
            transport.position = 0.0
            wrapTarget = 0.0
            if !enBoucle { transport.enLecture = false }
            pointDrag.lastSentEvents.removeAll()
            justLooped = true
        }
        // Right on the tick where playback wraps back to 0 (or to the loop
        // zone's start), `prev` still holds the old (pre-wrap) transport.position —
        // comparing it directly against early event times would make the
        // crossing check (prev < event.time <= transport.position) fail for anything
        // near the wrap target, since prev is much larger than those times.
        // Substitute a value just below the wrap target for that one tick
        // so events right at the start of the loop are correctly treated
        // as freshly crossed.
        let effectivePrev = justLooped ? wrapTarget - 1.0 : prev

        followPlayheadDuringPlayback()

        for piste in pistes {
            guard piste.type == .bang, !piste.isMuted else { continue }
            let tol = 0.001
            for event in piste.evenements {
                guard effectivePrev < event.time - tol && transport.position >= event.time - tol else { continue }
                let key = piste.nom + "-" + String(event.time)
                guard !pointDrag.lastSentEvents.contains(key) else { continue }
                pointDrag.lastSentEvents.insert(key)
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
                guard effectivePrev < event.time - tol && transport.position >= event.time - tol else { continue }
                let key = piste.nom + "-message-" + String(event.time)
                guard !pointDrag.lastSentEvents.contains(key) else { continue }
                pointDrag.lastSentEvents.insert(key)
                sendOSCMessage(piste.nom + " " + event.label, color: piste.couleur)
            }
        }

        for piste in pistes {
            guard piste.type == .curve, !piste.isMuted else { continue }
            // Only speaks where the curve is actually drawn — see the same
            // comment in sendOSCMessagesForPosition.
            let sortedEvents = piste.evenements.sorted { $0.time < $1.time }
            if sortedEvents.isEmpty { continue }

            let lastEventBefore = sortedEvents.last(where: { $0.time <= transport.position })
            let nextEvent = sortedEvents.first(where: { $0.time > transport.position })

            if let lastEventBefore = lastEventBefore, let nextEvent = nextEvent, lastEventBefore.segmentEnabled {
                let ratio = (transport.position - lastEventBefore.time) / (nextEvent.time - lastEventBefore.time)
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
                guard effectivePrev < event.time - tol && transport.position >= event.time - tol else { continue }
                let key = piste.nom + "-step-" + String(event.time)
                guard !pointDrag.lastSentEvents.contains(key) else { continue }
                pointDrag.lastSentEvents.insert(key)
                sendOSCMessage(piste.nom + " " + String(format: "%.2f", event.y), color: piste.couleur)
            }
        }
    }

    func startPlaybackTimer() {
        transport.timer?.invalidate()
        let rate = max(1, oscMessagesPerSecond)
        let interval = 1.0 / Double(rate)
        // Called directly, not deferred via DispatchQueue.main.async — the
        // timer is already added to RunLoop.main below, so it already runs
        // on the main thread; the extra async hop just added an avoidable
        // run-loop round-trip on every tick (up to 20/sec) for no benefit,
        // and could make tick timing slightly less even.
        let playbackTimer = Timer(timeInterval: interval, repeats: true) { _ in
            advancePlaybackTick()
        }
        // .common (not just .default) so playback keeps ticking even while
        // some other drag (a point, a track resize, the duration handle...)
        // is actively being tracked elsewhere in the app.
        RunLoop.main.add(playbackTimer, forMode: .common)
        transport.timer = playbackTimer
    }

    func handleReceivedOSCMessage(_ message: String, _ args: [OSCValue]) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        switch normalized {
        case "play":
            if !transport.enLecture {
                jumpToLoopZoneStartIfNeeded()
            }
            transport.enLecture = true
        case "pause":
            transport.enLecture = false
        case "stop":
            transport.enLecture = false
            transport.position = 0
            pointDrag.lastSentEvents.removeAll()
        case "goto":
            // A string argument is a marker name; a numeric one is a time in
            // seconds — mirrors the app's own "Go to Position" popup, which
            // offers the exact same two ways to navigate.
            switch args.first {
            case .string(let name):
                goToMarkerByName(name)
            case .float(let seconds):
                transport.position = min(max(Double(seconds), 0), transport.duree)
                sendOSCMessagesForPosition(transport.position)
                centerOnPlayhead()
            case .int(let seconds):
                transport.position = min(max(Double(seconds), 0), transport.duree)
                sendOSCMessagesForPosition(transport.position)
                centerOnPlayhead()
            case .none:
                break
            }
        case "loop":
            // An explicit 0/1 (or any nonzero number) sets the state
            // directly — safer for remote automation than a blind toggle,
            // which could drift out of sync with the app's own state.
            // No argument at all falls back to a plain toggle, matching the
            // local "C" hotkey.
            switch args.first {
            case .int(let value):
                enBoucle = value != 0
            case .float(let value):
                enBoucle = value != 0
            case .string, .none:
                enBoucle.toggle()
            }
        case "loopzone":
            // Two numeric args: start and end, in seconds — order doesn't
            // matter, sorted the same way a ruler-drawn zone is. Setting a
            // zone this way activates Loop right away, same as drawing one
            // by hand in the ruler.
            guard args.count >= 2,
                  let a = numericOSCValue(args[0]),
                  let b = numericOSCValue(args[1]) else { break }
            let clampedA = min(max(a, 0), transport.duree)
            let clampedB = min(max(b, 0), transport.duree)
            loopZone.loopZoneStart = min(clampedA, clampedB)
            loopZone.loopZoneEnd = max(clampedA, clampedB)
            enBoucle = true
        case "mute":
            // First argument: the track's name (matched exactly first, then
            // case-insensitively as a fallback — same leniency as marker
            // lookup). Second argument, if present, sets the state
            // explicitly (0/1, any nonzero counts as on); omit it to just
            // toggle, matching /loop's own convention.
            guard case .string(let trackName)? = args.first else { break }
            let trimmedName = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let idx = pistes.firstIndex(where: { $0.nom == trimmedName })
                ?? pistes.firstIndex(where: { $0.nom.caseInsensitiveCompare(trimmedName) == .orderedSame })
            else { break }
            if args.count >= 2, let stateValue = numericOSCValue(args[1]) {
                pistes[idx].isMuted = stateValue != 0
            } else {
                pistes[idx].isMuted.toggle()
            }
        default:
            break
        }
    }

    // Reads a numeric OSC argument regardless of whether the sender typed
    // it as a float or an int — most OSC clients aren't picky about which
    // one they emit for a plain number.
    private func numericOSCValue(_ value: OSCValue) -> Double? {
        switch value {
        case .float(let v): return Double(v)
        case .int(let v): return Double(v)
        case .string: return nil
        }
    }

    // Page-turn auto-scroll during playback: at higher zoom levels the
    // playhead used to just run off the right edge of the viewport with
    // nothing scrolling to keep up, making playback impossible to follow.
    // Rather than scrolling continuously to keep the playhead centered
    // (which makes the whole timeline swim under the eye while playing),
    // this only jumps once the playhead reaches the edge of what's
    // currently visible, landing it just past the track-label column —
    // the same "page flip" behavior as most DAWs' timeline views.
    func followPlayheadDuringPlayback() {
        let outerWidth = max(transport.timelineAreaWidth, 1)
        let largeurTimeline = outerWidth * CGFloat(transport.zoomX) - 140
        guard largeurTimeline > 0 else { return }
        let maxX = max(0, outerWidth * CGFloat(transport.zoomX) - outerWidth)
        // Nothing to scroll — the whole timeline already fits in the
        // viewport at this zoom level.
        guard maxX > 0 else { return }

        let playheadX = 140 + CGFloat(transport.position / transport.duree) * largeurTimeline
        let localX = playheadX - transport.scrollOffsetX

        // Off-screen to the right (normal forward playback outrunning the
        // current page) or to the left/behind the label column (e.g. right
        // after a loop-zone wrap or a seek to an earlier time) — either way,
        // jump so the playhead reappears just past the labels.
        if localX < 140 || localX > outerWidth {
            let margin: CGFloat = 20
            transport.scrollOffsetX = max(0, min(playheadX - 140 - margin, maxX))
        }
    }

    // Moved here from the old inline playhead triangle (now on the pinned
    // ruler strip — see RulerBar): dragging it snaps to the nearest
    // marker/grid line while ⌘ is held, same candidates and snap zone as
    // dragging a point.
    func handlePlayheadDragChanged(_ value: DragGesture.Value, largeurTimeline: CGFloat) {
        let xPos = Double(value.location.x - 140)
        var newPosition = (xPos / Double(largeurTimeline)) * transport.duree
        if NSEvent.modifierFlags.contains(.command),
           let snapped = nearestSnapTime(markersTrack: pistes[0], showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
            newPosition = snapped
        }
        transport.position = min(max(newPosition, 0), transport.duree)
        sendOSCMessagesForPosition(transport.position)
    }

    func handlePlayheadDoubleClick() {
        uiChrome.goToTimeString = formattedDuration(transport.position)
        uiChrome.goToMarkerNameString = ""
        pasteClipboard.showPlayheadPositionChoice = true
    }

    // The thin click-to-scrub strip just above the ruler's tick marks.
    func handleScrubTap(_ location: CGPoint, largeurTimeline: CGFloat) {
        guard location.x > 140 else { return }
        let clicked = (Double(location.x - 140) / Double(largeurTimeline)) * transport.duree
        transport.position = min(max(clicked, 0), transport.duree)
        sendOSCMessagesForPosition(transport.position)
    }

    func centerOnPlayhead() {
        let outerWidth = max(transport.timelineAreaWidth, 1)
        // transport.timelineAreaWidth already excludes the duration handle (the whole
        // timeline area is padded by its width), so no extra subtraction here
        // — this must mirror the largeurTimeline used for drawing exactly.
        let largeurTimeline = outerWidth * CGFloat(transport.zoomX) - 140
        guard largeurTimeline > 0 else { return }
        let playheadX = 140 + CGFloat(transport.position / transport.duree) * largeurTimeline
        transport.scrollOffsetX = max(0, playheadX - outerWidth / 2)
    }

    func goToNextMarker() {
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return }
        let target = sorted.first(where: { $0.time > transport.position + 0.001 })?.time ?? sorted[0].time
        transport.position = target
        sendOSCMessagesForPosition(transport.position)
        centerOnPlayhead()
    }

    func goToPreviousMarker() {
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return }
        let target = sorted.last(where: { $0.time < transport.position - 0.001 })?.time ?? sorted[sorted.count - 1].time
        transport.position = target
        sendOSCMessagesForPosition(transport.position)
        centerOnPlayhead()
    }

    @discardableResult
    func goToMarkerByName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            uiChrome.showGoToMarkerNoMatch = true
            return false
        }
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        let exactMatch = sorted.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })
        let partialMatch = sorted.first(where: { $0.label.range(of: trimmed, options: .caseInsensitive) != nil })
        guard let match = exactMatch ?? partialMatch else {
            uiChrome.showGoToMarkerNoMatch = true
            return false
        }
        transport.position = match.time
        sendOSCMessagesForPosition(transport.position)
        centerOnPlayhead()
        return true
    }

    func goToTime(_ text: String) {
        guard let parsed = parseDuration(text) else { return }
        transport.position = min(max(parsed, 0), transport.duree)
        sendOSCMessagesForPosition(transport.position)
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
        let trimmedMarker = uiChrome.goToMarkerNameString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMarker.isEmpty {
            // Presenting the "No match" alert while this sheet is
            // simultaneously dismissing doesn't reliably show in SwiftUI —
            // so on failure, keep the sheet open and surface it inline
            // instead of dismissing blindly.
            if goToMarkerByName(uiChrome.goToMarkerNameString) {
                uiChrome.playheadMarkerNotFound = false
                pasteClipboard.showPlayheadPositionChoice = false
            } else {
                uiChrome.playheadMarkerNotFound = true
            }
        } else {
            goToTime(uiChrome.goToTimeString)
            pasteClipboard.showPlayheadPositionChoice = false
        }
    }

    func recenterOnZoomChange(oldZoom: Double, newZoom: Double, outerWidth: CGFloat) {
        // Not just `guard !transport.isPinchZooming` (the flag TimelineScrollView's
        // Coordinator flips true/false around a pinch or Cmd+scroll gesture): on a
        // fast pinch, the gesture's last .changed and its .ended can land in the
        // same SwiftUI render, so by the time this onChange(of: zoomX) handler
        // fires, isPinchZooming can already be back to false even though newZoom
        // came from that gesture — which used to make this run anyway and
        // re-anchor on the playhead instead of the cursor, producing a visible
        // jump. lastCursorAnchoredZoom is stamped by the gesture handlers
        // themselves alongside their own cursor-anchored offsetX, so comparing
        // against it catches every zoom value the gesture already handled,
        // regardless of how the flag's timing lines up.
        guard newZoom != transport.lastCursorAnchoredZoom else { return }
        let largeurAvant = outerWidth * CGFloat(oldZoom) - 140
        guard largeurAvant > 0 else { return }

        let anchorTime = min(max(transport.position, 0), transport.duree)
        let absoluteContentXBefore = 140 + CGFloat(anchorTime / transport.duree) * largeurAvant
        let locationXInViewport = absoluteContentXBefore - transport.scrollOffsetX

        let largeurApres = outerWidth * CGFloat(newZoom) - 140
        guard largeurApres > 0 else { return }
        let absoluteContentXAfter = 140 + CGFloat(anchorTime / transport.duree) * largeurApres
        let maxX = max(0, outerWidth * CGFloat(newZoom) - outerWidth)
        let newOffsetX = max(0, min(absoluteContentXAfter - locationXInViewport, maxX))
        transport.scrollOffsetX = newOffsetX
    }

    func commitDureeEdit() {
        if let parsed = parseDuration(transport.dureeText) {
            transport.duree = max(parsed.rounded(), 1)
        }
        transport.dureeText = formattedDuration(transport.duree)
    }

    func startDurationDragTimer() {
        durationHandle.durationDragTimer?.invalidate()
        let tickInterval = 0.02
        let newTimer = Timer(timeInterval: tickInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                let dx = Double(durationHandle.durationDragCurrentDeltaX)
                let magnitude = pow(abs(dx), durationDragVelocityExponent) * durationDragVelocityScale
                let ratePerSecond = dx < 0 ? -magnitude : magnitude
                let rawDuree = transport.duree + ratePerSecond * tickInterval
                let quantized = (rawDuree * 100).rounded() / 100
                transport.duree = max(0.1, quantized)
                transport.dureeText = formattedDuration(transport.duree)
            }
        }
        // Timer.scheduledTimer only runs in the .default run loop mode,
        // which AppKit suspends while actively tracking a mouse drag (the
        // run loop switches to .eventTracking mode during that time) — so
        // the transport.timer would silently never fire while the drag is held.
        // Adding it in .common mode instead keeps it running throughout.
        RunLoop.main.add(newTimer, forMode: .common)
        durationHandle.durationDragTimer = newTimer
    }

    func stopDurationDragTimer() {
        durationHandle.durationDragTimer?.invalidate()
        durationHandle.durationDragTimer = nil
    }

}
