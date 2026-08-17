import SwiftUI

// All of ContentView's confirmation alerts and small state-driven sheets
// (clear/delete-all confirmations, go-to/loop-zone dialogs, paste-conflict
// alerts, rename track). Split out of `body` verbatim as one continuous
// modifier chain — same reasoning as ContentView+NotificationHandling.swift.
extension ContentView {
    func applyAlertsAndConfirmations<Content: View>(_ content: Content) -> some View {
        content
        .alert("Clear all tracks?", isPresented: $showClearAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                guard !tracksLocked else { return }
                for i in pistes.indices {
                    pistes[i].evenements.removeAll()
                }
                lastSentEvents.removeAll()
            }
        } message: {
            Text("This will erase every point on every track. This can't be undone.")
        }
        .alert("Delete all tracks?", isPresented: $showDeleteAllTracksConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAllTracks()
            }
        } message: {
            Text("This will delete every track except /markers. This can't be undone.")
        }
        .sheet(isPresented: $showPlayheadPositionChoice) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Go to Position")
                    .font(.headline)

                TextField("mm:ss", text: $goToTimeString)
                    .textFieldStyle(.roundedBorder)
                    .focused($playheadPositionFocusedField, equals: .time)
                    .onSubmit { goToChosenPlayheadPosition() }
                    .disabled(!goToMarkerNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                TextField("Marker name", text: $goToMarkerNameString)
                    .textFieldStyle(.roundedBorder)
                    .focused($playheadPositionFocusedField, equals: .marker)
                    .onSubmit { goToChosenPlayheadPosition() }
                    .onChange(of: goToMarkerNameString) { _, _ in
                        playheadMarkerNotFound = false
                    }
                    .disabled(goToMarkerNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && goToTimeString != goToTimeInitialValue)
                if playheadMarkerNotFound {
                    Text("No marker with that name was found.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Divider()

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        showPlayheadPositionChoice = false
                    }
                    .keyboardShortcut(.escape)
                    Button("Go") {
                        goToChosenPlayheadPosition()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 300)
            .onAppear {
                playheadPositionFocusedField = .time
                playheadMarkerNotFound = false
                goToTimeInitialValue = goToTimeString
            }
        }
        .sheet(isPresented: $showLoopZoneEditor) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Loop Zone")
                    .font(.headline)

                HStack {
                    Text("Start")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("mm:ss", text: $loopZoneEditStartString)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("End")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("mm:ss", text: $loopZoneEditEndString)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        showLoopZoneEditor = false
                    }
                    .keyboardShortcut(.escape)
                    Button("Apply") {
                        if let s = parseDuration(loopZoneEditStartString),
                           let e = parseDuration(loopZoneEditEndString) {
                            let clampedS = min(max(s, 0), duree)
                            let clampedE = min(max(e, 0), duree)
                            loopZoneStart = min(clampedS, clampedE)
                            loopZoneEnd = max(clampedS, clampedE)
                        }
                        showLoopZoneEditor = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 280)
        }
        .alert("Go to time", isPresented: $showGoToTimeDialog) {
            TextField("mm:ss", text: $goToTimeString)
            Button("Cancel", role: .cancel) { }
            Button("Go") {
                goToTime(goToTimeString)
            }
        } message: {
            Text("Enter a time as mm:ss.")
        }
        .alert("Go to marker", isPresented: $showGoToMarkerNameDialog) {
            TextField("Marker name", text: $goToMarkerNameString)
            Button("Cancel", role: .cancel) { }
            Button("Go") {
                goToMarkerByName(goToMarkerNameString)
            }
        } message: {
            Text("Enter the name of a marker to jump to.")
        }
        .alert("No match", isPresented: $showGoToMarkerNoMatch) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("No marker with that name was found.")
        }
        .alert("Different track type", isPresented: $showDifferentTypePasteAlert) {
            Button("Adapt (Scale to Fit)") {
                if let t = pendingPasteAnchorTime, let idx = pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: true)
                    lastPasteOffset = nil
                }
                isPasteModeActive = false
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
            Button("Cancel", role: .cancel) {
                // Dismiss only — stays in paste mode so the user can try a
                // different spot, or press Escape to back out entirely.
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
        } message: {
            Text("The copied points come from a different track type. Adapt them to this track (converting labels, rescaling values), or cancel?")
        }
        .alert("Different amplitude range", isPresented: $showPasteScaleRangeAlert) {
            Button("Scale to Fit") {
                if let t = pendingPasteAnchorTime, let idx = pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: true)
                    lastPasteOffset = nil
                }
                isPasteModeActive = false
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
            Button("Keep As-Is") {
                if let t = pendingPasteAnchorTime, let idx = pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: false)
                    lastPasteOffset = nil
                }
                isPasteModeActive = false
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
            Button("Cancel", role: .cancel) {
                // Dismiss only — stays in paste mode so the user can try a
                // different spot, or press Escape to back out entirely.
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
        } message: {
            Text("The copied points come from a track with a different amplitude range. Scale their values to fit this track's range, or paste them unchanged (clamped if out of range)?")
        }

        .alert("Overwrite track?", isPresented: Binding<Bool>(
            get: { pendingAutofillIndex != nil },
            set: { if !$0 { pendingAutofillIndex = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingAutofillIndex = nil
            }
            Button("Continue", role: .destructive) {
                if let index = pendingAutofillIndex {
                    proceedWithAutofill(for: index)
                }
                pendingAutofillIndex = nil
            }
        } message: {
            Text("This track already has points. Autofill will replace them all.")
        }
        .alert("Switch to Gate?", isPresented: Binding<Bool>(
            get: { pendingGateSwitchIndex != nil },
            set: { if !$0 { pendingGateSwitchIndex = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingGateSwitchIndex = nil
            }
            Button("Continue", role: .destructive) {
                if let index = pendingGateSwitchIndex {
                    applyGateModeSwitch(forTrackIndex: index)
                }
                pendingGateSwitchIndex = nil
            }
        } message: {
            Text("This track already has points. Switching to Gate will redistribute all their values to 0 or 1.")
        }
        .alert("Quantization step adjusted", isPresented: Binding<Bool>(
            get: { invalidQuantizeStepMessage != nil },
            set: { if !$0 { invalidQuantizeStepMessage = nil } }
        )) {
            Button("OK") { invalidQuantizeStepMessage = nil }
        } message: {
            Text(invalidQuantizeStepMessage ?? "")
        }
        .alert("Rename track", isPresented: Binding<Bool>(
            get: { indexPisteARenommer != nil },
            set: { if !$0 { indexPisteARenommer = nil } }
        )) {
            TextField("New name", text: $nouveauNomPiste)
            Button("OK") {
                if let index = indexPisteARenommer {
                    pistes[index].nom = nouveauNomPiste
                }
                indexPisteARenommer = nil
            }
            Button("Cancel", role: .cancel) { indexPisteARenommer = nil }
        }
    }
}
