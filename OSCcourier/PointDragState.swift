import Combine
import SwiftUI

/// Owns the state for the most gesture-heavy interactions on a track:
/// dragging a point or a whole selection (with the per-point baselines
/// captured on the first tick of a drag), ⌥-dragging a curve segment
/// to bend it, modifier-aware hover/cursor tracking, and Cmd/grid
/// snap-zone proximity used both for the live cursor and for the snap
/// decision itself. Also owns the last-sent-events de-dup set (OSC
/// output) and the global key-down monitor, since both are driven by
/// the same point-editing gestures.
final class PointDragState: ObservableObject {
    @Published var lastSentEvents: Set<String> = []
    @Published var keyDownMonitor: Any?

    @Published var isHoveringPoint: Bool = false
    @Published var isNearCurveControlZone: Bool = false
    @Published var isOptionHeldForCursor: Bool = false
    @Published var isShiftHeldForCursor: Bool = false

    @Published var groupDragBaseline: [UUID: Double] = [:]
    @Published var groupDragAnchorOriginalTime: Double?
    @Published var groupDragYBaseline: [UUID: Double] = [:]
    @Published var groupDragAnchorOriginalY: Double?

    @Published var curveDragSegmentID: UUID?
    @Published var curveDragBaseline: Double?
    @Published var curveDragBulgeBaseline: Double?

    @Published var isNearSnapZone: Bool = false
    @Published var isNearGridSnapZone: Bool = false
    @Published var isNearestSnapGrid: Bool = false
}
