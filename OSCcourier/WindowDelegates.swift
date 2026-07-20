import AppKit

// Tracks whether the outgoing-OSC-messages window is actually still open,
// independent of NSWindow.isVisible (which can lag/misreport around
// close()/showWindow() calls) — explicit state set via this delegate is
// more reliable for the Open/Close toggle behavior.
class OSCWindowCloseDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    // When set, this window's Undo/Redo (Cmd-Z / Cmd-Shift-Z) operate on this
    // shared manager instead of the empty, separate one AppKit would create
    // for the window by default — lets a secondary window (e.g. Points List)
    // share the main window's undo history rather than silently having its
    // own, unused one.
    var sharedUndoManager: UndoManager?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        sharedUndoManager
    }
}
