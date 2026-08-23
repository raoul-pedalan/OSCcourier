import SwiftUI
import AppKit

// All of ContentView's NotificationCenter-driven menu-command handling
// (Save/Load, track-adding, transport, go-to, view toggles, clipboard...).
// Split out of `body` verbatim as one continuous .onReceive chain — the
// original intermediate `let withReceivesN = ...` bindings existed only to
// keep the Swift type-checker's per-chunk workload small during
// compilation, not for any functional reason, so collapsing them back into
// one chain here changes nothing about registration order or behavior.
extension ContentView {
    // Whether THIS ContentView instance is the one the user is currently
    // interacting with. Every open OSCcourier window's ContentView
    // receives the exact same NotificationCenter broadcast for a given
    // menu command/keyboard shortcut (SwiftUI's Commands API has no
    // built-in per-window routing), so without this check pressing e.g.
    // ⌘C in one window would also copy in every other window open at the
    // same time. Counts this window's own auxiliary panels (Point List,
    // OSC Messages, etc.) as "frontmost" too, so a shortcut still reaches
    // the right document while one of those is focused instead of the
    // main window itself.
    var isFrontmostWindowGroup: Bool {
        guard let key = NSApp.keyWindow else { return false }
        if key === hostWindow { return true }
        if key === windowManagement.messagesWindowController?.window { return true }
        if key === windowManagement.pointListWindowController?.window { return true }
        if key === windowManagement.modifierKeysWindowController?.window { return true }
        if key === windowManagement.pdfWindowController?.window { return true }
        return false
    }

