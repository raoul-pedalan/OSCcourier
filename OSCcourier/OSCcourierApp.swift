//
//  OSCcourierApp.swift
//  OSCcourier
//
//  Created by bernard pierre on 27/06/2026.
//

import SwiftUI

@main
struct OSCcourierApp: App {
    // Shared with SettingsView via the same @AppStorage key, and persisted
    // across launches automatically (backed by UserDefaults).
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

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
