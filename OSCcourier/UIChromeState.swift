import Combine
import SwiftUI

/// Owns miscellaneous UI-chrome state that isn't tied to a specific
/// editing domain: full-screen tracking/observers, the modifier-key
/// flags-changed monitor, the Go To Time / Go To Marker dialogs, and
/// the grid-settings popup.
final class UIChromeState: ObservableObject {
    @Published var isFullScreen: Bool = false
    @Published var fullScreenEnterObserver: Any?
    @Published var fullScreenExitObserver: Any?
    @Published var flagsChangedMonitor: Any?

    @Published var showGoToTimeDialog: Bool = false
    @Published var goToTimeString: String = "00:00"
    @Published var goToTimeInitialValue: String = ""
    @Published var showGoToMarkerNameDialog: Bool = false
    @Published var goToMarkerNameString: String = ""
    @Published var showGoToMarkerNoMatch: Bool = false
    @Published var playheadMarkerNotFound: Bool = false

    @Published var showGridSettingsPopup: Bool = false
    @Published var gridPeriodString: String = "1.0"
    @Published var gridPhaseString: String = "0.0"
    @Published var gridPeriod: Double = 1.0
    @Published var gridPhase: Double = 0.0

    @Published var showTimeOffsetPopup: Bool = false
    @Published var timeOffsetString: String = "0.0"
}
