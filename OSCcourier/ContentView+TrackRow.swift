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
