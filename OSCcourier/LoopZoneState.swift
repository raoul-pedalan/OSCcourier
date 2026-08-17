import Combine
import SwiftUI

/// Owns the state for the loop zone (yellow band drawn in the ruler):
/// its bounds, the in-progress ruler drag used to create/resize it,
/// edge-resize/body-drag tracking, and the precise start/end editor
/// sheet opened by double-clicking the ruler.
enum LoopZoneEdge { case start, end }

final class LoopZoneState: ObservableObject {
    @Published var loopZoneStart: Double?
    @Published var loopZoneEnd: Double?

    @Published var rulerDragStartTime: Double?
    @Published var rulerDragCurrentTime: Double?

    @Published var resizingLoopZoneEdge: LoopZoneEdge?
    @Published var isNearLoopZoneEdge: Bool = false

    @Published var isDraggingLoopZoneBody: Bool = false
    @Published var loopZoneDragOriginalStart: Double?
    @Published var loopZoneDragOriginalEnd: Double?
    @Published var loopZoneDragAnchorTime: Double?

    @Published var showLoopZoneEditor: Bool = false
    @Published var loopZoneEditStartString: String = ""
    @Published var loopZoneEditEndString: String = ""
}
