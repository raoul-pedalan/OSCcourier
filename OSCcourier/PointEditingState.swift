import Combine
import SwiftUI

/// Owns the state for the track-rename field, the single-point edit
/// sheet, the amplitude-range editor entry point, point creation
/// tracking, and the quantize/gate popup's validation/pending-switch
/// state.
final class PointEditingState: ObservableObject {
    @Published var indexPisteARenommer: Int?
    @Published var nouveauNomPiste = ""

    @Published var pointAEditer: (trackIndex: Int, eventId: UUID)?
    @Published var nouvellePositionString = ""
    @Published var nouveauLabel = "M"
    @Published var nouveauComment = ""
    @Published var nouvelleYString = "0.5"
    @Published var amplitudeEditorTrackIndex: Int?

    @Published var creatingPointId: UUID?
    @Published var creatingPointTrackIndex: Int?

    @Published var invalidQuantizeStepMessage: String? = nil
    @Published var pendingGateSwitchIndex: Int? = nil
}
