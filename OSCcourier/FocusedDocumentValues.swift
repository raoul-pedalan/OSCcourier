import SwiftUI

// Points OSCcourierApp's menu Commands (Loop, Show Grid, Lock Tracks, etc.)
// at the frontmost ContentView's own per-window state objects, instead of
// a single UserDefaults-backed value shared by every open window. Each
// ContentView publishes this via .focusedSceneValue (see ContentView.swift)
// — scoped to the window/scene being key, not to which subview has
// keyboard focus, which is what "frontmost window" actually means here.
//
// Holds the two objects themselves (not per-field Bindings) specifically
// so this is Equatable by reference identity: ContentView's body runs on
// every playback tick (transport.position changes ~20x/sec), and without
// Equatable, SwiftUI has no way to tell that the "new" focused value on
// tick N+1 is the same as tick N — it reconstructs the app's menu bar
// commands on every single tick, which is what caused the choppy
// playback. With Equatable, ticks that don't touch these two objects
// produce an equal value, and SwiftUI skips republishing it.
struct OSCcourierFocusedDocument: Equatable {
    let transport: TransportState
    let uiChrome: UIChromeState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.transport === rhs.transport && lhs.uiChrome === rhs.uiChrome
    }
}

private struct OSCcourierFocusedDocumentKey: FocusedValueKey {
    typealias Value = OSCcourierFocusedDocument
}

extension FocusedValues {
    var oscCourierDocument: OSCcourierFocusedDocument? {
        get { self[OSCcourierFocusedDocumentKey.self] }
        set { self[OSCcourierFocusedDocumentKey.self] = newValue }
    }
}
