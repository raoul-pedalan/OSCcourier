import SwiftUI

// Extracted out of ContentView.swift's `body` because inlining this whole
// chunk (pinned header column + TimelineScrollView + its GeometryReader/
// ZStack/ForEach content + 4 onChange modifiers) there, alongside the
// already-nontrivial ruler block, pushed the type-checker over its
// complexity budget ("unable to type-check this expression in reasonable
// time"). Split into three separate functions/properties rather than one
// big one, for extra headroom — same reasoning that already motivated
// pulling TrackRow/TrackHeaderColumn/TrackContentColumn out as their own
// real View types instead of being computed inline.
extension ContentView {
    // The pinned header column beside the scrolling timeline area.
    @ViewBuilder
    func tracksArea(outerGeometry: GeometryProxy, rulerStripTotalHeight: CGFloat) -> some View {
        // The height actually available below the pinned ruler strip. Both
        // panes are pinned to exactly this, rather than being left to
        // negotiate their own heights: the header column's natural height is
        // the FULL stack of tracks (often far taller than the window), and
        // letting it report that made the HStack that tall too — whereupon
        // the scroll view, which reports only its own viewport height, got
        // vertically CENTERED inside that oversized row (HStack's default
        // alignment). That centering was the mystery offset: every track's
        // content sat exactly (tracksHeight - viewportHeight)/2 lower than
        // its header. alignment: .top removes the centering; the explicit
        // height below stops the row overflowing the window in the first
        // place.
        let availableHeight = max(outerGeometry.size.height - rulerStripTotalHeight, 0)

        // A ZStack, NOT an HStack side-by-side: the scroll view spans the
        // FULL width (exactly as it did before the header column was
        // pinned), and the header column is drawn ON TOP of its leftmost
        // 140pt. Laying the two out side by side instead shifted the whole
        // scrolling pane 140pt to the right — while its content still
        // reserves its own 140pt slot internally (see trackRowContent), and
        // while the ruler strip above still spans the full width from x=0.
        // The result was every timeline x-coordinate landing 140pt right of
        // the matching ruler tick (visible as the playhead splitting in two
        // between the ruler and the tracks). Overlaying keeps the scroll
        // view's coordinate space byte-for-byte identical to what the ruler,
        // grid, playhead and every track's point math already assume, so the
        // pinning costs no coordinate changes anywhere. It also gives the
        // right behaviour for free: content panned leftwards slides UNDER
        // the opaque header column rather than beside it, the way a DAW's
        // frozen track headers work.
        ZStack(alignment: .topLeading) {
            timelineScrollArea(outerGeometry: outerGeometry, rulerStripTotalHeight: rulerStripTotalHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            pinnedTrackHeaderColumn(availableHeight: availableHeight)
        }
        .frame(height: availableHeight, alignment: .top)
    }

    // Track-header column, pinned at the left: unlike the ruler (which
    // still shifts horizontally with the zoomed/panned content, just
    // clipped to a fixed window), this one doesn't live inside
    // TimelineScrollView's NSScrollView at all — it's a separate view that
    // only tracks the *vertical* scroll TimelineScrollView publishes back
    // out via transport.scrollOffsetY, so it stays fixed horizontally no
    // matter how far zoomed/panned the timeline is, while still scrolling
    // vertically in lockstep with whichever tracks are currently in view.
    // Same "big content, shifted, clipped to a window" trick as the ruler,
    // just on the Y axis.
    func pinnedTrackHeaderColumn(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(pistes.enumerated()), id: \.element.id) { index, _ in
                trackRowHeader(index: index)
            }
        }
        .frame(width: 140, alignment: .top)
        .offset(y: -transport.scrollOffsetY)
        // Hard-pinned to the viewport's height (not maxHeight: .infinity,
        // which still lets this report the full tracks-stack height upward
        // and blow the row's layout out — see tracksArea above), then
        // clipped, so only the currently-scrolled-to slice of headers shows.
        .frame(width: 140, height: availableHeight, alignment: .top)
        // Opaque: this now sits OVER the scroll view (see tracksArea), and
        // the 5pt gaps between header rows are clear — without a backing
        // colour, timeline content panned underneath would show through them
        // as moving slivers.
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
    }

    func timelineScrollArea(outerGeometry: GeometryProxy, rulerStripTotalHeight: CGFloat) -> some View {
        TimelineScrollView(
            offsetX: $transport.scrollOffsetX,
            offsetY: $transport.scrollOffsetY,
            zoomX: $transport.zoomX,
            isPinchZooming: $transport.isPinchZooming,
            zoomRange: 1.0...maxZoomX,
            duree: transport.duree,
            contentWidth: outerGeometry.size.width * CGFloat(transport.zoomX),
            contentHeight: max(outerGeometry.size.height - rulerStripTotalHeight, totalTracksHeight),
            zoomSensitivity: zoomKnobSensitivity
        ) {
            tracksContent(outerGeometry: outerGeometry)
        }
        .onChange(of: transport.zoomX) { oldZoom, newZoom in
            recenterOnZoomChange(oldZoom: oldZoom, newZoom: newZoom, outerWidth: outerGeometry.size.width)
        }
        .onAppear {
            transport.timelineAreaWidth = outerGeometry.size.width
        }
        .onChange(of: outerGeometry.size.width) { _, newWidth in
            transport.timelineAreaWidth = newWidth
            transport.zoomX = min(transport.zoomX, maxZoomX)
        }
        .onChange(of: transport.duree) { _, _ in
            transport.zoomX = min(transport.zoomX, maxZoomX)
        }
    }

    // NOTE: do NOT subtract durationHandleWidth here. The playhead, grid
    // and marker lines are drawn in the outer coordinate space (offset by
    // +140) while the points live inside each track's own space — both
    // derive from this same largeurTimeline, so shrinking it here
    // desynchronised them (playhead/grid drifted left of the points). The
    // handle's 18px are reserved on the container instead, further down,
    // which keeps a single consistent scale.
    //
    // Still 140 here (not 0), even though the real header now lives in the
    // pinned column above rather than inside this scroll view:
    // trackRowContent still reserves an invisible 140pt slot per row (see
    // ContentView+TrackRow.swift) so this value keeps matching every other
    // absolute-content x-coordinate elsewhere unchanged.
    func tracksContent(outerGeometry: GeometryProxy) -> some View {
        GeometryReader { geometry in
            let largeurTimeline = geometry.size.width - 140
            let totalHeight = visiblePistes.reduce(CGFloat(0)) { $0 + rowHeight(for: $1) } + CGFloat(visiblePistes.count * 5)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(Array(pistes.enumerated()), id: \.element.id) { index, _ in
                        trackRowContent(index: index, largeurTimeline: largeurTimeline)
                    }
                }

                markersGridAndPlayhead(largeurTimeline: largeurTimeline, totalHeight: totalHeight)
            }
        }
        .frame(width: outerGeometry.size.width * CGFloat(transport.zoomX))
    }
}
