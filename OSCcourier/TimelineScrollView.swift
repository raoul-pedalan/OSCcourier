import SwiftUI
import AppKit

// NSScrollView subclass that intercepts Cmd+scroll (mouse wheel or two-finger
// trackpad scroll) via a callback, instead of letting it pan the content —
// used to zoom anchored on the cursor, mirroring the existing pinch-to-zoom
// anchoring logic in TimelineScrollView's Coordinator.
class CommandScrollZoomScrollView: NSScrollView {
    var onCommandScroll: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            onCommandScroll?(event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

struct TimelineScrollView<Content: View>: NSViewRepresentable {
    @Binding var offsetX: CGFloat
    // Read-only from this view's perspective (see TransportState.scrollOffsetY):
    // published out from Coordinator.boundsChanged alongside offsetX, but never
    // pushed back in from updateNSView the way offsetX is — nothing currently
    // needs to programmatically set the vertical scroll position.
    @Binding var offsetY: CGFloat
    @Binding var zoomX: Double
    @Binding var isPinchZooming: Bool
    @Binding var lastCursorAnchoredZoom: Double
    var zoomRange: ClosedRange<Double> = 1.0...10.0
    var duree: Double
    var contentWidth: CGFloat
    // The outer geometry width, independent of zoom (contentWidth =
    // outerWidth * zoomX). Tracked separately rather than derived from
    // contentWidth/zoomX inside the Coordinator, because that derivation
    // silently breaks during a fast pinch gesture: NSMagnificationGestureRecognizer
    // delivers .changed events synchronously and faster than SwiftUI re-renders,
    // so contentWidth (only refreshed by updateNSView, tied to SwiftUI's render
    // cadence) can lag one or more zoom steps behind zoomXBinding.wrappedValue,
    // which is read live. outerWidth itself never changes with zoom (only on
    // window resize), so keeping it as its own tracked value sidesteps that
    // staleness entirely. See handleMagnification/handleCommandScroll.
    var outerWidth: CGFloat
    var contentHeight: CGFloat
    // Same per-pixel sensitivity used by the RotaryKnob (already scaled to
    // feel consistent regardless of track duration), reused here so Cmd+scroll
    // zooms at a comparable rate.
    var zoomSensitivity: Double = 0.05
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetX: $offsetX, offsetY: $offsetY, zoomX: $zoomX, isPinchZooming: $isPinchZooming, lastCursorAnchoredZoom: $lastCursorAnchoredZoom, zoomRange: zoomRange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CommandScrollZoomScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .allowed
        // NSScrollView's default automaticallyAdjustsContentInsets (true)
        // tries to avoid the window's toolbar/title bar by padding the
        // scroll view's own content — but it has no idea the ruler bar and
        // the pinned track-header column sitting above/beside it in the
        // SwiftUI hierarchy already account for that space, so it was
        // adding a large phantom top inset on top of SwiftUI's own layout.
        // That's what was pushing every row's content ~300pt lower than its
        // header counterpart in the pinned column (a constant offset, not
        // cumulative — confirmed by comparing row heights between the two,
        // which matched exactly). Disabling it removes the guesswork.
        scrollView.automaticallyAdjustsContentInsets = false
        // Belt-and-suspenders on top of the above: explicitly zero the
        // insets too, rather than trusting that turning off the automatic
        // adjustment alone clears whatever inset AppKit had already
        // computed.
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.allowsMagnification = false // we drive zoomX ourselves, not NSScrollView's own magnification
        scrollView.onCommandScroll = { [weak coordinator = context.coordinator] event in
            coordinator?.handleCommandScroll(event, in: scrollView)
        }

        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        scrollView.documentView = hosting
        // Force a deterministic starting scroll position instead of trusting
        // whatever AppKit defaults to when a fresh, larger-than-viewport
        // document view is first assigned — that default was leaving the
        // vertical position off by a constant amount (rows still landing at
        // the correct RELATIVE spacing from each other, just the whole
        // scrolled view starting short of true y=0), which showed up as
        // every row's content sitting noticeably lower than its header
        // counterpart in the pinned column.
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        context.coordinator.hostingView = hosting
        context.coordinator.scrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        let magnificationRecognizer = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnification(_:))
        )
        scrollView.addGestureRecognizer(magnificationRecognizer)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content()
        context.coordinator.zoomRange = zoomRange
        context.coordinator.duree = duree
        context.coordinator.currentContentWidth = contentWidth
        context.coordinator.currentOuterWidth = outerWidth
        context.coordinator.zoomSensitivity = zoomSensitivity