    func applyNotificationReceivers<Content: View>(_ content: Content) -> some View {
        let step1 = content
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierSave)) { _ in
            guard isFrontmostWindowGroup else { return }
            saveProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierSaveAs)) { _ in
            guard isFrontmostWindowGroup else { return }
            saveProjectAs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierLoad)) { _ in
            guard isFrontmostWindowGroup else { return }
            loadProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowHelp)) { _ in
            guard isFrontmostWindowGroup else { return }
            openPDFWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowModifierKeysHelp)) { _ in
            guard isFrontmostWindowGroup else { return }
            openModifierKeysHelpWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierPlayPause)) { _ in
            guard isFrontmostWindowGroup else { return }
            togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierStop)) { _ in
            guard isFrontmostWindowGroup else { return }
            transport.enLecture = false
            transport.position = 0.0
            pointDrag.invalidateSentCache()
        }

        let step2 = step1
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddBangTrack)) { _ in
            guard isFrontmostWindowGroup else { return }
            addTrack(couleur: .blue, type: .bang, height: 45)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddCurveTrack)) { _ in
            guard isFrontmostWindowGroup else { return }
            addTrack(couleur: .yellow, type: .curve, height: 60)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddMessageTrack)) { _ in
            guard isFrontmostWindowGroup else { return }
            addTrack(couleur: Color(red: 0.6549019607843137, green: 0.6784313725490196, blue: 0.0), type: .message, height: 45)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddStepTrack)) { _ in
            guard isFrontmostWindowGroup else { return }
            addTrack(couleur: Color(red: 0.608, green: 0.086, blue: 0.365), type: .step, height: 60)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierClearAll)) { _ in
            guard isFrontmostWindowGroup else { return }
            autofill.showClearAllConfirmation = true
        }

        let step3 = step2
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToTime)) { _ in
            guard isFrontmostWindowGroup else { return }
            uiChrome.goToTimeString = formattedDuration(transport.position)
            uiChrome.showGoToTimeDialog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToMarker)) { _ in
            guard isFrontmostWindowGroup else { return }
            goToNextMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToPreviousMarker)) { _ in
            guard isFrontmostWindowGroup else { return }
            goToPreviousMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierEditLoopZone)) { _ in
            guard isFrontmostWindowGroup else { return }
            loopZone.loopZoneEditStartString = formattedDuration(loopZone.loopZoneStart ?? 0)
            loopZone.loopZoneEditEndString = formattedDuration(loopZone.loopZoneEnd ?? 0)
            loopZone.showLoopZoneEditor = true
        }
        let step4 = step3
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierClearLoopZone)) { _ in
            guard isFrontmostWindowGroup else { return }
            loopZone.loopZoneStart = nil
            loopZone.loopZoneEnd = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToMarkerByName)) { _ in
            guard isFrontmostWindowGroup else { return }
            uiChrome.goToMarkerNameString = ""
            uiChrome.showGoToMarkerNameDialog = true
        }

        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierResetZoom)) { _ in
            guard isFrontmostWindowGroup else { return }
            transport.zoomX = 1.0
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierZoomToLoopZone)) { _ in
            guard isFrontmostWindowGroup else { return }
            zoomToFitLoopZone()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierResetTrackHeight)) { _ in
            guard isFrontmostWindowGroup else { return }
            // Only curve/step tracks are resizable (they're the ones with the
            // striped drag handle), so only those get reset — 60 is the same
            // default the handle's double-click reset uses.
            guard !tracksLocked else { return }
            for index in pistes.indices where pistes[index].type == .curve || pistes[index].type == .step {
                pistes[index].height = 60
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowPointList)) { _ in
            guard isFrontmostWindowGroup else { return }
            openPointListWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierTimeOffsetSelection)) { _ in
            guard isFrontmostWindowGroup else { return }
            openTimeOffsetPopup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierSelectAll)) { _ in
            guard isFrontmostWindowGroup else { return }
            // Same guard as Cut/Copy/Paste: only select every point if
            // we're not mid-edit in some other text field, otherwise fall
            // back to the standard system text select-all.
            if !(NSApp.keyWindow?.firstResponder is NSTextView) {
                selection.selectPointsInTimeRange(0, transport.duree, pistes: pistes)
            } else {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierToggleFoldAll)) { _ in
            guard isFrontmostWindowGroup else { return }
            toggleFoldAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDefineGrid)) { _ in
            guard isFrontmostWindowGroup else { return }
            openGridSettingsPopup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierOpenOSCMessagesWindow)) { _ in
            guard isFrontmostWindowGroup else { return }
            openOSCMessagesWindow()
        }

        return step4
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierMuteUnmuteAll)) { _ in
            guard isFrontmostWindowGroup else { return }
            muteUnmuteAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDeleteAllTracks)) { _ in
            guard isFrontmostWindowGroup else { return }
            autofill.showDeleteAllTracksConfirmation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDeleteSelectedPoints)) { _ in
            guard isFrontmostWindowGroup else { return }
            deleteSelectedPoints()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierCut)) { _ in
            guard isFrontmostWindowGroup else { return }
            // The menu's Cut item: cut = copy the point selection then
            // delete it (same guard as Copy/Paste — only when there's a
            // selection and we're not mid-edit in some other text field);
            // otherwise fall back to the standard system text cut.
            if !selection.selectedPointIDs.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                copySelectedPoints()
                deleteSelectedPoints()
            } else {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierCopy)) { _ in
            guard isFrontmostWindowGroup else { return }
            // The menu's Copy item: copy the point selection if there is
            // one (and we're not mid-edit in some other text field);
            // otherwise fall back to the standard system text copy.
            if !selection.selectedPointIDs.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                copySelectedPoints()
            } else {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierPaste)) { _ in
            guard isFrontmostWindowGroup else { return }
            // The menu's Paste item: enter point paste mode if the point
            // clipboard has something (and we're not mid-edit elsewhere);
            // otherwise fall back to the standard system text paste.
            if !pasteClipboard.pointClipboard.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                pasteClipboard.isPasteModeActive = true
            } else {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDuplicateSelection)) { _ in
            guard isFrontmostWindowGroup else { return }
            // Silently does nothing if there's no offset to repeat yet
            // (no clipboard, or no paste since the last copy) — same as
            // pressing ⌘D itself in that situation.
            guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return }
            duplicateSelectionWithSameOffset()
        }

    }
}
