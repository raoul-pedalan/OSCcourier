import SwiftUI

// Curve/step line drawing, extracted out of TrackContentColumn's body and
// made Equatable + wrapped in .equatable() at the call site.
//
// Why: TrackContentColumn observes `transport` (for the playhead, snap
// zones, etc.), so its whole body re-runs on every playback tick —
// transport.position changes ~20x/sec. The curve/step Path was being
// rebuilt from scratch on every one of those re-runs even though nothing
// it actually draws from (the track's own points/amplitude range, and
// transport.duree/largeurTimeline, which only change on zoom/duration
// edits) had changed — re-sorting the points and, for curved segments,
// re-sampling 24 steps each, purely because it lived in the same view as
// something that does need position updates. Equatable comparison here
// lets SwiftUI skip that work on ticks where none of these inputs moved.

struct CurvePathView: View, Equatable {
    let events: [TimelineEvent]
    let minAmplitude: Double
    let maxAmplitude: Double
    let duree: Double
    let largeurTimeline: CGFloat
    let height: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.events == rhs.events &&
        lhs.minAmplitude == rhs.minAmplitude &&
        lhs.maxAmplitude == rhs.maxAmplitude &&
        lhs.duree == rhs.duree &&
        lhs.largeurTimeline == rhs.largeurTimeline &&
        lhs.height == rhs.height
    }

    var body: some View {
        Path { path in
            let sortedEvents = events.sorted { $0.time < $1.time }
            let amplitudeRange = maxAmplitude - minAmplitude
            func yPos(for value: Double) -> CGFloat {
                let normalizedY = amplitudeRange > 0 ? (value - minAmplitude) / amplitudeRange : 0.5
                // Vertical margin = circle radius, so points at the extreme
                // values (0 or 1) aren't cut off by the .clipped()
                return curveMargin + (height - 2 * curveMargin) * (1 - normalizedY)
            }

            for (i, event) in sortedEvents.enumerated() {
                let xPos = CGFloat(event.time / duree) * largeurTimeline
                let point = CGPoint(x: xPos, y: yPos(for: event.y))
                if i == 0 {
                    path.move(to: point)
                } else {
                    let previous = sortedEvents[i - 1]
                    if !previous.segmentEnabled {
                        // Disabled segment: break the path instead of
                        // drawing a line, leaving a visible gap.
                        path.move(to: point)
                    } else if previous.segmentCurve == 0 && previous.segmentBulge == 0 {
                        path.addLine(to: point)
                    } else {
                        // Sample the S-curve; x advances linearly with t (time
                        // isn't warped), only the value (y) follows the curve.
                        let steps = 24
                        let previousXPos = CGFloat(previous.time / duree) * largeurTimeline
                        for step in 1...steps {
                            let t = Double(step) / Double(steps)
                            let curvedT = combinedProgress(t, curvature: previous.segmentCurve, bulge: previous.segmentBulge)
                            let x = previousXPos + (xPos - previousXPos) * CGFloat(t)
                            let value = previous.y + (event.y - previous.y) * curvedT
                            path.addLine(to: CGPoint(x: x, y: yPos(for: value)))
                        }
                    }
                }
            }
        }
        .stroke(.yellow, lineWidth: 2)
        .allowsHitTesting(false)
    }
}

struct StepPathView: View, Equatable {
    let events: [TimelineEvent]
    let minAmplitude: Double
    let maxAmplitude: Double
    let duree: Double
    let largeurTimeline: CGFloat
    let height: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.events == rhs.events &&
        lhs.minAmplitude == rhs.minAmplitude &&
        lhs.maxAmplitude == rhs.maxAmplitude &&
        lhs.duree == rhs.duree &&
        lhs.largeurTimeline == rhs.largeurTimeline &&
        lhs.height == rhs.height
    }

    var body: some View {
        Path { path in
            // Staircase (zero-order hold): each value is held until the
            // next event, without interpolation — no diagonal line.
            let sortedEvents = events.sorted { $0.time < $1.time }
            let amplitudeRange = maxAmplitude - minAmplitude
            func yPos(for event: TimelineEvent) -> CGFloat {
                let normalizedY = amplitudeRange > 0 ? (event.y - minAmplitude) / amplitudeRange : 0.5
                return curveMargin + (height - 2 * curveMargin) * (1 - normalizedY)
            }
            for (i, event) in sortedEvents.enumerated() {
                let xPos = CGFloat(event.time / duree) * largeurTimeline
                let y = yPos(for: event)
                if i == 0 {
                    path.move(to: CGPoint(x: xPos, y: y))
                } else {
                    // Horizontal segment (held value) then vertical jump
                    path.addLine(to: CGPoint(x: xPos, y: path.currentPoint?.y ?? y))
                    path.addLine(to: CGPoint(x: xPos, y: y))
                }
            }
        }
        .stroke(Color(red: 0.608, green: 0.086, blue: 0.365), lineWidth: 3)
    }
}
