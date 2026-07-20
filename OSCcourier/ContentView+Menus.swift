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
        lastSentEvents.removeAll()
    }

    func addTrack(couleur: Color, type: TrackType, height: CGFloat) {
        guard !tracksLocked else { return }
        pistes.append(TimelineTrack(nom: nextTrackName, couleur: couleur, evenements: [], type: type, height: height))
    }

    // Finds the next free "<base>.N" name for a duplicate. Strips any
    // existing ".N" suffix from the source name first, so duplicating a
    // duplicate keeps incrementing off the same base instead of nesting
    // suffixes ("/track_4.1" -> "/track_4.2", never "/track_4.1.1").
    func nextDuplicateName(basedOn name: String) -> String {
        var base = name
        if let dotRange = base.range(of: #"\.\d+$"#, options: .regularExpression) {
            base.removeSubrange(dotRange)
        }
        let existingNames = Set(pistes.map { $0.nom })
        var n = 1
        while existingNames.contains("\(base).\(n)") {
            n += 1
        }
        return "\(base).\(n)"
    }

    // Inserts a copy of the track at `index` right after it. Fresh UUIDs for
    // both the track and every one of its points — reusing the originals
    // would create duplicate ids across tracks, which breaks anything keyed
    // by id across the whole timeline (e.g. the Points List table, whose rows
    // are flattened from every track into one id-keyed list).
    func duplicateTrack(at index: Int) {
        guard !tracksLocked, pistes.indices.contains(index) else { return }
        let original = pistes[index]
        let copy = TimelineTrack(
            nom: nextDuplicateName(basedOn: original.nom),
            couleur: original.couleur,
            evenements: original.evenements.map { event in
                TimelineEvent(time: event.time, label: event.label, y: event.y,
                               segmentCurve: event.segmentCurve, segmentBulge: event.segmentBulge,
                               segmentEnabled: event.segmentEnabled, comment: event.comment)
            },
            type: original.type,
            isMuted: original.isMuted,
            minAmplitude: original.minAmplitude,
            maxAmplitude: original.maxAmplitude,
            height: original.height,
            isFolded: original.isFolded,
            isGate: original.isGate,
            quantizeStep: original.quantizeStep,
            quantizeEnabled: original.quantizeEnabled
        )
        pistes.insert(copy, at: index + 1)
    }

    func openOSCMessagesWindow() {
        // No per-window appearance handling here anymore: NSApp.appearance
        // (set app-wide from the Appearance setting) already covers every
        // window, including this one and its title bar.
        if let controller = messagesWindowController {
            if isOSCWindowVisible {
                controller.window?.close()
                isOSCWindowVisible = false
            } else {
                controller.showWindow(nil)
                isOSCWindowVisible = true
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
        window.title = "Outgoing OSC Messages"
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
            isOSCWindowVisible = false
        }
        window.delegate = delegate
        oscWindowCloseDelegate = delegate

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

        messagesWindowController = NSWindowController(window: window)
        messagesWindowController?.showWindow(nil)
        isOSCWindowVisible = true
    }

    func openModifierKeysHelpWindow() {
        if let controller = modifierKeysWindowController {
            if isModifierKeysWindowVisible {
                controller.window?.close()
                isModifierKeysWindowVisible = false
            } else {
                controller.showWindow(nil)
                isModifierKeysWindowVisible = true
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
            isModifierKeysWindowVisible = false
        }
        window.delegate = delegate
        modifierKeysCloseDelegate = delegate

        window.center()

        modifierKeysWindowController = NSWindowController(window: window)
        modifierKeysWindowController?.showWindow(nil)
        isModifierKeysWindowVisible = true
    }

}
