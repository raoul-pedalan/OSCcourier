import SwiftUI
import AppKit

/// The left-hand header column of a single track row: name (double-click
/// to rename), mute/clear/duplicate/delete buttons, fold triangle,
/// reorder handle, and (curve/step tracks) the amplitude range +
/// quantization tick labels.
///
/// A real `View` rather than a `ContentView` method, so SwiftUI gives
/// each track's header its own identity for diffing — dragging one
/// track's reorder handle no longer invalidates every other header.
/// `pistes` mirrors ContentView's own bridge onto `timelineStore`
/// exactly (same undo-registering setter via `setPistes`), so every
/// `pistes[index]` read/write below behaves identically to before.
struct TrackHeaderColumn: View {
    @ObservedObject var timelineStore: TimelineStore
    @ObservedObject var pointDrag: PointDragState
    @ObservedObject var pointEditing: PointEditingState
    @ObservedObject var trackAmplitudeEdit: TrackAmplitudeEditState
    @ObservedObject var trackDragReorder: TrackDragReorderState
    @ObservedObject var autofill: AutofillState
    @ObservedObject var uiChrome: UIChromeState

    let index: Int

    // Was @AppStorage, shared by every open window — now proxies to
    // uiChrome (per-window, threaded in above).
    private var tracksLocked: Bool { uiChrome.tracksLocked }

    private var pistes: [TimelineTrack] {
        get { timelineStore.pistes }
        nonmutating set { timelineStore.setPistes(newValue) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(pistes[index].couleur)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if index == 0 {
                Text("/markers")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.leading, 10)
                    .offset(y: 5)
                    .onTapGesture(count: 2) { }
            } else {
                Text(pistes[index].nom)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.leading, 10)
                    .offset(y: 5)
                    .onTapGesture(count: 2) {
                        guard !tracksLocked else { return }
                        let piste = pistes[index]
                        pointEditing.indexPisteARenommer = index
                        pointEditing.nouveauNomPiste = piste.nom
                    }

                // Drag handle for reordering this track among its siblings
                // ("markers" at index 0 stays pinned, never reordered).
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    // Dimmed when tracks are locked: the gesture below is a
                    // no-op then, so the handle shouldn't look draggable.
                    .foregroundColor(.black.opacity(tracksLocked ? 0.12 : 0.35))
                    .padding(6)
                    .contentShape(Rectangle())
                    .offset(x: 116, y: 2)
                    .gesture(
                        DragGesture(minimumDistance: 3, coordinateSpace: .global)
                            .onChanged { value in
                                guard !tracksLocked else { return }
                                if trackDragReorder.reorderingIndex == nil {
                                    trackDragReorder.reorderingIndex = index
                                    trackDragReorder.reorderBaselineOffset = 0
                                }
                                guard let currentIndex = trackDragReorder.reorderingIndex else { return }
                                let effectiveTranslation = value.translation.height - trackDragReorder.reorderBaselineOffset

                                if effectiveTranslation > 0, currentIndex < pistes.count - 1 {
                                    let belowHeight = rowHeight(for: pistes[currentIndex + 1]) + 5
                                    if effectiveTranslation > belowHeight / 2 {
                                        pistes.swapAt(currentIndex, currentIndex + 1)
                                        trackDragReorder.reorderBaselineOffset += belowHeight
                                        trackDragReorder.reorderingIndex = currentIndex + 1
                                    }
                                } else if effectiveTranslation < 0, currentIndex > 1 {
                                    let aboveHeight = rowHeight(for: pistes[currentIndex - 1]) + 5
                                    if effectiveTranslation < -aboveHeight / 2 {
                                        pistes.swapAt(currentIndex, currentIndex - 1)
                                        trackDragReorder.reorderBaselineOffset -= aboveHeight
                                        trackDragReorder.reorderingIndex = currentIndex - 1
                                    }
                                }

                                trackDragReorder.reorderDragTranslation = value.translation.height - trackDragReorder.reorderBaselineOffset
                            }
                            .onEnded { _ in
                                trackDragReorder.reorderingIndex = nil
                                trackDragReorder.reorderDragTranslation = 0
                                trackDragReorder.reorderBaselineOffset = 0
                            }
                    )
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.openHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .help("Drag to reorder this track")
            }

