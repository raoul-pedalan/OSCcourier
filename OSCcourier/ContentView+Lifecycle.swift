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

        dureeText = formattedDuration(duree)

        // Incoming OSC messages control transport from the outside.
        oscManager.onOSCMessageReceived = handleReceivedOSCMessage
        oscManager.startListening(port: oscReceivePort)

        // .onHover alone only fires on enter/exit; this keeps the point
        // cursor (shift/cmd) in sync if the modifier key changes while
        // the mouse stays over the same point.
        if flagsChangedMonitor == nil {
            flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                updatePointCursor()
                isOptionHeldForCursor = event.modifierFlags.contains(.option)
                isShiftHeldForCursor = event.modifierFlags.contains(.shift)
                return event
            }
        }

        // Backspace removes the current lasso selection.
        if keyDownMonitor == nil {
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Don't hijack any of these while the user is editing text
                // somewhere else (renaming a track, a field in a sheet,
                // Settings...) — let the key through as normal text editing.
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    return event
                }

                // Backspace: delete the current selection.
                if event.keyCode == 51 {
                    guard !selectedPointIDs.isEmpty else { return event }
                    deleteSelectedPoints()
                    return nil
                }

                // ⌘C: copy the current selection.
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
                    guard !selectedPointIDs.isEmpty else { return event }
                    copySelectedPoints()
                    return nil
                }

                // ⌘X: cut = copy the current selection, then delete it.
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "x" {
                    guard !selectedPointIDs.isEmpty else { return event }
                    copySelectedPoints()
                    deleteSelectedPoints()
                    return nil
                }

                // ⌘V: enter paste mode (red crosshair cursor) — the actual
                // paste happens on click, handled by each track's own gesture.
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
                    guard !pointClipboard.isEmpty else { return event }
                    isPasteModeActive = true
                    return nil
                }

                // Escape: cancel paste mode.
                if event.keyCode == 53, isPasteModeActive {
                    isPasteModeActive = false
                    return nil
                }

                return event
            }
        }

        if fullScreenEnterObserver == nil {
            fullScreenEnterObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
                isFullScreen = true
            }
        }
        if fullScreenExitObserver == nil {
            fullScreenExitObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
                isFullScreen = false
            }
        }

        startPlaybackTimer()
    }

    func tearDownOnDisappear() {
        timer?.invalidate()
        timer = nil
        oscManager.cancelConnection()
        oscManager.stopListening()
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let observer = fullScreenEnterObserver {
            NotificationCenter.default.removeObserver(observer)
            fullScreenEnterObserver = nil
        }
        if let observer = fullScreenExitObserver {
            NotificationCenter.default.removeObserver(observer)
            fullScreenExitObserver = nil
        }
        stopDurationDragTimer()
        oscFlashTimer?.invalidate()
        oscFlashTimer = nil
    }

}
