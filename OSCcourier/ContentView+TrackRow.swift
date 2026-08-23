import SwiftUI

// Thin adapters building the two halves of a track row — split so the
// header can be rendered once in the pinned left column (ContentView.swift)
// and the content once inside the horizontally/vertically-scrolling
// TimelineScrollView, instead of one combined TrackRow living entirely
// inside the scroll view the way it used to (which is what let the headers
// scroll out of view horizontally when zoomed/panned — the whole point of
// pinning them). Both share the exact same per-index visibility gate and
// drag-reorder offset/zIndex/opacity, driven by the same trackDragReorder
// state, so the two independently-scrolled panes still animate a reorder
// drag in lockstep.
extension ContentView {
    @ViewBuilder
    func trackRowHeader(index: Int) -> some View {
        if index != 0 || showMarkersTrack {
            TrackHeaderColumn(
                timelineStore: timelineStore,
                pointDrag: pointDrag,
                pointEditing: pointEditing,
                trackAmplitudeEdit: trackAmplitudeEdit,
                trackDragReorder: trackDragReorder,
                autofill: autofill,
                uiChrome: uiChrome,
                index: index
            )
            .offset(y: trackDragReorder.reorderingIndex == index ? trackDragReorder.reorderDragTranslation : 0)
            .zIndex(trackDragReorder.reorderingIndex == index ? 1 : 0)
            .opacity(trackDragReorder.reorderingIndex == index ? 0.85 : 1.0)
            Rectangle().fill(Color.clear).frame(height: 5)
        }
    }

    // The curve/step amplitude-range labels (max/mid/min, or OPEN/CLOSED
    // for a gate track) and the quantization ticks — extracted out of
    // TrackHeaderColumn.body, which used to draw them directly but is now
    // an opaque pane clipped at x=140. These are deliberately positioned
    // past that boundary (up to x=204) so they still poke into the start
    // of the track content, same as before the header/content split; see
    // pinnedTrackGraduationsOverlay (ContentView+TracksArea.swift) for how
    // this is layered semi-transparent and non-interactive on top of
    // everything else.
    @ViewBuilder
    func trackRowGraduations(index: Int) -> some View {
        if index != 0 || showMarkersTrack {
            ZStack(alignment: .topLeading) {
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

                    // Quantization ticks. They occupy the column where the range
                    // labels' own gray ticks used to be (those are hidden while
                    // this shows), so there's a single tick scale instead of two
                    // competing ones. Blue keeps them readable as the
                    // quantization grid. Only the visible subset (see
                    // visibleQuantizeTicks) is drawn, so a fine step on a short
                    // track doesn't turn into a solid block.
                    if !pistes[index].isGate {
                        HeaderQuantizeTicksView(piste: pistes[index], trackHeight: trackHeight)
                            .equatable()
                            // Right edge stays at 150, level with where the gray
                            // ticks end (144 + tickWidth); left edge pulled back
                            // so it lines up with where the gray dash would be.
                            .frame(width: 15, height: trackHeight, alignment: .topLeading)
                            .offset(x: 135)
                    }
                }
            }
            .frame(width: 210, height: rowHeight(for: pistes[index]), alignment: .topLeading)
            Rectangle().fill(Color.clear).frame(height: 5)
        }
    }

    @ViewBuilder
    func trackRowContent(index: Int, largeurTimeline: CGFloat) -> some View {
        if index != 0 || showMarkersTrack {
            HStack(spacing: 0) {
                // Reserves exactly the same 140pt the row's header used to
                // occupy here, so largeurTimeline and every absolute-content
                // x-coordinate elsewhere (ruler ticks, grid, playhead,
                // TrackContentColumn's own point math) stay untouched — the
                // real, interactive header now lives only in the pinned
                // column to the left of the whole scroll view, so this slot
                // just needs to keep reserving its width, not draw anything.
                // Explicit height too, not just width: a bare Color/Shape
                // left without a height constraint is flexible, and in a
                // VStack proposed more total height than its fixed-size rows
                // actually need (contentHeight can exceed totalTracksHeight,
                // e.g. a short timeline in a tall window), a flexible child
                // greedily expands to soak up the leftover space — ballooning
                // this whole row (an HStack reports the max of its children's
                // heights) even though TrackContentColumn itself stays
                // pinned at rowHeight. That's what was pushing the content
                // rows out of alignment with the pinned header column, whose
                // rows stayed correctly sized since TrackHeaderColumn has no
                // such unconstrained sibling. Matching rowHeight here exactly
                // (not just width) keeps this placeholder just as rigid.
                Color.clear
                    .frame(width: 140, height: rowHeight(for: pistes[index]))
                    .allowsHitTesting(false)
                TrackContentColumn(
                    timelineStore: timelineStore,
                    pointDrag: pointDrag,
                    pointEditing: pointEditing,
                    selection: selection,
                    pasteClipboard: pasteClipboard,
                    transport: transport,
                    uiChrome: uiChrome,
                    index: index,
                    largeurTimeline: largeurTimeline,
                    onBeginCreatingPoint: { location, trackIndex, width in
                        beginCreatingPoint(at: location, trackIndex: trackIndex, largeurTimeline: width)
                    },
                    onUpdateCreatingPoint: { location, width in
                        updateCreatingPoint(at: location, largeurTimeline: width)
                    },
                    onFinishCreatingPoint: {
                        finishCreatingPoint()
                    },
                    onToggleSegmentEnabled: { time, trackIndex in
                        toggleSegmentEnabled(forTime: time, trackIndex: trackIndex)
                    },
                    onBeginEditingPoint: { eventId in
                        beginEditingPoint(eventId: eventId)
                    },
                    onPasteDragEnded: { value, trackIndex, width in
                        handlePasteDragEnded(value, trackIndex: trackIndex, largeurTimeline: width)
                    }
                )
            }
            .offset(y: trackDragReorder.reorderingIndex == index ? trackDragReorder.reorderDragTranslation : 0)
            .zIndex(trackDragReorder.reorderingIndex == index ? 1 : 0)
            .opacity(trackDragReorder.reorderingIndex == index ? 0.85 : 1.0)
            .onHover { hovering in
                // Same belt-and-suspenders as TrackRow used to do for the
                // whole row: if the mouse leaves this track's content area
                // without passing back through the curve area's own hover
                // handler, make sure the segment-erase cursor doesn't stay
                // stuck on.
                if !hovering && pointDrag.isNearCurveControlZone {
                    pointDrag.isNearCurveControlZone = false
                    pointDrag.updateCursor(pasteModeActive: pasteClipboard.isPasteModeActive, magneticGridSnap: magneticGridSnap)
                }
            }
            Rectangle().fill(Color.clear).frame(height: 5)
        }
    }
}
