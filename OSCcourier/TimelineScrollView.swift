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

        let newFrame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        if context.coordinator.hostingView?.frame != newFrame {
            context.coordinator.hostingView?.frame = newFrame
        }

        // Only push our own offset into the scroll view if it actually changed
        // (i.e. it was set programmatically from outside, e.g. on zoom change).
        // This avoids fighting with the user's own trackpad/scroll input.
        if abs(context.coordinator.lastKnownOffset - offsetX) > 0.5 {
            let maxX = max(0, contentWidth - scrollView.contentView.bounds.width)
            let clampedX = max(0, min(offsetX, maxX))
            scrollView.contentView.scroll(to: NSPoint(x: clampedX, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            context.coordinator.lastKnownOffset = clampedX
        }
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

        @objc func boundsChanged(_ note: Notification) {
            guard let clipView = note.object as? NSClipView else { return }
            let x = clipView.bounds.origin.x
            lastKnownOffset = x
            DispatchQueue.main.async { [weak self] in
                self?.offsetXBinding.wrappedValue = x
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
