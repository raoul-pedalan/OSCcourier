import Combine
import SwiftUI

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
}
