import SwiftUI
import AppKit

/// The right-hand timeline column of a single track row: background,
/// quantization grid lines, the point-creation background gesture (per
/// track type), the curve/step path drawing, every point's marker +
/// drag/tap gestures, the lasso overlay, and paste-mode handling.
///
/// A real `View` rather than a `ContentView` method, so each track's
/// content gets its own SwiftUI identity for diffing. Most gesture
/// handlers are called directly on the state object that owns them
/// (PointDragState, SelectionState, PasteClipboardState); the handful
/// that reach into the point-editing/undo logic in
/// ContentView+PointEditing.swift are passed in as closures, since that
/// logic stays together as one unit rather than being split apart.
/// `pistes` mirrors ContentView's own bridge onto `timelineStore`
/// exactly (same undo-registering setter via `setPistes`).
struct TrackContentColumn: View {
    @ObservedObject var timelineStore: TimelineStore
    @ObservedObject var pointDrag: PointDragState
    @ObservedObject var pointEditing: PointEditingState
    @ObservedObject var selection: SelectionState
    @ObservedObject var pasteClipboard: PasteClipboardState
    @ObservedObject var transport: TransportState
    @ObservedObject var uiChrome: UIChromeState

    let index: Int
    let largeurTimeline: CGFloat

    // These three used to be @AppStorage, read straight from
    // UserDefaults — shared by every open OSCcourier window instead of
    // being per-window. Now proxy to uiChrome (already threaded in above,
    // per-window on ContentView).
    private var tracksLocked: Bool { uiChrome.tracksLocked }
    private var showGrid: Bool { uiChrome.showGrid }
    private var showPointCoordinates: Bool { uiChrome.showPointCoordinates }
    @AppStorage("magneticGridSnap") private var magneticGridSnap: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    let onBeginCreatingPoint: (CGPoint, Int, CGFloat) -> Void
    let onUpdateCreatingPoint: (CGPoint, CGFloat) -> Void
    let onFinishCreatingPoint: () -> Void
    let onToggleSegmentEnabled: (Double, Int) -> Void
    let onBeginEditingPoint: (UUID) -> Void
    let onPasteDragEnded: (DragGesture.Value, Int, CGFloat) -> Void

    private var pistes: [TimelineTrack] {
        get { timelineStore.pistes }
        nonmutating set { timelineStore.setPistes(newValue) }
    }

    // Same 0.3/0.18 track-background tint as ContentView's own
    // trackBackgroundOpacity — dark backgrounds need it pulled back so it
    // doesn't read too saturated.
    private var trackBackgroundOpacity: Double {
        colorScheme == .dark ? 0.18 : 0.3
    }

