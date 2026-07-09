//
//  OSCcourierApp.swift
//  OSCcourier
//
//  Created by bernard pierre on 27/06/2026.
//

import SwiftUI

// Disables macOS's automatic window-tabbing feature (which is what injects
// "Show Tab Bar" / "Show All Tabs" into the View menu on its own — this is
// AppKit-level behavior, not something controllable via SwiftUI's Commands
// API, hence the small AppDelegate hook).
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}

@main
struct OSCcourierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Shared with SettingsView via the same @AppStorage key, and persisted
    // across launches automatically (backed by UserDefaults).
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    // Shared with ContentView via the same @AppStorage keys, so the menu's
    // Toggle checkmarks stay in sync with the actual toolbar/track state.
    @AppStorage("showGrid") private var showGrid: Bool = false
    @AppStorage("showPointCoordinates") private var showPointCoordinates: Bool = true
    @AppStorage("showMarkersTrack") private var showMarkersTrack: Bool = true
    @AppStorage("showCommandBar") private var showCommandBar: Bool = true
    @AppStorage("tracksLocked") private var tracksLocked: Bool = false
    @AppStorage("enBoucle") private var enBoucle: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .edgesIgnoringSafeArea(.top)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .OSCcourierSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    NotificationCenter.default.post(name: .OSCcourierSaveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Load…") {
                    NotificationCenter.default.post(name: .OSCcourierLoad, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Play") {
                Button("Play/Pause") {
                    NotificationCenter.default.post(name: .OSCcourierPlayPause, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Stop") {
                    NotificationCenter.default.post(name: .OSCcourierStop, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [])

                Toggle("Loop", isOn: $enBoucle)
                    .keyboardShortcut("l", modifiers: [])

                Divider()

                Button("Go to (mm:ss)…") {
                    NotificationCenter.default.post(name: .OSCcourierGoToTime, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Go to Marker…") {
                    NotificationCenter.default.post(name: .OSCcourierGoToMarkerByName, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Button("Go to Next Marker") {
                    NotificationCenter.default.post(name: .OSCcourierGoToMarker, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Go to Previous Marker") {
                    NotificationCenter.default.post(name: .OSCcourierGoToPreviousMarker, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            // CommandGroup(after: .toolbar) inserts these items into macOS's
            // own native "View" menu (the one that already carries "Enter
            // Full Screen"), instead of creating a brand-new top-level menu
            // also titled "View" — CommandMenu always creates a separate
            // menu even if the title matches an existing one, which is what
            // caused the duplicate "View" menu before.
            CommandGroup(after: .toolbar) {
                Divider()
                Toggle("Command Bar", isOn: $showCommandBar)
                    .keyboardShortcut("b", modifiers: .command)

                Divider()
                Button("Reset Horizontal Zoom") {
                    NotificationCenter.default.post(name: .OSCcourierResetZoom, object: nil)
                }
                .keyboardShortcut("z", modifiers: [])

                Button("Fold/Unfold All Tracks") {
                    NotificationCenter.default.post(name: .OSCcourierToggleFoldAll, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Toggle("Show Point Coordinates", isOn: $showPointCoordinates)
                    .keyboardShortcut("x", modifiers: [.command, .option])

                Divider()

                Button("Define Grid…") {
                    NotificationCenter.default.post(name: .OSCcourierDefineGrid, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .option])

                Toggle("Display Grid", isOn: $showGrid)
                    .keyboardShortcut("g", modifiers: .command)

                Divider()

                Toggle("Show Markers Track", isOn: $showMarkersTrack)

                Divider()

                Button("Open Outgoing OSC Message Window") {
                    NotificationCenter.default.post(name: .OSCcourierOpenOSCMessagesWindow, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
            }

            CommandMenu("Tracks") {
                Button("Add Bang Track") {
                    NotificationCenter.default.post(name: .OSCcourierAddBangTrack, object: nil)
                }
                Button("Add Curve Track") {
                    NotificationCenter.default.post(name: .OSCcourierAddCurveTrack, object: nil)
                }
                Button("Add Step Track") {
                    NotificationCenter.default.post(name: .OSCcourierAddStepTrack, object: nil)
                }
                Button("Add Message Track") {
                    NotificationCenter.default.post(name: .OSCcourierAddMessageTrack, object: nil)
                }

                Divider()

                Toggle("Lock Tracks", isOn: $tracksLocked)
                    .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Clear All Tracks…") {
                    NotificationCenter.default.post(name: .OSCcourierClearAll, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button("Mute/Unmute All") {
                    NotificationCenter.default.post(name: .OSCcourierMuteUnmuteAll, object: nil)
                }
                Button("Delete All Tracks…") {
                    NotificationCenter.default.post(name: .OSCcourierDeleteAllTracks, object: nil)
                }
            }

            CommandGroup(replacing: .help) {
                Button("OSCcourier Help") {
                    NotificationCenter.default.post(name: .OSCcourierShowHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        // SwiftUI automatically adds this as "Preferences…" (⌘,) under the
        // app's own menu (here, "OSCcourier").
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("oscAddressPrefix") private var oscAddressPrefix: String = ""
    @AppStorage("oscReceivePort") private var oscReceivePort: Int = 7500

    var body: some View {
        Form {
            Toggle("Dark theme", isOn: $isDarkMode)

            Divider()
                .padding(.horizontal, -20)

            TextField("OSC send address prefix", text: $oscAddressPrefix)
            TextField("OSC receive port", value: $oscReceivePort, formatter: NumberFormatter())
        }
        .padding(20)
        .frame(width: 300)
    }
}
