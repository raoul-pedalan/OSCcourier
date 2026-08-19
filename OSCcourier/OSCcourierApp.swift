//
//  OSCcourierApp.swift
//  OSCcourier
//
//  Created by bernard pierre on 27/06/2026.
//

import SwiftUI
import UniformTypeIdentifiers

// Shared appearance setting: "Auto" follows the system, "Light"/"Dark" force
// a specific scheme. Backed by a plain String @AppStorage (rather than a
// Bool) since it has 3 states, and shared across every window via the same
// UserDefaults key.
//
// Crucially, this is applied ONCE, globally, via NSApp.appearance (see
// applyAppearance below) rather than per-window/per-view. That's the only
// reliable way on macOS: SwiftUI's .preferredColorScheme only styles SwiftUI
// views, leaving AppKit-backed controls (NSTextField behind TextField, title
// bars, etc.) on the window's own NSAppearance — which is what produced the
// inconsistent "white text fields on a dark window" in Auto mode. Setting
// NSApp.appearance makes every window and every control follow suit, with no
// per-window plumbing to get out of sync.
enum AppearanceMode: String, CaseIterable {
    case auto, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: return nil   // nil = follow the system
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    // Applies this mode to the whole app, affecting every window at once.
    func apply() {
        NSApp.appearance = nsAppearance
    }

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .auto
    }
}

// Disables macOS's automatic window-tabbing feature (which is what injects
// "Show Tab Bar" / "Show All Tabs" into the View menu on its own — this is
// AppKit-level behavior, not something controllable via SwiftUI's Commands
// API, hence the small AppDelegate hook).
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the saved appearance once, app-wide, as soon as NSApp exists.
        AppearanceMode.current.apply()
    }
}

// Holds a file to load for the next window that appears, when "Open
// Recent" is used while no window currently exists to receive a direct
// notification. Set right before requesting a new window, consumed (and
// cleared) by that window's ContentView as soon as it appears — a plain
// shared variable instead of passing data through the Scene/WindowGroup
// system, since there's only ever one file in transit at a time.
enum PendingFileLoad {
    static var url: URL?
}

@main