        // Bracket BOTH the document-view resize below and the explicit
        // scroll correction that follows it with isApplyingProgrammaticScroll.
        // Shrinking the document view below the scroll view's current scroll
        // position makes AppKit silently clamp that position back into range
        // as a side effect of the resize itself (posting its own
        // boundsDidChangeNotification) — separately from, and *before*, the
        // explicit scroll(to:) call further down. Without covering the
        // resize too, that implicit AppKit clamp gets misread by
        // boundsChanged as a genuine user scroll and published back out as
        // the authoritative offset — overwriting the playhead/cursor-anchored
        // offset the recenter was in the middle of applying. That's what made
        // zooming back OUT quickly momentarily lose the anchor.
        context.coordinator.isApplyingProgrammaticScroll = true

        let newFrame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        if context.coordinator.hostingView?.frame != newFrame {
            context.coordinator.hostingView?.frame = newFrame
        }

        // Only push our own offset into the scroll view if it actually
        // changed — i.e. it was set programmatically from outside (a
        // zoom-driven recenter, or the playhead auto-follow). A user-driven
        // scroll can't reach this branch: boundsChanged publishes offsetX
        // synchronously, so by the time any re-render lands here the two
        // already agree and the difference is 0. (This used to also need an
        // isSyncingUserScroll guard, back when that publish was deferred a
        // runloop tick and the two could momentarily disagree — see
        // boundsChanged.)
        if abs(context.coordinator.lastKnownOffset - offsetX) > 0.5 {
            let maxX = max(0, contentWidth - scrollView.contentView.bounds.width)
            let clampedX = max(0, min(offsetX, maxX))
            // Preserve whatever vertical scroll position the user is
            // currently at instead of hardcoding y: 0. This path used to
            // only fire on a zoom-driven horizontal recenter, where
            // resetting to the top was harmless (zooming rarely happens
            // mid-scroll through a tall stack of tracks). Now that
            // followPlayheadDuringPlayback() also drives offsetX — once per
            // page-flip during playback, tracks or not — hardcoding y: 0
            // here snapped the vertical scroll back to the top of the
            // tracks (right under the loop zone) on every single page-flip,
            // discarding wherever the user had scrolled down to.
            let currentY = scrollView.contentView.bounds.origin.y
            scrollView.contentView.scroll(to: NSPoint(x: clampedX, y: currentY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            context.coordinator.lastKnownOffset = clampedX
        }

        context.coordinator.isApplyingProgrammaticScroll = false
    }

    class Coordinator: NSObject {
        var offsetXBinding: Binding<CGFloat>
        var offsetYBinding: Binding<CGFloat>
        var zoomXBinding: Binding<Double>
        var isPinchZoomingBinding: Binding<Bool>
        var lastCursorAnchoredZoomBinding: Binding<Double>
        var zoomRange: ClosedRange<Double>
        var duree: Double = 30
        var currentContentWidth: CGFloat = 0
        var currentOuterWidth: CGFloat = 0
        var zoomSensitivity: Double = 0.05
        weak var hostingView: NSHostingView<Content>?
        weak var scrollView: NSScrollView?
        var lastKnownOffset: CGFloat = 0
        var lastKnownOffsetY: CGFloat = 0
        // Set (also from updateNSView, not private for the same reason)
        // around a scroll(to:) call we trigger ourselves, so boundsChanged
        // can tell that echo apart from a real user-driven scroll instead
        // of treating it the same way. See both call sites for why.
        var isApplyingProgrammaticScroll = false
        private var zoomAtGestureStart: Double = 1.0
        // Debounces isPinchZoomingBinding back to false after Cmd+scroll
        // activity stops, since discrete mouse-wheel events (unlike a real
        // pinch gesture) don't carry an explicit .ended phase to rely on.
        private var commandScrollResetWorkItem: DispatchWorkItem?

        init(offsetX: Binding<CGFloat>, offsetY: Binding<CGFloat>, zoomX: Binding<Double>, isPinchZooming: Binding<Bool>, lastCursorAnchoredZoom: Binding<Double>, zoomRange: ClosedRange<Double>) {
            self.offsetXBinding = offsetX
            self.offsetYBinding = offsetY
            self.zoomXBinding = zoomX
            self.isPinchZoomingBinding = isPinchZooming
            self.lastCursorAnchoredZoomBinding = lastCursorAnchoredZoom
            self.zoomRange = zoomRange
        }

        // Written explicitly (rather than relying on the compiler-synthesized
        // deinit) to work around a Swift compiler crash (SILOptimizer /
        // EarlyPerfInliner segfault) that only reproduces in Release/Archive
        // builds targeting macOS 14.6 as the minimum deployment. @_optimize(none)
        // keeps this one function out of that optimization pass. Also takes
        // the opportunity to remove the NSView.boundsDidChangeNotification
        // observer added in makeNSView, which was never being cleaned up.
        @_optimize(none)
        deinit {
            NotificationCenter.default.removeObserver(self)
            commandScrollResetWorkItem?.cancel()
        }

        @objc func boundsChanged(_ note: Notification) {
            guard let clipView = note.object as? NSClipView else { return }
            if isApplyingProgrammaticScroll {
                // Echo of a scroll updateNSView just triggered itself (e.g.
                // applying a zoom-driven recenter). lastKnownOffset was
                // already set to this exact value by that caller, and the
                // SwiftUI-side offsetX already holds it too (that's *why*
                // we scrolled) — there's nothing to reconcile or publish
                // back — and republishing it here would fight whatever
                // set it in the first place.
                return
            }
            if isPinchZoomingBinding.wrappedValue {
                // A magnify gesture (or Cmd+scroll zoom) is in progress.
                // handleMagnification/handleCommandScroll are the sole
                // source of truth for offsetX for the whole duration — they
                // compute it themselves to keep the point under the cursor
                // anchored, then push it through offsetXBinding, which
                // updateNSView applies with its own explicit scroll(to:)
                // (guarded by isApplyingProgrammaticScroll above).
                //
                // But a real pinch on a trackpad rarely holds the two
                // fingers perfectly still — the same slight finger movement
                // that drives NSMagnificationGestureRecognizer also reaches
                // NSScrollView's own default scrollWheel handling as
                // incidental panning, moving this clip view natively and
                // posting this exact notification — NOT wrapped by
                // isApplyingProgrammaticScroll above, since it didn't come
                // from our own scroll(to:) call. Confirmed via ZOOMDBG: an
                // updateNSView log with no preceding pinch log line, and an
                // offsetX(prop) that didn't match the last cursor-anchored
                // value computed by the gesture. Publishing that incidental
                // drift as if it were real user intent stomped on the
                // anchor math mid-gesture — that was the visible sideways
                // jump on a fast pinch. Ignore it here; the next
                // updateNSView pass (still driven by our own offsetX) will
                // explicitly scroll the clip view back to where the
                // cursor-anchored math says it belongs.
                return
            }
            lastKnownOffset = clipView.bounds.origin.x
            lastKnownOffsetY = clipView.bounds.origin.y

            // BOTH offsets are published synchronously, right here.
            //
            // These used to be deferred to the next runloop tick via
            // DispatchQueue.main.async, for two stated reasons — a race and
            // a coalescing optimisation. Neither survives scrutiny now that
            // views outside the scroll view (the pinned ruler strip, which
            // offsets by X; the pinned track-header column, which offsets by
            // Y) have to stay glued to the content while it scrolls: that
            // deferral is exactly one frame of visible lag between the two
            // panes and the tracks.
            //
            // The race: updateNSView runs on every SwiftUI re-render, so
            // during the gap between updating lastKnownOffset and the
            // binding actually landing, an unrelated re-render could call
            // updateNSView while offsetX still held its old pre-scroll value
            // — read as an external change, scrolling the content back to
            // where the user just panned from (the two-finger-pan jitter,
            // only visible zoomed in). Publishing synchronously CLOSES that
            // gap rather than guarding it: lastKnownOffset and offsetX are
            // now updated in the same call, so they can never disagree, and
            // updateNSView's own `abs(lastKnownOffset - offsetX) > 0.5`
            // check declines to correct anything all by itself.
            //
            // The coalescing: a fast trackpad pan can deliver several
            // scrollWheel events per runloop tick, and the worry was one
            // full SwiftUI re-render per event. But SwiftUI already
            // coalesces its own updates — several objectWillChange sends in
            // one runloop cycle still schedule a single view update — so the
            // manual hop bought no re-renders back; it only delayed them.
            //
            // Safe to do from here: this path is reached only for genuine
            // user-driven scrolls (the programmatic echo returns above), so
            // it's an AppKit event callback, never a SwiftUI view update.
            offsetXBinding.wrappedValue = lastKnownOffset
            offsetYBinding.wrappedValue = lastKnownOffsetY
        }

        @objc func handleMagnification(_ recognizer: NSMagnificationGestureRecognizer) {
            guard let scrollView = scrollView else { return }

            switch recognizer.state {
            case .began:
                zoomAtGestureStart = zoomXBinding.wrappedValue
                isPinchZoomingBinding.wrappedValue = true
            case .changed:
                let currentZoom = zoomXBinding.wrappedValue
                let outerWidth = currentOuterWidth
                let largeurAvant = outerWidth * CGFloat(currentZoom) - 140
                guard largeurAvant > 0 else { return }

                // Where is the mouse right now, in viewport-local coordinates?
                let locationX = recognizer.location(in: scrollView).x

                // Which timeline instant is currently under the mouse?
                let absoluteContentXBefore = offsetXBinding.wrappedValue + locationX
                let anchorTime = min(max(Double((absoluteContentXBefore - 140) / largeurAvant) * duree, 0), duree)

                // recognizer.magnification is cumulative since .began, e.g. 0.3 = pinched out 30%
                let proposed = zoomAtGestureStart * (1 + recognizer.magnification)
                let newZoom = min(max(proposed, zoomRange.lowerBound), zoomRange.upperBound)
                zoomXBinding.wrappedValue = newZoom

                // Recompute the offset so that same instant stays under the mouse
                let largeurApres = outerWidth * CGFloat(newZoom) - 140
                guard largeurApres > 0 else { return }
                let absoluteContentXAfter = 140 + CGFloat(anchorTime / duree) * largeurApres
                let maxX = max(0, outerWidth * CGFloat(newZoom) - scrollView.contentView.bounds.width)
                let newOffsetX = max(0, min(absoluteContentXAfter - locationX, maxX))
                offsetXBinding.wrappedValue = newOffsetX
                lastCursorAnchoredZoomBinding.wrappedValue = newZoom
            case .ended, .cancelled, .failed:
                // Deferred instead of synchronous: recenterOnZoomChange's
                // onChange(of: zoomX) handler in ContentView guards on
                // lastCursorAnchoredZoom now (see TransportState), not on
                // this flag directly, so this is no longer racing that
                // guard — but isPinchZooming also gates the Cmd+scroll
                // sensitivity elsewhere, and flipping it the instant the
                // gesture ends (rather than after SwiftUI has had a chance
                // to render the final .changed's values at least once)
                // still isn't necessary to rush.
                DispatchQueue.main.async { [weak self] in
                    self?.isPinchZoomingBinding.wrappedValue = false
                }
            default:
                break
            }
        }

        // Cmd+scroll (mouse wheel or two-finger trackpad scroll): zooms
        // anchored on the cursor position, same math as handleMagnification
        // above but driven by scrollingDeltaY instead of a pinch gesture.
        func handleCommandScroll(_ event: NSEvent, in scrollView: NSScrollView) {
            let currentZoom = zoomXBinding.wrappedValue
            let outerWidth = currentOuterWidth
            let largeurAvant = outerWidth * CGFloat(currentZoom) - 140
            guard largeurAvant > 0 else { return }

            // Where is the mouse right now, in viewport-local coordinates?
            let locationInView = scrollView.convert(event.locationInWindow, from: nil)
            let locationX = locationInView.x

            // Which timeline instant is currently under the mouse?
            let absoluteContentXBefore = offsetXBinding.wrappedValue + locationX
            let anchorTime = min(max(Double((absoluteContentXBefore - 140) / largeurAvant) * duree, 0), duree)

            let delta = Double(event.scrollingDeltaY)
            let proposed = currentZoom + delta * zoomSensitivity
            let newZoom = min(max(proposed, zoomRange.lowerBound), zoomRange.upperBound)
            guard newZoom != currentZoom else { return }

            // Suppress the SwiftUI-side playhead-anchored recentering
            // (onChange(of: zoomX) in ContentView) for the duration of this
            // gesture, same as during a real pinch — we're doing our own
            // cursor-anchored recentering right here instead.
            isPinchZoomingBinding.wrappedValue = true
            commandScrollResetWorkItem?.cancel()
            let resetItem = DispatchWorkItem { [weak self] in
                self?.isPinchZoomingBinding.wrappedValue = false
            }
            commandScrollResetWorkItem = resetItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: resetItem)

            zoomXBinding.wrappedValue = newZoom

            // Recompute the offset so that same instant stays under the mouse
            let largeurApres = outerWidth * CGFloat(newZoom) - 140
            guard largeurApres > 0 else { return }
            let absoluteContentXAfter = 140 + CGFloat(anchorTime / duree) * largeurApres
            let maxX = max(0, outerWidth * CGFloat(newZoom) - scrollView.contentView.bounds.width)
            let newOffsetX = max(0, min(absoluteContentXAfter - locationX, maxX))
            offsetXBinding.wrappedValue = newOffsetX
            lastCursorAnchoredZoomBinding.wrappedValue = newZoom
        }
    }
}
