import SwiftUI

// The full toolbar command bar (transport buttons, zoom knob, duration
// field, track-add buttons, save/load) shown when showCommandBar is true,
// falling back to compactControlBar otherwise. Split out of `body`
// verbatim — no logic changes.
extension ContentView {
    @ViewBuilder
    var toolbarBar: some View {
            if showCommandBar {
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
                Button(action: { transport.enLecture = false; transport.position = 0.0; pointDrag.lastSentEvents.removeAll() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundColor(.black)
                        .frame(width: 60, height: 32)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Button(action: { enBoucle.toggle() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(enBoucle ? .black : .gray)
                        .frame(width: 60, height: 32)
                        .background(enBoucle ? Color.yellow : Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
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
                    .overlay(alignment: .bottom) {
                        Text("duration")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 23)
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
                    .overlay(alignment: .bottom) {
                        Text("transport.position")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 23)
                    }
                TextField("OSC", text: Binding(
                    get: { oscManager.address },
                    set: { newValue in
                        oscManager.address = newValue
                        oscManager.setupOSCConnection()
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 150, height: 22)
                .focused($focusedField, equals: .oscAddress)
                .onSubmit {
                    if focusedField == .oscAddress { focusedField = nil }
                }
                .overlay(alignment: .bottom) {
                    Text("OSC address")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 23)
                }
                HStack(spacing: 0) {
                    Button(action: {
                        addTrack(couleur: .blue, type: .bang, height: 45)
                    }) {
                        Image("button_bangTrack")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("bang")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 18)
                    }

                    Button(action: {
                        addTrack(couleur: .yellow, type: .curve, height: 60)
                    }) {
                        Image("button_curveTrack")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("curve")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 18)
                    }

                    Button(action: {
                        addTrack(couleur: Color(red: 0.6549019607843137, green: 0.6784313725490196, blue: 0.0), type: .message, height: 45)
                    }) {
                        Image("button_messageTrack")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("message")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 18)
                    }

                    Button(action: {
                        addTrack(couleur: Color(red: 0.608, green: 0.086, blue: 0.365), type: .step, height: 60)
                    }) {
                        Image("button_stepTrack")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("step")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 18)
                    }
                }
                Button(action: { showPointCoordinates.toggle() }) {
                    Text("x,y")
                        .font(.body)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 28)
                        .background(showPointCoordinates ? Color.yellow : Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Image(systemName: "grid")
                    .font(.body)
                    .foregroundColor(.black)
                    .frame(width: 44, height: 28)
                    .background(showGrid ? Color.yellow : Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                Button(action: {
                    autofill.showClearAllConfirmation = true
                }) {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 28)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Button(action: openOSCMessagesWindow) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.body)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 28)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Show OSC messages")
                .overlay(alignment: .bottom) {
                    Text("OSC")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 20)
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
                .help("Show points list")
                .overlay(alignment: .bottom) {
                    Text("points")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 20)
                }

                Button(action: saveProject) {
                    Text("Save")
                }
                .buttonStyle(.bordered)
                .padding(.leading, 100)
                Button(action: loadProject) {
                    Text("Load")
                }
                .buttonStyle(.bordered)
            }
            .overlay(alignment: .leading) {
                // An overlay (not a regular HStack item) so it doesn't push
                // Play/Stop/etc. sideways — only its own leading padding
                // positions it, always at exactly half of Play's fixed
                // distance from this same leading edge.
                RotaryKnob(value: $transport.zoomX, range: 1.0...maxZoomX, onDoubleTap: {
                    transport.zoomX = 1.0
                }, sensitivity: zoomKnobSensitivity)
                .overlay(alignment: .bottom) {
                    Text("zoom")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 19)
                }
                .padding(.leading, zoomKnobLeadingDistance)
            }
            .padding(.horizontal)
            .padding(.top, uiChrome.isFullScreen ? 0 : 30)
            .frame(height: uiChrome.isFullScreen ? 70 : 100)

            Spacer().frame(height: 10)
            } else {
                compactControlBar
            }
    }
}
