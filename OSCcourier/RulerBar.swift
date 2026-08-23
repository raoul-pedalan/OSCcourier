import SwiftUI
import AppKit

/// The time ruler bar above the tracks: the loop-zone band (and its live
/// drag preview) and the tick marks/labels (masked so they never spill
/// over the 140px track-header column). The lock toggle used to live here
/// too, but moved out to ContentView's own fixed pane above the header
/// column (see rulerBar in ContentView.swift) once that pane stopped
/// scrolling with the ruler — this view no longer touches tracksLocked at
/// all.
///
/// A real `View` rather than a `ContentView` method, so SwiftUI gives it
/// its own identity for diffing: it re-renders when the loop zone or
/// transport actually change, instead of every time anything anywhere in
/// ContentView does. Its dependencies are explicit in the signature —
/// the two state objects it observes, the layout widths it can't compute
/// itself, and the ruler gesture handlers (which still live on
/// ContentView, since they reach across into snapping/track data).
struct RulerBar: View {
    @ObservedObject var loopZone: LoopZoneState
    @ObservedObject var transport: TransportState

    let largeurTimeline: CGFloat
    let outerWidth: CGFloat
    let geometryWidth: CGFloat

    // enBoucle lives on transport — a per-window ObservableObject passed
    // in above, rather than reading its own @AppStorage straight from
    // UserDefaults (which used to mean every open OSCcourier window
    // shared the same Loop state instead of each window having its own).
    private var enBoucle: Bool { transport.enBoucle }

