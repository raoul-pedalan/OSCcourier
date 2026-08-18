import SwiftUI

// All of ContentView's confirmation alerts and small state-driven sheets
// (clear/delete-all confirmations, go-to/loop-zone dialogs, paste-conflict
// alerts, rename track). Split out of `body` verbatim as one continuous
// modifier chain — same reasoning as ContentView+NotificationHandling.swift.
extension ContentView {
    func applyAlertsAndConfirmations<Content: View>(_ content: Content) -> some View {
        let step1 = content
        .alert("Clear all tracks?", isPresented: $autofill.showClearAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                guard !tracksLocked else { return }
                for i in pistes.indices {
                    pistes[i].evenements.removeAll()
                }
                pointDrag.invalidateSentCache()
            }
        } message: {
            Text("This will erase every point on every track. This can't be undone.")
        }
        .alert("Delete all tracks?", isPresented: $autofill.showDeleteAllTracksConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAllTracks()
            }
        } message: {
            Text("This will delete every track except /markers. This can't be undone.")
        }
        .sheet(isPresented: $pasteClipboard.showPlayheadPositionChoice) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Go to Position")
                    .font(.headline)

                TextField("mm:ss", text: $uiChrome.goToTimeString)
                    .textFieldStyle(.roundedBorder)
                    .focused($playheadPositionFocusedField, equals: .time)
                    .onSubmit { goToChosenPlayheadPosition() }
                    .disabled(!uiChrome.goToMarkerNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                TextField("Marker name", text: $uiChrome.goToMarkerNameString)
                    .textFieldStyle(.roundedBorder)
                    .focused($playheadPositionFocusedField, equals: .marker)
                    .onSubmit { goToChosenPlayheadPosition() }
                    .onChange(of: uiChrome.goToMarkerNameString) { _, _ in
                        uiChrome.playheadMarkerNotFound = false
                    }
                    .disabled(uiChrome.goToMarkerNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && uiChrome.goToTimeString != uiChrome.goToTimeInitialValue)
                if uiChrome.playheadMarkerNotFound {
                    Text("No marker with that name was found.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Divider()

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        pasteClipboard.showPlayheadPositionChoice = false
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
                uiChrome.playheadMarkerNotFound = false
                uiChrome.goToTimeInitialValue = uiChrome.goToTimeString
            }
        }
        .sheet(isPresented: $loopZone.showLoopZoneEditor) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Loop Zone")
                    .font(.headline)

                HStack {
                    Text("Start")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("mm:ss", text: $loopZone.loopZoneEditStartString)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("End")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("mm:ss", text: $loopZone.loopZoneEditEndString)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        loopZone.showLoopZoneEditor = false
                    }
                    .keyboardShortcut(.escape)
                    Button("Apply") {
                        if let s = parseDuration(loopZone.loopZoneEditStartString),
                           let e = parseDuration(loopZone.loopZoneEditEndString) {
                            let clampedS = min(max(s, 0), transport.duree)
                            let clampedE = min(max(e, 0), transport.duree)
                            loopZone.loopZoneStart = min(clampedS, clampedE)
                            loopZone.loopZoneEnd = max(clampedS, clampedE)
                        }
                        loopZone.showLoopZoneEditor = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 280)
        }
        .alert("Go to time", isPresented: $uiChrome.showGoToTimeDialog) {
            TextField("mm:ss", text: $uiChrome.goToTimeString)
            Button("Cancel", role: .cancel) { }
            Button("Go") {
                goToTime(uiChrome.goToTimeString)
            }
        } message: {
            Text("Enter a time as mm:ss.")
        }
        .alert("Go to marker", isPresented: $uiChrome.showGoToMarkerNameDialog) {
            TextField("Marker name", text: $uiChrome.goToMarkerNameString)
            Button("Cancel", role: .cancel) { }
            Button("Go") {
                goToMarkerByName(uiChrome.goToMarkerNameString)
            }
        } message: {
            Text("Enter the name of a marker to jump to.")
        }
        .alert("No match", isPresented: $uiChrome.showGoToMarkerNoMatch) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("No marker with that name was found.")
        }
        .alert("Different track type", isPresented: $pasteClipboard.showDifferentTypePasteAlert) {
            Button("Adapt (Scale to Fit)") {
                if let t = pasteClipboard.pendingPasteAnchorTime, let idx = pasteClipboard.pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: true)
                    pasteClipboard.lastPasteOffset = nil
                }
                pasteClipboard.isPasteModeActive = false
                pasteClipboard.pendingPasteAnchorTime = nil
                pasteClipboard.pendingPasteTrackIndex = nil
            }
            Button("Cancel", role: .cancel) {
                // Dismiss only — stays in paste mode so the user can try a
                // different spot, or press Escape to back out entirely.
                pasteClipboard.pendingPasteAnchorTime = nil
                pasteClipboard.pendingPasteTrackIndex = nil
            }
        } message: {
            Text("The copied points come from a different track type. Adapt them to this track (converting labels, rescaling values), or cancel?")
        }
        .alert("Different amplitude range", isPresented: $pasteClipboard.showPasteScaleRangeAlert) {
            Button("Scale to Fit") {
                if let t = pasteClipboard.pendingPasteAnchorTime, let idx = pasteClipboard.pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: true)
                    pasteClipboard.lastPasteOffset = nil
                }
                pasteClipboard.isPasteModeActive = false
                pasteClipboard.pendingPasteAnchorTime = nil
                pasteClipboard.pendingPasteTrackIndex = nil
            }
            Button("Keep As-Is") {
                if let t = pasteClipboard.pendingPasteAnchorTime, let idx = pasteClipboard.pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: false)
                    pasteClipboard.lastPasteOffset = nil
                }
                pasteClipboard.isPasteModeActive = false
                pasteClipboard.pendingPasteAnchorTime = nil
                pasteClipboard.pendingPasteTrackIndex = nil
            }
            Button("Cancel", role: .cancel) {
                // Dismiss only — stays in paste mode so the user can try a
                // different spot, or press Escape to back out entirely.
                pasteClipboard.pendingPasteAnchorTime = nil
                pasteClipboard.pendingPasteTrackIndex = nil
            }
        } message: {
            Text("The copied points come from a track with a different amplitude range. Scale their values to fit this track's range, or paste them unchanged (clamped if out of range)?")
        }

        return step1
        .alert("Overwrite track?", isPresented: Binding<Bool>(
            get: { autofill.pendingAutofillIndex != nil },
            set: { if !$0 { autofill.pendingAutofillIndex = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                autofill.pendingAutofillIndex = nil
            }
            Button("Continue", role: .destructive) {
                if let index = autofill.pendingAutofillIndex {
                    autofill.proceedWithAutofill(for: index, track: pistes[index])
                }
                autofill.pendingAutofillIndex = nil
            }
        } message: {
            Text("This track already has points. Autofill will replace them all.")
        }
        .alert("Switch to Gate?", isPresented: Binding<Bool>(
            get: { pointEditing.pendingGateSwitchIndex != nil },
            set: { if !$0 { pointEditing.pendingGateSwitchIndex = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pointEditing.pendingGateSwitchIndex = nil
            }
            Button("Continue", role: .destructive) {
                if let index = pointEditing.pendingGateSwitchIndex {
                    applyGateModeSwitch(forTrackIndex: index)
                }
                pointEditing.pendingGateSwitchIndex = nil
            }
        } message: {
            Text("This track already has points. Switching to Gate will redistribute all their values to 0 or 1.")
        }
        .alert("Quantization step adjusted", isPresented: Binding<Bool>(
            get: { pointEditing.invalidQuantizeStepMessage != nil },
            set: { if !$0 { pointEditing.invalidQuantizeStepMessage = nil } }
        )) {
            Button("OK") { pointEditing.invalidQuantizeStepMessage = nil }
        } message: {
            Text(pointEditing.invalidQuantizeStepMessage ?? "")
        }
        .alert("Rename track", isPresented: Binding<Bool>(
            get: { pointEditing.indexPisteARenommer != nil },
            set: { if !$0 { pointEditing.indexPisteARenommer = nil } }
        )) {
            TextField("New name", text: $pointEditing.nouveauNomPiste)
            Button("OK") {
                if let index = pointEditing.indexPisteARenommer {
                    pistes[index].nom = pointEditing.nouveauNomPiste
                }
                pointEditing.indexPisteARenommer = nil
            }
            Button("Cancel", role: .cancel) { pointEditing.indexPisteARenommer = nil }
        }
    }
}