    // Right-click menu — same content on all three background gesture
    // layers below (bang/message, curve, step), so it's available
    // regardless of where on the track's empty background the user
    // right-clicks.
    @ViewBuilder
    private var selectAllTrackPointsMenuItem: some View {
        Button("Select All Track Points") {
            selection.selectAllPoints(onTrack: pistes[index])
        }
        Button("Time Offset Selection…") {
            uiChrome.timeOffsetString = "0.0"
            uiChrome.showTimeOffsetPopup = true
        }
        .disabled(selection.selectedPointIDs.isEmpty)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(pistes[index].type != .normal ? pistes[index].couleur.opacity(trackBackgroundOpacity) : Color.clear)
                .frame(width: largeurTimeline, height: rowHeight(for: pistes[index]))

            // Quantization lines, drawn across the full width of the track.
            // They live HERE, in the track's own container (which is already
            // largeurTimeline wide), and not in the header ZStack alongside
            // the range labels — widening that one to timeline width
            // overflowed its 140px slot and wrecked the row's layout.
            if !pistes[index].isFolded,
               pistes[index].type == .curve || pistes[index].type == .step,
               !pistes[index].isGate,
               pistes[index].quantizeActive {
                ContentQuantizeGridLinesView(
                    piste: pistes[index],
                    trackHeight: rowHeight(for: pistes[index]),
                    largeurTimeline: largeurTimeline
                )
                .equatable()
            }

            if !pistes[index].isFolded {
            if pistes[index].type == .bang || pistes[index].type == .message {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: largeurTimeline, height: rowHeight(for: pistes[index]))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // ⇧⌥ is the lasso-selection gesture (handled
                                // elsewhere as a .simultaneousGesture on this same
                                // track) — never create a point for it.
                                guard !(NSEvent.modifierFlags.contains(.shift) && NSEvent.modifierFlags.contains(.option)), !pasteClipboard.isPasteModeActive else { return }
                                if pointEditing.creatingPointId == nil {
                                    onBeginCreatingPoint(value.startLocation, index, largeurTimeline)
                                }
                                onUpdateCreatingPoint(value.location, largeurTimeline)
                            }
                            .onEnded { _ in
                                onFinishCreatingPoint()
                            }
                    )
                    .contextMenu { selectAllTrackPointsMenuItem }
            } else if pistes[index].type == .curve {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: largeurTimeline, height: pistes[index].height)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !tracksLocked else { return }
                                // Shift near the curve line means "toggle this
                                // segment's hole", and Option means "bend the
                                // segment" (handled by its own gesture) — neither
                                // should create a point.
                                if NSEvent.modifierFlags.contains(.shift) { return }
                                if NSEvent.modifierFlags.contains(.option) { return }
                                if pasteClipboard.isPasteModeActive { return }
                                if pointEditing.creatingPointId == nil {
                                    onBeginCreatingPoint(value.startLocation, index, largeurTimeline)
                                }
                                onUpdateCreatingPoint(value.location, largeurTimeline)
                            }
                            .onEnded { value in
                                guard !tracksLocked else { return }
                                if pointEditing.creatingPointId != nil {
                                    onFinishCreatingPoint()
                                    return
                                }
                                // No point was being created: this was a Shift
                                // click on (or near) the curve line.
                                let time = (Double(value.location.x) / Double(largeurTimeline)) * transport.duree
                                if NSEvent.modifierFlags.contains(.shift),
                                   !NSEvent.modifierFlags.contains(.option),
                                   let curveY = curveYPosition(forTime: time, track: pistes[index]) {
                                    let distance = abs(Double(value.location.y) - Double(curveY))
                                    let threshold: Double = isSegmentEnabled(forTime: time, track: pistes[index]) ? 12 : 24
                                    if distance < threshold {
                                        onToggleSegmentEnabled(time, index)
                                    }
                                }
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            // Compute everything locally; only write @State when the
                            // value actually changes, so plain mouse movement doesn't
                            // trigger a body re-render per pixel (which is what broke
                            // the hover stream in a previous iteration).
                            let time = (Double(location.x) / Double(largeurTimeline)) * transport.duree
                            let nearZone: Bool
                            if let curveY = curveYPosition(forTime: time, track: pistes[index]) {
                                nearZone = abs(Double(location.y) - Double(curveY)) < 12
                            } else {
                                nearZone = false
                            }
                            if pointDrag.isNearCurveControlZone != nearZone {
                                pointDrag.isNearCurveControlZone = nearZone
                            }
                            // Receiving this hover means the mouse is on the curve
                            // area itself, NOT on a point (points are separate
                            // subviews stacked above; they intercept hover) — so
                            // pointDrag.isHoveringPoint is stale if still true. That stale
                            // true was making updatePointCursor() impose the
                            // delete-point cursor (eraser.badge.xmark) here.
                            if pointDrag.isHoveringPoint {
                                pointDrag.isHoveringPoint = false
                            }
                        case .ended:
                            if pointDrag.isNearCurveControlZone {
                                pointDrag.isNearCurveControlZone = false
                            }
                        }
                    }
                    // Attached simultaneously (not exclusively) so it never
                    // blocks the plain tap-to-add-point gesture above; it only
                    // actually does anything once Option is held and the drag
                    // exceeds the minimum distance.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                pointDrag.handleCurveBendDragChanged(value, trackIndex: index, largeurTimeline: largeurTimeline, pistes: &pistes, duree: transport.duree)
                            }
                            .onEnded { _ in
                                pointDrag.handleCurveBendDragEnded()
                            }
                    )
                    .contextMenu { selectAllTrackPointsMenuItem }

                // Purely cosmetic cursor layer: uses AppKit's own cursor-rect
                // system (reliable even during plain hover, unlike NSCursor.set()
                // calls) to show the bend cursor whenever near the curve with
                // Option held. allowsHitTesting(false) so it never intercepts
                // clicks/drags — those stay on the Color.clear view above.
                CursorOverlay(
                    isActive: pointDrag.isNearCurveControlZone && pointDrag.isOptionHeldForCursor && !pointDrag.isShiftHeldForCursor,
                    symbolName: "point.bottomleft.forward.to.point.topright.filled.scurvepath"
                )
                .frame(width: largeurTimeline, height: pistes[index].height)
                .allowsHitTesting(false)

                // Same AppKit cursor-rect mechanism as the bend cursor above,
                // but with a dynamic resolver: the symbol depends on where
                // (in time) the mouse currently is — eraser over a live
                // segment near the line, pencil anywhere within a disabled
                // one (no line drawn there to aim at), nothing otherwise.
                // This replaced an imperative NSCursor.set() call driven by
                // SwiftUI's onContinuousHover, which turned out not to fire
                // reliably while a modifier key was held down during mouse
                // movement.
                CursorOverlay(
                    isActive: pointDrag.isShiftHeldForCursor && !pointDrag.isOptionHeldForCursor && !tracksLocked && !pasteClipboard.isPasteModeActive,
                    dynamicSymbol: { point in
                        let time = (Double(point.x) / Double(largeurTimeline)) * transport.duree
                        guard let curveY = curveYPosition(forTime: time, track: pistes[index]) else { return nil }
                        let distance = abs(Double(point.y) - Double(curveY))
                        if !isSegmentEnabled(forTime: time, track: pistes[index]) {
                            // Disabled segment (a "hole"): nothing is drawn to
                            // aim at, so a more generous band than the live
                            // segment's counts as close enough to reconnect.
                            return distance < 24 ? ("pencil.tip.crop.circle.badge.plus", .black) : nil
                        } else {
                            return distance < 12 ? ("eraser.badge.xmark", .black) : nil
                        }
                    }
                )
                .frame(width: largeurTimeline, height: pistes[index].height)
                .allowsHitTesting(false)
            } else if pistes[index].type == .step {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: largeurTimeline, height: pistes[index].height)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // ⇧⌥ is the lasso-selection gesture (handled
                                // elsewhere as a .simultaneousGesture on this same
                                // track) — never create a point for it.
                                guard !(NSEvent.modifierFlags.contains(.shift) && NSEvent.modifierFlags.contains(.option)), !pasteClipboard.isPasteModeActive else { return }
                                if pointEditing.creatingPointId == nil {
                                    onBeginCreatingPoint(value.startLocation, index, largeurTimeline)
                                }
                                onUpdateCreatingPoint(value.location, largeurTimeline)
                            }
                            .onEnded { _ in
                                onFinishCreatingPoint()
                            }
                    )
                    .contextMenu { selectAllTrackPointsMenuItem }
            }

            if pistes[index].type == .curve && pistes[index].evenements.count > 1 {
                CurvePathView(
                    events: pistes[index].evenements,
                    minAmplitude: pistes[index].minAmplitude,
                    maxAmplitude: pistes[index].maxAmplitude,
                    duree: transport.duree,
                    largeurTimeline: largeurTimeline,
                    height: pistes[index].height
                )
                .equatable()
            }

            if pistes[index].type == .step && pistes[index].evenements.count > 1 {
                StepPathView(
                    events: pistes[index].evenements,
                    minAmplitude: pistes[index].minAmplitude,
                    maxAmplitude: pistes[index].maxAmplitude,
                    duree: transport.duree,
                    largeurTimeline: largeurTimeline,
                    height: pistes[index].height
                )
                .equatable()
            }

            ForEach(pistes[index].evenements) { event in
                let xPos = CGFloat(event.time / transport.duree) * largeurTimeline
                let amplitudeRange = pistes[index].maxAmplitude - pistes[index].minAmplitude
                let normalizedY = amplitudeRange > 0 ? (event.y - pistes[index].minAmplitude) / amplitudeRange : 0.5
                let pointY = (pistes[index].type == .curve || pistes[index].type == .step) ? curveMargin + (pistes[index].height - 2 * curveMargin) * (1 - normalizedY) : (index == 0 ? 22 : 15)

                if (pistes[index].type == .bang && index != 0) || pistes[index].type == .message {
                    Rectangle()
                        .fill(pistes[index].couleur)
                        .frame(width: 1, height: 45)
                        .position(x: xPos, y: 22.5)
                        .opacity(0.5)
                }

                VStack(spacing: 0) {
                    if index == 0 {
                        ZStack {
                            Rectangle()
                .fill(selection.selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
                                .frame(width: 6, height: 6)

                            if showPointCoordinates {
                                Text(String(format: "%.2f", event.time) + "s")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .offset(y: 12)
                            }
                        }
                        .overlay(alignment: .top) {
                            Text(event.label)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .fixedSize()
                                .offset(y: showPointCoordinates ? -12 : -16)
                        }
                        // Label-to-square gap stays fixed (via the overlay above);
                        // this shifts the whole rigid group down a bit when the
                        // coordinate text is hidden, so it stays roughly centered
                        // in the track rather than sitting high with empty space
                        // below it.
                        .offset(y: showPointCoordinates ? 0 : 6)
                    } else {
                        if pistes[index].type == .message {
                            Text(event.label)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                                .offset(y: 3)

                            ZStack {
                                Text("T")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(selection.selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)

                                if showPointCoordinates {
                                    Text(String(format: "%.2f", event.time) + "s")
                                        .font(.caption2)
                                        .foregroundColor(.black)
                                        .offset(y: 12)
                                }
                            }
                        } else if pistes[index].type == .bang {
                            Rectangle()
                            .fill(selection.selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
                                .frame(width: 8, height: 8)
                                .rotationEffect(.degrees(45))

                            if showPointCoordinates {
                                Text(String(format: "%.2f", event.time) + ", " + String(format: "%.2f", event.y))
                                    .font(.caption2)
                                    .foregroundColor(.black)
                                    .offset(y: 12)
                            }
                        } else {
                            // Curve/step point: anchor the label to the marker itself
                            // via an overlay (rather than stacking it in the VStack),
                            // so flipping it above/below doesn't shift where the
                            // marker sits relative to the path.
                            let labelAbove = normalizedY < 0.5
                            Group {
                                if pistes[index].type == .step {
                                    if pistes[index].isGate {
                                        Rectangle()
                                        .stroke(selection.selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur, lineWidth: 2.5)
                                            .frame(width: 10, height: 10)
                                            .contentShape(Rectangle())
                                    } else {
                                        ZStack {
                                            Rectangle()
                                            .fill(selection.selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
                                                .frame(width: 17, height: 3)
                                                .rotationEffect(.degrees(45))
                                            Rectangle()
                                            .fill(selection.selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
                                                .frame(width: 17, height: 3)
                                                .rotationEffect(.degrees(-45))
                                        }
                                        .frame(width: 17, height: 17)
                                        .contentShape(Rectangle())
                                    }
                                } else {
                                    Circle()
                                .fill(selection.selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
                                        .frame(width: 12, height: 12)
                                }
                            }
                            .overlay(alignment: labelAbove ? .top : .bottom) {
                                if showPointCoordinates {
                                    Text(String(format: "%.2f", event.time) + ", " + String(format: "%.2f", event.y))
                                        .font(.caption2)
                                        .foregroundColor(.black)
                                        .fixedSize()
                                        .offset(y: labelAbove ? -12 : 12)
                                }
                            }
                        }
                    }
                }
                .position(x: xPos, y: pointY)
                .onHover { hovering in
                    pointDrag.isHoveringPoint = hovering
                    // A point is a separate subview stacked above the curve
                    // line; moving onto it should stop the curve area from
                    // being considered "hovered" for cursor purposes.
                    if pointDrag.isNearCurveControlZone {
                        pointDrag.isNearCurveControlZone = false
                    }
                    if hovering {
                        pointDrag.isNearSnapZone = isNearMarker(markersTrack: pistes[0], showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: Double(xPos), largeurTimeline: Double(largeurTimeline))
                        pointDrag.isNearGridSnapZone = nearestGridTime(showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: Double(xPos), largeurTimeline: Double(largeurTimeline)) != nil
                        pointDrag.isNearestSnapGrid = isNearestSnapAGridLine(markersTrack: pistes[0], showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: Double(xPos), largeurTimeline: Double(largeurTimeline))
                    }
                    pointDrag.updateCursor(pasteModeActive: pasteClipboard.isPasteModeActive, magneticGridSnap: magneticGridSnap)
                }
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            pointDrag.handlePointDragChanged(
                                value, eventID: event.id, trackIndex: index, largeurTimeline: largeurTimeline,
                                pistes: &pistes, selection: selection, pasteClipboard: pasteClipboard,
                                uiChrome: uiChrome, transport: transport,
                                showGrid: showGrid, magneticGridSnap: magneticGridSnap, tracksLocked: tracksLocked
                            )
                        }
                        .onEnded { _ in
                            pointDrag.handlePointDragEnded(trackIndex: index, pistes: &pistes, selection: selection)
                        }
                )
                .onTapGesture(count: 1) {
                    pointDrag.handlePointTap(eventID: event.id, trackIndex: index, pistes: &pistes, selection: selection, tracksLocked: tracksLocked)
                }
                .onTapGesture(count: 2) {
                    onBeginEditingPoint(event.id)
                }
            }
            } // end if !pistes[index].isFolded
            else {
                foldedGhostTrace(for: pistes[index], largeurTimeline: largeurTimeline, duree: transport.duree)
            }
        }
        .frame(width: largeurTimeline, height: rowHeight(for: pistes[index]))
        .clipped()
        .overlay(alignment: .topLeading) {
            // Visual feedback while dragging — only drawn on the track the
            // lasso actually started on.
            if selection.lassoTrackIndex == index,
               let start = selection.lassoStartLocation,
               let current = selection.lassoCurrentLocation {
                let rect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 1))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }
        }
        // Idle-hover cursor for lasso-selection mode (⇧⌥ held, not yet
        // dragging) — the imperative .set() call inside the drag gesture
        // above takes over once the drag actually starts. Also doubles as
        // the paste-mode cursor (red, no drag needed to trigger it).
        .overlay {
            CursorOverlay(
                isActive: (pointDrag.isShiftHeldForCursor && pointDrag.isOptionHeldForCursor && !tracksLocked) || pasteClipboard.isPasteModeActive,
                symbolName: pasteClipboard.isPasteModeActive && (pointDrag.isNearSnapZone || pointDrag.isNearGridSnapZone)
                    ? "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left"
                    : "dot.crosshair",
                color: pasteClipboard.isPasteModeActive ? .red : .black
            )
            .allowsHitTesting(false)
        }
        // While in paste mode, track snap proximity continuously (same
        // candidates as a point drag) so the cursor reflects where a
        // click-up would actually land, before the user even clicks.
        .onContinuousHover { phase in
            pasteClipboard.handlePasteHover(
                phase: phase, largeurTimeline: largeurTimeline, markersTrack: pistes[0],
                showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase,
                duree: transport.duree, magneticGridSnap: magneticGridSnap, pointDrag: pointDrag
            )
        }
        // ⌥⇧-drag lassos points on THIS track only — attached as
        // .simultaneousGesture (not .gesture) so it never blocks the
        // ordinary click-to-create-point / drag-to-move-point gestures
        // underneath; it only actually does anything once both modifiers
        // are held.
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { value in
                    selection.handleLassoDragChanged(value, trackIndex: index, largeurTimeline: largeurTimeline, tracksLocked: tracksLocked, isPasteModeActive: pasteClipboard.isPasteModeActive)
                }
                .onEnded { value in
                    selection.handleLassoDragEnded(value, trackIndex: index, largeurTimeline: largeurTimeline, piste: pistes[index], duree: transport.duree)
                }
        )
        // Paste-mode click: minimumDistance 0 so a plain click and a
        // click-drag both land here, using the release location either
        // way — a plain click pastes right there, a click-drag pastes
        // wherever it ended (with the same Cmd/grid snap as a point drag).
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    pasteClipboard.handlePasteDragChanged(
                        value, largeurTimeline: largeurTimeline, markersTrack: pistes[0],
                        showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase,
                        duree: transport.duree, magneticGridSnap: magneticGridSnap, pointDrag: pointDrag
                    )
                }
                .onEnded { value in
                    onPasteDragEnded(value, index, largeurTimeline)
                }
        )
    }
}
