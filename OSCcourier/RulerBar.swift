import SwiftUI

/// The time ruler bar above the tracks: the loop-zone band (and its live
/// drag preview), the lock toggle, and the tick marks/labels (masked so
/// they never spill over the 140px track-header column).
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
    @ObservedObject var uiChrome: UIChromeState

    let largeurTimeline: CGFloat
    let outerWidth: CGFloat
    let geometryWidth: CGFloat

    // enBoucle lives on transport, tracksLocked on uiChrome — both
    // per-window ObservableObjects passed in above, rather than each
    // reading its own @AppStorage straight from UserDefaults (which used
    // to mean every open OSCcourier window shared the same Loop/Lock
    // state instead of each window having its own).
    private var enBoucle: Bool { transport.enBoucle }
    private var tracksLocked: Bool { uiChrome.tracksLocked }

    let onHover: (HoverPhase) -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onDoubleClick: () -> Void
    let onSelectPointsInLoopZone: () -> Void
    let onTimeOffsetSelection: () -> Void

    var body: some View {
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
            if tracksLocked {
                Rectangle().fill(Color.black).frame(width: 140, height: 24)
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
            Button(action: { uiChrome.tracksLocked.toggle() }) {
                Image(systemName: tracksLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 18))
                    .foregroundColor(tracksLocked ? .red : .gray)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .help(tracksLocked ? "Tracks are locked (⌘L)" : "Tracks are unlocked (⌘L)")
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
    }
}
