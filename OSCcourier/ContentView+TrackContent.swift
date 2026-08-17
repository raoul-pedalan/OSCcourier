import SwiftUI
import AppKit

// The right-hand timeline column of a single track row: background,
// quantization grid lines, the point-creation background gesture (per track
// type), the curve/step path drawing, every point's marker + drag/tap
// gestures, the lasso overlay, and paste-mode handling. Split out of
// `body`'s per-track ForEach verbatim — no logic changes. Needs
// `largeurTimeline` explicitly since that's a local computed in body's
// GeometryReader, not a ContentView member. Paired with
// ContentView+TrackHeader.swift via trackRow(index:) in
// ContentView+TrackRow.swift.
extension ContentView {
    func trackContentColumn(index: Int, largeurTimeline: CGFloat) -> some View {
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
                                                    let trackH = rowHeight(for: pistes[index])
                                                    let range = pistes[index].maxAmplitude - pistes[index].minAmplitude
                                                    ForEach(visibleQuantizeTicks(forTrackIndex: index), id: \.self) { value in
                                                        let normalized = range > 0 ? (value - pistes[index].minAmplitude) / range : 0
                                                        let y = curveMargin + (trackH - 2 * curveMargin) * (1 - normalized)
                                                        Rectangle()
                                                            // Fainter than the short header ticks: a full-width line
                                                            // at their opacity would compete with the curve itself.
                                                            .fill(Color.blue.opacity(0.22))
                                                            .frame(width: largeurTimeline, height: 1)
                                                            .offset(y: y - trackH / 2)
                                                    }
                                                    .allowsHitTesting(false)
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
                                                                        beginCreatingPoint(at: value.startLocation, trackIndex: index, largeurTimeline: largeurTimeline)
                                                                    }
                                                                    updateCreatingPoint(at: value.location, largeurTimeline: largeurTimeline)
                                                                }
                                                                .onEnded { _ in
                                                                    finishCreatingPoint()
                                                                }
                                                        )
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
                                                                        beginCreatingPoint(at: value.startLocation, trackIndex: index, largeurTimeline: largeurTimeline)
                                                                    }
                                                                    updateCreatingPoint(at: value.location, largeurTimeline: largeurTimeline)
                                                                }
                                                                .onEnded { value in
                                                                    guard !tracksLocked else { return }
                                                                    if pointEditing.creatingPointId != nil {
                                                                        finishCreatingPoint()
                                                                        return
                                                                    }
                                                                    // No point was being created: this was a Shift
                                                                    // click on (or near) the curve line.
                                                                    let time = (Double(value.location.x) / Double(largeurTimeline)) * transport.duree
                                                                    if NSEvent.modifierFlags.contains(.shift),
                                                                       !NSEvent.modifierFlags.contains(.option),
                                                                       let curveY = curveYPosition(forTime: time, trackIndex: index),
                                                                       abs(Double(value.location.y) - Double(curveY)) < 12 {
                                                                        toggleSegmentEnabled(forTime: time, trackIndex: index)
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
                                                                if let curveY = curveYPosition(forTime: time, trackIndex: index) {
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
                                                                // Direct, imperative cursor control tied to actual
                                                                // mouse movement — no @State involved, so it works
                                                                // regardless of SwiftUI's render cycle.
                                                                if NSEvent.modifierFlags.contains(.shift) && !NSEvent.modifierFlags.contains(.option) {
                                                                    applyShiftSegmentCursor(at: location, trackIndex: index, largeurTimeline: largeurTimeline)
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
                                                                    handleCurveBendDragChanged(value, trackIndex: index, largeurTimeline: largeurTimeline)
                                                                }
                                                                .onEnded { _ in
                                                                    handleCurveBendDragEnded()
                                                                }
                                                        )

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
                                                                        beginCreatingPoint(at: value.startLocation, trackIndex: index, largeurTimeline: largeurTimeline)
                                                                    }
                                                                    updateCreatingPoint(at: value.location, largeurTimeline: largeurTimeline)
                                                                }
                                                                .onEnded { _ in
                                                                    finishCreatingPoint()
                                                                }
                                                        )
                                                }

                                                if pistes[index].type == .curve && pistes[index].evenements.count > 1 {
                                                    Path { path in
                                                        let sortedEvents = pistes[index].evenements.sorted { $0.time < $1.time }
                                                        let amplitudeRange = pistes[index].maxAmplitude - pistes[index].minAmplitude
                                                        func yPos(for value: Double) -> CGFloat {
                                                            let normalizedY = amplitudeRange > 0 ? (value - pistes[index].minAmplitude) / amplitudeRange : 0.5
                                                            // Vertical margin = circle radius, so points at the extreme
                                                            // values (0 or 1) aren't cut off by the .clipped()
                                                            return curveMargin + (pistes[index].height - 2 * curveMargin) * (1 - normalizedY)
                                                        }

                                                        for (i, event) in sortedEvents.enumerated() {
                                                            let xPos = CGFloat(event.time / transport.duree) * largeurTimeline
                                                            let point = CGPoint(x: xPos, y: yPos(for: event.y))
                                                            if i == 0 {
                                                                path.move(to: point)
                                                            } else {
                                                                let previous = sortedEvents[i - 1]
                                                                if !previous.segmentEnabled {
                                                                    // Disabled segment: break the path instead of
                                                                    // drawing a line, leaving a visible gap.
                                                                    path.move(to: point)
                                                                } else if previous.segmentCurve == 0 && previous.segmentBulge == 0 {
                                                                    path.addLine(to: point)
                                                                } else {
                                                                    // Sample the S-curve; x advances linearly with t (time
                                                                    // isn't warped), only the value (y) follows the curve.
                                                                    let steps = 24
                                                                    let previousXPos = CGFloat(previous.time / transport.duree) * largeurTimeline
                                                                    for step in 1...steps {
                                                                        let t = Double(step) / Double(steps)
                                                                        let curvedT = combinedProgress(t, curvature: previous.segmentCurve, bulge: previous.segmentBulge)
                                                                        let x = previousXPos + (xPos - previousXPos) * CGFloat(t)
                                                                        let value = previous.y + (event.y - previous.y) * curvedT
                                                                        path.addLine(to: CGPoint(x: x, y: yPos(for: value)))
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                    .stroke(.yellow, lineWidth: 2)
                                                    .allowsHitTesting(false)
                                                }

                                                if pistes[index].type == .step && pistes[index].evenements.count > 1 {
                                                    Path { path in
                                                        // Staircase (zero-order hold): each value is held until the
                                                        // next event, without interpolation — no diagonal line.
                                                        let sortedEvents = pistes[index].evenements.sorted { $0.time < $1.time }
                                                        let amplitudeRange = pistes[index].maxAmplitude - pistes[index].minAmplitude
                                                        func yPos(for event: TimelineEvent) -> CGFloat {
                                                            let normalizedY = amplitudeRange > 0 ? (event.y - pistes[index].minAmplitude) / amplitudeRange : 0.5
                                                            return curveMargin + (pistes[index].height - 2 * curveMargin) * (1 - normalizedY)
                                                        }
                                                        for (i, event) in sortedEvents.enumerated() {
                                                            let xPos = CGFloat(event.time / transport.duree) * largeurTimeline
                                                            let y = yPos(for: event)
                                                            if i == 0 {
                                                                path.move(to: CGPoint(x: xPos, y: y))
                                                            } else {
                                                                // Horizontal segment (held value) then vertical jump
                                                                path.addLine(to: CGPoint(x: xPos, y: path.currentPoint?.y ?? y))
                                                                path.addLine(to: CGPoint(x: xPos, y: y))
                                                            }
                                                        }
                                                    }
                                                    .stroke(Color(red: 0.608, green: 0.086, blue: 0.365), lineWidth: 3)
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
                                                            pointDrag.isNearSnapZone = isNearMarker(xPos: Double(xPos), largeurTimeline: Double(largeurTimeline))
                                                            pointDrag.isNearGridSnapZone = nearestGridTime(xPos: Double(xPos), largeurTimeline: Double(largeurTimeline)) != nil
                                                            pointDrag.isNearestSnapGrid = isNearestSnapAGridLine(xPos: Double(xPos), largeurTimeline: Double(largeurTimeline))
                                                        }
                                                        updatePointCursor()
                                                    }
                                                    .gesture(
                                                        DragGesture(minimumDistance: 5)
                                                            .onChanged { value in
                                                                handlePointDragChanged(value, eventID: event.id, trackIndex: index, largeurTimeline: largeurTimeline)
                                                            }
                                                            .onEnded { _ in
                                                                handlePointDragEnded(trackIndex: index)
                                                            }
                                                    )
                                                    .onTapGesture(count: 1) {
                                                        handlePointTap(eventID: event.id, trackIndex: index)
                                                    }
                                                    .onTapGesture(count: 2) {
                                                        beginEditingPoint(eventId: event.id)
                                                    }
                                                }
                                                } // end if !pistes[index].isFolded
                                                else {
                                                    foldedGhostTrace(for: pistes[index], largeurTimeline: largeurTimeline)
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
                                                handlePasteHover(phase: phase, largeurTimeline: largeurTimeline)
                                            }
                                            // ⌥⇧-drag lassos points on THIS track only — attached as
                                            // .simultaneousGesture (not .gesture) so it never blocks the
                                            // ordinary click-to-create-point / drag-to-move-point gestures
                                            // underneath; it only actually does anything once both modifiers
                                            // are held.
                                            .simultaneousGesture(
                                                DragGesture(minimumDistance: 3, coordinateSpace: .local)
                                                    .onChanged { value in
                                                        handleLassoDragChanged(value, trackIndex: index, largeurTimeline: largeurTimeline)
                                                    }
                                                    .onEnded { value in
                                                        handleLassoDragEnded(value, trackIndex: index, largeurTimeline: largeurTimeline)
                                                    }
                                            )
                                            // Paste-mode click: minimumDistance 0 so a plain click and a
                                            // click-drag both land here, using the release location either
                                            // way — a plain click pastes right there, a click-drag pastes
                                            // wherever it ended (with the same Cmd/grid snap as a point drag).
                                            .simultaneousGesture(
                                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                                    .onChanged { value in
                                                        handlePasteDragChanged(value, largeurTimeline: largeurTimeline)
                                                    }
                                                    .onEnded { value in
                                                        handlePasteDragEnded(value, trackIndex: index, largeurTimeline: largeurTimeline)
                                                    }
                                            )
    }
}
