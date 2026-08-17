import SwiftUI

// Sheet-based popups used by ContentView (autofill dialogs, point/range
// editors, grid settings). Split out from ContentView.swift so the giant
// `body` expression doesn't also have to carry these — moved verbatim,
// no logic changes.
extension ContentView {

    // Extracted out of `body` (rather than inline sheet closures) so the
    // Swift type-checker doesn't have to solve the whole giant `body`
    // expression as one unit — a large body with many chained modifiers and
    // deeply nested inline view trees can time out the type-checker;
    // pulling each sheet's content into its own typed computed property
    // gives it a much smaller, independent expression to check.
    var autofillRectangleSheet: some View {
        let isGateTrack = autofill.autofillTrackIndex.map { pistes[$0].isGate } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            Text("Autofill Rectangle")
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                Text("T (s.)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofill.autofillPeriodString)
            }
            HStack {
                Text("Φ (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofill.autofillPhaseString)
            }
            HStack {
                Text("PW (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofill.autofillPulseWidthString)
            }
            HStack {
                Text("Range")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                Text("min")
                    .foregroundColor(.gray.opacity(0.7))
                TextField("", text: $autofill.autofillAmpMinString)
                    .disabled(isGateTrack)
                Text("max")
                    .foregroundColor(.gray.opacity(0.7))
                TextField("", text: $autofill.autofillAmpMaxString)
                    .disabled(isGateTrack)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    autofill.autofillTrackIndex = nil
                }
                Button("OK") {
                    commitAutofillRectangle()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    var autofillWaveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Autofill Curve")
                .font(.headline)
                .padding(.bottom, 4)

            Picker("", selection: $autofill.waveIsSine) {
                Text("Sin").tag(true)
                Text("Saw").tag(false)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("T (s.)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofill.wavePeriodString)
            }
            HStack {
                Text("Φ (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofill.wavePhaseString)
            }
            HStack {
                Text("Skew")
                    .foregroundColor(autofill.waveIsSine ? .gray.opacity(0.3) : .gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofill.waveSkewString)
                    .disabled(autofill.waveIsSine)
            }
            HStack {
                Text("Range")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                Text("min")
                    .foregroundColor(.gray.opacity(0.7))
                TextField("", text: $autofill.waveAmpMinString)
                Text("max")
                    .foregroundColor(.gray.opacity(0.7))
                TextField("", text: $autofill.waveAmpMaxString)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    autofill.waveTrackIndex = nil
                }
                Button("OK") {
                    commitAutofillWave()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    // Point editor. A sheet rather than an alert, because alerts on macOS can
    // only host single-line TextFields — the multi-line comment box needs a
    // TextEditor, which an alert won't render.
    var editPointSheet: some View {
        let trackIndex = pointEditing.pointAEditer?.trackIndex ?? 0
        let isMarkersTrack = trackIndex == 0
        let isMessageTrack = pistes.indices.contains(trackIndex) && pistes[trackIndex].type == .message
        let hasY = pistes.indices.contains(trackIndex) && (pistes[trackIndex].type == .curve || pistes[trackIndex].type == .step)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Edit point")
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                Text("Position (s)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $pointEditing.nouvellePositionString)
            }
            if hasY {
                HStack {
                    // The label reflects the track's actual amplitude range,
                    // which is customizable per track (and forced to 0/1 only
                    // in Gate mode) — not a hardcoded 0-1.
                    Text(String(format: "Y [%g, %g]", pistes[trackIndex].minAmplitude, pistes[trackIndex].maxAmplitude))
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 100, alignment: .trailing)
                    TextField("", text: $pointEditing.nouvelleYString)
                }
            }
            if isMarkersTrack || isMessageTrack {
                HStack {
                    Text("Label")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 100, alignment: .trailing)
                    TextField("", text: $pointEditing.nouveauLabel)
                }
            }

            HStack(alignment: .top) {
                Text("Comment")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $pointEditing.nouveauComment)
                    // A plain single-line field: no newlines to type in the
                    // first place, and Return submits (like every other
                    // field in this sheet) instead of inserting a line break.
                    .onSubmit { commitPointEdit() }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    pointEditing.pointAEditer = nil
                }
                Button("OK") {
                    commitPointEdit()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 360)
    }

    var autofillBangSheet: some View {
        let isMarkersTrack = autofill.bangTrackIndex == 0
        let isMessageTrack = autofill.bangTrackIndex.map { pistes[$0].type == .message } ?? false
        let title = isMarkersTrack ? "Autofill Markers" : (isMessageTrack ? "Autofill Message" : "Autofill Bang")
        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                Text("T (s.)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofill.bangPeriodString)
            }
            HStack {
                Text("Φ (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofill.bangPhaseString)
            }
            if isMarkersTrack || isMessageTrack {
                HStack {
                    Text("Prefix")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 80, alignment: .trailing)
                    TextField(isMarkersTrack ? "M" : "key", text: $autofill.bangLabelPrefixString)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    autofill.bangTrackIndex = nil
                }
                Button("OK") {
                    commitAutofillBang()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    var gridSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grid")
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                Text("T mini (s.)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $uiChrome.gridPeriodString)
            }
            HStack {
                Text("Φ (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $uiChrome.gridPhaseString)
            }

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Snap to grid")
                    .foregroundColor(.gray.opacity(0.7))
                Picker("", selection: $magneticGridSnap) {
                    Text("⌘ + clic").tag(false)
                    Text("Magnetic").tag(true)
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    uiChrome.showGridSettingsPopup = false
                }
                Button("OK") {
                    commitGridSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    // Range editor for curve/step tracks. Curve tracks only ever show the
    // min/max fields (Float behavior). Step tracks additionally get a
    // Float/Gate toggle: Gate locks the range to 0...1 (boolean on/off) and
    // hides the min/max fields entirely, since there's nothing to configure.
    var rangeEditorSheet: some View {
        let isStepTrack = pointEditing.amplitudeEditorTrackIndex.map { pistes[$0].type == .step } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            Text("Range")
                .font(.headline)
                .padding(.bottom, 4)

            if isStepTrack {
                Picker("", selection: $trackAmplitudeEdit.tempIsGate) {
                    Text("Float").tag(false)
                    Text("Gate").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: trackAmplitudeEdit.tempIsGate) { _, nowGate in
                    // Gate locks the range to 0...1 — reflect that in the
                    // (now disabled) fields, rather than leaving them showing
                    // stale Float values that no longer apply.
                    if nowGate {
                        trackAmplitudeEdit.tempMinAmplitude = "0.00"
                        trackAmplitudeEdit.tempMaxAmplitude = "1.00"
                        // Step value kept — only switched off — so returning to
                        // Float brings it back.
                        trackAmplitudeEdit.tempQuantizeEnabled = false
                    }
                }
            }

            // Shown in every mode, but disabled in Gate: Gate locks the range
            // to 0/1 and is itself a quantization, so there's nothing to set —
            // greying the fields out (rather than hiding them) keeps the sheet
            // from changing size as you toggle Float/Gate.
            let isGateMode = isStepTrack && trackAmplitudeEdit.tempIsGate

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("max")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 40, alignment: .trailing)
                    TextField("max", text: $trackAmplitudeEdit.tempMaxAmplitude)
                }
                HStack {
                    Text("min")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 40, alignment: .trailing)
                    TextField("min", text: $trackAmplitudeEdit.tempMinAmplitude)
                }

                Divider()
                    .padding(.vertical, 2)

                Toggle("Quantize", isOn: $trackAmplitudeEdit.tempQuantizeEnabled)
                    .onChange(of: trackAmplitudeEdit.tempQuantizeEnabled) { _, enabled in
                        // Only seed a value if there isn't one yet: an existing
                        // step is kept (shown greyed while off) so toggling
                        // back on restores exactly what was there.
                        if enabled, (Double(trackAmplitudeEdit.tempQuantizeStep) ?? 0) <= 0 {
                            let minV = Double(trackAmplitudeEdit.tempMinAmplitude) ?? 0
                            let maxV = Double(trackAmplitudeEdit.tempMaxAmplitude) ?? 1
                            let range = maxV - minV
                            trackAmplitudeEdit.tempQuantizeStep = String(format: "%g", range > 0 ? range / 10 : 0.1)
                        }
                    }

                HStack {
                    Text("quantif.")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 55, alignment: .trailing)
                    TextField("", text: $trackAmplitudeEdit.tempQuantizeStep)
                        .disabled(!trackAmplitudeEdit.tempQuantizeEnabled)
                }
                .opacity(trackAmplitudeEdit.tempQuantizeEnabled ? 1 : 0.45)

                Text("Point values snap to multiples of this step.")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(isGateMode)
            .opacity(isGateMode ? 0.45 : 1)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    pointEditing.amplitudeEditorTrackIndex = nil
                }
                Button("OK") {
                    commitAmplitudeEdit()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    // Presents each editor/autofill popup as a .sheet keyed to its own
    // optional-index/id @State. Split out of `body` verbatim — same
    // reasoning as ContentView+NotificationHandling.swift.
    func applySheetPresentation<Content: View>(_ content: Content) -> some View {
        content
        .sheet(isPresented: Binding<Bool>(
            get: { pointEditing.pointAEditer != nil },
            set: { if !$0 { pointEditing.pointAEditer = nil } }
        )) {
            editPointSheet
        }
        .sheet(isPresented: Binding<Bool>(
            get: { pointEditing.amplitudeEditorTrackIndex != nil },
            set: { if !$0 { pointEditing.amplitudeEditorTrackIndex = nil } }
        )) {
            rangeEditorSheet
        }
        .sheet(isPresented: Binding<Bool>(
            get: { autofill.autofillTrackIndex != nil },
            set: { if !$0 { autofill.autofillTrackIndex = nil } }
        )) {
            autofillRectangleSheet
        }
        .sheet(isPresented: Binding<Bool>(
            get: { autofill.waveTrackIndex != nil },
            set: { if !$0 { autofill.waveTrackIndex = nil } }
        )) {
            autofillWaveSheet
        }
        .sheet(isPresented: Binding<Bool>(
            get: { autofill.bangTrackIndex != nil },
            set: { if !$0 { autofill.bangTrackIndex = nil } }
        )) {
            autofillBangSheet
        }
        .sheet(isPresented: $uiChrome.showGridSettingsPopup) {
            gridSettingsSheet
        }
    }
}
