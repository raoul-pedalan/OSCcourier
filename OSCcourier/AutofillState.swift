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
}