            // Fold/unfold: collapses the track's header down to just its
            // name, this triangle, and the reorder handle, and hides its
            // points/curves in the timeline area.
            Button(action: {
                pistes[index].isFolded.toggle()
            }) {
                Image(systemName: pistes[index].isFolded ? "arrowtriangle.right.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.black.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .offset(x: 100, y: 6)
            .help(pistes[index].isFolded ? "Unfold track" : "Fold track")

            if !pistes[index].isFolded && (pistes[index].type == .curve || pistes[index].type == .step) {
                let trackHeight = pistes[index].height
                let topY = curveMargin
                let midY = trackHeight / 2
                let bottomY = trackHeight - curveMargin
                let tickWidth: CGFloat = 6

                if pistes[index].type == .step && pistes[index].isGate {
                    // Gate mode is strictly boolean — no middle value, so just
                    // show TRUE (top) / FALSE (bottom) instead of 3 numeric ticks.
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 3) {
                            // Hidden only when quantization is on, since the blue
                            // ticks then occupy this same column — no point having
                            // two tick scales stacked on each other. A clear spacer
                            // keeps the labels in place either way.
                            Rectangle()
                                .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
                                .frame(width: tickWidth, height: 1)
                            Text("OPEN")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .offset(y: topY - 6)

                        HStack(spacing: 3) {
                            // Hidden only when quantization is on, since the blue
                            // ticks then occupy this same column — no point having
                            // two tick scales stacked on each other. A clear spacer
                            // keeps the labels in place either way.
                            Rectangle()
                                .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
                                .frame(width: tickWidth, height: 1)
                            Text("CLOSED")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .offset(y: bottomY - 6)
                    }
                    .frame(width: 60, height: trackHeight, alignment: .topLeading)
                    .offset(x: 144)
                } else {
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 3) {
                            // Hidden only when quantization is on, since the blue
                            // ticks then occupy this same column — no point having
                            // two tick scales stacked on each other. A clear spacer
                            // keeps the labels in place either way.
                            Rectangle()
                                .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
                                .frame(width: tickWidth, height: 1)
                            Text(String(format: "%.2f", pistes[index].maxAmplitude))
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .offset(y: topY - 6)

                        HStack(spacing: 3) {
                            // Hidden only when quantization is on, since the blue
                            // ticks then occupy this same column — no point having
                            // two tick scales stacked on each other. A clear spacer
                            // keeps the labels in place either way.
                            Rectangle()
                                .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
                                .frame(width: tickWidth, height: 1)
                            Text(String(format: "%.2f", (pistes[index].minAmplitude + pistes[index].maxAmplitude) / 2))
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .offset(y: midY - 6)

                        HStack(spacing: 3) {
                            // Hidden only when quantization is on, since the blue
                            // ticks then occupy this same column — no point having
                            // two tick scales stacked on each other. A clear spacer
                            // keeps the labels in place either way.
                            Rectangle()
                                .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
                                .frame(width: tickWidth, height: 1)
                            Text(String(format: "%.2f", pistes[index].minAmplitude))
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .offset(y: bottomY - 6)
                    }
                    .frame(width: 60, height: trackHeight, alignment: .topLeading)
                    .offset(x: 144)
                }

                // Quantization ticks. They now occupy the column where the
                // range labels' own gray ticks used to be (those are gone),
                // so there's a single tick scale instead of two competing
                // ones. Blue keeps them readable as the quantization grid.
                // Only the visible subset (see visibleQuantizeTicks) is
                // drawn, so a fine step on a short track doesn't turn into
                // a solid block.
                if !pistes[index].isGate {
                    HeaderQuantizeTicksView(piste: pistes[index], trackHeight: trackHeight)
                        .equatable()
                    // Right edge stays at 150, level with where the gray ticks
                    // end (144 + tickWidth); the left edge is pulled back so
                    // they only just reach into the header (which ends at 140).
                    .frame(width: 15, height: trackHeight, alignment: .topLeading)
                    .offset(x: 135)
                    .allowsHitTesting(false)
                }
            }

            if !pistes[index].isFolded {
            if index == 0 {
                HStack(spacing: 5) {
                    Button(action: { pistes[index].isMuted.toggle() }) {
                        Image(systemName: pistes[index].isMuted ? "speaker.slash.fill" : "speaker.fill")
                            .foregroundColor(pistes[index].isMuted ? .gray : .green)
                    }
                    .buttonStyle(.borderless)
                    .help(pistes[index].isMuted ? "Unmute track" : "Mute track")

                    Button(action: {
                        guard !tracksLocked else { return }
                        // The /markers track can't be duplicated (or deleted) —
                        // only hidden by folding — so ⌥-hover here never switches
                        // this button into duplicate mode; it always just clears.
                        pistes[index].evenements.removeAll()
                        pointDrag.invalidateSentCache()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear all points on this track")
                }
                .offset(x: -20)
                .padding(.trailing, 20)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                Button(action: {
                    guard !tracksLocked else { return }
                    autofill.openAutofillPopup(for: index, track: pistes[index])
                }) {
                    Image(systemName: "pencil.tip.crop.circle.fill")
                }
                .buttonStyle(.borderless)
                .padding(.leading, 10)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .help("Autofill: generate evenly spaced markers")
            } else {
                HStack(spacing: 5) {
                    if pistes[index].type == .curve || pistes[index].type == .step {
                        Button(action: {
                            pointEditing.amplitudeEditorTrackIndex = index
                            trackAmplitudeEdit.tempMinAmplitude = String(format: "%.2f", pistes[index].minAmplitude)
                            trackAmplitudeEdit.tempMaxAmplitude = String(format: "%.2f", pistes[index].maxAmplitude)
                            trackAmplitudeEdit.tempIsGate = pistes[index].isGate
                            trackAmplitudeEdit.tempQuantizeStep = String(format: "%g", pistes[index].quantizeStep)
                            trackAmplitudeEdit.tempQuantizeEnabled = pistes[index].quantizeEnabled
                        }) {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit min/max amplitude range")
                    }

                    Button(action: { pistes[index].isMuted.toggle() }) {
                        Image(systemName: pistes[index].isMuted ? "speaker.slash.fill" : "speaker.fill")
                            .foregroundColor(pistes[index].isMuted ? .gray : .green)
                    }
                    .buttonStyle(.borderless)
                    .help(pistes[index].isMuted ? "Unmute track" : "Mute track")

                    Button(action: {
                        guard !tracksLocked else { return }
                        if pointDrag.isOptionHeldForCursor && trackDragReorder.duplicateHoverTrackIndex == index {
                            timelineStore.duplicateTrack(at: index)
                        } else {
                            pistes[index].evenements.removeAll()
                            pointDrag.invalidateSentCache()
                        }
                    }) {
                        // Fixed frame: swapping between the two SF Symbols (they have
                        // slightly different intrinsic widths) must not nudge the
                        // neighboring buttons in this row — only the icon inside
                        // this fixed box changes, never the row's layout.
                        // Color stays gray in both modes — only the symbol itself
                        // changes (plus the tooltip) — so there's no color to pick
                        // that has to fight the track's own color for contrast.
                        Image(systemName: (pointDrag.isOptionHeldForCursor && trackDragReorder.duplicateHoverTrackIndex == index) ? "doc.on.doc.fill" : "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .onHover { hovering in
                        trackDragReorder.duplicateHoverTrackIndex = hovering ? index : (trackDragReorder.duplicateHoverTrackIndex == index ? nil : trackDragReorder.duplicateHoverTrackIndex)
                    }
                    .help((pointDrag.isOptionHeldForCursor && trackDragReorder.duplicateHoverTrackIndex == index) ? "Duplicate track" : "Clear all points on this track (hold ⌥ while hovering this button to duplicate the track instead)")

                    Button(action: { guard !tracksLocked else { return }; pistes.remove(at: index); pointDrag.invalidateSentCache() }) {
                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this track")
                }
                .padding(.trailing, 20)
                .padding(.bottom, (pistes[index].type == .bang || pistes[index].type == .message) ? 6 : 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                Button(action: {
                    guard !tracksLocked else { return }
                    autofill.openAutofillPopup(for: index, track: pistes[index])
                }) {
                    Image(systemName: "pencil.tip.crop.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Autofill: generate a pattern for this track")
                .padding(.leading, 10)
                .padding(.bottom, (pistes[index].type == .bang || pistes[index].type == .message) ? 6 : 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            if pistes[index].type == .curve || pistes[index].type == .step {
                VStack(spacing: 0) {
                    Spacer()
                    DiagonalStripes(stripeWidth: 1.5, spacing: 1.5)
                        .stroke(
                            // Curve gets a fixed, more-orange-leaning yellow for
                            // the stripes themselves (rather than the track's own
                            // pure yellow) — background stays as-is below. Step
                            // keeps the dynamic track color for its stripes.
                            pistes[index].type == .curve
                                ? Color(red: 1.0, green: 0.75, blue: 0.1)
                                : pistes[index].couleur,
                            lineWidth: 1.5
                        )
                        .background(
                            // Fixed background per type, independent of the track's
                            // own color — both branches must be the same concrete
                            // type (plain Color) or the compiler chokes trying to
                            // type-check this ternary inside such a deeply nested
                            // modifier chain. Curve gets a warm orange, step a
                            // magenta/pink — user-picked to read clearly at this
                            // 4px height regardless of the track's own color.
                            pistes[index].type == .curve
                                ? Color(red: 1.0, green: 0.58, blue: 0.004)
                                : Color(red: 1.0, green: 0.196, blue: 0.988)
                        )
                        .frame(width: 140, height: 4)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if trackDragReorder.draggedTrackIndex != index {
                                        trackDragReorder.draggedTrackIndex = index
                                        trackDragReorder.dragStartHeight = pistes[index].height
                                    }
                                    let newHeight = max(30, trackDragReorder.dragStartHeight + value.translation.height)
                                    pistes[index].height = newHeight
                                }
                                .onEnded { _ in
                                    trackDragReorder.draggedTrackIndex = nil
                                }
                        )
                        .onHover { isHovering in
                            if isHovering {
                                NSCursor.resizeUpDown.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                        .onTapGesture(count: 2) {
                            pistes[index].height = 60
                        }
                }
            }
            } // end if !pistes[index].isFolded
        }
        .frame(width: 140, height: rowHeight(for: pistes[index]))
    }
}
