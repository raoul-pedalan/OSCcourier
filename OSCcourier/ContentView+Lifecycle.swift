import SwiftUI
import AppKit

extension ContentView {

    func setupOnAppear() {
        // macOS assigns first responder to the first key-view-eligible
        // NSTextField right after the window appears, regardless of
        // FocusState's initial value — so we explicitly clear it again
        // a beat later to actually win that race.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedField = nil
        }

        // A window opened specifically to load a recent file (see
        // OSCcourierApp's "Open Recent" handling) — cleared right after
        // reading it, so a later, ordinary window doesn't load it again.
        if let url = PendingFileLoad.url {
            PendingFileLoad.url = nil
            loadProject(from: url)
        }

        transport.dureeText = formattedDuration(transport.duree)

        // Incoming OSC messages control transport from the outside.
        oscManager.onOSCMessageReceived = handleReceivedOSCMessage
        oscManager.startListening(port: oscReceivePort)

        // .onHover alone only fires on enter/exit; this keeps the point
        // cursor (shift/cmd) in sync if the modifier key changes while
        // the mouse stays over the same point.
        if uiChrome.flagsChangedMonitor == nil {
            uiChrome.flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                pointDrag.updateCursor(pasteModeActive: pasteClipboard.isPasteModeActive, magneticGridSnap: magneticGridSnap)
                pointDrag.isOptionHeldForCursor = event.modifierFlags.contains(.option)
                pointDrag.isShiftHeldForCursor = event.modifierFlags.contains(.shift)
                return event
            }
        }

        // Backspace removes the current lasso selection.
        if pointDrag.keyDownMonitor == nil {
            pointDrag.keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Don't hijack any of these while the user is editing text
                // somewhere else (renaming a track, a field in a sheet,
                // Settings...) — let the key through as normal text editing.
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    return event
                }

                // Backspace: delete the current selection.
                if event.keyCode == 51 {
                    guard !selection.selectedPointIDs.isEmpty else { return event }
                    deleteSelectedPoints()
                    return nil
                }

                // Arrow keys: nudge the selection by one screen pixel.
                // 123=Left, 124=Right, 125=Down, 126=Up.
                if [123, 124, 125, 126].contains(event.keyCode) {
                    guard !selection.selectedPointIDs.isEmpty else { return event }
                    switch event.keyCode {
                    case 123: nudgeSelection(timePixels: -1, valuePixels: 0)
                    case 124: nudgeSelection(timePixels: 1, valuePixels: 0)
                    case 125: nudgeSelection(timePixels: 0, valuePixels: -1)
                    case 126: nudgeSelection(timePixels: 0, valuePixels: 1)
                    default: break
                    }
                    return nil
                }

                // ⌘C: copy the current selection.
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
                    guard !selection.selectedPointIDs.isEmpty else { return event }
                    copySelectedPoints()
                    return nil
                }

                // ⌘X: cut = copy the current selection, then delete it.
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "x" {
                    guard !selection.selectedPointIDs.isEmpty else { return event }
                    copySelectedPoints()
                    deleteSelectedPoints()
                    return nil
                }

                // ⌘V: enter paste mode (red crosshair cursor) — the actual
                // paste happens on click, handled by each track's own gesture.
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
                    guard !pasteClipboard.pointClipboard.isEmpty else { return event }
                    pasteClipboard.isPasteModeActive = true
                    return nil
                }

                // ⌘D: repeat the last paste at the same offset again.
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "d" {
                    guard !pasteClipboard.pointClipboard.isEmpty, pasteClipboard.lastPasteAnchorTime != nil else { return event }
                    duplicateSelectionWithSameOffset()
                    return nil
                }

                // Escape: cancel paste mode.
                if event.keyCode == 53, pasteClipboard.isPasteModeActive {
                    pasteClipboard.isPasteModeActive = false
                    return nil
                }

                return event
            }
        }

        if uiChrome.fullScreenEnterObserver == nil {
            uiChrome.fullScreenEnterObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
                uiChrome.isFullScreen = true
            }
        }
        if uiChrome.fullScreenExitObserver == nil {
            uiChrome.fullScreenExitObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
                uiChrome.isFullScreen = false
            }
        }

        startPlaybackTimer()
    }

    func tearDownOnDisappear() {
        transport.timer?.invalidate()
        transport.timer = nil
        oscManager.cancelConnection()
        oscManager.stopListening()
        if let monitor = uiChrome.flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            uiChrome.flagsChangedMonitor = nil
        }
        if let monitor = pointDrag.keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            pointDrag.keyDownMonitor = nil
        }
        if let observer = uiChrome.fullScreenEnterObserver {
            NotificationCenter.default.removeObserver(observer)
            uiChrome.fullScreenEnterObserver = nil
        }
        if let observer = uiChrome.fullScreenExitObserver {
            NotificationCenter.default.removeObserver(observer)
            uiChrome.fullScreenExitObserver = nil
        }
        stopDurationDragTimer()
        transport.oscFlashTimer?.invalidate()
        transport.oscFlashTimer = nil
    }

}
