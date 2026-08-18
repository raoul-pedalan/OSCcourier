import Combine
import SwiftUI
import AppKit

/// Owns the state for point selection: the set of currently-selected
/// point IDs (white-rendered, cleared by any ordinary click/drag
/// elsewhere), and an in-progress ⌥⇧ lasso drag (which track it
/// started on, and its start/current location in that track's local
/// coordinate space).
final class SelectionState: ObservableObject {
    @Published var selectedPointIDs: Set<UUID> = []

    @Published var lassoTrackIndex: Int?
    @Published var lassoStartLocation: CGPoint?
    @Published var lassoCurrentLocation: CGPoint?

    // ⌥⇧-drag lassos points on THIS track only — attached as
    // .simultaneousGesture (not .gesture) so it never blocks the
    // ordinary click-to-create-point / drag-to-move-point gestures
    // underneath; it only actually does anything once both modifiers
    // are held.
    func handleLassoDragChanged(_ value: DragGesture.Value, trackIndex index: Int, largeurTimeline: CGFloat, tracksLocked: Bool, isPasteModeActive: Bool) {
        guard !tracksLocked, !isPasteModeActive,
              NSEvent.modifierFlags.contains(.shift),
              NSEvent.modifierFlags.contains(.option) else { return }
        // onContinuousHover (used for the idle-hover cursor) stops firing
        // once a real drag begins, so reassert the cursor manually for the
        // duration of the lasso drag itself — same pattern as the
        // curve-bend cursor.
        cursor(fromSymbol: "dot.crosshair").set()
        if lassoTrackIndex == nil {
            lassoTrackIndex = index
            lassoStartLocation = value.startLocation
        }
        guard lassoTrackIndex == index else { return }
        lassoCurrentLocation = value.location
    }

    func handleLassoDragEnded(_ value: DragGesture.Value, trackIndex index: Int, largeurTimeline: CGFloat, piste: TimelineTrack, duree: Double) {
        guard lassoTrackIndex == index, let start = lassoStartLocation else {
            lassoTrackIndex = nil
            lassoStartLocation = nil
            lassoCurrentLocation = nil
            return
        }
        let rect = CGRect(
            x: min(start.x, value.location.x),
            y: min(start.y, value.location.y),
            width: abs(value.location.x - start.x),
            height: abs(value.location.y - start.y)
        )
        let trackHeight = rowHeight(for: piste)
        var newSelection: Set<UUID> = []
        for event in piste.evenements {
            let xPos = CGFloat(event.time / duree) * largeurTimeline
            let pointY: CGFloat
            if piste.type == .curve || piste.type == .step {
                let amplitudeRange = piste.maxAmplitude - piste.minAmplitude
                let normalizedY = amplitudeRange > 0 ? (event.y - piste.minAmplitude) / amplitudeRange : 0.5
                pointY = curveMargin + (trackHeight - 2 * curveMargin) * (1 - normalizedY)
            } else {
                pointY = index == 0 ? 22 : 15
            }
            if rect.contains(CGPoint(x: xPos, y: pointY)) {
                newSelection.insert(event.id)
            }
        }
        selectedPointIDs = newSelection
        lassoTrackIndex = nil
        lassoStartLocation = nil
        lassoCurrentLocation = nil
    }
}
