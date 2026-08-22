import SwiftUI
import AppKit

extension ContentView {

    func toggleFoldAll() {
        let shouldFold = pistes.contains { !$0.isFolded }
        for i in pistes.indices {
            pistes[i].isFolded = shouldFold
        }
    }

    func muteUnmuteAll() {
        let shouldMute = !pistes.allSatisfy { $0.isMuted }
        for i in pistes.indices {
            pistes[i].isMuted = shouldMute
        }
    }

    func deleteAllTracks() {
        guard !tracksLocked else { return }
        pistes = [pistes[0]]
        pointDrag.invalidateSentCache()
    }

    func addTrack(couleur: Color, type: TrackType, height: CGFloat) {
        guard !tracksLocked else { return }
        pistes.append(TimelineTrack(nom: nextTrackName, couleur: couleur, evenements: [], type: type, height: height))
    }

    func openOSCMessagesWindow() {
        // No per-window appearance handling here anymore: NSApp.appearance
        // (set app-wide from the Appearance setting) already covers every
        // window, including this one and its title bar.
        if let controller = windowManagement.messagesWindowController {
            if windowManagement.isOSCWindowVisible {
                controller.window?.close()
                windowManagement.isOSCWindowVisible = false
            } else {
                controller.showWindow(nil)
                windowManagement.isOSCWindowVisible = true
            }
            return
        }

        let contentView = OSCMessagesView(messageStore: messageStore)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 300)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = oscMessagesWindowTitle
        window.setFrameAutosaveName("OSCMessagesWindow")
        window.setContentSize(NSSize(width: 220, height: 300))
        window.contentView = hostingView
        window.minSize = NSSize(width: 50, height: 300)
        // Without this, closing a manually-created NSWindow (not from a
        // nib) can release it out from under us, leaving our controller
        // holding a stale reference on the next toggle.
        window.isReleasedWhenClosed = false

        let delegate = OSCWindowCloseDelegate()
        delegate.onClose = {
            windowManagement.isOSCWindowVisible = false
        }
        window.delegate = delegate
        windowManagement.oscWindowCloseDelegate = delegate

        // Top-right of the screen, with a small margin from the edges —
        // applied after setFrameAutosaveName so it always ends up there,
        // rather than wherever a previously saved frame happened to be.
        if let screenFrame = NSScreen.main?.visibleFrame {
            let margin: CGFloat = 20
            let origin = NSPoint(
                x: screenFrame.maxX - window.frame.width - margin,
                y: screenFrame.maxY - window.frame.height - margin
            )
            window.setFrameOrigin(origin)
        }

        windowManagement.messagesWindowController = NSWindowController(window: window)
        windowManagement.messagesWindowController?.showWindow(nil)
        windowManagement.isOSCWindowVisible = true
    }

    // Filename first, then the window's own purpose — same order as the
    // Point List window's title (see pointListWindowTitle).
    var oscMessagesWindowTitle: String {
        (savedFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + " — OSC out"
    }

    func updateOSCMessagesWindowTitle() {
        windowManagement.messagesWindowController?.window?.title = oscMessagesWindowTitle
    }

    func openModifierKeysHelpWindow() {
        if let controller = windowManagement.modifierKeysWindowController {
            if windowManagement.isModifierKeysWindowVisible {
                controller.window?.close()
                windowManagement.isModifierKeysWindowVisible = false
            } else {
                controller.showWindow(nil)
                windowManagement.isModifierKeysWindowVisible = true
            }
            return
        }

        let hostingView = NSHostingView(rootView: ModifierKeysHelpView())
        // Sized from the view's own natural (un-scrolled, fixed-content)
        // size rather than a guessed constant — with no ScrollView inside,
        // fittingSize reports the real height needed to show every entry
        // at once, so the window opens at the right size the first time.
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 420)
        let fittingSize = hostingView.fittingSize
        let contentWidth = max(fittingSize.width, 380)
        let contentHeight = max(fittingSize.height, 240)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Modifier Keys"
        window.setFrameAutosaveName("ModifierKeysWindow")
        window.contentView = hostingView
        window.minSize = NSSize(width: 380, height: 240)
        window.isReleasedWhenClosed = false

        let delegate = OSCWindowCloseDelegate()
        delegate.onClose = {
            windowManagement.isModifierKeysWindowVisible = false
        }
        window.delegate = delegate
        windowManagement.modifierKeysCloseDelegate = delegate

        window.center()

        windowManagement.modifierKeysWindowController = NSWindowController(window: window)
        windowManagement.modifierKeysWindowController?.showWindow(nil)
        windowManagement.isModifierKeysWindowVisible = true
    }

}
