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

    // Prefix only now — the receive port is a permanently visible inline
    // field in the toolbar (see oscReceivePortString below), not part of
    // this popup anymore.
    @Published var showOSCPrefixPopup: Bool = false
    @Published var oscAddressPrefixString: String = ""
    @Published var oscReceivePortString: String = "7500"

    // These four used to be @AppStorage, independently read by several
    // views (ContentView, RulerBar, TrackContentColumn, TrackHeaderColumn,
    // TrackRow) straight from UserDefaults — which meant they were shared
    // by every open OSCcourier window instead of being per-window. Now
    // live here, on the one UIChromeState instance each ContentView
    // already owns and threads down to those views, so every reader sees
    // the same (per-window) value.
    @Published var showGrid: Bool = false
    @Published var showPointCoordinates: Bool = true
    @Published var showMarkersTrack: Bool = true
    @Published var tracksLocked: Bool = false
    // Also moved here (from a plain @State on ContentView) so
    // OSCcourierFocusedDocument can hold a stable object reference for
    // it too — see FocusedDocumentValues.swift.
    @Published var showCommandBar: Bool = true
}
