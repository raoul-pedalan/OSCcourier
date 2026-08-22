import Combine
import SwiftUI

/// Owns the state for playback transport and timeline zoom/scroll:
/// duration, current position, play/pause, the playback tick timer,
/// horizontal zoom and scroll, and the OSC-activity flash indicator.
final class TransportState: ObservableObject {
    @Published var duree: Double = 30.0
    @Published var dureeText: String = "00:30.00"
    @Published var position: Double = 0.0
    @Published var enLecture: Bool = false
    @Published var timer: Timer?
    @Published var lastTickTimestamp: Double?

    @Published var zoomX: Double = 1.0
    @Published var scrollOffsetX: CGFloat = 0
    // Published the same way as scrollOffsetX (from TimelineScrollView's
    // Coordinator via boundsChanged) but read-only from the outside — nothing
    // currently drives vertical scroll programmatically the way zoom/playhead
    // drive scrollOffsetX. Exists so the pinned track-header column (see
    // ContentView.swift) can mirror the tracks' vertical scroll position and
    // stay aligned with whichever rows are currently in view.
    @Published var scrollOffsetY: CGFloat = 0
    @Published var isPinchZooming: Bool = false
    // Stamped by TimelineScrollView's Coordinator every time a pinch or
    // Cmd+scroll gesture sets zoomX together with its own cursor-anchored
    // scrollOffsetX, so ContentView's onChange(of: zoomX)-driven
    // recenterOnZoomChange (which anchors on the playhead instead) can tell
    // "this exact zoom value was already anchored by the gesture, nothing to
    // redo" via a plain value comparison — instead of trusting isPinchZooming
    // alone, which can already be back to false by the time this fires: a fast
    // gesture's last .changed and its .ended can land in the same SwiftUI
    // render, so the live flag isn't a reliable signal for which zoomX values
    // came from the gesture. See recenterOnZoomChange and handleMagnification/
    // handleCommandScroll.
    @Published var lastCursorAnchoredZoom: Double = 0
    @Published var timelineAreaWidth: CGFloat = 1500

    @Published var isOSCFlashing: Bool = false
    @Published var oscFlashTimer: Timer?

    // Was @AppStorage, shared by every open OSCcourier window — moved
    // here (per-window, like everything else on this object) so looping
    // in one window's document doesn't loop every other open window too.
    @Published var enBoucle: Bool = false
}
