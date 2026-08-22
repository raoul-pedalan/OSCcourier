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
    @Binding var zoomX: Double
    @Binding var isPinchZooming: Bool
    var zoomRange: ClosedRange<Double> = 1.0...10.0
    var duree: Double
    var contentWidth: CGFloat
    var contentHeight: CGFloat
    // Same per-pixel sensitivity used by the RotaryKnob (already scaled to
    // feel consistent regardless of track duration), reused here so Cmd+scroll
    // zooms at a comparable rate.
    var zoomSensitivity: Double = 0.05
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetX: $offsetX, zoomX: $zoomX, isPinchZooming: $isPinchZooming, zoomRange: zoomRange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CommandScrollZoomScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .allowed
        scrollView.allowsMagnification = false // we drive zoomX ourselves, not NSScrollView's own magnification
        scrollView.onCommandScroll = { [weak coordinator = context.coordinator] event in
            coordinator?.handleCommandScroll(event, in: scrollView)
        }

        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        scrollView.documentView = hosting

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
        context.coordinator.zoomSensitivity = zoomSensitivity

        // Bracket BOTH the document-view resize below and the explicit
        // scroll correction that follows it with isApplyingProgrammaticScroll.
        // Shrinking the document view below the scroll view's current scroll
        // position makes AppKit silently clamp that position back into range
        // as a side effect of the resize itself (posting its own
        // boundsDidChangeNotification) — separately from, and *before*, the
        // explicit scroll(to:) call further down. Without covering the
        // resize too, that implicit AppKit clamp was being misread by
        // boundsChanged as a genuine user scroll, which set
        // isSyncingUserScroll and caused the *next* real correction (the
        // actual playhead/cursor-anchored recenter) to be skipped by the
        // guard below, one tick later. That's what made zooming back OUT
        // quickly momentarily lose the anchor.
        context.coordinator.isApplyingProgrammaticScroll = true

        let newFrame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        if context.coordinator.hostingView?.frame != newFrame {
            context.coordinator.hostingView?.frame = newFrame
        }

        // Only push our own offset into the scroll view if it actually changed
        // (i.e. it was set programmatically from outside, e.g. on zoom change)
        // AND we're not in the middle of reflecting the user's own scroll back
        // up to SwiftUI (see boundsChanged/isSyncingUserScroll) — otherwise this
        // can catch `offsetX` still holding its pre-scroll value and snap the
        // content straight back to where the user just panned from.
        if !context.coordinator.isSyncingUserScroll && abs(context.coordinator.lastKnownOffset - offsetX) > 0.5 {
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
        var zoomXBinding: Binding<Double>
        var isPinchZoomingBinding: Binding<Bool>
        var zoomRange: ClosedRange<Double>
        var duree: Double = 30
        var currentContentWidth: CGFloat = 0
        var zoomSensitivity: Double = 0.05
        weak var hostingView: NSHostingView<Content>?
        weak var scrollView: NSScrollView?
        var lastKnownOffset: CGFloat = 0
        // See boundsChanged / updateNSView. Not private: read from
        // updateNSView, which is a method of the enclosing
        // TimelineScrollView struct, not of Coordinator itself.
        var isSyncingUserScroll = false
        // Set (also from updateNSView, not private for the same reason)
        // around a scroll(to:) call we trigger ourselves, so boundsChanged
        // can tell that echo apart from a real user-driven scroll instead
        // of treating it the same way. See both call sites for why.
        var isApplyingProgrammaticScroll = false
        // Coalesces a burst of scrollWheel events (a trackpad pan can
        // deliver several within one runloop tick) into a single SwiftUI
        // publish instead of one per event. See boundsChanged.
        private var offsetFlushScheduled = false
        private var zoomAtGestureStart: Double = 1.0
        // Debounces isPinchZoomingBinding back to false after Cmd+scroll
        // activity stops, since discrete mouse-wheel events (unlike a real
        // pinch gesture) don't carry an explicit .ended phase to rely on.
        private var commandScrollResetWorkItem: DispatchWorkItem?

        init(offsetX: Binding<CGFloat>, zoomX: Binding<Double>, isPinchZooming: Binding<Bool>, zoomRange: ClosedRange<Double>) {
            self.offsetXBinding = offsetX
            self.zoomXBinding = zoomX
            self.isPinchZoomingBinding = isPinchZooming
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
                // back. Doing so anyway was the bug: it set
                // isSyncingUserScroll, which then made the *next* real
                // programmatic correction get skipped by updateNSView's
                // guard, one tick later.
                return
            }
            lastKnownOffset = clipView.bounds.origin.x
            // Set before the async hop below and cleared only once it lands.
            // updateNSView runs on every SwiftUI re-render, not just when
            // offsetX changes, so during the gap between updating
            // lastKnownOffset here and the binding actually landing on the
            // main queue, some unrelated re-render could call updateNSView
            // while offsetX still holds its old (pre-scroll) value — which
            // then reads as an external change and scrolls the content
            // straight back to that old position. That race is what was
            // causing the two-finger-pan jitter/snap-back when zoomed in
            // (only visible once zoomed, since only then is there anything
            // to actually scroll). Skipping the correction while a sync is
            // in flight avoids it.
            isSyncingUserScroll = true

            // Coalesce: if a flush is already scheduled for this runloop
            // tick, just let it pick up the latest lastKnownOffset above
            // instead of scheduling another one. A fast trackpad pan can
            // deliver several scrollWheel events per tick, and each one
            // used to schedule its own SwiftUI publish — i.e. a full
            // re-render pass over ContentView's tree (RulerBar and others
            // observe the whole `transport` object) — for every single
            // sub-frame delta. That redundant work is part of why panning
            // felt less than fluid; publishing once per tick with the
            // freshest value is all SwiftUI actually needs to stay in sync.
            guard !offsetFlushScheduled else { return }
            offsetFlushScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.offsetFlushScheduled = false
                self.offsetXBinding.wrappedValue = self.lastKnownOffset
                self.isSyncingUserScroll = false
            }
        }

        @objc func handleMagnification(_ recognizer: NSMagnificationGestureRecognizer) {
            guard let scrollView = scrollView else { return }

            switch recognizer.state {
            case .began:
                zoomAtGestureStart = zoomXBinding.wrappedValue
                isPinchZoomingBinding.wrappedValue = true
            case .changed:
                let currentZoom = zoomXBinding.wrappedValue
                let outerWidth = currentContentWidth / CGFloat(currentZoom)
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
            case .ended, .cancelled, .failed:
                isPinchZoomingBinding.wrappedValue = false
            default:
                break
            }
        }

        // Cmd+scroll (mouse wheel or two-finger trackpad scroll): zooms
        // anchored on the cursor position, same math as handleMagnification
        // above but driven by scrollingDeltaY instead of a pinch gesture.
        func handleCommandScroll(_ event: NSEvent, in scrollView: NSScrollView) {
            let currentZoom = zoomXBinding.wrappedValue
            let outerWidth = currentContentWidth / CGFloat(currentZoom)
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
        }
    }
}
