import SwiftUI

// The compact command bar (View menu toggle, ⌘B) and the duration trim
// handle pinned to the timeline's right edge, plus their small text/tooltip
// helpers. Split out from ContentView.swift verbatim — no logic changes.
extension ContentView {

    // Compact alternative to the full toolbar (toggled via the View menu,
    // ⌘B): a full-width bar acting as an extended version of the transport.position
    // display — same black/blue styling, but stretched across the window
    // with the transport.position centered, a play/pause indicator ~50px to its left,
    // and a loop indicator on the right.
    // "Paused" vs "stopped" aren't separately tracked in the app's state
    // (both are just transport.enLecture == false); we approximate "stopped" as
    // transport.enLecture == false with transport.position back at 0 (which Stop always does,
    // unlike Pause), and show nothing in that case per the spec ("rien si
    // stop").
    // Two-tone "Duration mm:ss" label for the compact command bar, built via
    // AttributedString rather than concatenating separate Text views with
    // `+` (deprecated since macOS 26 in favor of string interpolation /
    // AttributedString for per-segment styling).
    var durationLabelText: Text {
        var attributed = AttributedString("Duration ")
        attributed.foregroundColor = .gray
        var value = AttributedString(formattedDuration(transport.duree))
        value.foregroundColor = Color(red: 0.3, green: 0.6, blue: 1.0)
        attributed.append(value)
        return Text(attributed)
    }

    var compactControlBar: some View {
        ZStack {
            Rectangle().fill(Color.black)
            Text(formattedPosition(transport.position))
                .font(.system(size: 20, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    showCommandBar = true
                }
                .help("Current playback position (double-click to show the full command bar, ⌘B)")
            Group {
                if transport.enLecture {
                    Image(systemName: "play.fill")
                        .foregroundColor(Color(red: 0.5, green: 1.0, blue: 0.2))
                } else if transport.position > 0.001 {
                    Image(systemName: "pause.fill")
                        .foregroundColor(.gray)
                }
            }
            .font(.body)
            .offset(x: -100)
            if enBoucle {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.yellow)
                    .font(.body)
                    .offset(x: 100)
            }
            durationLabelText
                .font(.caption2)
                .offset(x: -220)
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                Text("OSC")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundColor(transport.isOSCFlashing ? .yellow : .clear)
            .offset(x: 220)
        }
        .frame(height: 32)
        .padding(.top, uiChrome.isFullScreen ? 0 : 30)
    }

    // A reserved margin strip pinned to the right edge of the window,
    // spanning the full height (ruler + tracks): background matching the
    // app's outer background, a thin vertical divider at its left edge, and
    // a triangle handle at the top. Dragging the whole strip horizontally
    // trims the track's total duration (right = longer, left = shorter),
    // independent of scroll transport.position or zoom.
    // Starts the repeating transport.timer that continuously applies the duration
    // drag's current rate of change (see durationHandle.durationDragCurrentDeltaX) for as
    // long as the drag is held — this is what makes it velocity-based
    // rather than a one-shot transport.position mapping.


    var durationDragHandle: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.gray.opacity(0.07))
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrowtriangle.left.fill")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.7))
                .offset(x: -3, y: -4)
                .padding(.top, 6)
        }
        .overlay(alignment: .topTrailing) {
            if durationHandle.isDraggingDurationHandle {
                durationTooltip
                    .fixedSize()
                    .padding(.trailing, 3)
                    .offset(y: 22)
            }
        }
        .frame(width: durationHandleWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !tracksLocked else { return }
                    if !durationHandle.isDraggingDurationHandle {
                        durationHandle.isDraggingDurationHandle = true
                        startDurationDragTimer()
                    }
                    durationHandle.durationDragCurrentDeltaX = value.translation.width
                }
                .onEnded { _ in
                    stopDurationDragTimer()
                    durationHandle.isDraggingDurationHandle = false
                    durationHandle.durationDragCurrentDeltaX = 0
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .help("Drag to change duration")
    }

    // Small callout bubble shown while dragging the duration handle,
    // pointing up at it from below, displaying the exact duration
    // (mm:ss:cc) as it's being adjusted live. Anchored by its trailing edge
    // (not centered) so the body always extends leftward into the window
    // instead of overflowing past the right edge, since the handle itself
    // sits right at that edge.
    var durationTooltip: some View {
        VStack(alignment: .trailing, spacing: 0) {
            UpPointingTriangle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 10, height: 6)
                .padding(.trailing, 8)
            Text(formattedPosition(transport.duree))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.85))
                .cornerRadius(6)
        }
    }


}
