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
    @Published var isPinchZooming: Bool = false
    @Published var timelineAreaWidth: CGFloat = 1500

    @Published var isOSCFlashing: Bool = false
    @Published var oscFlashTimer: Timer?
}
