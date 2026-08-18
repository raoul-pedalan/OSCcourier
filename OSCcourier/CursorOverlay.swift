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
//
// Two modes:
//  - Fixed symbol (symbolName/color): the whole overlay always shows the
//    same cursor while active (e.g. the Option bend cursor).
//  - Dynamic symbol (dynamicSymbol closure): the symbol/color can depend on
//    where within the overlay the mouse currently is (e.g. the Shift
//    erase-vs-reconnect cursor, which differs depending on the x position).
//    Needs `.mouseMoved` tracking too, since cursorUpdate(with:) alone only
//    reliably fires on tracking-area *entry*, not on every pixel moved
//    within an already-entered area.
struct CursorOverlay: NSViewRepresentable {
    var isActive: Bool
    var symbolName: String = ""
    var color: NSColor = .black
    var dynamicSymbol: ((CGPoint) -> (name: String, color: NSColor)?)?

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.symbolName = symbolName
        view.isActive = isActive
        view.color = color
        view.dynamicSymbol = dynamicSymbol
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        let activeChanged = nsView.isActive != isActive
        let symbolChanged = nsView.symbolName != symbolName
        let colorChanged = nsView.color != color
        nsView.symbolName = symbolName
        nsView.isActive = isActive
        nsView.color = color
        nsView.dynamicSymbol = dynamicSymbol
        // cursorUpdate/mouseEntered only fire on actual mouse movement (or on
        // a tracking-area boundary crossing), so if isActive just flipped
        // (e.g. Option pressed/released with the mouse sitting still) — or
        // the symbol/color changed while already active (e.g. sliding from a
        // live segment straight into a hole without leaving the zone) —
        // force the cursor to update right now if the mouse happens to
        // already be within this view.
        guard (activeChanged || symbolChanged || colorChanged), let window = nsView.window, window.isKeyWindow else { return }
        let mouseLocation = nsView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard nsView.bounds.contains(mouseLocation) else { return }
        nsView.applyCursor(at: mouseLocation)
    }

    // Builds a cursor-sized NSImage for a system symbol name, falling back
    // to a known-valid symbol (rather than a blank NSImage) if the name
    // doesn't resolve — an invalid name would otherwise silently produce an
    // invisible cursor, which is very hard to notice while testing.
    static func symbolImage(named symbolName: String, color: NSColor = .black) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: nil)
            ?? NSImage()
        return base.withSymbolConfiguration(config) ?? base
    }

    class TrackingView: NSView {
        var symbolName: String = ""
        var isActive: Bool = false
        var color: NSColor = .black
        var dynamicSymbol: ((CGPoint) -> (name: String, color: NSColor)?)?
        private var trackingArea: NSTrackingArea?

        // NSView defaults to a bottom-left origin (Y increasing upward);
        // SwiftUI — and every geometry helper this overlay's dynamicSymbol
        // resolvers call into (curveYPosition, etc.) — uses a top-left
        // origin (Y increasing downward). Without this, `bounds` and
        // `convert(_:from:)` report Y flipped relative to what those
        // resolvers expect, so a Y-dependent cursor (the Shift
        // eraser/reconnect one) would compare against the wrong band and
        // only "accidentally" match near the vertical center.
        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                // .mouseMoved is needed on top of .cursorUpdate so a
                // dynamicSymbol resolver gets re-evaluated continuously as
                // the mouse moves *within* an already-entered area, not
                // just once on entry.
                options: [.activeAlways, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        func applyCursor(at point: CGPoint) {
            // When inactive, deliberately do NOTHING — don't force the
            // arrow. This overlay sits stacked over the whole curve area,
            // so an inactive overlay resetting to arrow on every
            // cursorUpdate/mouseEntered was silently clobbering cursors
            // set by other mechanisms underneath.
            guard isActive else { return }
            if let dynamicSymbol {
                if let resolved = dynamicSymbol(point) {
                    NSCursor(image: CursorOverlay.symbolImage(named: resolved.name, color: resolved.color), hotSpot: NSPoint(x: 8, y: 8)).set()
                } else {
                    NSCursor.arrow.set()
                }
            } else {
                NSCursor(image: CursorOverlay.symbolImage(named: symbolName, color: color), hotSpot: NSPoint(x: 8, y: 8)).set()
            }
        }

        override func cursorUpdate(with event: NSEvent) {
            applyCursor(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            applyCursor(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            applyCursor(at: convert(event.locationInWindow, from: nil))
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
