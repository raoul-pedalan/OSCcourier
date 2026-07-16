import SwiftUI
import AppKit

// A transparent overlay that shows a custom SF-Symbol cursor over its whole
// area when `isActive` is true, using an NSTrackingArea with .cursorUpdate —
// the AppKit API specifically meant for dynamically customizing the cursor.
// Unlike ad-hoc NSCursor.set() calls (which macOS silently overrides on
// plain mouse-moved events outside of an active drag) or static cursor rects
// (which didn't reliably activate in this deeply-nested SwiftUI hierarchy),
// cursorUpdate(with:) is the callback AppKit itself invokes to let us decide
// the cursor, so our .set() call inside it is respected.
struct CursorOverlay: NSViewRepresentable {
    var isActive: Bool
    var symbolName: String

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.symbolName = symbolName
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        let activeChanged = nsView.isActive != isActive
        let symbolChanged = nsView.symbolName != symbolName
        nsView.symbolName = symbolName
        nsView.isActive = isActive
        // cursorUpdate/mouseEntered only fire on actual mouse movement (or on
        // a tracking-area boundary crossing), so if isActive just flipped
        // (e.g. Option pressed/released with the mouse sitting still) — or
        // the symbol changed while already active (e.g. sliding from a live
        // segment straight into a hole without leaving the zone) — force
        // the cursor to update right now if the mouse happens to already be
        // within this view.
        guard (activeChanged || symbolChanged), let window = nsView.window, window.isKeyWindow else { return }
        let mouseLocation = nsView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard nsView.bounds.contains(mouseLocation) else { return }
        if isActive {
            NSCursor(image: CursorOverlay.symbolImage(named: symbolName), hotSpot: NSPoint(x: 8, y: 8)).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // Builds a cursor-sized NSImage for a system symbol name, falling back
    // to a known-valid symbol (rather than a blank NSImage) if the name
    // doesn't resolve — an invalid name would otherwise silently produce an
    // invisible cursor, which is very hard to notice while testing.
    static func symbolImage(named symbolName: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: nil)
            ?? NSImage()
        return base.withSymbolConfiguration(config) ?? base
    }

    class TrackingView: NSView {
        var symbolName: String = ""
        var isActive: Bool = false
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .cursorUpdate, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func cursorUpdate(with event: NSEvent) {
            // When inactive, deliberately do NOTHING — don't force the
            // arrow. This overlay sits stacked over the whole curve area,
            // so an inactive overlay resetting to arrow on every
            // cursorUpdate/mouseEntered was silently clobbering cursors
            // set by other mechanisms underneath (e.g. the Shift
            // erase/reconnect cursor applied from onContinuousHover).
            guard isActive else { return }
            NSCursor(image: CursorOverlay.symbolImage(named: symbolName), hotSpot: NSPoint(x: 8, y: 8)).set()
        }

        override func mouseEntered(with event: NSEvent) {
            cursorUpdate(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            // Only reset if this overlay was the one that set a custom
            // cursor (i.e. it's currently active) — an inactive overlay
            // has no business resetting anything on the way out either.
            if isActive {
                NSCursor.arrow.set()
            }
        }
    }
}
