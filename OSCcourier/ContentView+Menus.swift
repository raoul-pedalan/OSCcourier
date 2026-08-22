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
        if toggleAuxiliaryPanel(
            windowManagement.messagesWindowController,
            isVisible: windowManagement.isOSCWindowVisible,
            setVisible: { windowManagement.isOSCWindowVisible = $0 }
        ) {
            return
        }

        let (controller, delegate) = makeAuxiliaryPanel(
            content: OSCMessagesView(messageStore: messageStore),
            title: oscMessagesWindowTitle,
            autosaveName: "OSCMessagesWindow",
            initialSize: NSSize(width: 220, height: 300),
            minSize: NSSize(width: 50, height: 300),
            position: .topRightCorner(margin: 20),
            onClose: { windowManagement.isOSCWindowVisible = false }
        )
        windowManagement.messagesWindowController = controller
        windowManagement.oscWindowCloseDelegate = delegate
        controller.showWindow(nil)
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
        if toggleAuxiliaryPanel(
            windowManagement.modifierKeysWindowController,
            isVisible: windowManagement.isModifierKeysWindowVisible,
            setVisible: { windowManagement.isModifierKeysWindowVisible = $0 }
        ) {
            return
        }

        let (controller, delegate) = makeAuxiliaryPanel(
            content: ModifierKeysHelpView(),
            title: "Modifier Keys",
            autosaveName: "ModifierKeysWindow",
            initialSize: NSSize(width: 380, height: 420),
            minSize: NSSize(width: 380, height: 240),
            position: .center,
            sizeToFitContent: true,
            onClose: { windowManagement.isModifierKeysWindowVisible = false }
        )
        windowManagement.modifierKeysWindowController = controller
        windowManagement.modifierKeysCloseDelegate = delegate
        controller.showWindow(nil)
        windowManagement.isModifierKeysWindowVisible = true
    }

}
