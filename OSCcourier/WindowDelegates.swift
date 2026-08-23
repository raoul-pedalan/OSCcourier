import AppKit
import SwiftUI

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

// Confirms before closing the main document window if it has unsaved
// changes — WindowGroup gives no built-in "Save changes?" prompt the way
// DocumentGroup/NSDocument does, so this fills that gap directly at the
// NSWindowDelegate level. Installed on each ContentView's own NSWindow via
// WindowAccessor.
//
// Also reused for Cmd+Q: AppDelegate.applicationShouldTerminate loops over
// every open window and calls this same windowShouldClose, so quitting
// with unsaved changes anywhere prompts exactly like closing that window
// individually would, one window at a time, stopping at the first Cancel.
class MainWindowCloseDelegate: NSObject, NSWindowDelegate {
    var hasUnsavedChanges: (() -> Bool)?
    // Runs Save for this window; returns whether it actually completed —
    // false if the user cancels the save panel, or the write fails, in
    // which case the window must NOT close (that would discard the very
    // changes "Save" was supposed to keep).
    var save: (() -> Bool)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedChanges?() == true else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to this document?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: // Save
            return save?() ?? false
        case .alertSecondButtonReturn: // Don't Save
            return true
        default: // Cancel
            return false
        }
    }
}

// MARK: - Auxiliary panel construction

/// Where a newly created auxiliary panel should land — applied last, once
/// the window has settled at its final size, so it isn't computed against
/// a stale frame.
enum AuxiliaryPanelPosition {
    case center
    case topRightCorner(margin: CGFloat)
}

/// Builds one of OSCcourier's auxiliary SwiftUI-backed panels (OSC
/// messages log, point list, modifier-keys help): a manually-created
/// NSWindow hosting a SwiftUI view, wired up the same way every time —
/// non-released-on-close, a close delegate reporting back through
/// `onClose`, and a chosen initial position.
///
/// Factored out after three near-identical ~25-line copies of this block
/// had accumulated across the panels (openOSCMessagesWindow,
/// openModifierKeysHelpWindow, openPointListWindow) — one of those copies
/// is what caused the "Update Constraints in Window" crash on the
/// Modifier Keys window (see its `sizeToFitContent` handling below), so
/// the fix now lives in one place instead of three.
///
/// Returns both the controller and the delegate: the delegate must be
/// retained separately by the caller (NSWindow.delegate is unowned), same
/// as before this was factored out.
func makeAuxiliaryPanel<Content: View>(
    content: Content,
    title: String,
    autosaveName: String,
    initialSize: NSSize,
    minSize: NSSize,
    position: AuxiliaryPanelPosition,
    sizeToFitContent: Bool = false,
    sharedUndoManager: UndoManager? = nil,
    onClose: @escaping () -> Void
) -> (NSWindowController, OSCWindowCloseDelegate) {
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = NSRect(origin: .zero, size: initialSize)

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: initialSize),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = title
    window.setFrameAutosaveName(autosaveName)
    window.contentView = hostingView
    window.minSize = minSize
    // Without this, closing a manually-created NSWindow (not from a nib)
    // can release it out from under us, leaving our controller holding a
    // stale reference on the next toggle.
    window.isReleasedWhenClosed = false

    if sizeToFitContent {
        // Measured only now that the hosting view is actually attached to
        // a live window: measuring it while still detached can return a
        // size that doesn't match what SwiftUI settles on once it has a
        // real window/screen context to lay out in. That mismatch is what
        // drove AppKit into a runaway "needs another Update Constraints
        // in Window pass" loop on the Modifier Keys window — crashing
        // once the pass count exceeded the window's view count.
        let fittingSize = hostingView.fittingSize
        let contentWidth = max(fittingSize.width, minSize.width)
        let contentHeight = max(fittingSize.height, minSize.height)
        window.setContentSize(NSSize(width: contentWidth, height: contentHeight))
    }

    let delegate = OSCWindowCloseDelegate()
    delegate.onClose = onClose
    delegate.sharedUndoManager = sharedUndoManager
    window.delegate = delegate

    switch position {
    case .center:
        window.center()
    case .topRightCorner(let margin):
        // Applied after setFrameAutosaveName so it always ends up there,
        // rather than wherever a previously saved frame happened to be.
        if let screenFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(
                x: screenFrame.maxX - window.frame.width - margin,
                y: screenFrame.maxY - window.frame.height - margin
            )
            window.setFrameOrigin(origin)
        }
    }

    return (NSWindowController(window: window), delegate)
}

/// Shared open/close toggle for an auxiliary panel that may already exist:
/// if `controller` is non-nil, this closes, re-shows, or brings forward
/// its window and flips the visibility flag as needed, and returns `true`
/// so the caller can `return` early instead of rebuilding the window from
/// scratch. Returns `false` (doing nothing) when there's no existing
/// controller yet, i.e. this is the first time the panel is being opened.
func toggleAuxiliaryPanel(
    _ controller: NSWindowController?,
    isVisible: Bool,
    setVisible: (Bool) -> Void
) -> Bool {
    guard let controller else { return false }
    if isVisible {
        // Only close it if it's already the key window — otherwise the
        // panel is open but sitting behind something else (the main
        // window, most often), and closing it on the next invocation of
        // the same menu item reads as "nothing happened" at best or "my
        // window vanished" at worst. Bringing it forward instead matches
        // how a "Show X" command behaves everywhere else; closing only
        // once it's already frontmost keeps this feeling like a toggle
        // rather than losing the close path entirely.
        if controller.window?.isKeyWindow == true {
            controller.window?.close()
            setVisible(false)
        } else {
            controller.window?.makeKeyAndOrderFront(nil)
        }
    } else {
        controller.showWindow(nil)
        setVisible(true)
    }
    return true
}
