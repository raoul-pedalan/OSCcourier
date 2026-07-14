// PointsListStore
import SwiftUI
import Combine

// One row of the points list. Flattened out of the tracks/events model so the
// table doesn't have to reach back into ContentView's state — including the
// metadata the editor popup needs, so the window never has to know anything
// about TrackType.
struct PointListRow: Identifiable {
    let id: UUID
    let trackName: String
    let trackColor: Color
    let time: Double
    let label: String
    let y: Double
    let comment: String

    let hasY: Bool          // curve/step tracks carry an editable value
    let hasLabel: Bool      // markers/message tracks carry an editable label
    let minAmplitude: Double
    let maxAmplitude: Double

    // What the Value column shows (empty for tracks with no y).
    var valueText: String {
        hasY ? String(format: "%.2f", y) : ""
    }
}

// Which single field a double-click opened for editing.
enum PointField: Hashable {
    case time, label, y, comment

    var title: String {
        switch self {
        case .time: return "Position (s)"
        case .label: return "Label"
        case .y: return "Value"
        case .comment: return "Comment"
        }
    }
}

// A single committed edit, described by the window and applied by ContentView.
// Only the field that was edited is set; the rest stay nil.
struct PointEdit {
    let id: UUID
    var time: Double? = nil
    var label: String? = nil
    var y: Double? = nil
    var comment: String? = nil
}

// Shared between ContentView and the points list window. ContentView pushes a
// fresh snapshot into `rows` whenever the tracks change; because the window's
// view observes this object, it re-renders live instead of showing a stale
// snapshot from whenever it was opened.
class PointsListStore: ObservableObject {
    @Published var rows: [PointListRow] = []
    // Track names in timeline order, used to populate the filter menu. Kept
    // separate from `rows` so the menu still lists a track even when it has no
    // points yet.
    @Published var trackNames: [String] = []

    // The window never mutates the timeline itself: it describes the edit and
    // ContentView applies it, with the same clamping/snapping/quantization the
    // timeline uses. Keeps a single source of truth.
    var onCommitEdit: ((PointEdit) -> Void)?
}
