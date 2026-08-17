import Combine
import SwiftUI

/// Owns the copy/paste-of-points state: the clipboard itself (with the
/// source track's type and amplitude range, so a same-type mismatch
/// can be detected and offered a rescale), paste-mode tracking, and
/// the bookkeeping ⌘D needs to repeat the last paste at a constant
/// offset.
final class PasteClipboardState: ObservableObject {
    @Published var pointClipboard: [PointClipboardEntry] = []
    @Published var pointClipboardTrackType: TrackType?
    @Published var isPasteModeActive: Bool = false
    @Published var showDifferentTypePasteAlert: Bool = false
    @Published var showPlayheadPositionChoice: Bool = false

    @Published var pointClipboardSourceMinAmplitude: Double?
    @Published var pointClipboardSourceMaxAmplitude: Double?
    @Published var pointClipboardOriginalEarliestTime: Double?

    @Published var lastPasteAnchorTime: Double?
    @Published var lastPasteTrackIndex: Int?
    @Published var lastPasteOffset: Double?

    @Published var pendingPasteAnchorTime: Double?
    @Published var pendingPasteTrackIndex: Int?
    @Published var showPasteScaleRangeAlert: Bool = false
}
