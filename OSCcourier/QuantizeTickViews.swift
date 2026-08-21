import SwiftUI

// Quantization tick marks (the short blue ticks in the track header, and
// the fainter full-width guide lines across the curve/step content area),
// extracted out of TrackHeaderColumn/TrackContentColumn's bodies for the
// same reason as CurveStepPathViews: those bodies re-run on every
// playback tick (their parent, TrackRow, observes `transport`), which
// recomputed visibleQuantizeTicks and rebuilt every tick mark even though
// none of that depends on transport.position at all — only on the
// track's own amplitude range/quantize settings and its height.
// `piste: TimelineTrack` is already Equatable, so comparing the whole
// struct is enough to detect "nothing relevant changed" without having
// to enumerate its fields by hand.

struct HeaderQuantizeTicksView: View, Equatable {
    let piste: TimelineTrack
    let trackHeight: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.piste == rhs.piste && lhs.trackHeight == rhs.trackHeight
    }

    var body: some View {
        let range = piste.maxAmplitude - piste.minAmplitude
        ZStack(alignment: .topLeading) {
            ForEach(visibleQuantizeTicks(forTrack: piste), id: \.self) { value in
                let normalized = range > 0 ? (value - piste.minAmplitude) / range : 0
                let y = curveMargin + (trackHeight - 2 * curveMargin) * (1 - normalized)
                Rectangle()
                    .fill(Color.blue.opacity(0.55))
                    .frame(width: 15, height: 1)
                    .offset(y: y)
            }
        }
    }
}

struct ContentQuantizeGridLinesView: View, Equatable {
    let piste: TimelineTrack
    let trackHeight: CGFloat
    let largeurTimeline: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.piste == rhs.piste && lhs.trackHeight == rhs.trackHeight && lhs.largeurTimeline == rhs.largeurTimeline
    }

    var body: some View {
        let range = piste.maxAmplitude - piste.minAmplitude
        // topLeading + a plain offset(y: y), same as HeaderQuantizeTicksView
        // above — NOT the "offset(y: y - trackHeight/2)" this used to rely
        // on, which only worked by accident because the raw ForEach used
        // to be spliced directly into TrackContentColumn's own top-level
        // ZStack and centered against ITS height. Once extracted into its
        // own View, that implicit shared coordinate space was gone, and
        // every line collapsed toward this view's own (much smaller,
        // content-sized) center instead of the track's real center — this
        // explicit frame is what the calculation actually needs.
        ZStack(alignment: .topLeading) {
            ForEach(visibleQuantizeTicks(forTrack: piste), id: \.self) { value in
                let normalized = range > 0 ? (value - piste.minAmplitude) / range : 0
                let y = curveMargin + (trackHeight - 2 * curveMargin) * (1 - normalized)
                Rectangle()
                    .fill(Color.blue.opacity(0.22))
                    .frame(width: largeurTimeline, height: 1)
                    .offset(y: y)
            }
        }
        .frame(width: largeurTimeline, height: trackHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