    let onHover: (HoverPhase) -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onDoubleClick: () -> Void
    let onSelectPointsInLoopZone: () -> Void
    let onTimeOffsetSelection: () -> Void
    // The click-to-scrub strip and the playhead triangle used to live
    // separately, further down in the scrollable tracks content (see
    // ContentView+MarkersGridPlayhead.swift) — moved here now that the
    // ruler is pinned above the tracks instead of scrolling away with
    // them, so this is the one place the playhead stays reachable however
    // far you've scrolled down.
    let onScrubTap: (CGPoint) -> Void
    let onPlayheadDragChanged: (DragGesture.Value) -> Void
    let onPlayheadDoubleClick: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            // Everything that must occupy exactly the ruler's 24pt band —
            // grouped into its own ZStack, explicitly sized and clipped to
            // that height. Without this, RulerBar's OUTER ZStack sized
            // itself (and centered its children) around whichever child was
            // tallest — usually the tick labels, a point or two taller than
            // 24pt once font metrics are counted — which nudged the loop
            // zone/background rects (fixed at exactly 24pt, top-to-bottom)
            // off-center from the ticks by that same sliver, showing as a
            // gap between the loop zone band and the tick marks/labels it's
            // supposed to sit directly behind. Pinning this group to the
            // top of a hard 24pt frame keeps every one of them flush
            // against the same edge instead of independently centered.
            ZStack(alignment: .leading) {
            Rectangle().fill(Color.gray.opacity(0.1)).frame(height: 24)
            // The loop zone band: matches the Loop button's own colors
            // exactly (solid yellow active, gray when off), so the zone
            // and the button read as one and the same "loop" state.
            if let start = loopZone.loopZoneStart, let end = loopZone.loopZoneEnd {
                let x1 = CGFloat(min(start, end) / transport.duree) * largeurTimeline
                let x2 = CGFloat(max(start, end) / transport.duree) * largeurTimeline
                Rectangle()
                    .fill(enBoucle ? Color.yellow : Color.gray.opacity(0.15))
                    .frame(width: max(x2 - x1, 1), height: 24)
                    .offset(x: 140 + x1)
            } else if let dragStart = loopZone.rulerDragStartTime, let dragCurrent = loopZone.rulerDragCurrentTime {
                // Live preview while dragging out a brand new zone.
                let x1 = CGFloat(min(dragStart, dragCurrent) / transport.duree) * largeurTimeline
                let x2 = CGFloat(max(dragStart, dragCurrent) / transport.duree) * largeurTimeline
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: max(x2 - x1, 1), height: 24)
                    .offset(x: 140 + x1)
            }
            Color.clear
                .contentShape(Rectangle())
                .frame(height: 24)
                .onContinuousHover { phase in
                    onHover(phase)
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            onDragChanged(value)
                        }
                        .onEnded { value in
                            onDragEnded(value)
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        onDoubleClick()
                    }
                )
                .contextMenu {
                    if loopZone.loopZoneStart != nil, loopZone.loopZoneEnd != nil {
                        Button("Edit Loop Zone…") {
                            onDoubleClick()
                        }
                        Divider()
                        Button("Select Points in Time Range (All Tracks)") {
                            onSelectPointsInLoopZone()
                        }
                        Button("Time Offset Selection…") {
                            onTimeOffsetSelection()
                        }
                    }
                }
                .overlay {
                    CursorOverlay(
                        isActive: loopZone.isNearLoopZoneEdge || loopZone.resizingLoopZoneEdge != nil,
                        symbolName: "chevron.left.chevron.right"
                    )
                    .allowsHitTesting(false)
                }
                .help(loopZone.loopZoneStart != nil && loopZone.loopZoneEnd != nil
                      ? "Drag the edges to resize the loop zone, drag the middle to move it, double-click to edit it precisely (toggle looping with C)"
                      : "Drag to create a loop zone (toggle looping with C)")
            // Dynamic tick interval: depends on pixels per second (so it already
            // accounts for zoom, via largeurTimeline), not just the total duration —
            // otherwise, zoomed in a lot on a long track, the interval would represent
            // thousands of pixels and no tick would fall within the visible area.
            let pixelsPerSecond = largeurTimeline / CGFloat(max(transport.duree, 0.001))
            let minPixelSpacing: CGFloat = 100
            let niceIntervals: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
            let labelInterval = niceIntervals.first(where: { CGFloat($0) * pixelsPerSecond >= minPixelSpacing }) ?? (niceIntervals.last ?? 3600)

            // Only generate ticks for the currently visible portion (plus a small
            // buffer), not the whole duration: zoomed in a lot, computing ticks over
            // an entire long track would be both useless (invisible) and costly
            // (tens of thousands of elements).
            let buffer: CGFloat = 200
            let visibleStartSeconde = max(0, Double((transport.scrollOffsetX - buffer - 140) / largeurTimeline) * transport.duree)
            let visibleEndSeconde = min(transport.duree, Double((transport.scrollOffsetX + outerWidth + buffer - 140) / largeurTimeline) * transport.duree)
            let firstTick = max(0, (visibleStartSeconde / labelInterval).rounded(.down) * labelInterval)

            // The ticks are masked so that anything drawn left of the
            // header margin is hidden. A label is centered on its
            // graduation, so the first one ("00:00.00" at t=0) is
            // wider than the space available to its left and would
            // otherwise spill over the track headers. The tick marks
            // and the playhead don't move at all — this only hides
            // the overflow.
            ZStack(alignment: .leading) {
                ForEach(Array(stride(from: firstTick, through: max(firstTick, visibleEndSeconde), by: labelInterval)), id: \.self) { seconde in
                    VStack(spacing: 0) {
                        // The label at t=0 is dropped: centered on its graduation,
                        // it would sit half-over the track headers, and the mask
                        // below just chopped it in half. The tick mark stays.
                        Text(seconde == 0 ? "" : formattedTick(seconde, labelInterval: labelInterval))
                            .font(.caption)
                        Rectangle().fill(Color.gray).frame(width: 1, height: 5)
                    }
                    .frame(width: 70) // fixed, so the center stays exact regardless of label text width
                    .padding(.leading, 140)
                    .offset(x: CGFloat(seconde / transport.duree) * largeurTimeline - 35)

                    // 9 unlabeled intermediate ticks, splitting each labeled
                    // interval into 10 — half the height of the main ticks,
                    // same top edge (right under where the label would be),
                    // so they read as subdivisions rather than a second
                    // competing scale.
                    ForEach(1..<10, id: \.self) { sub in
                        let subSeconde = seconde + labelInterval * Double(sub) / 10
                        if subSeconde <= visibleEndSeconde {
                            VStack(spacing: 0) {
                                Text(" ").font(.caption).opacity(0)
                                Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 1, height: 2.5)
                            }
                            .frame(width: 70)
                            .padding(.leading, 140)
                            .offset(x: CGFloat(subSeconde / transport.duree) * largeurTimeline - 35)
                        }
                    }
                }
            }
            // Pinned to the full available width so the mask below lines
            // up with real coordinates — otherwise the ZStack would size
            // itself to its content and the mask's 140px would land
            // somewhere else entirely.
            .frame(width: geometryWidth, alignment: .leading)
            .mask(
                HStack(spacing: 0) {
                    Color.clear.frame(width: 140)
                    Color.black
                }
            )
            }
            .frame(height: 24, alignment: .top)
            .clipped()

            // Thin click-to-scrub strip right above the tick marks — not on
            // the ruler's own tap area, which is dedicated to the loop
            // zone. Added BEFORE the triangle below so the triangle (added
            // later, on top in z-order) keeps first dibs on hit-testing
            // over its own small area — otherwise this band would swallow
            // every click/double-click meant for the triangle itself.
            DiagonalStripes(stripeWidth: 3, spacing: 3)
                .stroke(Color.gray.opacity(0.5), lineWidth: 3)
                .frame(height: 15)
                // Padded to the same 24pt reference height as the ruler's
                // "core" band (top-aligned) before the offset below. The
                // outer ZStack above centers children vertically by
                // default (alignment: .leading only pins the horizontal
                // axis) — without this, the core band (naturally 24pt)
                // and this 15pt strip get centered independently, landing
                // this strip (24-15)/2 = 4.5pt lower than the offset below
                // assumes. That's exactly the ~4px overlap into the top of
                // the loop zone that kept showing up: the stripe pattern
                // bleeding down over what should have been solid yellow.
                // Padding to 24 first makes this strip's reported size
                // match the core band's, so centering has no effect on
                // either, and the offset below lands it exactly flush.
                .frame(height: 24, alignment: .top)
                .offset(y: -15)
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .frame(height: 15)
                .frame(height: 24, alignment: .top)
                .offset(y: -15)
                .onTapGesture { location in
                    onScrubTap(location)
                }

            // The playhead: a short flagpole through the ruler's own
            // height plus the draggable triangle above it. The line
            // continues on down through the tracks separately (see
            // ContentView+MarkersGridPlayhead.swift) — that half stays
            // purely visual now, since dragging happens up here where the
            // playhead is always reachable.
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.red).frame(width: 2, height: 24)
                Image(systemName: "triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .rotationEffect(.degrees(180))
                    .offset(x: -6, y: -12)
            }
            // .offset() shifts the triangle's RENDERED position but not this
            // ZStack's own hit-testable bounds, which stay anchored to the
            // thin 2pt-wide line — so without this, dragging only worked from
            // the line itself, never from the triangle that visually pokes out
            // above and to the side of it. An explicit Path-based content
            // shape doesn't affect layout size/position (only which region
            // responds to gestures), so the existing offset/coordinate math
            // below is untouched.
            .contentShape(Path(CGRect(x: -8, y: -14, width: 16, height: 24 + 14)))
            .offset(x: CGFloat(transport.position / transport.duree) * largeurTimeline + 140)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onPlayheadDragChanged(value)
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    // simultaneousGesture (not .onTapGesture): the drag
                    // above uses minimumDistance 0, which would otherwise
                    // win exclusive recognition and swallow every tap
                    // before a double-tap could ever be detected.
                    onPlayheadDoubleClick()
                }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
    }
}
