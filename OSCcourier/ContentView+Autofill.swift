import SwiftUI
import AppKit

extension ContentView {

    func rectangleEvents(period: Double, phase: Double, pulseWidth: Double, ampMin: Double, ampMax: Double, duree: Double) -> [TimelineEvent] {
        guard period > 0 else { return [] }
        let phaseOffset = phase * period
        let highDuration = min(max(pulseWidth, 0), 1) * period

        var events: [TimelineEvent] = []
        let firstN = Int((-phaseOffset / period).rounded(.down)) - 1
        var n = firstN
        while true {
            let cycleStart = Double(n) * period + phaseOffset
            if cycleStart > duree { break }
            let highEnd = cycleStart + highDuration
            if cycleStart >= 0 && cycleStart <= duree {
                events.append(TimelineEvent(time: cycleStart, label: "", y: ampMax))
            }
            if highEnd >= 0 && highEnd <= duree {
                events.append(TimelineEvent(time: highEnd, label: "", y: ampMin))
            }
            n += 1
        }

        // Make sure playback starting at t=0 reflects the correct held value,
        // even if the first generated edge falls after 0.
        if !events.contains(where: { $0.time == 0 }) {
            let containingN = Int(((0 - phaseOffset) / period).rounded(.down))
            let cycleStart0 = Double(containingN) * period + phaseOffset
            let highEnd0 = cycleStart0 + highDuration
            let valueAtZero = (0 >= cycleStart0 && 0 < highEnd0) ? ampMax : ampMin
            events.insert(TimelineEvent(time: 0, label: "", y: valueAtZero), at: 0)
        }

        return events.sorted { $0.time < $1.time }
    }

    func curvedProgress(_ t: Double, curvature: Double) -> Double {
        guard curvature != 0 else { return t }
        let k = pow(2, curvature)
        if t < 0.5 {
            return pow(t * 2, k) / 2
        } else {
            return 1 - pow((1 - t) * 2, k) / 2
        }
    }

    func bulgeProgress(_ t: Double, bulge: Double) -> Double {
        guard bulge != 0 else { return t }
        let k = pow(2, bulge)
        return pow(t, k)
    }

    func combinedProgress(_ t: Double, curvature: Double, bulge: Double) -> Double {
        curvedProgress(bulgeProgress(t, bulge: bulge), curvature: curvature)
    }

    func waveEvents(isSine: Bool, period: Double, phase: Double, skew: Double, ampMin: Double, ampMax: Double, duree: Double) -> [TimelineEvent] {
        guard period > 0 else { return [] }
        let phaseOffset = phase * period
        var events: [TimelineEvent] = []

        if isSine {
            // Only place control points at the peaks and troughs (where a sine's
            // tangent is naturally horizontal), and let the existing curve
            // interpolation (segmentCurve) compute the shape between them —
            // instead of approximating the wave with many sampled points.
            // curvature ≈ 1.0 was picked to closely match a real sine's shape
            // between a peak and a trough (a symmetric S-curve is a good fit,
            // since sine also has zero slope at the extremes and its steepest
            // slope exactly at the midpoint).
            let sineSegmentCurvature = 1.0
            let halfPeriod = period / 2
            let firstPeakTime = phaseOffset + period / 4
            let firstN = Int(((0 - firstPeakTime) / halfPeriod).rounded(.down)) - 1
            var n = firstN
            while true {
                let time = firstPeakTime + Double(n) * halfPeriod
                if time > duree { break }
                let parity = ((n % 2) + 2) % 2 // n=0 → first peak, alternating from there
                let value = parity == 0 ? ampMax : ampMin
                if time >= 0 && time <= duree {
                    events.append(TimelineEvent(time: time, label: "", y: value, segmentCurve: sineSegmentCurvature))
                }
                n += 1
            }
        } else {
            // Skew = fraction of the period spent rising (0...1). 0.5 = symmetric
            // triangle; near 1 = classic rising sawtooth; near 0 = reversed sawtooth.
            let riseDuration = min(max(skew, 0.01), 0.99) * period
            let firstN = Int(((0 - phaseOffset) / period).rounded(.down)) - 1
            var n = firstN
            while true {
                let cycleStart = Double(n) * period + phaseOffset
                if cycleStart > duree { break }
                let peakTime = cycleStart + riseDuration
                if cycleStart >= 0 && cycleStart <= duree {
                    events.append(TimelineEvent(time: cycleStart, label: "", y: ampMin))
                }
                if peakTime >= 0 && peakTime <= duree {
                    events.append(TimelineEvent(time: peakTime, label: "", y: ampMax))
                }
                n += 1
            }
        }

        return events.sorted { $0.time < $1.time }
    }

