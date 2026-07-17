import SwiftUI
import AppKit

extension ContentView {

    func rowHeight(for piste: TimelineTrack) -> CGFloat {
        if piste.isFolded { return foldedTrackHeight }
        return (piste.type == .bang || piste.type == .message) ? 45 : piste.height
    }

    func gateSnappedY(_ y: Double, forTrackIndex index: Int) -> Double {
        let piste = pistes[index]

        if piste.type == .step && piste.isGate {
            let midpoint = (piste.minAmplitude + piste.maxAmplitude) / 2
            return y >= midpoint ? piste.maxAmplitude : piste.minAmplitude
        }

        guard piste.type == .curve || piste.type == .step else { return y }
        return quantizedY(y, forTrackIndex: index)
    }

    func quantizedY(_ y: Double, forTrackIndex index: Int) -> Double {
        let piste = pistes[index]
        let step = piste.quantizeStep
        guard piste.quantizeActive else { return y }
        let offset = y - piste.minAmplitude
        let snapped = piste.minAmplitude + (offset / step).rounded() * step
        return min(max(snapped, piste.minAmplitude), piste.maxAmplitude)
    }

    func quantizeTickValues(forTrackIndex index: Int) -> [Double] {
        let piste = pistes[index]
        let step = piste.quantizeStep
        let range = piste.maxAmplitude - piste.minAmplitude
        guard piste.quantizeActive, range > 0 else { return [] }
        let count = Int((range / step).rounded(.down))
        guard count >= 1, count <= 500 else { return [] }
        return (0...count).map { piste.minAmplitude + Double($0) * step }
    }

