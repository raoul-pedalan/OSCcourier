import SwiftUI

// The full toolbar command bar (transport buttons, zoom knob, duration
// field, track-add buttons, save/load) shown when showCommandBar is true,
// falling back to compactControlBar otherwise. Split out of `body`
// verbatim — no logic changes.
extension ContentView {
    @ViewBuilder
    var toolbarBar: some View {
            if showCommandBar {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                toolbarBarContent
                Spacer(minLength: 0)
            }

            Spacer().frame(height: 10)
            } else {
                compactControlBar
            }
    }

    // The full row of transport/OSC/track/save buttons, wrapped by
    // `toolbarBar` in a Spacer-HStack-Spacer so the whole group is treated
    // as one block and stays centered in the window as it's resized,
    // instead of hugging the window's leading edge.
    @ViewBuilder
    private var toolbarBarContent: some View {
            HStack {
                Button(action: { togglePlayback() }) {
                    Image(systemName: transport.enLecture ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.black)
                        .frame(width: 60, height: 32)
                        .background(transport.enLecture ? Color(red: 0.5, green: 1.0, blue: 0.2) : Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.leading, playButtonLeadingDistance)
                .help(transport.enLecture ? "Pause (Space)" : "Play (Space)")
                Button(action: { transport.enLecture = false; transport.position = 0.0; pointDrag.lastSentEvents.removeAll() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundColor(.black)
                        .frame(width: 60, height: 32)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Stop and return to the start (Return)")
                Button(action: { enBoucle.toggle() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(enBoucle ? .black : .gray)
                        .frame(width: 60, height: 32)
                        .background(enBoucle ? Color.yellow : Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(enBoucle ? "Looping is on (C)" : "Looping is off (C)")
                TextField("Duration", text: $transport.dureeText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 85, height: 22)
                    .focused($focusedField, equals: .duree)
                    .onSubmit {
                        commitDureeEdit()
                        if focusedField == .duree { focusedField = nil }
                    }
                    .onChange(of: focusedField) { oldValue, newValue in
                        if oldValue == .duree && newValue != .duree {
                            commitDureeEdit()
                        }
                    }
                    .help("Track duration, in seconds")
                    .overlay(alignment: .bottom) {
                        Text("duration")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 25)
                    }
                Text(formattedPosition(transport.position))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))
                    .frame(width: 120, height: 22)
                    .background(Color.black)
                    .cornerRadius(5)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        showCommandBar = false
                    }
                    .help("Current playback position (double-click to hide the command bar, ⌘B)")
                    .overlay(alignment: .bottom) {
                        Text("transport.position")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 25)
                    }
                // The prefix button, address field, and receive-port field
                // are one logical group, so a single caption row spans them
                // — "└─ OSC address  out ────── in ─┘" all on one baseline,
                // not the address field's own width.
                HStack(spacing: 6) {
                    Button(action: { openOSCPrefixPopup() }) {
                        Image(systemName: "plus.circle")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 18, height: 22)
                    .help("OSC send address prefix")

                    TextField("OSC", text: Binding(
                        get: { oscManager.address },
                        set: { newValue in
                            oscManager.address = newValue
                            oscManager.setupOSCConnection()
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    // Wide enough for a long address ("255.255.255.255:65535")
                    // without clipping — the old 105 only fit something like
                    // "127.0.0.1:7400" exactly.
                    .frame(width: 155, height: 22)
                    .focused($focusedField, equals: .oscAddress)
                    .onSubmit {
                        if focusedField == .oscAddress { focusedField = nil }
                    }
                    .help("OSC destination address (host:port) — messages are sent here")

                    TextField("port", text: $uiChrome.oscReceivePortString)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 50, height: 22)
                        .focused($focusedField, equals: .oscPort)
                        .onSubmit {
                            commitOSCPortEdit()
                            if focusedField == .oscPort { focusedField = nil }
                        }
                        .onChange(of: focusedField) { oldValue, newValue in
                            if oldValue == .oscPort && newValue != .oscPort {
                                commitOSCPortEdit()
                            }
                        }
                        .help("Local port this window listens on for incoming OSC")
                }
                .overlay(alignment: .bottom) {
                    // Two separate rows: a bracket row (ticks + one
                    // continuous line spanning the whole group, closer to
                    // the fields) and a text row below it ("OSC address
                    // out" centered under the address field, "in" centered
                    // under the port field). Keeping the bracket as a
                    // single unbroken line avoids the disconnected look of
                    // trying to split it into per-field segments.
                    VStack(spacing: 4) {
                        HStack(alignment: .bottom, spacing: 0) {
                            Rectangle().fill(Color.gray.opacity(0.6)).frame(width: 1, height: 5)
                            Rectangle().fill(Color.gray.opacity(0.6)).frame(height: 1)
                            Rectangle().fill(Color.gray.opacity(0.6)).frame(width: 1, height: 5)
                        }

                        HStack(alignment: .bottom, spacing: 6) {
                            // Spacer matching the prefix (+) button's width,
                            // so the two text blocks below line up under
                            // the address/port fields, not the button.
                            Color.clear.frame(width: 18)

                            // "OSC address  out", centered under the address field.
                            HStack(alignment: .bottom, spacing: 4) {
                                Spacer(minLength: 0)
                                Text("OSC address")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.6))
                                    .fixedSize()
                                Text("out")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.6))
                                    .fixedSize()
                                Spacer(minLength: 0)
                            }
                            .frame(width: 155)

                            // "in", centered under the port field.
                            HStack(alignment: .bottom, spacing: 4) {
                                Spacer(minLength: 0)
                                Text("in")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.6))
                                    .fixedSize()
                                Spacer(minLength: 0)
                            }
                            .frame(width: 50)
                        }
                    }
                    .offset(y: 25)
                }
                .padding(.leading, 20)
                .padding(.trailing, 20)
                // The four SVG assets (button_bangTrack etc.) already bake
                // in their own rounded outer corners (bang=left, step=right)
                // and the thin divider lines between segments, so placing
                // them edge-to-edge is all that's needed for the seamless
                // pill look — no extra clipShape/divider views on top.
                HStack(spacing: 0) {
                    Button(action: {
                        addTrack(couleur: .blue, type: .bang, height: 45)
                    }) {
                        Image("button_bangTrack")
                            .resizable()
                            .frame(width: 44, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Add a bang track")
                    .overlay(alignment: .bottom) {
                        Text("bang")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 22)
                    }

                    Button(action: {
                        addTrack(couleur: .yellow, type: .curve, height: 60)
                    }) {
                        Image("button_curveTrack")
                            .resizable()
                            .frame(width: 44, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Add a curve track")
                    .overlay(alignment: .bottom) {
                        Text("curve")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 22)
                    }

                    Button(action: {
                        addTrack(couleur: Color(red: 0.6549019607843137, green: 0.6784313725490196, blue: 0.0), type: .message, height: 45)
                    }) {
                        Image("button_messageTrack")
                            .resizable()
                            .frame(width: 44, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Add a message track")
                    .overlay(alignment: .bottom) {
                        Text("message")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 22)
                    }

                    Button(action: {
                        addTrack(couleur: Color(red: 0.608, green: 0.086, blue: 0.365), type: .step, height: 60)
                    }) {
                        Image("button_stepTrack")
                            .resizable()
                            .frame(width: 44, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Add a step track")
                    .overlay(alignment: .bottom) {
                        Text("step")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 22)
                    }
                }
                .padding(.trailing, 20)


                HStack(spacing: 0) {
                    Button(action: { showPointCoordinates.toggle() }) {
                        Text("x,y")
                            .font(.body)
                            .foregroundColor(.black)
                            .frame(width: 44, height: 28)
                            .background(showPointCoordinates ? Color.yellow : Color.gray.opacity(0.15))
                    }
                    .buttonStyle(.plain)
                    .help(showPointCoordinates ? "Hide point coordinates (⌘⌥X)" : "Show point coordinates (⌘⌥X)")

                    Rectangle().fill(Color.black.opacity(0.2)).frame(width: 1, height: 28)

                    Image(systemName: "grid")
                        .font(.body)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 28)
                        .background(showGrid ? Color.yellow : Color.gray.opacity(0.15))
                        .contentShape(Rectangle())
                        // Option+click opens the grid settings without touching
                        // showGrid; a plain click toggles the grid on/off. Single
                        // onTapGesture checking the modifier at click time (same
                        // pattern used elsewhere, e.g. shift-click to delete a
                        // point), rather than double-click, which doesn't affect
                        // the toggle state at all.
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.option) {
                                openGridSettingsPopup()
                            } else {
                                showGrid.toggle()
                            }
                        }
                        .help(showGrid ? "Hide grid (⌘G, ⌥-click or ⌘⌥G for grid settings)" : "Show grid (⌘G, ⌥-click or ⌘⌥G for grid settings)")
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                // "Clear All Tracks" used to have a toolbar button here too —
                // removed as redundant clutter for an infrequent, destructive
                // action: it's still available via Tracks > Clear All Tracks…
                // (see OSCcourierApp.swift), same confirmation alert either way.
                Button(action: openOSCMessagesWindow) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.body)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 28)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Show outgoing OSC messages (M)")
                .overlay(alignment: .bottom) {
                    Text("OSC")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 22)
                }

                Button(action: openPointListWindow) {
                    Image(systemName: "list.bullet")
                        .font(.body)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 28)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Show points list (P)")
                .overlay(alignment: .bottom) {
                    Text("points")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 22)
                }

                Button(action: saveProject) {
                    Text("Save")
                        .frame(width: 60, height: 20)
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Save the project (⌘S)")
                .padding(.leading, 60)
                Button(action: loadProject) {
                    Text("Load")
                        .frame(width: 60, height: 20)
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Load a project — opens in a new window (⌘O)")
            }
            .overlay(alignment: .leading) {
                // An overlay (not a regular HStack item) so it doesn't push
                // Play/Stop/etc. sideways — only its own leading padding
                // positions it, always at exactly half of Play's fixed
                // distance from this same leading edge.
                RotaryKnob(value: $transport.zoomX, range: 1.0...maxZoomX, onDoubleTap: {
                    transport.zoomX = 1.0
                }, sensitivity: zoomKnobSensitivity)
                .help("Drag to zoom the timeline (double-click or Z to reset)")
                .overlay(alignment: .bottom) {
                    Text("zoom")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 21)
                }
                .padding(.leading, zoomKnobLeadingDistance)
            }
            .padding(.horizontal)
            .padding(.top, uiChrome.isFullScreen ? 0 : 30)
            .frame(height: uiChrome.isFullScreen ? 70 : 100)
    }

    func openOSCPrefixPopup() {
        uiChrome.oscAddressPrefixString = oscAddressPrefix
        uiChrome.showOSCPrefixPopup = true
    }

    func commitOSCPrefixPopup() {
        oscAddressPrefix = uiChrome.oscAddressPrefixString
        uiChrome.showOSCPrefixPopup = false
    }

    // The receive-port field is now always visible in the toolbar (not
    // behind a popup), committed on blur/Return like Duration — not live
    // per keystroke, since every change restarts the OSC listen socket
    // (see .onChange(of: oscReceivePort) in ContentView.swift).
    func commitOSCPortEdit() {
        if let port = Int(uiChrome.oscReceivePortString.trimmingCharacters(in: .whitespaces)) {
            oscReceivePort = port
        } else {
            uiChrome.oscReceivePortString = String(oscReceivePort)
        }
    }
}