    func bangEvents(period: Double, phase: Double, duree: Double, defaultLabel: String = "", numberedLabelPrefix: String? = nil) -> [TimelineEvent] {
        guard period > 0 else { return [] }
        let phaseOffset = phase * period
        var events: [TimelineEvent] = []
        var n = 0
        var counter = 1
        while true {
            let time = Double(n) * period + phaseOffset
            if time > duree { break }
            if time >= 0 {
                let label: String
                if let prefix = numberedLabelPrefix {
                    label = "\(prefix)_\(counter)"
                    counter += 1
                } else {
                    label = defaultLabel
                }
                events.append(TimelineEvent(time: time, label: label, y: 0.5))
            }
            n += 1
        }
        return events
    }

    func openAutofillPopup(for index: Int) {
        guard !tracksLocked else { return }
        if pistes[index].evenements.isEmpty {
            proceedWithAutofill(for: index)
        } else {
            pendingAutofillIndex = index
        }
    }

    func proceedWithAutofill(for index: Int) {
        switch pistes[index].type {
        case .step:
            autofillTrackIndex = index
            autofillPeriodString = "1.0"
            autofillPhaseString = "0.0"
            autofillPulseWidthString = "0.5"
            autofillAmpMinString = String(format: "%.2f", pistes[index].minAmplitude)
            autofillAmpMaxString = String(format: "%.2f", pistes[index].maxAmplitude)
        case .curve:
            waveTrackIndex = index
            waveIsSine = true
            wavePeriodString = "1.0"
            wavePhaseString = "0.0"
            waveSkewString = "0.5"
            waveAmpMinString = String(format: "%.2f", pistes[index].minAmplitude)
            waveAmpMaxString = String(format: "%.2f", pistes[index].maxAmplitude)
        case .bang, .message:
            bangTrackIndex = index
            bangPeriodString = "1.0"
            bangPhaseString = "0.0"
            bangLabelPrefixString = pistes[index].type == .message ? "key" : "M"
        case .normal:
            break
        }
    }

    func commitAutofillRectangle() {
        if let index = autofillTrackIndex,
           let period = Double(autofillPeriodString),
           let phase = Double(autofillPhaseString),
           let pulseWidth = Double(autofillPulseWidthString),
           let ampMin = Double(autofillAmpMinString),
           let ampMax = Double(autofillAmpMaxString) {
            pistes[index].evenements = rectangleEvents(
                period: period,
                phase: phase,
                pulseWidth: pulseWidth,
                ampMin: ampMin,
                ampMax: ampMax,
                duree: duree
            )
            lastSentEvents.removeAll()
        }
        autofillTrackIndex = nil
    }

    func commitAutofillWave() {
        if let index = waveTrackIndex,
           let period = Double(wavePeriodString),
           let phase = Double(wavePhaseString),
           let skew = Double(waveSkewString),
           let ampMin = Double(waveAmpMinString),
           let ampMax = Double(waveAmpMaxString) {
            pistes[index].evenements = waveEvents(
                isSine: waveIsSine,
                period: period,
                phase: phase,
                skew: skew,
                ampMin: ampMin,
                ampMax: ampMax,
                duree: duree
            )
            lastSentEvents.removeAll()
        }
        waveTrackIndex = nil
    }

    func commitAutofillBang() {
        if let index = bangTrackIndex,
           let period = Double(bangPeriodString),
           let phase = Double(bangPhaseString) {
            let isMarkersTrack = index == 0
            let isMessageTrack = pistes[index].type == .message
            let trimmedPrefix = bangLabelPrefixString.trimmingCharacters(in: .whitespaces)
            let numberedLabelPrefix: String?
            if isMarkersTrack {
                numberedLabelPrefix = trimmedPrefix.isEmpty ? "M" : trimmedPrefix
            } else if isMessageTrack {
                numberedLabelPrefix = trimmedPrefix.isEmpty ? "key" : trimmedPrefix
            } else {
                numberedLabelPrefix = nil
            }
            pistes[index].evenements = bangEvents(
                period: period,
                phase: phase,
                duree: duree,
                numberedLabelPrefix: numberedLabelPrefix
            )
            lastSentEvents.removeAll()
        }
        bangTrackIndex = nil
    }

}
