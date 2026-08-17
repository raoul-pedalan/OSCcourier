import Combine
import SwiftUI

/// Owns the state for reordering tracks by dragging their header
/// (which row is being dragged, live vertical translation, the
/// baseline offset used to compute swaps) and for the duplicate-track
/// drag-and-drop hover indicator.
final class TrackDragReorderState: ObservableObject {
    @Published var draggedTrackIndex: Int?
    @Published var duplicateHoverTrackIndex: Int?
    @Published var dragStartHeight: CGFloat = 0

    @Published var reorderingIndex: Int?
    @Published var reorderDragTranslation: CGFloat = 0
    @Published var reorderBaselineOffset: CGFloat = 0
}
