import SwiftUI

// Point marker glyph, extracted out of TrackContentColumn's per-event
// ForEach and made Equatable + wrapped in .equatable() at the call site —
// same pattern and rationale as CurveStepPathViews.swift.
//
// Why: TrackContentColumn observes `transport`, so its whole body re-runs
// on every playback tick (transport.position, ~20x/sec), even though a
// point marker's own visual output never depends on the playhead. This
// wrapper lets SwiftUI skip rebuilding each marker's glyph on ticks where
// none of its actual inputs (selection, coordinates, track color, etc.)
// changed.
//
// Gestures (.onHover/.gesture/.onTapGesture) stay attached at the ForEach
// call site, not here — they need live `pointDrag`/`selection` object
// references, not just values.
struct PointMarkerView: View, Equatable {
    let trackIndex: Int
    let type: TrackType
    let isGate: Bool
    let couleur: Color
    let eventLabel: String
    let eventTime: Double
    let eventY: Double
    let isSelected: Bool
    let showPointCoordinates: Bool
    let normalizedY: Double
    let coordinatesColorOnDarkMarker: Color
    let coordinatesColorOnLightMarker: Color

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.trackIndex == rhs.trackIndex &&
        lhs.type == rhs.type &&
        lhs.isGate == rhs.isGate &&
        lhs.couleur == rhs.couleur &&
        lhs.eventLabel == rhs.eventLabel &&
        lhs.eventTime == rhs.eventTime &&
        lhs.eventY == rhs.eventY &&
        lhs.isSelected == rhs.isSelected &&
        lhs.showPointCoordinates == rhs.showPointCoordinates &&
        lhs.normalizedY == rhs.normalizedY &&
        lhs.coordinatesColorOnDarkMarker == rhs.coordinatesColorOnDarkMarker &&
        lhs.coordinatesColorOnLightMarker == rhs.coordinatesColorOnLightMarker
    }

    var body: some View {
        VStack(spacing: 0) {
            if trackIndex == 0 {
                ZStack {
                    Rectangle()
                        .fill(isSelected ? Color.white : couleur)
                        .frame(width: 6, height: 6)

                    if showPointCoordinates {
                        Text(String(format: "%.2f", eventTime) + "s")
                            .font(.caption2)
                            .foregroundColor(coordinatesColorOnDarkMarker)
                            .offset(y: 12)
                    }
                }
                .overlay(alignment: .top) {
                    Text(eventLabel)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .fixedSize()
                        .offset(y: showPointCoordinates ? -12 : -16)
                }
                .offset(y: showPointCoordinates ? 0 : 6)
            } else {
                if type == .message {
                    Text(eventLabel)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                        .offset(y: 3)

                    ZStack {
                        Text("T")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isSelected ? Color.white : couleur)

                        if showPointCoordinates {
                            Text(String(format: "%.2f", eventTime) + "s")
                                .font(.caption2)
                                .foregroundColor(coordinatesColorOnLightMarker)
                                .offset(y: 12)
                        }
                    }
                } else if type == .bang {
                    Rectangle()
                        .fill(isSelected ? Color.white : couleur)
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(45))

                    if showPointCoordinates {
                        Text(String(format: "%.2f", eventTime) + ", " + String(format: "%.2f", eventY))
                            .font(.caption2)
                            .foregroundColor(coordinatesColorOnLightMarker)
                            .offset(y: 12)
                    }
                } else {
                    // Curve/step point: anchor the label to the marker itself
                    // via an overlay (rather than stacking it in the VStack),
                    // so flipping it above/below doesn't shift where the
                    // marker sits relative to the path.
                    let labelAbove = normalizedY < 0.5
                    Group {
                        if type == .step {
                            if isGate {
                                Rectangle()
                                    .stroke(isSelected ? Color.white : couleur, lineWidth: 2.5)
                                    .frame(width: 10, height: 10)
                                    .contentShape(Rectangle())
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(isSelected ? Color.white : couleur)
                                        .frame(width: 17, height: 3)
                                        .rotationEffect(.degrees(45))
                                    Rectangle()
                                        .fill(isSelected ? Color.white : couleur)
                                        .frame(width: 17, height: 3)
                                        .rotationEffect(.degrees(-45))
                                }
                                .frame(width: 17, height: 17)
                                .contentShape(Rectangle())
                            }
                        } else {
                            Circle()
                                .fill(isSelected ? Color.white : couleur)
                                .frame(width: 12, height: 12)
                        }
                    }
                    .overlay(alignment: labelAbove ? .top : .bottom) {
                        if showPointCoordinates {
                            Text(String(format: "%.2f", eventTime) + ", " + String(format: "%.2f", eventY))
                                .font(.caption2)
                                .foregroundColor(coordinatesColorOnLightMarker)
                                .fixedSize()
                                .offset(y: labelAbove ? -12 : 12)
                        }
                    }
                }
            }
        }
    }
}
