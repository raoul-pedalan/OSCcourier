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

    // Recent-file clicks (and anything similar in the future) need to know
    // whether there's an actual ContentView window to receive the load
    // notification, or whether one needs to be (re)created first — closing
    // the last window doesn't quit the app, but it does mean nothing is
    // listening for that notification anymore. Distinguished from our own
    // secondary windows (Point List, OSC Messages, etc.) by their known
    // fixed titles, since none of them should count as "the main window."
    private var isMainWindowOpen: Bool {
        let auxiliaryTitles: Set<String> = ["Point List", "OSC Messages", "Modifier Keys", "Help"]
        return NSApp.windows.contains { window in
            window.isVisible && !auxiliaryTitles.contains(window.title)
        }
    }

    private func openRecentFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        if isMainWindowOpen {
            NotificationCenter.default.post(name: .OSCcourierLoadRecentFile, object: url)
        } else {
            // With zero visible windows, the app may no longer be the
            // active/frontmost application — and some AppKit actions
            // (opening a new window among them) can be silently dropped
            // until it's explicitly reactivated. Running from Xcode masks
            // this, since the debugger keeps the app active throughout.
            NSApp.activate(ignoringOtherApps: true)
            PendingFileLoad.url = url
            openWindow(id: "main")
        }
    }

    // "Load…" used to just post a notification for ContentView to show its
    // own NSOpenPanel — which had exactly the same problem as Open Recent:
    // nothing listens when there's no window. Showing the panel directly
    // from here (NSOpenPanel doesn't need a ContentView to run) and then
    // routing the chosen URL through the same isMainWindowOpen /
    // PendingFileLoad path as Open Recent fixes both at once.
    private func loadFileFromMenu() {
        if !isMainWindowOpen {
            // Same reactivation as openRecentFile — needed here too, since
            // NSOpenPanel itself can fail to appear at all while the app
            // isn't active, which is exactly what was observed: nothing
            // happened at all, not even the panel showing up.
            NSApp.activate(ignoringOtherApps: true)
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isMainWindowOpen {
            NotificationCenter.default.post(name: .OSCcourierLoadRecentFile, object: url)
        } else {
            PendingFileLoad.url = url
            openWindow(id: "main")
        }
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

                // No "Select All" here — deliberately omitted, since this
                // app has no notion of "select all" outside the lasso.
                Button("Delete Selection") {
                    NotificationCenter.default.post(name: .OSCcourierDeleteSelectedPoints, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
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

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.auto.rawValue
    @AppStorage("oscAddressPrefix") private var oscAddressPrefix: String = ""
    @AppStorage("oscReceivePort") private var oscReceivePort: Int = 7500
    // How many OSC messages per second continuous (curve) tracks emit while
    // playing. Stored as an Int; the playback timer interval is 1/this.
    @AppStorage("oscMessagesPerSecond") private var oscMessagesPerSecond: Int = 20

    // Sensible range for continuous automation over local UDP OSC: below ~5/s
    // fast moves audibly step; above ~100/s mostly just floods the receiver.
    private let minRate = 5.0
    private let maxRate = 100.0

    // Fixed column widths. Everything is laid out against these two constants
    // rather than letting SwiftUI size things intrinsically — that's what
    // keeps rows from shifting when a field gains focus, when the numeric
    // value changes width (9 -> 100), or when a control swaps for another.
    private let labelWidth: CGFloat = 195
    private let controlWidth: CGFloat = 220

    // Double-clicking the numeric value swaps it for an editable field.
    @State private var isEditingRate = false
    @State private var rateEditText = ""
    @FocusState private var rateFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Appearance") {
                Picker("", selection: $appearanceModeRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Divider()

            row("OSC send address prefix") {
                TextField("", text: $oscAddressPrefix)
                    .textFieldStyle(.roundedBorder)
            }

            row("OSC receive port") {
                TextField("", value: $oscReceivePort, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            row("OSC output rate (msg/s.)") {
                resolutionControl
            }
            // Space for the tick overlay, reserved on the row as a whole
            // rather than inside resolutionControl — adding it there would
            // make the control taller again, which is precisely what threw
            // the label's vertical centering off.
            .padding(.bottom, 26)
        }
        .padding(20)
        .frame(width: labelWidth + controlWidth + 60, alignment: .leading)
        // Appearance is handled app-wide via NSApp.appearance — no
        // .preferredColorScheme anywhere, so SwiftUI views and AppKit-backed
        // controls (TextField, title bar) can't disagree with each other.
        .onChange(of: appearanceModeRaw) { _, newValue in
            (AppearanceMode(rawValue: newValue) ?? .auto).apply()
        }
    }

    // One settings row: right-aligned label of fixed width, then the control
    // in a fixed-width slot. Both widths are constant, so nothing reflows.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .lineLimit(1)
                .fixedSize()
                .frame(width: labelWidth, alignment: .trailing)
            content()
                .frame(width: controlWidth, alignment: .leading)
        }
    }

    private var resolutionControl: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { Double(oscMessagesPerSecond) },
                    set: { newValue in
                        // Magnetic snap to the recommended default (20):
                        // within 3 of it, stick to exactly 20.
                        oscMessagesPerSecond = abs(newValue - 20) < 3 ? 20 : Int(newValue.rounded())
                    }
                ),
                in: minRate...maxRate
            )
            // Both states (read-only Text and the editable TextField) live
            // in a ZStack with one fixed frame, and only their opacity is
            // toggled — so the slot's size never changes and nothing in
            // the window can shift when entering/leaving edit mode.
            ZStack(alignment: .trailing) {
                Text("\(oscMessagesPerSecond)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .opacity(isEditingRate ? 0 : 1)
                TextField("", text: $rateEditText)
                    // .plain (not .roundedBorder): the native bordered style
                    // has its own intrinsic padding/size, which would resize
                    // this slot on entering edit mode. The focus ring below is
                    // drawn as an overlay instead — overlays sit outside the
                    // layout flow, so it's purely visual and shifts nothing.
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($rateFieldFocused)
                    .opacity(isEditingRate ? 1 : 0)
                    .disabled(!isEditingRate)
                    .onSubmit { commitRateEdit() }
                    .onExitCommand { isEditingRate = false }
                    .onChange(of: rateFieldFocused) { _, focused in
                        if !focused && isEditingRate { commitRateEdit() }
                    }
            }
            .frame(width: 30, alignment: .trailing)
            .overlay {
                if isEditingRate {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                rateEditText = "\(oscMessagesPerSecond)"
                isEditingRate = true
                rateFieldFocused = true
            }
        }
        // Ticks drawn as an overlay rather than stacked below in a VStack:
        // an overlay sits OUTSIDE the layout flow, so this control's height
        // stays exactly the slider's height. That's what lets the row's
        // normal vertical centering put the label right on the slider,
        // instead of centering it against slider + ticks combined (which is
        // what pushed it down).
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    tickMark(label: "", atX: tickX(for: 5, width: width) + 10, width: width)
                    tickMark(label: "default", atX: tickX(for: 20, width: width) + 8, width: width) {
                        oscMessagesPerSecond = 20
                    }
                    tickMark(label: "", atX: tickX(for: 100, width: width) - 10, width: width)
                }
            }
            .frame(height: 26)
            .offset(y: 26)
        }
    }

    private func commitRateEdit() {
        if let v = Int(rateEditText.trimmingCharacters(in: .whitespaces)) {
            oscMessagesPerSecond = min(max(v, Int(minRate)), Int(maxRate))
        }
        isEditingRate = false
        rateFieldFocused = false
    }

    private func tickX(for value: Double, width: CGFloat) -> CGFloat {
        // The slider's usable track is inset from its bounds by roughly half
        // a knob on each side; subtracting the numeric readout's width keeps
        // the ticks under the slider itself rather than the whole HStack.
        let trackWidth = width - 38
        return CGFloat((value - minRate) / (maxRate - minRate)) * trackWidth
    }

    // A single tick: a short vertical line at the slider's value position,
    // with a caption centered under it. An optional onTap makes it clickable
    // — used so clicking "default" snaps back to 20.
    private func tickMark(label: String, atX: CGFloat, width: CGFloat, onTap: (() -> Void)? = nil) -> some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 1, height: 5)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize()
        }
        .frame(width: 80)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .position(x: min(max(atX, 0), width), y: 11)
    }
}
