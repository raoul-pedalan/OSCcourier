// PointsListStore
import SwiftUI
import Combine

// One row of the points list. Flattened out of the tracks/events model so the
// table doesn't have to reach back into ContentView's state.
struct PointListRow: Identifiable {
    let id: UUID
    let trackName: String
    let trackColor: Color
    let time: Double
    let label: String
    let value: String
    let comment: String
}

// Shared between ContentView and the points list window. ContentView pushes a
// fresh snapshot into `rows` whenever the tracks change; because the window's
// view observes this object, it re-renders live instead of showing a stale
// snapshot from whenever it was opened.
class PointsListStore: ObservableObject {
    @Published var rows: [PointListRow] = []
    // Track names in timeline order, used to populate the filter menu. Kept
    // separate from `rows` so the menu still lists a track even when it has no
    // points yet (and so the menu's order follows the timeline, not the
    // time-sorted rows).
    @Published var trackNames: [String] = []

    // The list window never mutates the timeline itself — it asks ContentView
    // to open its existing point editor for the given event, and the edit is
    // applied there. Keeps a single source of truth (ContentView's `pistes`)
    // and reuses the same validation/snapping the timeline already does.
    var onRequestEdit: ((UUID) -> Void)?
}
