import SwiftUI

// All of ContentView's NotificationCenter-driven menu-command handling
// (Save/Load, track-adding, transport, go-to, view toggles, clipboard...).
// Split out of `body` verbatim as one continuous .onReceive chain — the
// original intermediate `let withReceivesN = ...` bindings existed only to
// keep the Swift type-checker's per-chunk workload small during
// compilation, not for any functional reason, so collapsing them back into
// one chain here changes nothing about registration order or behavior.
extension ContentView {
    func applyNotificationReceivers<Content: View>(_ content: Content) -> some View {
        let step1 = content
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierSave)) { _ in
            saveProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierSaveAs)) { _ in
            saveProjectAs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierLoad)) { _ in
            loadProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierLoadRecentFile)) { notification in
            guard let url = notification.object as? URL else { return }
            loadProject(from: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowHelp)) { _ in
            openPDFWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowModifierKeysHelp)) { _ in
            openModifierKeysHelpWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierPlayPause)) { _ in
            togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierStop)) { _ in
            enLecture = false
            position = 0.0
            lastSentEvents.removeAll()
        }

        let step2 = step1
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddBangTrack)) { _ in
            addTrack(couleur: .blue, type: .bang, height: 45)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddCurveTrack)) { _ in
            addTrack(couleur: .yellow, type: .curve, height: 60)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddMessageTrack)) { _ in
            addTrack(couleur: Color(red: 0.6549019607843137, green: 0.6784313725490196, blue: 0.0), type: .message, height: 45)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddStepTrack)) { _ in
            addTrack(couleur: Color(red: 0.608, green: 0.086, blue: 0.365), type: .step, height: 60)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierClearAll)) { _ in
            showClearAllConfirmation = true
        }

        let step3 = step2
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToTime)) { _ in
            goToTimeString = formattedDuration(position)
            showGoToTimeDialog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToMarker)) { _ in
            goToNextMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToPreviousMarker)) { _ in
            goToPreviousMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierEditLoopZone)) { _ in
            loopZoneEditStartString = formattedDuration(loopZoneStart ?? 0)
            loopZoneEditEndString = formattedDuration(loopZoneEnd ?? 0)
            showLoopZoneEditor = true
        }
        let step4 = step3
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierClearLoopZone)) { _ in
            loopZoneStart = nil
            loopZoneEnd = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToMarkerByName)) { _ in
            goToMarkerNameString = ""
            showGoToMarkerNameDialog = true
        }

        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierResetZoom)) { _ in
            zoomX = 1.0
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierResetTrackHeight)) { _ in
            // Only curve/step tracks are resizable (they're the ones with the
            // striped drag handle), so only those get reset — 60 is the same
            // default the handle's double-click reset uses.
            guard !tracksLocked else { return }
            for index in pistes.indices where pistes[index].type == .curve || pistes[index].type == .step {
                pistes[index].height = 60
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowPointList)) { _ in
            openPointListWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierToggleFoldAll)) { _ in
            toggleFoldAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDefineGrid)) { _ in
            openGridSettingsPopup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierOpenOSCMessagesWindow)) { _ in
            openOSCMessagesWindow()
        }

        return step4
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierMuteUnmuteAll)) { _ in
            muteUnmuteAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDeleteAllTracks)) { _ in
            showDeleteAllTracksConfirmation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDeleteSelectedPoints)) { _ in
            deleteSelectedPoints()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierCut)) { _ in
            // The menu's Cut item: cut = copy the point selection then
            // delete it (same guard as Copy/Paste — only when there's a
            // selection and we're not mid-edit in some other text field);
            // otherwise fall back to the standard system text cut.
            if !selectedPointIDs.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                copySelectedPoints()
                deleteSelectedPoints()
            } else {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierCopy)) { _ in
            // The menu's Copy item: copy the point selection if there is
            // one (and we're not mid-edit in some other text field);
            // otherwise fall back to the standard system text copy.
            if !selectedPointIDs.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                copySelectedPoints()
            } else {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierPaste)) { _ in
            // The menu's Paste item: enter point paste mode if the point
            // clipboard has something (and we're not mid-edit elsewhere);
            // otherwise fall back to the standard system text paste.
            if !pointClipboard.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                isPasteModeActive = true
            } else {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDuplicateSelection)) { _ in
            // Silently does nothing if there's no offset to repeat yet
            // (no clipboard, or no paste since the last copy) — same as
            // pressing ⌘D itself in that situation.
            guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return }
            duplicateSelectionWithSameOffset()
        }

    }
}
