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