    func visibleQuantizeTicks(forTrackIndex index: Int) -> [Double] {
        let all = quantizeTickValues(forTrackIndex: index)
        guard all.count > 1 else { return all }
        let usableHeight = pistes[index].height - 2 * curveMargin
        guard usableHeight > 0 else { return [] }
        let spacing = usableHeight / CGFloat(all.count - 1)
        let minSpacing: CGFloat = 7
        guard spacing < minSpacing else { return all }
        let rawSkip = Double(minSpacing / spacing)
        let niceSteps: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500]
        let skip = Int(niceSteps.first(where: { $0 >= rawSkip }) ?? 500)
        return all.enumerated().compactMap { i, v in i % skip == 0 ? v : nil }
    }

    @ViewBuilder
    func foldedGhostTrace(for piste: TimelineTrack, largeurTimeline: CGFloat) -> some View {
        let h = foldedTrackHeight
        let margin: CGFloat = 3
        switch piste.type {
        case .bang, .message:
            ForEach(piste.evenements) { event in
                let xPos = CGFloat(event.time / duree) * largeurTimeline
                Rectangle()
                    .fill(piste.couleur.opacity(0.7))
                    .frame(width: 1, height: h * 0.6)
                    .position(x: xPos, y: h / 2)
            }
            .allowsHitTesting(false)
        case .curve:
            if piste.evenements.count > 1 {
                Path { path in
                    let sorted = piste.evenements.sorted { $0.time < $1.time }
                    let amplitudeRange = piste.maxAmplitude - piste.minAmplitude
                    func yPos(for value: Double) -> CGFloat {
                        let normalizedY = amplitudeRange > 0 ? (value - piste.minAmplitude) / amplitudeRange : 0.5
                        return margin + (h - 2 * margin) * (1 - normalizedY)
                    }
                    for (i, event) in sorted.enumerated() {
                        let xPos = CGFloat(event.time / duree) * largeurTimeline
                        let point = CGPoint(x: xPos, y: yPos(for: event.y))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(piste.couleur.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)
            }
        case .step:
            if piste.evenements.count > 1 {
                Path { path in
                    let sorted = piste.evenements.sorted { $0.time < $1.time }
                    let amplitudeRange = piste.maxAmplitude - piste.minAmplitude
                    func yPos(for event: TimelineEvent) -> CGFloat {
                        let normalizedY = amplitudeRange > 0 ? (event.y - piste.minAmplitude) / amplitudeRange : 0.5
                        return margin + (h - 2 * margin) * (1 - normalizedY)
                    }
                    for (i, event) in sorted.enumerated() {
                        let xPos = CGFloat(event.time / duree) * largeurTimeline
                        let y = yPos(for: event)
                        if i == 0 {
                            path.move(to: CGPoint(x: xPos, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: xPos, y: path.currentPoint?.y ?? y))
                            path.addLine(to: CGPoint(x: xPos, y: y))
                        }
                    }
                }
                .stroke(piste.couleur.opacity(0.7), lineWidth: 1.5)
                .allowsHitTesting(false)
            }
        case .normal:
            EmptyView()
        }
    }

    func curveYPosition(forTime time: Double, trackIndex: Int) -> CGFloat? {
        let sorted = pistes[trackIndex].evenements.sorted { $0.time < $1.time }
        guard sorted.count > 1, let first = sorted.first, let last = sorted.last,
              time >= first.time, time <= last.time else { return nil }

        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            guard time >= a.time && time <= b.time else { continue }
            let t = (b.time - a.time) > 0 ? (time - a.time) / (b.time - a.time) : 0
            let curvedT = combinedProgress(t, curvature: a.segmentCurve, bulge: a.segmentBulge)
            let value = a.y + (b.y - a.y) * curvedT
            let amplitudeRange = pistes[trackIndex].maxAmplitude - pistes[trackIndex].minAmplitude
            let normalizedY = amplitudeRange > 0 ? (value - pistes[trackIndex].minAmplitude) / amplitudeRange : 0.5
            return curveMargin + (pistes[trackIndex].height - 2 * curveMargin) * (1 - normalizedY)
        }
        return nil
    }

    func isSegmentEnabled(forTime time: Double, trackIndex: Int) -> Bool {
        let sorted = pistes[trackIndex].evenements.sorted { $0.time < $1.time }
        guard sorted.count > 1 else { return true }
        for i in 0..<(sorted.count - 1) {
            guard time >= sorted[i].time && time <= sorted[i + 1].time else { continue }
            return sorted[i].segmentEnabled
        }
        return true
    }

    func applyShiftSegmentCursor(at location: CGPoint, trackIndex: Int, largeurTimeline: CGFloat) {
        let time = (Double(location.x) / Double(largeurTimeline)) * duree
        if let curveY = curveYPosition(forTime: time, trackIndex: trackIndex),
           abs(Double(location.y) - Double(curveY)) < 12 {
            if isSegmentEnabled(forTime: time, trackIndex: trackIndex) {
                cursor(fromSymbol: "eraser.fill").set()
            } else {
                cursor(fromSymbol: "point.topleft.down.to.point.bottomright.curvepath.fill").set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    func toggleSegmentEnabled(forTime time: Double, trackIndex: Int) {
        let sorted = pistes[trackIndex].evenements.sorted { $0.time < $1.time }
        guard sorted.count > 1 else { return }
        for i in 0..<(sorted.count - 1) {
            guard time >= sorted[i].time && time <= sorted[i + 1].time else { continue }
            if let eventIndex = pistes[trackIndex].evenements.firstIndex(where: { $0.id == sorted[i].id }) {
                pistes[trackIndex].evenements[eventIndex].segmentEnabled.toggle()
                lastSentEvents.removeAll()
            }
            return
        }
    }

    func cursor(fromSymbol name: String, color: NSColor = .black) -> NSCursor {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(.init(paletteColors: [color]))
        // Falls back to a known-valid symbol (rather than an empty NSImage)
        // if `name` doesn't resolve — an invalid SF Symbol name would
        // otherwise silently produce an invisible cursor, which is exactly
        // the kind of bug that's very hard to notice/debug from testing
        // alone.
        let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: nil)
            ?? NSImage()
        let image = baseImage.withSymbolConfiguration(config) ?? baseImage
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }

    func snapCandidateTimes(largeurTimeline: Double) -> [Double] {
        var times = pistes[0].evenements.map { $0.time }
        if showGrid {
            times.append(contentsOf: visibleGridLineTimes(largeurTimeline: CGFloat(largeurTimeline)))
        }
        return times
    }

    func nearestTime(among candidates: [Double], xPos: Double, largeurTimeline: Double) -> Double? {
        guard !candidates.isEmpty, duree > 0 else { return nil }
        let closest = candidates.min(by: { a, b in
            let xA = (a / duree) * largeurTimeline
            let xB = (b / duree) * largeurTimeline
            return abs(xA - xPos) < abs(xB - xPos)
        })
        guard let closest = closest else { return nil }
        let closestXPos = (closest / duree) * largeurTimeline
        return abs(closestXPos - xPos) < 7 ? closest : nil
    }

    func nearestSnapTime(xPos: Double, largeurTimeline: Double) -> Double? {
        nearestTime(among: snapCandidateTimes(largeurTimeline: largeurTimeline), xPos: xPos, largeurTimeline: largeurTimeline)
    }

    func nearestMarkerTime(xPos: Double, largeurTimeline: Double) -> Double? {
        nearestTime(among: pistes[0].evenements.map { $0.time }, xPos: xPos, largeurTimeline: largeurTimeline)
    }

    func nearestGridTime(xPos: Double, largeurTimeline: Double) -> Double? {
        guard showGrid else { return nil }
        return nearestTime(among: visibleGridLineTimes(largeurTimeline: CGFloat(largeurTimeline)), xPos: xPos, largeurTimeline: largeurTimeline)
    }

    func isNearestSnapAGridLine(xPos: Double, largeurTimeline: Double) -> Bool {
        let markerTime = nearestMarkerTime(xPos: xPos, largeurTimeline: largeurTimeline)
        let gridTime = nearestGridTime(xPos: xPos, largeurTimeline: largeurTimeline)
        guard let gridTime else { return false }
        guard let markerTime else { return true }
        let markerX = (markerTime / duree) * largeurTimeline
        let gridX = (gridTime / duree) * largeurTimeline
        return abs(gridX - xPos) < abs(markerX - xPos)
    }

    func isNearMarker(xPos: Double, largeurTimeline: Double) -> Bool {
        nearestSnapTime(xPos: xPos, largeurTimeline: largeurTimeline) != nil
    }

    func updatePointCursor() {
        // Paste mode owns the cursor entirely while active — don't let a
        // stray modifier-key change (e.g. releasing ⌘ right after ⌘V)
        // clobber the red crosshair with the arrow just because the mouse
        // isn't currently over a point.
        guard !isPasteModeActive else { return }
        guard isHoveringPoint else {
            NSCursor.arrow.set()
            return
        }
        if NSEvent.modifierFlags.contains(.shift) {
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

    func gridLineTimes(period: Double, phase: Double, duree: Double) -> [Double] {
        guard period > 0 else { return [] }
        let phaseOffset = phase * period
        var times: [Double] = []
        var n = 0
        while true {
            let time = Double(n) * period + phaseOffset
            if time > duree { break }
            if time >= 0 { times.append(time) }
            n += 1
        }
        return times
    }

    func visibleGridLineTimes(largeurTimeline: CGFloat) -> [Double] {
        let allTimes = gridLineTimes(period: gridPeriod, phase: gridPhase, duree: duree)
        guard duree > 0, gridPeriod > 0, largeurTimeline > 0 else { return allTimes }
        let pixelsPerLine = largeurTimeline * CGFloat(gridPeriod / duree)
        let minSpacing: CGFloat = 16
        guard pixelsPerLine < minSpacing else { return allTimes }
        // How many consecutive lines to fold into one to reach minSpacing —
        // rounded up to a "nice" step (1, 2, 5, 10, 20, 50...) so the
        // remaining visible lines still land on clean multiples of the
        // original period rather than an arbitrary skip count.
        let rawSkip = Double(minSpacing / pixelsPerLine)
        let niceSteps: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000]
        let skip = niceSteps.first(where: { $0 >= rawSkip }) ?? (niceSteps.last ?? 1000)
        return allTimes.enumerated().compactMap { index, time in
            index % Int(skip) == 0 ? time : nil
        }
    }

    func commitGridSettings() {
        if let period = Double(gridPeriodString), let phase = Double(gridPhaseString) {
            gridPeriod = period
            gridPhase = phase
        }
        showGridSettingsPopup = false
    }

    func openGridSettingsPopup() {
        gridPeriodString = String(format: "%.2f", gridPeriod)
        gridPhaseString = String(format: "%.2f", gridPhase)
        showGridSettingsPopup = true
    }

    func applyGateModeSwitch(forTrackIndex index: Int) {
        pistes[index].isGate = true
        pistes[index].minAmplitude = 0
        pistes[index].maxAmplitude = 1
        // Gate is itself a 0/1 quantization, so quantization is switched off —
        // but its step value is kept, so returning to Float restores it.
        pistes[index].quantizeEnabled = false
        for i in pistes[index].evenements.indices {
            pistes[index].evenements[i].y = gateSnappedY(pistes[index].evenements[i].y, forTrackIndex: index)
        }
        lastSentEvents.removeAll()
    }

    func commitAmplitudeEdit() {
        guard let index = amplitudeEditorTrackIndex else {
            amplitudeEditorTrackIndex = nil
            return
        }
        if pistes[index].type == .step && tempIsGate {
            // Switching FROM Float TO Gate with existing points would
            // silently redistribute all their values to 0/1 — warn first
            // instead, and only apply once the user confirms.
            if !pistes[index].isGate && !pistes[index].evenements.isEmpty {
                pendingGateSwitchIndex = index
                amplitudeEditorTrackIndex = nil
                return
            }
            applyGateModeSwitch(forTrackIndex: index)
        } else {
            if pistes[index].type == .step {
                pistes[index].isGate = false
            }
            if let minVal = Double(tempMinAmplitude), let maxVal = Double(tempMaxAmplitude) {
                pistes[index].minAmplitude = minVal
                pistes[index].maxAmplitude = maxVal
            }
            // The step value is stored regardless of the on/off flag, so
            // switching quantization off and back on restores what was dialled
            // in rather than resetting to zero.
            pistes[index].quantizeEnabled = tempQuantizeEnabled
            if let stepVal = Double(tempQuantizeStep), stepVal > 0 {
                let range = pistes[index].maxAmplitude - pistes[index].minAmplitude
                let maxStep = range / 2
                // A step bigger than half the range would leave fewer than three
                // usable values (the track would collapse onto its endpoints), so
                // it's clamped — and the user is told, rather than silently getting
                // something other than what they typed. Only warn when it's
                // actually in effect.
                if range > 0 && stepVal > maxStep {
                    pistes[index].quantizeStep = maxStep
                    if tempQuantizeEnabled {
                        invalidQuantizeStepMessage = String(
                            format: "A step of %g is too large for the range [%g, %g]. It must not exceed half the range, so it has been set to %g.",
                            stepVal, pistes[index].minAmplitude, pistes[index].maxAmplitude, maxStep
                        )
                    }
                } else {
                    pistes[index].quantizeStep = range > 0 ? stepVal : 0
                }
            }
            // NOTE: existing points are deliberately NOT re-snapped onto the
            // new grid. Unlike Gate — which is a mode change that forces every
            // value to 0/1 — quantization is an input aid: it constrains points
            // as they're created or dragged, but never silently rewrites work
            // that's already been placed.
        }
        amplitudeEditorTrackIndex = nil
    }

}
