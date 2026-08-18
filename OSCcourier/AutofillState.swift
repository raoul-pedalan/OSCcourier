import Combine
import SwiftUI

/// Owns the state for the three autofill popups (Rectangle for step
/// tracks, Wave for curve tracks, Bang for bang/message tracks) plus
/// the shared "overwrite existing track?" confirmation and the
/// clear-all/delete-all-tracks confirmations.
final class AutofillState: ObservableObject {
    @Published var autofillTrackIndex: Int?
    @Published var autofillPeriodString: String = "1.0"
    @Published var autofillPhaseString: String = "0.0"
    @Published var autofillPulseWidthString: String = "0.5"
    @Published var autofillAmpMinString: String = "0.0"
    @Published var autofillAmpMaxString: String = "1.0"

    @Published var waveTrackIndex: Int?
    @Published var waveIsSine: Bool = true // true = Sin, false = Saw
    @Published var wavePeriodString: String = "1.0"
    @Published var wavePhaseString: String = "0.0"
    @Published var waveSkewString: String = "0.5"
    @Published var waveAmpMinString: String = "0.0"
    @Published var waveAmpMaxString: String = "1.0"

    @Published var bangTrackIndex: Int?
    @Published var bangPeriodString: String = "1.0"
    @Published var bangPhaseString: String = "0.0"
    @Published var bangLabelPrefixString: String = "key"

    @Published var pendingAutofillIndex: Int?
    @Published var showClearAllConfirmation = false
    @Published var showDeleteAllTracksConfirmation = false

    // Pressing the pencil button on a track that already has points asks
    // for confirmation first (pendingAutofillIndex) instead of overwriting
    // silently; an empty track skips straight to the popup.
    func openAutofillPopup(for index: Int, track piste: TimelineTrack) {
        if piste.evenements.isEmpty {
            proceedWithAutofill(for: index, track: piste)
        } else {
            pendingAutofillIndex = index
        }
    }

    func proceedWithAutofill(for index: Int, track piste: TimelineTrack) {
        switch piste.type {
        case .step:
            autofillTrackIndex = index
            autofillPeriodString = "1.0"
            autofillPhaseString = "0.0"
            autofillPulseWidthString = "0.5"
            autofillAmpMinString = String(format: "%.2f", piste.minAmplitude)
            autofillAmpMaxString = String(format: "%.2f", piste.maxAmplitude)
        case .curve:
            waveTrackIndex = index
            waveIsSine = true
            wavePeriodString = "1.0"
            wavePhaseString = "0.0"
            waveSkewString = "0.5"
            waveAmpMinString = String(format: "%.2f", piste.minAmplitude)
            waveAmpMaxString = String(format: "%.2f", piste.maxAmplitude)
        case .bang, .message:
            bangTrackIndex = index
            bangPeriodString = "1.0"
            bangPhaseString = "0.0"
            bangLabelPrefixString = piste.type == .message ? "key" : "M"
        case .normal:
            break
        }
    }
}
