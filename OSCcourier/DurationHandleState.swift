import Combine
import SwiftUI

/// Owns the state for the draggable timeline-duration handle at the
/// trailing edge of the ruler (drag-in-progress flag, live delta, and
/// the repeat timer used while the handle is held past the edge).
final class DurationHandleState: ObservableObject {
    @Published var isDraggingDurationHandle: Bool = false
    @Published var durationDragCurrentDeltaX: CGFloat = 0
    @Published var durationDragTimer: Timer?
}
