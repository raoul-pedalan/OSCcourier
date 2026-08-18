import SwiftUI
import AppKit

// Everything drawn in the outer timeline ZStack besides the ruler+tracks
// VStack: the gray marker lines, the optional grid overlay, the thin
// click-to-scrub strip above the ruler, and the playhead itself (line +
// triangle + drag/double-click handling).
//
// Deliberately NOT extracted into a `struct ... : View` like RulerBar was:
// the marker lines and the playhead position themselves with `.position()`
// and `.offset()`, which resolve against the coordinate space of their
// direct parent — the outer ZStack in `body`. Wrapping them in their own
// View would insert an intermediate container that sizes to its content
// rather than filling that same space, silently shifting where every one
// of these lands. Kept as a @ViewBuilder function so they stay direct
// children of that ZStack.
extension ContentView {
    @ViewBuilder
    func markersGridAndPlayhead(largeurTimeline: CGFloat, totalHeight: CGFloat) -> some View {
        // Gray vertical lines for each marker on the "markers" track,
        // drawn here (outside the .clipped() area of each individual track)
        // so they can span through all the tracks below.
        ForEach(pistes[0].evenements) { event in
            let xPos = CGFloat(event.time / transport.duree) * largeurTimeline + 140
            Rectangle()
                .fill(pistes[0].couleur)
                .frame(width: 1, height: CGFloat(totalHeight) - 15)
                .position(x: xPos, y: (15 + CGFloat(totalHeight)) / 2)
                .opacity(0.5)
                .allowsHitTesting(false)
        }

        // Grid overlay: evenly spaced dashed vertical lines across all
        // tracks (period/phase set via double-clicking the grid button),
        // same span as the marker lines above but dashed and purely visual.
        if showGrid {
            ForEach(visibleGridLineTimes(gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, largeurTimeline: largeurTimeline), id: \.self) { time in
                let xPos = CGFloat(time / transport.duree) * largeurTimeline + 140
                Path { path in
                    path.move(to: CGPoint(x: xPos, y: 15))
                    path.addLine(to: CGPoint(x: xPos, y: CGFloat(totalHeight)))
                }
                .stroke(Color.gray.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .allowsHitTesting(false)
            }
        }

        // Moving the playhead by click lives here, in a thin strip right
        // above the ruler (roughly the height of the playhead triangle) —
        // not on the ruler itself, which is dedicated entirely to the loop
        // zone. Added BEFORE the triangle below so the triangle (added
        // later, on top in z-order) keeps first dibs on hit-testing over
        // its own small area — otherwise this band would swallow every
        // click/double-click meant for the triangle itself.
        // Same full-width + x>140 guard pattern as the ruler's own gesture
        // (rather than a narrower frame + .offset), since .offset doesn't
        // reliably shift a gesture's reported location the same way it
        // shifts the view visually — this proven pattern avoids that trap.
        DiagonalStripes(stripeWidth: 3, spacing: 3)
            .stroke(Color.gray.opacity(0.5), lineWidth: 3)
            .frame(height: 15)
            .offset(y: -15)
            .allowsHitTesting(false)
        Color.clear
            .contentShape(Rectangle())
            .frame(height: 15)
            .offset(y: -15)
            .onTapGesture { location in
                guard location.x > 140 else { return }
                let clicked = (Double(location.x - 140) / Double(largeurTimeline)) * transport.duree
                transport.position = min(max(clicked, 0), transport.duree)
                sendOSCMessagesForPosition(transport.position)
            }

        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.red).frame(width: 2, height: CGFloat(totalHeight))
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
        .contentShape(Path(CGRect(x: -8, y: -14, width: 16, height: CGFloat(totalHeight) + 14)))
        .offset(x: CGFloat(transport.position / transport.duree) * largeurTimeline + 140)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let xPos = Double(value.location.x - 140)
                    var newPosition = (xPos / Double(largeurTimeline)) * transport.duree
                    // ⌘ snaps the playhead to the nearest marker/grid
                    // line — the same snap zone and candidates a point
                    // drag uses, so the two behave identically.
                    if NSEvent.modifierFlags.contains(.command),
                       let snapped = nearestSnapTime(markersTrack: pistes[0], showGrid: showGrid, gridPeriod: uiChrome.gridPeriod, gridPhase: uiChrome.gridPhase, duree: transport.duree, xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
                        newPosition = snapped
                    }
                    transport.position = min(max(newPosition, 0), transport.duree)
                    sendOSCMessagesForPosition(transport.position)
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                // simultaneousGesture (not .onTapGesture): the drag
                // above uses minimumDistance 0, which would otherwise
                // win exclusive recognition and swallow every tap
                // before a double-tap could ever be detected.
                uiChrome.goToTimeString = formattedDuration(transport.position)
                uiChrome.goToMarkerNameString = ""
                pasteClipboard.showPlayheadPositionChoice = true
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