struct OSCcourierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Shared with SettingsView and ContentView via the same @AppStorage key.
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.auto.rawValue
    // Shared with ContentView via the same @AppStorage keys, so the menu's
    // Toggle checkmarks stay in sync with the actual toolbar/track state.
    @AppStorage("showGrid") private var showGrid: Bool = false
    @AppStorage("showPointCoordinates") private var showPointCoordinates: Bool = true
    @AppStorage("showMarkersTrack") private var showMarkersTrack: Bool = true
    @AppStorage("showCommandBar") private var showCommandBar: Bool = true
    @AppStorage("tracksLocked") private var tracksLocked: Bool = false
    @AppStorage("enBoucle") private var enBoucle: Bool = false
    // Shared with ContentView via the same @AppStorage key — updated there
    // on every save/load, read here to build the Open Recent submenu.
    @AppStorage("recentFilePaths") private var recentFilePathsData: String = ""
    @Environment(\.openWindow) private var openWindow

    // Loading a file — whether via "Load…" or "Open Recent" — always opens
    // it in a brand-new window and leaves any already-open windows alone.
    // This used to post a notification that every open ContentView
    // listened for, so with several windows open they'd ALL get
    // overwritten with the loaded file; routing through PendingFileLoad +
    // openWindow instead means exactly one (new) window ever receives it.
    private func openRecentFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        // The app may not be the active/frontmost application when this
        // fires (e.g. picked from the Dock menu) — and some AppKit actions
        // (opening a new window among them) can be silently dropped until
        // it's explicitly reactivated. Running from Xcode masks this, since
        // the debugger keeps the app active throughout.
        NSApp.activate(ignoringOtherApps: true)
        PendingFileLoad.url = url
        openWindow(id: "main")
    }

    private func loadFileFromMenu() {
        // Same reactivation as openRecentFile — needed here too, since
        // NSOpenPanel itself can fail to appear at all while the app isn't
        // active.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        PendingFileLoad.url = url
        openWindow(id: "main")
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .edgesIgnoringSafeArea(.top)
                // Appearance is applied app-wide via NSApp.appearance (see
                // AppearanceMode.apply), so no .preferredColorScheme here —
                // mixing the two is exactly what caused the inconsistencies.
                .onChange(of: appearanceModeRaw) { _, newValue in
                    (AppearanceMode(rawValue: newValue) ?? .auto).apply()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                // Routed through the standard AppKit responder chain (not a
                // custom closure) so Cut/Copy/Paste keep working normally
                // inside every text field in the app (renaming a track,
                // Settings fields...) exactly as the default menu items did.
                Button("Cut") {
                    NotificationCenter.default.post(name: .OSCcourierCut, object: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NotificationCenter.default.post(name: .OSCcourierCopy, object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    NotificationCenter.default.post(name: .OSCcourierPaste, object: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Duplicate") {
                    NotificationCenter.default.post(name: .OSCcourierDuplicateSelection, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Select All") {
                    NotificationCenter.default.post(name: .OSCcourierSelectAll, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Delete Selection") {
                    NotificationCenter.default.post(name: .OSCcourierDeleteSelectedPoints, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])

                Button("Time Offset Selected Points…") {
                    NotificationCenter.default.post(name: .OSCcourierTimeOffsetSelection, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
            }

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
                    loadFileFromMenu()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    let recentPaths = recentFilePathsData.split(separator: "\n").map(String.init)
                    if recentPaths.isEmpty {
                        Text("No Recent Files")
                    } else {
                        ForEach(recentPaths, id: \.self) { path in
                            Button(URL(fileURLWithPath: path).lastPathComponent) {
                                openRecentFile(at: path)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            recentFilePathsData = ""
                        }
                    }
                }

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
                    .keyboardShortcut("c", modifiers: [])

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

                Divider()

                Button("Edit Loop Zone…") {
                    NotificationCenter.default.post(name: .OSCcourierEditLoopZone, object: nil)
                }

                Button("Clear Loop Zone") {
                    NotificationCenter.default.post(name: .OSCcourierClearLoopZone, object: nil)
                }
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

                Button("Reset Track Height") {
                    NotificationCenter.default.post(name: .OSCcourierResetTrackHeight, object: nil)
                }
                .keyboardShortcut("h", modifiers: [])

                Button("Fold/Unfold All Tracks") {
                    NotificationCenter.default.post(name: .OSCcourierToggleFoldAll, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Toggle("Show Point Coordinates", isOn: $showPointCoordinates)
                    .keyboardShortcut("x", modifiers: [.command, .option])

                Divider()

                Button("Grid Settings…") {
                    NotificationCenter.default.post(name: .OSCcourierDefineGrid, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .option])

                Toggle("Show Grid", isOn: $showGrid)
                    .keyboardShortcut("g", modifiers: .command)

                Divider()

                Toggle("Show Markers Track", isOn: $showMarkersTrack)

                Divider()

                Button("Outgoing OSC Messages") {
                    NotificationCenter.default.post(name: .OSCcourierOpenOSCMessagesWindow, object: nil)
                }
                .keyboardShortcut("m", modifiers: [])

                Button("Point List") {
                    NotificationCenter.default.post(name: .OSCcourierShowPointList, object: nil)
                }
                .keyboardShortcut("p", modifiers: [])
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

                Button("Modifier Keys") {
                    NotificationCenter.default.post(name: .OSCcourierShowModifierKeysHelp, object: nil)
                }
            }
        }

        // SwiftUI automatically adds this as "Preferences…" (⌘,) under the
        // app's own menu (here, "OSCcourier").
        Settings {
            SettingsView()
        }
    }
}

