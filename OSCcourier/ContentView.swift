import SwiftUI
import PDFKit
import UniformTypeIdentifiers

//Deliverer
// A circle with smooth rounded "teeth" around its edge, like a gear or a
// flower — used to give the RotaryKnob a notched/knurled look.
struct NotchedKnobShape: Shape {
    var lobes: Int = 8
    var lobeDepth: CGFloat = 0.22 // fraction of the base radius

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2
        let segments = 240
        for i in 0...segments {
            let theta = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            let r = baseRadius * (1 - lobeDepth / 2 + lobeDepth / 2 * cos(CGFloat(lobes) * theta))
            let point = CGPoint(x: center.x + r * cos(theta), y: center.y + r * sin(theta))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct RotaryKnob: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onDoubleTap: () -> Void
    // Drag distance -> value change. Defaults to the value tuned for a 30s
    // track; callers with a range that scales with something else (like
    // zoomX, whose usable span grows with the track duration) should pass a
    // proportionally scaled sensitivity so the knob "feels" the same
    // regardless of how wide the range currently is.
    var sensitivity: Double = 0.05
    @State private var initialValue: Double?
    @State private var initialTranslation: CGFloat?

    var body: some View {
        ZStack {
            NotchedKnobShape()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 30, height: 30)

            NotchedKnobShape()
                .stroke(Color.gray, lineWidth: 2)
                .frame(width: 30, height: 30)
        }
        .rotationEffect(.degrees(valueToAngle(value: value)))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { gesture in
                    if initialValue == nil {
                        initialValue = value
                        initialTranslation = gesture.translation.height
                    } else {
                        let translationDiff = initialTranslation! - gesture.translation.height
                        let newValue = initialValue! + Double(translationDiff) * sensitivity
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                }
                .onEnded { _ in
                    initialValue = nil
                    initialTranslation = nil
                }
        )
        // Simultaneous (not exclusive) so it isn't swallowed by the drag
        // gesture above, which claims the interaction immediately since it
        // has minimumDistance: 0 — a plain .onTapGesture would never fire.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap()
            }
        )
    }

    private func valueToAngle(value: Double) -> Double {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return normalized * 270 - 135
    }
}

struct TimelineEvent: Identifiable, Comparable, Codable, Equatable {
    let id: UUID
    var time: Double
    var label: String
    var y: Double = 0.5
    // Curvature of the curve segment that starts at this point and ends at
    // the next point (curve tracks only). 0 = straight line. Positive values
    // bend it into a symmetric S-curve (like Logic Pro's automation curve
    // tool): stays close to this point's value, then transitions rapidly
    // around the segment's midpoint, then flattens near the next point's value.
    // Controlled by horizontal drag on the segment.
    var segmentCurve: Double = 0
    // Simple power-curve bulge for this segment (no inflection point, unlike
    // segmentCurve's S-shape) — a plain concave/convex bow in one direction
    // only. Controlled by vertical drag on the segment.
    var segmentBulge: Double = 0
    // Whether the segment starting at this point (curve tracks only) is
    // drawn/played at all. Shift-clicking a segment's line toggles this,
    // punching a silent "hole" in the curve — both endpoints stay exactly
    // where they are, but nothing is drawn or sent between them.
    var segmentEnabled: Bool = true
    // Free-form multi-line note attached to this point. Purely informational:
    // never sent over OSC, never drawn on the timeline — it only shows up in
    // the point's edit sheet (double-click).
    var comment: String = ""

    init(id: UUID = UUID(), time: Double, label: String, y: Double = 0.5, segmentCurve: Double = 0, segmentBulge: Double = 0, segmentEnabled: Bool = true, comment: String = "") {
        self.id = id
        self.time = time
        self.label = label
        self.y = y
        self.segmentCurve = segmentCurve
        self.segmentBulge = segmentBulge
        self.segmentEnabled = segmentEnabled
        self.comment = comment
    }

    static func < (lhs: TimelineEvent, rhs: TimelineEvent) -> Bool {
        lhs.time < rhs.time
    }

    // Custom decoding so projects saved before these fields existed still load:
    // any key that's absent falls back to its default rather than throwing.
    enum CodingKeys: String, CodingKey {
        case id, time, label, y, segmentCurve, segmentBulge, segmentEnabled, comment
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        time = try c.decode(Double.self, forKey: .time)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        segmentCurve = try c.decodeIfPresent(Double.self, forKey: .segmentCurve) ?? 0
        segmentBulge = try c.decodeIfPresent(Double.self, forKey: .segmentBulge) ?? 0
        segmentEnabled = try c.decodeIfPresent(Bool.self, forKey: .segmentEnabled) ?? true
        comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
    }
}

// SwiftUI's Color isn't natively Codable, so we go through plain RGBA
// components to save/load it.
struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        red = Double(nsColor.redComponent)
        green = Double(nsColor.greenComponent)
        blue = Double(nsColor.blueComponent)
        opacity = Double(nsColor.alphaComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct TimelineTrack: Identifiable, Codable, Equatable {
    let id: UUID
    var nom: String
    var couleur: Color
    var evenements: [TimelineEvent]
    var type: TrackType
    var isMuted: Bool = false
    var minAmplitude: Double = 0.0
    var maxAmplitude: Double = 1.0
    var height: CGFloat = 60
    // When true, the track's header is collapsed to just its name, the
    // fold triangle, and the reorder handle — its points/curves are hidden.
    var isFolded: Bool = false
    // Step tracks only: when true, the track is in "Gate" mode (boolean
    // 0/1 values, min/max locked to 0...1, no range editing) instead of
    // "Float" mode (arbitrary min/max range). Unused by curve tracks.
    var isGate: Bool = false
    // Curve/step tracks: vertical quantization step, in track value units.
    // 0 = off (free positioning). When > 0, point values snap to multiples of
    // this step, offset from minAmplitude — for MIDI notes, preset indices,
    // and other discrete-valued automation. Meaningless in Gate mode, where
    // values are already constrained to 0/1.
    var quantizeStep: Double = 0

    init(id: UUID = UUID(), nom: String, couleur: Color, evenements: [TimelineEvent], type: TrackType, isMuted: Bool = false, minAmplitude: Double = 0.0, maxAmplitude: Double = 1.0, height: CGFloat = 60, isFolded: Bool = false, isGate: Bool = false, quantizeStep: Double = 0) {
        self.id = id
        self.nom = nom
        self.couleur = couleur
        self.evenements = evenements
        self.type = type
        self.isMuted = isMuted
        self.minAmplitude = minAmplitude
        self.maxAmplitude = maxAmplitude
        self.height = height
        self.isFolded = isFolded
        self.isGate = isGate
        self.quantizeStep = quantizeStep
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, couleur, evenements, type, isMuted, minAmplitude, maxAmplitude, height, isFolded, isGate, quantizeStep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nom = try container.decode(String.self, forKey: .nom)
        couleur = try container.decode(CodableColor.self, forKey: .couleur).color
        evenements = try container.decode([TimelineEvent].self, forKey: .evenements)
        type = try container.decode(TrackType.self, forKey: .type)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        minAmplitude = try container.decode(Double.self, forKey: .minAmplitude)
        maxAmplitude = try container.decode(Double.self, forKey: .maxAmplitude)
        height = CGFloat(try container.decode(Double.self, forKey: .height))
        // Absent from older save files — default to unfolded rather than failing to decode.
        isFolded = try container.decodeIfPresent(Bool.self, forKey: .isFolded) ?? false
        isGate = try container.decodeIfPresent(Bool.self, forKey: .isGate) ?? false
        quantizeStep = try container.decodeIfPresent(Double.self, forKey: .quantizeStep) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nom, forKey: .nom)
        try container.encode(CodableColor(color: couleur), forKey: .couleur)
        try container.encode(evenements, forKey: .evenements)
        try container.encode(type, forKey: .type)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(minAmplitude, forKey: .minAmplitude)
        try container.encode(maxAmplitude, forKey: .maxAmplitude)
        try container.encode(Double(height), forKey: .height)
        try container.encode(isFolded, forKey: .isFolded)
        try container.encode(isGate, forKey: .isGate)
        try container.encode(quantizeStep, forKey: .quantizeStep)
    }
}

enum TrackType: String, Codable {
    case bang, curve, step, message, normal
}

// Top-level project file format. `_comment` is a real field (not a stripped
// // comment — plain JSON doesn't support those) so the file stays
// self-documenting if someone opens it in a text editor, while remaining
// strictly valid JSON.
struct SaveData: Codable {
    var _comment: String = "OSCcourier project file. Contains all track/point data plus basic UI settings (duration, OSC address, zoom level)."
    var duree: Double
    var oscAddress: String
    var zoomX: Double
    var pistes: [TimelineTrack]
}

// MARK: - Direct-control horizontal scroll view (used to keep the zoom centered on screen)
//
// We don't use SwiftUI's ScrollViewReader/scrollTo here: it races against the
// content-size change caused by zoomX, which makes programmatic recentering
// unreliable. Driving an NSScrollView directly gives us a deterministic offset.

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

// Used by the File menu commands (defined in the App file) to trigger
// save/load without ContentView needing to expose its private functions.
extension Notification.Name {
    static let OSCcourierSave = Notification.Name("OSCcourierSave")
    static let OSCcourierSaveAs = Notification.Name("OSCcourierSaveAs")
    static let OSCcourierLoad = Notification.Name("OSCcourierLoad")
    static let OSCcourierShowHelp = Notification.Name("OSCcourierShowHelp")
    static let OSCcourierPlayPause = Notification.Name("OSCcourierPlayPause")
    static let OSCcourierStop = Notification.Name("OSCcourierStop")
    static let OSCcourierAddBangTrack = Notification.Name("OSCcourierAddBangTrack")
    static let OSCcourierAddCurveTrack = Notification.Name("OSCcourierAddCurveTrack")
    static let OSCcourierAddMessageTrack = Notification.Name("OSCcourierAddMessageTrack")
    static let OSCcourierAddStepTrack = Notification.Name("OSCcourierAddStepTrack")
    static let OSCcourierClearAll = Notification.Name("OSCcourierClearAll")
    static let OSCcourierGoToTime = Notification.Name("OSCcourierGoToTime")
    static let OSCcourierGoToMarker = Notification.Name("OSCcourierGoToMarker")
    static let OSCcourierGoToPreviousMarker = Notification.Name("OSCcourierGoToPreviousMarker")
    static let OSCcourierGoToMarkerByName = Notification.Name("OSCcourierGoToMarkerByName")
    static let OSCcourierResetZoom = Notification.Name("OSCcourierResetZoom")
    static let OSCcourierResetTrackHeight = Notification.Name("OSCcourierResetTrackHeight")
    static let OSCcourierShowPointsList = Notification.Name("OSCcourierShowPointsList")
    static let OSCcourierToggleFoldAll = Notification.Name("OSCcourierToggleFoldAll")
    static let OSCcourierDefineGrid = Notification.Name("OSCcourierDefineGrid")
    static let OSCcourierOpenOSCMessagesWindow = Notification.Name("OSCcourierOpenOSCMessagesWindow")
    static let OSCcourierMuteUnmuteAll = Notification.Name("OSCcourierMuteUnmuteAll")
    static let OSCcourierDeleteAllTracks = Notification.Name("OSCcourierDeleteAllTracks")
}

struct ContentView: View {
    @StateObject private var oscManager = OSCManager()
    @StateObject private var messageStore = OSCMessageStore()
    @StateObject private var pointsListStore = PointsListStore()
    @State private var duree: Double = 30.0
    @State private var dureeText: String = "00:30.00"
    @State private var position: Double = 0.0
    @State private var enLecture: Bool = false
    @AppStorage("enBoucle") private var enBoucle: Bool = false
    @State private var timer: Timer?
    // Real wall-clock timestamp of the previous playback tick (monotonic
    // clock, in seconds). Used to advance `position` by the actual elapsed
    // time between ticks instead of an assumed fixed 0.05 — Timer doesn't
    // guarantee exact intervals, so assuming a fixed delta would let small
    // per-tick errors accumulate into real drift over a long playback session.
    @State private var lastTickTimestamp: Double?
    @State private var zoomX: Double = 1.0
    @State private var pistes: [TimelineTrack] = [
        TimelineTrack(nom: "/markers", couleur: Color(red: 0.45, green: 0.4, blue: 0.4), evenements: [], type: .bang, height: 45),
        TimelineTrack(nom: "/track_1", couleur: .blue, evenements: [], type: .bang, height: 45),
        TimelineTrack(nom: "/track_2", couleur: .yellow, evenements: [], type: .curve, height: 60),
        TimelineTrack(nom: "/track_3", couleur: .yellow, evenements: [], type: .curve, height: 60),
        TimelineTrack(nom: "/track_4", couleur: Color(red: 0.608, green: 0.086, blue: 0.365), evenements: [], type: .step, height: 60)
    ]
    @State private var lastSentEvents: Set<String> = []
    @State private var indexPisteARenommer: Int?
    @State private var nouveauNomPiste = ""
    @State private var pointAEditer: (trackIndex: Int, eventId: UUID)?
    @State private var nouvellePositionString = ""
    @State private var nouveauLabel = "M"
    @State private var nouveauComment = ""
    @State private var nouvelleYString = "0.5"
    @State private var amplitudeEditorTrackIndex: Int?
    // Autofill Rectangle popup (step tracks): generates a rectangular/pulse
    // pattern of step events across the track.
    @State private var autofillTrackIndex: Int?
    @State private var autofillPeriodString: String = "1.0"
    @State private var autofillPhaseString: String = "0.0"
    @State private var autofillPulseWidthString: String = "0.5"
    @State private var autofillAmpMinString: String = "0.0"
    @State private var autofillAmpMaxString: String = "1.0"

    // Autofill Wave popup (curve tracks): generates a sine or (skewed) sawtooth wave.
    @State private var waveTrackIndex: Int?
    @State private var waveIsSine: Bool = true // true = Sin, false = Saw
    @State private var wavePeriodString: String = "1.0"
    @State private var wavePhaseString: String = "0.0"
    @State private var waveSkewString: String = "0.5"
    @State private var waveAmpMinString: String = "0.0"
    @State private var waveAmpMaxString: String = "1.0"

    // Autofill Bang popup (bang/markers tracks): generates evenly spaced bangs.
    @State private var bangTrackIndex: Int?
    @State private var bangPeriodString: String = "1.0"
    @State private var bangPhaseString: String = "0.0"
    // Message tracks only: prefix used for generated labels ("prefix_1",
    // "prefix_2", ...), replacing the previously hardcoded "key".
    @State private var bangLabelPrefixString: String = "key"
    // Set when the pencil button is pressed on a track that already has
    // points, to show an "Overwrite track?" confirmation before opening
    // the actual autofill popup.
    @State private var pendingAutofillIndex: Int?
    @State private var showClearAllConfirmation = false
    @State private var showDeleteAllTracksConfirmation = false
    // Modifier-aware cursor over points: shift = delete cursor, cmd = snap cursor.
    // Tracks whether the mouse is currently over any point, and listens for
    // modifier key changes while hovering (since .onHover alone only fires on
    // enter/exit, not when a modifier key is pressed mid-hover).
    @State private var isHoveringPoint: Bool = false
    // Option-drag on a curve segment (Logic Pro automation-curve style).
    // Whether the cursor is currently within the erase/bend zone (12px) of
    // this hovered curve track's line. Boolean on purpose: it only changes
    // on zone transitions (rare), unlike storing the raw hover position in
    // @State, which changed every single pixel of mouse movement and forced
    // a full body re-render per pixel — constantly rebuilding the hover
    // stream and tracking areas, which is what silently broke both the
    // Option and Shift hover cursors.
    @State private var isNearCurveControlZone: Bool = false
    @State private var isOptionHeldForCursor: Bool = false
    @State private var curveDragSegmentID: UUID?
    @State private var curveDragBaseline: Double?
    @State private var curveDragBulgeBaseline: Double?
    @State private var isNearSnapZone: Bool = false
    // Tracks proximity to a grid line specifically (not markers) — used to
    // show the snap cursor for "magnetic grid" auto-snap even without ⌘ held.
    @State private var isNearGridSnapZone: Bool = false
    // Whether the closest ⌘-snap target (marker or grid line combined) is
    // specifically the grid line — used only to color the snap cursor.
    @State private var isNearestSnapGrid: Bool = false
    @State private var flagsChangedMonitor: Any?
    // Tracks whether the window is currently full screen, so the top
    // padding reserved to clear the title bar can be dropped once that
    // title bar itself is hidden (full screen has no title bar to avoid).
    @State private var isFullScreen: Bool = false
    @State private var fullScreenEnterObserver: Any?
    @State private var fullScreenExitObserver: Any?
    @State private var tempMinAmplitude: String = "0"
    @State private var tempMaxAmplitude: String = "1"
    @State private var tempIsGate: Bool = false
    @State private var tempQuantizeStep: String = "0"
    @State private var tempQuantizeEnabled: Bool = false
    // Set when the user commits a quantize step that had to be clamped, so we
    // can tell them rather than silently changing what they typed.
    @State private var invalidQuantizeStepMessage: String? = nil
    @State private var pendingGateSwitchIndex: Int? = nil
    @State private var messagesWindowController: NSWindowController?
    // Explicit visibility tracking for the OSC messages window's Open/Close
    // toggle — more reliable than reading NSWindow.isVisible directly.
    @State private var isOSCWindowVisible: Bool = false
    @State private var oscWindowCloseDelegate: OSCWindowCloseDelegate?
    // Points list window (same open/close toggle pattern as the OSC one).
    @State private var pointsListWindowController: NSWindowController?
    @State private var isPointsListWindowVisible: Bool = false
    @State private var pointsListCloseDelegate: OSCWindowCloseDelegate?
    @State private var pdfWindowController: NSWindowController?
    // Remembers the file chosen on the first Save, so subsequent saves
    // silently overwrite it instead of prompting again.
    @State private var savedFileURL: URL?
    // Managing focus explicitly (defaulting to nil) stops macOS from
    // automatically giving keyboard focus to the first text field at launch.
    private enum ToolbarField: Hashable {
        case duree, oscAddress
    }
    @FocusState private var focusedField: ToolbarField?
    @State private var draggedTrackIndex: Int?
    @State private var dragStartHeight: CGFloat = 0
    // Duration trim handle, pinned to the right edge of the window: drag
    // horizontally to grow/shrink the track's total duration.
    @State private var isDraggingDurationHandle: Bool = false
    // Velocity-based drag: the horizontal offset from where the drag
    // started controls the *rate* of change (seconds of duree per second
    // held), rather than directly mapping to a duree delta. A repeating
    // timer applies that rate continuously while the drag is held.
    @State private var durationDragCurrentDeltaX: CGFloat = 0
    @State private var durationDragTimer: Timer?
    // Brief flash indicator for the compact command bar's "OSC" label,
    // lit up for a short moment each time an OSC message actually goes out.
    @State private var isOSCFlashing: Bool = false
    @State private var oscFlashTimer: Timer?
    // How fast duree changes per second, per pixel of horizontal offset
    // from the drag's start point.
    // Non-linear speed curve: rate = sign(dx) * |dx|^exponent * scale.
    // exponent > 1 makes small offsets noticeably slower (more precise) and
    // large offsets noticeably faster than a plain linear mapping would.
    private let durationDragVelocityExponent: Double = 1.8
    private let durationDragVelocityScale: Double = 0.00126
    // Track reordering (drag handle in the header). "markers" (index 0) stays pinned.
    @State private var reorderingIndex: Int?
    @State private var reorderDragTranslation: CGFloat = 0
    // Accumulates by ± the swapped neighbor's height each time a swap happens during
    // the same drag, so the raw (cumulative-since-start) gesture translation can be
    // corrected into the right visual offset without ever being overwritten wrong.
    @State private var reorderBaselineOffset: CGFloat = 0

    // Vertical margin (= circle radius) reserved at the top/bottom of a curve
    // track so that points at the extreme values (0 or 1) aren't half-clipped.
    // Shared by the ruler labels, the path, and the point positions so they
    // all stay consistent with each other.
    private let curveMargin: CGFloat = 6

    // Height a folded track's row is reduced to: just enough for the name,
    // fold triangle, and reorder handle.
    private let foldedTrackHeight: CGFloat = 24

    // Width of the duration trim handle strip pinned to the window's right
    // edge. Shared so the timeline drawing width can reserve exactly this
    // much, keeping the end of the tracks aligned with the handle's bar.
    private let durationHandleWidth: CGFloat = 18

    // The actual row height to use for a given track: folded tracks always
    // collapse to foldedTrackHeight, regardless of type; otherwise bang/message
    // tracks are a fixed 45, and curve/step tracks use their own `height`.
    private func rowHeight(for piste: TimelineTrack) -> CGFloat {
        if piste.isFolded { return foldedTrackHeight }
        return (piste.type == .bang || piste.type == .message) ? 45 : piste.height
    }

    // Applies whatever vertical constraint the track has to a raw y value.
    // Called from every point-creating/point-moving path (click, drag, editor),
    // so both Gate mode and quantization behave consistently everywhere.
    //
    // Gate takes priority: it's already a strict 0/1 quantization, so a step
    // value on top of it would be meaningless (and is hidden in the UI).
    private func gateSnappedY(_ y: Double, forTrackIndex index: Int) -> Double {
        let piste = pistes[index]

        if piste.type == .step && piste.isGate {
            let midpoint = (piste.minAmplitude + piste.maxAmplitude) / 2
            return y >= midpoint ? piste.maxAmplitude : piste.minAmplitude
        }

        guard piste.type == .curve || piste.type == .step else { return y }
        return quantizedY(y, forTrackIndex: index)
    }

    // Snaps y to the nearest multiple of the track's quantizeStep, measured
    // from minAmplitude (so the range's own bounds are always reachable), then
    // clamps back into range — rounding could otherwise land just outside it.
    private func quantizedY(_ y: Double, forTrackIndex index: Int) -> Double {
        let piste = pistes[index]
        let step = piste.quantizeStep
        guard step > 0 else { return y }
        let offset = y - piste.minAmplitude
        let snapped = piste.minAmplitude + (offset / step).rounded() * step
        return min(max(snapped, piste.minAmplitude), piste.maxAmplitude)
    }

    // The y values every quantization tick sits on, for a track. Empty when
    // quantization is off. Capped so an absurdly small step can't generate
    // thousands of ticks (the UI thins them out further; this is the hard
    // safety limit on the underlying set).
    private func quantizeTickValues(forTrackIndex index: Int) -> [Double] {
        let piste = pistes[index]
        let step = piste.quantizeStep
        let range = piste.maxAmplitude - piste.minAmplitude
        guard step > 0, range > 0 else { return [] }
        let count = Int((range / step).rounded(.down))
        guard count >= 1, count <= 500 else { return [] }
        return (0...count).map { piste.minAmplitude + Double($0) * step }
    }

    // Which of those ticks to actually draw at the track's current height:
    // keeps every Nth one (N from a "nice" progression) so they never get
    // closer than a legible minimum, exactly like the horizontal grid does.
    private func visibleQuantizeTicks(forTrackIndex index: Int) -> [Double] {
        let all = quantizeTickValues(forTrackIndex: index)
        guard all.count > 1 else { return all }
        let usableHeight = pistes[index].height - 2 * curveMargin
        guard usableHeight > 0 else { return [] }
        let spacing = usableHeight / CGFloat(all.count - 1)
        let minSpacing: CGFloat = 7
        guard spacing < minSpacing else { return all }
        let rawSkip = Double(minSpacing / spacing)
        let niceSteps: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500]
        let skip = Int(niceSteps.first(where: { $0 >= rawSkip }) ?? 500)
        return all.enumerated().compactMap { i, v in i % skip == 0 ? v : nil }
    }

    // A lightweight, non-interactive "ghost" preview of a folded track's
    // content — no point markers, no coordinate labels, no gestures, just a
    // faint trace so the track's shape/pattern stays recognizable while
    // collapsed. Curve/step segments are drawn as straight lines here
    // (ignoring segmentCurve/segmentBulge) since the folded row is too thin
    // for the curvature to read anyway.
    @ViewBuilder
    private func foldedGhostTrace(for piste: TimelineTrack, largeurTimeline: CGFloat) -> some View {
        let h = foldedTrackHeight
        let margin: CGFloat = 3
        switch piste.type {
        case .bang, .message:
            ForEach(piste.evenements) { event in
                let xPos = CGFloat(event.time / duree) * largeurTimeline
                Rectangle()
                    .fill(piste.couleur.opacity(0.7))
                    .frame(width: 1, height: h * 0.6)
                    .position(x: xPos, y: h / 2)
            }
            .allowsHitTesting(false)
        case .curve:
            if piste.evenements.count > 1 {
                Path { path in
                    let sorted = piste.evenements.sorted { $0.time < $1.time }
                    let amplitudeRange = piste.maxAmplitude - piste.minAmplitude
                    func yPos(for value: Double) -> CGFloat {
                        let normalizedY = amplitudeRange > 0 ? (value - piste.minAmplitude) / amplitudeRange : 0.5
                        return margin + (h - 2 * margin) * (1 - normalizedY)
                    }
                    for (i, event) in sorted.enumerated() {
                        let xPos = CGFloat(event.time / duree) * largeurTimeline
                        let point = CGPoint(x: xPos, y: yPos(for: event.y))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(piste.couleur.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)
            }
        case .step:
            if piste.evenements.count > 1 {
                Path { path in
                    let sorted = piste.evenements.sorted { $0.time < $1.time }
                    let amplitudeRange = piste.maxAmplitude - piste.minAmplitude
                    func yPos(for event: TimelineEvent) -> CGFloat {
                        let normalizedY = amplitudeRange > 0 ? (event.y - piste.minAmplitude) / amplitudeRange : 0.5
                        return margin + (h - 2 * margin) * (1 - normalizedY)
                    }
                    for (i, event) in sorted.enumerated() {
                        let xPos = CGFloat(event.time / duree) * largeurTimeline
                        let y = yPos(for: event)
                        if i == 0 {
                            path.move(to: CGPoint(x: xPos, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: xPos, y: path.currentPoint?.y ?? y))
                            path.addLine(to: CGPoint(x: xPos, y: y))
                        }
                    }
                }
                .stroke(piste.couleur.opacity(0.7), lineWidth: 1.5)
                .allowsHitTesting(false)
            }
        case .normal:
            EmptyView()
        }
    }

    // MARK: - Zoom-centering state
    @State private var scrollOffsetX: CGFloat = 0
    // True while a pinch gesture is in progress: TimelineScrollView's Coordinator
    // handles its own mouse-anchored centering during a pinch, so the viewport-center
    // recentering below (used for the RotaryKnob) should stand down while this is true.
    @State private var isPinchZooming: Bool = false
    // Toggle for showing/hiding the "time, value" coordinate labels next to points.
    @AppStorage("showPointCoordinates") private var showPointCoordinates: Bool = true
    // Toggle for showing/hiding the timeline grid overlay.
    @AppStorage("showGrid") private var showGrid: Bool = false
    @AppStorage("oscMessagesPerSecond") private var oscMessagesPerSecond: Int = 20
    // Toggles between the full command bar (toolbar with all controls) and
    // a compact, full-width control line (position + play/loop indicators).
    @AppStorage("showCommandBar") private var showCommandBar: Bool = true
    // Shared with OSCcourierApp's menu commands via the same @AppStorage keys.
    @AppStorage("showMarkersTrack") private var showMarkersTrack: Bool = true
    @AppStorage("tracksLocked") private var tracksLocked: Bool = false
    // "Go to (mm:ss)" dialog, triggered from the Play menu.
    @State private var showGoToTimeDialog: Bool = false
    @State private var goToTimeString: String = "00:00"
    @State private var showGoToMarkerNameDialog: Bool = false
    @State private var goToMarkerNameString: String = ""
    @State private var showGoToMarkerNoMatch: Bool = false
    // Grid line generation: evenly spaced dashed vertical lines across all
    // tracks, same period/phase model as the bang autofill.
    @State private var showGridSettingsPopup: Bool = false
    @State private var gridPeriodString: String = "1.0"
    @State private var gridPhaseString: String = "0.0"
    @State private var gridPeriod: Double = 1.0
    @State private var gridPhase: Double = 0.0
    // Width of the timeline viewport (updated from the outer GeometryReader), used to
    // compute how much zoom is needed to reach the 1s = 1000px target regardless of `duree`.
    @State private var timelineAreaWidth: CGFloat = 1500

    // Maximum zoom factor such that at max zoom, 1 second of timeline = 1000px,
    // no matter how long the track (`duree`) is. Without this, a fixed max zoom
    // (e.g. 10x) isn't enough to reach that resolution once `duree` gets large.
    private var maxZoomX: Double {
        let outerWidth = max(timelineAreaWidth, 1)
        let desiredLargeur = 1000.0 * duree // pixels needed so that 1s = 1000px
        let zoom = (desiredLargeur + 140) / outerWidth
        return max(1.0, zoom)
    }

    // maxZoomX computed as if duree were pinned at 30s (same outerWidth) —
    // used purely as a reference span for calibrating the zoom knob's
    // sensitivity below, not for the actual zoom range.
    private var referenceMaxZoomX: Double {
        let outerWidth = max(timelineAreaWidth, 1)
        let desiredLargeur = 1000.0 * 30.0
        return max(1.0, (desiredLargeur + 140) / outerWidth)
    }

    // The zoom knob was tuned to feel right for a 30s track (sensitivity
    // 0.05). Since the usable zoom range (1...maxZoomX) grows with `duree`,
    // a fixed sensitivity would require dragging proportionally further for
    // longer tracks to reach the same zoom level. Scaling sensitivity by the
    // ratio of the current range's span to the 30s-reference span keeps the
    // same drag distance always covering the same *fraction* of the range.
    private var zoomKnobSensitivity: Double {
        let referenceSpan = max(referenceMaxZoomX - 1.0, 0.0001)
        let currentSpan = max(maxZoomX - 1.0, 0.0001)
        return 0.05 * (currentSpan / referenceSpan)
    }

    // Tracks actually shown in the timeline — all of them, unless the
    // "/markers" track (always index 0) is hidden via showMarkersTrack.
    private var visiblePistes: [TimelineTrack] {
        showMarkersTrack ? pistes : Array(pistes.dropFirst())
    }

    // Real total height of the ruler + all tracks (mirrors the `totalHeight` computed
    // inside the inner GeometryReader), plus the top padding reserved for the playhead
    // triangle. Used as the document's actual height so vertical scrolling can reveal
    // tracks that would otherwise be clipped below the visible viewport.
    private var totalTracksHeight: CGFloat {
        24 + visiblePistes.reduce(CGFloat(0)) { $0 + rowHeight(for: $1) } + CGFloat(visiblePistes.count * 5) + 14
    }

    // Shared naming counter across all track types (bang or curve), so a new
    // track never reuses a number already taken by a track of the other color.
    // Based on the highest existing /track_N suffix rather than a raw count,
    // so it stays correct even after tracks have been deleted or reordered.
    private var nextTrackName: String {
        let existingNumbers = pistes.compactMap { piste -> Int? in
            guard piste.nom.hasPrefix("/track_") else { return nil }
            return Int(piste.nom.dropFirst("/track_".count))
        }
        return "/track_\((existingNumbers.max() ?? 0) + 1)"
    }

    // Formats a duration in seconds as "mm:ss" (playback position/timer keeps
    // its own separate "mm:ss:cc" formatter below; this one is for the
    // editable duration field, which only needs whole-second precision).
    // "mm:ss.cc" — centiseconds included because the duration trim handle
    // adjusts by 0.01s steps: rounding the display to whole seconds made the
    // field look frozen while trimming, and misreported the actual duration.
    private func formattedDuration(_ seconds: Double) -> String {
        let totalCentiseconds = Int((seconds * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let secs = (totalCentiseconds / 100) % 60
        let centis = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, secs, centis)
    }

    // Parses a duration back into seconds. Deliberately permissive, so typing
    // a duration stays simple even though the display is precise: "30",
    // "30.5", "00:30" and "00:30.47" are all accepted.
    private func parseDuration(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
            return minutes * 60 + seconds
        } else if parts.count == 1, let seconds = Double(parts[0]) {
            return seconds
        }
        return nil
    }

    // Formats a ruler tick label. Ticks spaced 1s apart or more show plain
    // "mm:ss"; ticks spaced under 1s apart (zoomed in a lot) additionally
    // show centiseconds ("mm:ss.cc"), since otherwise consecutive sub-second
    // ticks would render identically.
    private func formattedTick(_ seconds: Double, labelInterval: Double) -> String {
        let totalCentiseconds = Int((seconds * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let secs = (totalCentiseconds / 100) % 60
        let centis = totalCentiseconds % 100
        if labelInterval < 1 {
            return String(format: "%02d:%02d.%02d", minutes, secs, centis)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    // Formats a duration in seconds as "mm:ss:cc" (minutes:seconds:centiseconds).
    private func formattedPosition(_ seconds: Double) -> String {
        let totalCentiseconds = Int((seconds * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let secs = (totalCentiseconds / 100) % 60
        let centis = totalCentiseconds % 100
        return String(format: "%02d:%02d:%02d", minutes, secs, centis)
    }

    private func encodedProjectData() -> Data? {
        let data = SaveData(duree: duree, oscAddress: oscManager.address, zoomX: zoomX, pistes: pistes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(data)
    }

    private func saveProject() {
        guard let jsonData = encodedProjectData() else { return }

        if let url = savedFileURL {
            try? jsonData.write(to: url)
        } else {
            promptAndSave(jsonData)
        }
    }

    // Always prompts for a new location, regardless of any previously saved file.
    private func saveProjectAs() {
        guard let jsonData = encodedProjectData() else { return }
        promptAndSave(jsonData)
    }

    private func promptAndSave(_ jsonData: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "OSCcourier.json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            savedFileURL = url
            try? jsonData.write(to: url)
        }
    }

    private func loadProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let jsonData = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SaveData.self, from: jsonData) else { return }

        enLecture = false
        position = 0
        lastSentEvents.removeAll()
        duree = decoded.duree
        dureeText = formattedDuration(decoded.duree)
        zoomX = decoded.zoomX
        oscManager.address = decoded.oscAddress
        oscManager.setupOSCConnection()
        pistes = decoded.pistes
        savedFileURL = url // further saves overwrite the file we just loaded
    }

    private func openPDFWindow() {
        if pdfWindowController != nil {
            pdfWindowController?.showWindow(nil)
            return
        }
        guard let pdfURL = Bundle.main.url(forResource: "Help", withExtension: "pdf") else { return }
        let document = PDFDocument(url: pdfURL)
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.5

        // Size the window to fit the PDF's actual page at that same scale,
        // instead of a fixed guess, so nothing gets cut off horizontally.
        var contentWidth: CGFloat = 600
        var contentHeight: CGFloat = 800
        if let page = document?.page(at: 0) {
            let pageBounds = page.bounds(for: .mediaBox)
            contentWidth = pageBounds.width * pdfView.scaleFactor
            contentHeight = pageBounds.height * pdfView.scaleFactor
        }
        if let screenFrame = NSScreen.main?.visibleFrame {
            contentWidth = min(contentWidth, screenFrame.width * 0.9)
            contentHeight = min(contentHeight, screenFrame.height * 0.9)
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered,
                             defer: false)
        window.title = "Help"
        window.center()
        window.contentView = pdfView
        pdfWindowController = NSWindowController(window: window)
        pdfWindowController?.showWindow(nil)
    }

    // Shared with SettingsView via the same @AppStorage key.
    @AppStorage("oscAddressPrefix") private var oscAddressPrefix: String = ""
    @AppStorage("oscReceivePort") private var oscReceivePort: Int = 7500
    // Grid snap mode: false = grid lines only snap like markers do, via
    // ⌘+drag; true = "magnetic grid", points snap to the nearest grid line
    // automatically while dragging, no ⌘ needed. Markers themselves always
    // require ⌘ either way — this setting only affects grid-line snapping.
    @AppStorage("magneticGridSnap") private var magneticGridSnap: Bool = false

    private func sendOSCMessage(_ message: String, color: Color = .primary) {
        let fullMessage = oscAddressPrefix + message
        oscManager.sendMessage(fullMessage)
        messageStore.addMessage(fullMessage, color: color)
        flashOSCIndicator()
    }

    private func flashOSCIndicator() {
        isOSCFlashing = true
        oscFlashTimer?.invalidate()
        let t = Timer(timeInterval: 0.15, repeats: false) { _ in
            DispatchQueue.main.async {
                isOSCFlashing = false
            }
        }
        // .common so the flash still resets promptly even if the user is
        // mid-drag on something else when messages are sent.
        RunLoop.main.add(t, forMode: .common)
        oscFlashTimer = t
    }

    // Rebuilds the points list snapshot into the shared store. Called whenever
    // the tracks change, so the (observing) list window stays live.
    private func refreshPointsList() {
        var rows: [PointListRow] = []
        for (trackIndex, piste) in pistes.enumerated() {
            // Only markers and message tracks carry a meaningful label. Bang
            // and curve/step points don't — any label they hold is leftover
            // default state, so showing it (e.g. a stray "M") is just noise.
            let hasLabel = trackIndex == 0 || piste.type == .message
            for event in piste.evenements {
                let value: String
                switch piste.type {
                case .curve, .step:
                    value = String(format: "%.2f", event.y)
                default:
                    value = ""
                }
                rows.append(PointListRow(
                    id: event.id,
                    trackName: piste.nom,
                    trackColor: piste.couleur,
                    time: event.time,
                    label: hasLabel ? event.label : "",
                    value: value,
                    comment: event.comment
                ))
            }
        }
        pointsListStore.rows = rows.sorted { $0.time < $1.time }
        pointsListStore.trackNames = pistes.map { $0.nom }
    }

    // Opens the point editor for a given event, wherever it lives. Shared by
    // the timeline's double-click and the points list window, so both go
    // through exactly the same editing path.
    private func beginEditingPoint(eventId: UUID) {
        guard !tracksLocked else { return }
        for (trackIndex, piste) in pistes.enumerated() {
            guard let event = piste.evenements.first(where: { $0.id == eventId }) else { continue }
            pointAEditer = (trackIndex, eventId)
            nouvellePositionString = String(format: "%.2f", event.time)
            nouvelleYString = String(format: "%.2f", event.y)
            nouveauComment = event.comment
            if trackIndex == 0 || piste.type == .message {
                nouveauLabel = event.label
            }
            // The editor is a sheet on the main window, so bring that window
            // forward — otherwise, when the edit was triggered from the list
            // window, the sheet would open behind it.
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            return
        }
    }

    private func openPointsListWindow() {
        refreshPointsList()

        // Wired every time (cheap, and the closure captures fresh state) so
        // the list window can ask us to open the standard point editor.
        pointsListStore.onRequestEdit = { eventId in
            beginEditingPoint(eventId: eventId)
        }

        if let controller = pointsListWindowController {
            if isPointsListWindowVisible {
                controller.window?.close()
                isPointsListWindowVisible = false
            } else {
                controller.showWindow(nil)
                isPointsListWindowVisible = true
            }
            return
        }

        // The view observes pointsListStore, so no need to rebuild the hosting
        // view on reopen — it re-renders on its own whenever the store changes.
        let hostingView = NSHostingView(rootView: PointsListView(store: pointsListStore))
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 380)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Points List"
        window.setFrameAutosaveName("PointsListWindow")
        window.contentView = hostingView
        window.minSize = NSSize(width: 520, height: 300)
        window.isReleasedWhenClosed = false
        // Deliberately NOT a floating window: a floating list parked in the
        // middle of the screen would sit on top of every sheet the main window
        // opens (point editor, autofill, grid settings...), hiding them.

        let delegate = OSCWindowCloseDelegate()
        delegate.onClose = {
            isPointsListWindowVisible = false
        }
        window.delegate = delegate
        pointsListCloseDelegate = delegate

        window.center()

        pointsListWindowController = NSWindowController(window: window)
        pointsListWindowController?.showWindow(nil)
        isPointsListWindowVisible = true
    }

    private func openOSCMessagesWindow() {
        // No per-window appearance handling here anymore: NSApp.appearance
        // (set app-wide from the Appearance setting) already covers every
        // window, including this one and its title bar.
        if let controller = messagesWindowController {
            if isOSCWindowVisible {
                controller.window?.close()
                isOSCWindowVisible = false
            } else {
                controller.showWindow(nil)
                isOSCWindowVisible = true
            }
            return
        }

        let contentView = OSCMessagesView(messageStore: messageStore)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 300)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Outgoing OSC Messages"
        window.setFrameAutosaveName("OSCMessagesWindow")
        window.setContentSize(NSSize(width: 220, height: 300))
        window.contentView = hostingView
        window.minSize = NSSize(width: 50, height: 300)
        // Without this, closing a manually-created NSWindow (not from a
        // nib) can release it out from under us, leaving our controller
        // holding a stale reference on the next toggle.
        window.isReleasedWhenClosed = false

        let delegate = OSCWindowCloseDelegate()
        delegate.onClose = {
            isOSCWindowVisible = false
        }
        window.delegate = delegate
        oscWindowCloseDelegate = delegate

        // Top-right of the screen, with a small margin from the edges —
        // applied after setFrameAutosaveName so it always ends up there,
        // rather than wherever a previously saved frame happened to be.
        if let screenFrame = NSScreen.main?.visibleFrame {
            let margin: CGFloat = 20
            let origin = NSPoint(
                x: screenFrame.maxX - window.frame.width - margin,
                y: screenFrame.maxY - window.frame.height - margin
            )
            window.setFrameOrigin(origin)
        }

        messagesWindowController = NSWindowController(window: window)
        messagesWindowController?.showWindow(nil)
        isOSCWindowVisible = true
    }

    // Generates a rectangular/pulse-train pattern of step events across [0, duree].
    // period: T in seconds. phase: fraction of the period (0...1) the pattern is
    // shifted by. pulseWidth: fraction of the period (0...1) spent at ampMax.
    private func rectangleEvents(period: Double, phase: Double, pulseWidth: Double, ampMin: Double, ampMax: Double, duree: Double) -> [TimelineEvent] {
        guard period > 0 else { return [] }
        let phaseOffset = phase * period
        let highDuration = min(max(pulseWidth, 0), 1) * period

        var events: [TimelineEvent] = []
        let firstN = Int((-phaseOffset / period).rounded(.down)) - 1
        var n = firstN
        while true {
            let cycleStart = Double(n) * period + phaseOffset
            if cycleStart > duree { break }
            let highEnd = cycleStart + highDuration
            if cycleStart >= 0 && cycleStart <= duree {
                events.append(TimelineEvent(time: cycleStart, label: "", y: ampMax))
            }
            if highEnd >= 0 && highEnd <= duree {
                events.append(TimelineEvent(time: highEnd, label: "", y: ampMin))
            }
            n += 1
        }

        // Make sure playback starting at t=0 reflects the correct held value,
        // even if the first generated edge falls after 0.
        if !events.contains(where: { $0.time == 0 }) {
            let containingN = Int(((0 - phaseOffset) / period).rounded(.down))
            let cycleStart0 = Double(containingN) * period + phaseOffset
            let highEnd0 = cycleStart0 + highDuration
            let valueAtZero = (0 >= cycleStart0 && 0 < highEnd0) ? ampMax : ampMin
            events.insert(TimelineEvent(time: 0, label: "", y: valueAtZero), at: 0)
        }

        return events.sorted { $0.time < $1.time }
    }

    // Generates a sine or skewed-sawtooth wave for curve tracks (piecewise-linear
    // interpolation between the generated points, so a Sin wave needs many
    // samples per period to look smooth; a Saw only needs 2 points per cycle
    // since it's already piecewise-linear).
    // Warps a normalized progress value t (0...1) into a symmetric S-curve
    // shape based on a single curvature parameter, matching Logic Pro's
    // automation curve tool. curvature == 0 leaves t unchanged (straight line).
    private func curvedProgress(_ t: Double, curvature: Double) -> Double {
        guard curvature != 0 else { return t }
        let k = pow(2, curvature)
        if t < 0.5 {
            return pow(t * 2, k) / 2
        } else {
            return 1 - pow((1 - t) * 2, k) / 2
        }
    }

    // A simple power-curve warp with no inflection point (single concave or
    // convex bow throughout, unlike curvedProgress's symmetric S-shape).
    // bulge == 0 leaves t unchanged (straight line).
    private func bulgeProgress(_ t: Double, bulge: Double) -> Double {
        guard bulge != 0 else { return t }
        let k = pow(2, bulge)
        return pow(t, k)
    }

    // Combines both warps: horizontal drag (segmentCurve, S-shape) and
    // vertical drag (segmentBulge, simple bow) apply together.
    private func combinedProgress(_ t: Double, curvature: Double, bulge: Double) -> Double {
        curvedProgress(bulgeProgress(t, bulge: bulge), curvature: curvature)
    }

    // The curve's rendered y-position (in track-local pixels), at a given
    // time, accounting for each segment's curvature. Returns nil if the time
    // falls outside the track's own point range (no curve there).
    private func curveYPosition(forTime time: Double, trackIndex: Int) -> CGFloat? {
        let sorted = pistes[trackIndex].evenements.sorted { $0.time < $1.time }
        guard sorted.count > 1, let first = sorted.first, let last = sorted.last,
              time >= first.time, time <= last.time else { return nil }

        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            guard time >= a.time && time <= b.time else { continue }
            let t = (b.time - a.time) > 0 ? (time - a.time) / (b.time - a.time) : 0
            let curvedT = combinedProgress(t, curvature: a.segmentCurve, bulge: a.segmentBulge)
            let value = a.y + (b.y - a.y) * curvedT
            let amplitudeRange = pistes[trackIndex].maxAmplitude - pistes[trackIndex].minAmplitude
            let normalizedY = amplitudeRange > 0 ? (value - pistes[trackIndex].minAmplitude) / amplitudeRange : 0.5
            return curveMargin + (pistes[trackIndex].height - 2 * curveMargin) * (1 - normalizedY)
        }
        return nil
    }

    // Whether the segment containing `time` is currently a hole
    // (segmentEnabled == false). Used to pick the erase vs. reconnect
    // cursor symbol while hovering. Defaults to true (no hole) if there's
    // no such segment.
    private func isSegmentEnabled(forTime time: Double, trackIndex: Int) -> Bool {
        let sorted = pistes[trackIndex].evenements.sorted { $0.time < $1.time }
        guard sorted.count > 1 else { return true }
        for i in 0..<(sorted.count - 1) {
            guard time >= sorted[i].time && time <= sorted[i + 1].time else { continue }
            return sorted[i].segmentEnabled
        }
        return true
    }

    // Directly applies the Shift segment-erase/reconnect cursor for a given
    // mouse location, imperatively — called from the curve area's
    // onContinuousHover on every real mouse movement. No @State involved,
    // so it works regardless of SwiftUI's render cycle.
    private func applyShiftSegmentCursor(at location: CGPoint, trackIndex: Int, largeurTimeline: CGFloat) {
        let time = (Double(location.x) / Double(largeurTimeline)) * duree
        if let curveY = curveYPosition(forTime: time, trackIndex: trackIndex),
           abs(Double(location.y) - Double(curveY)) < 12 {
            if isSegmentEnabled(forTime: time, trackIndex: trackIndex) {
                cursor(fromSymbol: "eraser.fill").set()
            } else {
                cursor(fromSymbol: "point.topleft.down.to.point.bottomright.curvepath.fill").set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    // Toggles segmentEnabled on whichever segment (curve tracks only)
    // contains `time`, punching or filling a silent "hole" in the curve.
    // Both endpoints stay untouched — only the interpolation/OSC output
    // between them is switched on or off.
    private func toggleSegmentEnabled(forTime time: Double, trackIndex: Int) {
        let sorted = pistes[trackIndex].evenements.sorted { $0.time < $1.time }
        guard sorted.count > 1 else { return }
        for i in 0..<(sorted.count - 1) {
            guard time >= sorted[i].time && time <= sorted[i + 1].time else { continue }
            if let eventIndex = pistes[trackIndex].evenements.firstIndex(where: { $0.id == sorted[i].id }) {
                pistes[trackIndex].evenements[eventIndex].segmentEnabled.toggle()
                lastSentEvents.removeAll()
            }
            return
        }
    }

    private func waveEvents(isSine: Bool, period: Double, phase: Double, skew: Double, ampMin: Double, ampMax: Double, duree: Double) -> [TimelineEvent] {
        guard period > 0 else { return [] }
        let phaseOffset = phase * period
        var events: [TimelineEvent] = []

        if isSine {
            // Only place control points at the peaks and troughs (where a sine's
            // tangent is naturally horizontal), and let the existing curve
            // interpolation (segmentCurve) compute the shape between them —
            // instead of approximating the wave with many sampled points.
            // curvature ≈ 1.0 was picked to closely match a real sine's shape
            // between a peak and a trough (a symmetric S-curve is a good fit,
            // since sine also has zero slope at the extremes and its steepest
            // slope exactly at the midpoint).
            let sineSegmentCurvature = 1.0
            let halfPeriod = period / 2
            let firstPeakTime = phaseOffset + period / 4
            let firstN = Int(((0 - firstPeakTime) / halfPeriod).rounded(.down)) - 1
            var n = firstN
            while true {
                let time = firstPeakTime + Double(n) * halfPeriod
                if time > duree { break }
                let parity = ((n % 2) + 2) % 2 // n=0 → first peak, alternating from there
                let value = parity == 0 ? ampMax : ampMin
                if time >= 0 && time <= duree {
                    events.append(TimelineEvent(time: time, label: "", y: value, segmentCurve: sineSegmentCurvature))
                }
                n += 1
            }
        } else {
            // Skew = fraction of the period spent rising (0...1). 0.5 = symmetric
            // triangle; near 1 = classic rising sawtooth; near 0 = reversed sawtooth.
            let riseDuration = min(max(skew, 0.01), 0.99) * period
            let firstN = Int(((0 - phaseOffset) / period).rounded(.down)) - 1
            var n = firstN
            while true {
                let cycleStart = Double(n) * period + phaseOffset
                if cycleStart > duree { break }
                let peakTime = cycleStart + riseDuration
                if cycleStart >= 0 && cycleStart <= duree {
                    events.append(TimelineEvent(time: cycleStart, label: "", y: ampMin))
                }
                if peakTime >= 0 && peakTime <= duree {
                    events.append(TimelineEvent(time: peakTime, label: "", y: ampMax))
                }
                n += 1
            }
        }

        return events.sorted { $0.time < $1.time }
    }

    // Generates evenly spaced bang events for bang/markers tracks.
    // defaultLabel is empty by design: plain bang tracks have no meaningful
    // label (only markers and message tracks do, and those pass an explicit
    // numberedLabelPrefix). It used to default to "M", which silently stamped
    // every autofilled bang with a stray marker-style label.
    private func bangEvents(period: Double, phase: Double, duree: Double, defaultLabel: String = "", numberedLabelPrefix: String? = nil) -> [TimelineEvent] {
        guard period > 0 else { return [] }
        let phaseOffset = phase * period
        var events: [TimelineEvent] = []
        var n = 0
        var counter = 1
        while true {
            let time = Double(n) * period + phaseOffset
            if time > duree { break }
            if time >= 0 {
                let label: String
                if let prefix = numberedLabelPrefix {
                    label = "\(prefix)_\(counter)"
                    counter += 1
                } else {
                    label = defaultLabel
                }
                events.append(TimelineEvent(time: time, label: label, y: 0.5))
            }
            n += 1
        }
        return events
    }

    // Called by the pencil button. Warns first if the track already has
    // points (since autofill replaces them entirely), otherwise opens the
    // relevant popup directly.
    // Builds an NSCursor from an SF Symbol image, tinted the given color.
    private func cursor(fromSymbol name: String, color: NSColor = .black) -> NSCursor {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(.init(paletteColors: [color]))
        // Falls back to a known-valid symbol (rather than an empty NSImage)
        // if `name` doesn't resolve — an invalid SF Symbol name would
        // otherwise silently produce an invisible cursor, which is exactly
        // the kind of bug that's very hard to notice/debug from testing
        // alone.
        let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: nil)
            ?? NSImage()
        let image = baseImage.withSymbolConfiguration(config) ?? baseImage
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }

    // All snap-target times currently available: marker positions, plus grid
    // lines when the grid is visible. Uses the same thinned-out set that's
    // actually rendered (visibleGridLineTimes), so snapping never lands on
    // a grid line that isn't visible on screen.
    private func snapCandidateTimes(largeurTimeline: Double) -> [Double] {
        var times = pistes[0].evenements.map { $0.time }
        if showGrid {
            times.append(contentsOf: visibleGridLineTimes(largeurTimeline: CGFloat(largeurTimeline)))
        }
        return times
    }

    // Finds the closest time to xPos among a given set of candidates, if any
    // falls within the 7px snap zone — nil otherwise.
    private func nearestTime(among candidates: [Double], xPos: Double, largeurTimeline: Double) -> Double? {
        guard !candidates.isEmpty, duree > 0 else { return nil }
        let closest = candidates.min(by: { a, b in
            let xA = (a / duree) * largeurTimeline
            let xB = (b / duree) * largeurTimeline
            return abs(xA - xPos) < abs(xB - xPos)
        })
        guard let closest = closest else { return nil }
        let closestXPos = (closest / duree) * largeurTimeline
        return abs(closestXPos - xPos) < 7 ? closest : nil
    }

    // The closest snap-target time to xPos (in timeline pixels), if any
    // falls within the 7px snap zone — nil otherwise. Combines markers and
    // grid lines (used for the ⌘-driven snap, and the hover snap-cursor
    // indicator, which treat both the same way).
    private func nearestSnapTime(xPos: Double, largeurTimeline: Double) -> Double? {
        nearestTime(among: snapCandidateTimes(largeurTimeline: largeurTimeline), xPos: xPos, largeurTimeline: largeurTimeline)
    }

    // Markers only (no grid lines) — the counterpart to nearestGridTime,
    // used to tell which of the two a combined ⌘-snap actually landed on.
    private func nearestMarkerTime(xPos: Double, largeurTimeline: Double) -> Double? {
        nearestTime(among: pistes[0].evenements.map { $0.time }, xPos: xPos, largeurTimeline: largeurTimeline)
    }

    // Grid lines only (no markers) — used for "magnetic grid" auto-snap,
    // which should never pull a point onto a marker without ⌘. Matches the
    // thinned-out set actually rendered on screen (visibleGridLineTimes),
    // so you can never snap to a line you can't see.
    private func nearestGridTime(xPos: Double, largeurTimeline: Double) -> Double? {
        guard showGrid else { return nil }
        return nearestTime(among: visibleGridLineTimes(largeurTimeline: CGFloat(largeurTimeline)), xPos: xPos, largeurTimeline: largeurTimeline)
    }

    // When both a marker and a grid line are within the snap zone, which one
    // is actually closer to xPos? Used purely to pick the cursor color
    // (marker snap stays black, grid snap turns gray) — the actual snapping
    // logic elsewhere already picks the true closest via nearestSnapTime.
    private func isNearestSnapAGridLine(xPos: Double, largeurTimeline: Double) -> Bool {
        let markerTime = nearestMarkerTime(xPos: xPos, largeurTimeline: largeurTimeline)
        let gridTime = nearestGridTime(xPos: xPos, largeurTimeline: largeurTimeline)
        guard let gridTime else { return false }
        guard let markerTime else { return true }
        let markerX = (markerTime / duree) * largeurTimeline
        let gridX = (gridTime / duree) * largeurTimeline
        return abs(gridX - xPos) < abs(markerX - xPos)
    }

    // Is xPos (in timeline pixels) within the 7px snap zone of the nearest
    // marker line or grid line?
    private func isNearMarker(xPos: Double, largeurTimeline: Double) -> Bool {
        nearestSnapTime(xPos: xPos, largeurTimeline: largeurTimeline) != nil
    }

    // Applies the right cursor for the current hover + modifier-key state
    // while hovering an actual point. Curve-segment hover (Option-bend,
    // Shift-erase/reconnect) is handled separately by CursorOverlay
    // instances, which use AppKit's cursor-rect/tracking-area system —
    // more reliable than ad-hoc NSCursor.set() calls during plain hover
    // (macOS silently overrides those outside an active drag), which is
    // why that logic doesn't live here.
    private func updatePointCursor() {
        guard isHoveringPoint else {
            NSCursor.arrow.set()
            return
        }
        if NSEvent.modifierFlags.contains(.shift) {
            cursor(fromSymbol: "eraser.badge.xmark").set()
        } else if NSEvent.modifierFlags.contains(.command) && isNearSnapZone {
            let color: NSColor = isNearestSnapGrid ? .gray : .black
            cursor(fromSymbol: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left", color: color).set()
        } else if magneticGridSnap && isNearGridSnapZone {
            cursor(fromSymbol: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left", color: .gray).set()
        } else {
            NSCursor.arrow.set()
        }
    }


    // Generates evenly spaced grid line times across [0, duree] — same
    // period/phase model as bangEvents, but returning bare times (no labels
    // needed since grid lines are purely visual, not OSC-emitting events).
    private func gridLineTimes(period: Double, phase: Double, duree: Double) -> [Double] {
        guard period > 0 else { return [] }
        let phaseOffset = phase * period
        var times: [Double] = []
        var n = 0
        while true {
            let time = Double(n) * period + phaseOffset
            if time > duree { break }
            if time >= 0 { times.append(time) }
            n += 1
        }
        return times
    }

    // For DISPLAY only (never for snapping, which stays at full granularity):
    // thins out the grid lines when their pixel spacing would be too dense
    // to read — e.g. a 1s grid period over a 5-minute track at fit-to-window
    // zoom would otherwise pack hundreds of dashed lines into a tiny space.
    // Keeps every Nth line (N = smallest power-of-two-ish multiplier that
    // brings the spacing above a legible minimum) instead of changing the
    // actual period itself.
    private func visibleGridLineTimes(largeurTimeline: CGFloat) -> [Double] {
        let allTimes = gridLineTimes(period: gridPeriod, phase: gridPhase, duree: duree)
        guard duree > 0, gridPeriod > 0, largeurTimeline > 0 else { return allTimes }
        let pixelsPerLine = largeurTimeline * CGFloat(gridPeriod / duree)
        let minSpacing: CGFloat = 16
        guard pixelsPerLine < minSpacing else { return allTimes }
        // How many consecutive lines to fold into one to reach minSpacing —
        // rounded up to a "nice" step (1, 2, 5, 10, 20, 50...) so the
        // remaining visible lines still land on clean multiples of the
        // original period rather than an arbitrary skip count.
        let rawSkip = Double(minSpacing / pixelsPerLine)
        let niceSteps: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000]
        let skip = niceSteps.first(where: { $0 >= rawSkip }) ?? (niceSteps.last ?? 1000)
        return allTimes.enumerated().compactMap { index, time in
            index % Int(skip) == 0 ? time : nil
        }
    }

    private func commitGridSettings() {
        if let period = Double(gridPeriodString), let phase = Double(gridPhaseString) {
            gridPeriod = period
            gridPhase = phase
        }
        showGridSettingsPopup = false
    }

    private func openGridSettingsPopup() {
        gridPeriodString = String(format: "%.2f", gridPeriod)
        gridPhaseString = String(format: "%.2f", gridPhase)
        showGridSettingsPopup = true
    }

    // Scrolls the timeline horizontally so the playhead is centered in the
    // viewport, regardless of the current zoom level. Used after any "go to"
    // jump (time, next marker, marker by name) so the result is always
    // actually visible, not just updated off-screen.
    private func centerOnPlayhead() {
        let outerWidth = max(timelineAreaWidth, 1)
        // timelineAreaWidth already excludes the duration handle (the whole
        // timeline area is padded by its width), so no extra subtraction here
        // — this must mirror the largeurTimeline used for drawing exactly.
        let largeurTimeline = outerWidth * CGFloat(zoomX) - 140
        guard largeurTimeline > 0 else { return }
        let playheadX = 140 + CGFloat(position / duree) * largeurTimeline
        scrollOffsetX = max(0, playheadX - outerWidth / 2)
    }

    // Jumps the playhead to the next marker strictly after the current
    // position; wraps around to the earliest marker if there is none, or
    // does nothing if there are no markers at all.
    private func goToNextMarker() {
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return }
        let target = sorted.first(where: { $0.time > position + 0.001 })?.time ?? sorted[0].time
        position = target
        sendOSCMessagesForPosition(position)
        centerOnPlayhead()
    }

    // Jumps the playhead to the previous marker strictly before the current
    // position; wraps around to the latest marker if there is none, or does
    // nothing if there are no markers at all.
    private func goToPreviousMarker() {
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return }
        let target = sorted.last(where: { $0.time < position - 0.001 })?.time ?? sorted[sorted.count - 1].time
        position = target
        sendOSCMessagesForPosition(position)
        centerOnPlayhead()
    }

    // Jumps the playhead to the marker whose label matches `name`.
    // Tries an exact case-insensitive match first, then falls back to a
    // case-insensitive substring match (so a partial name, or one with a
    // stray extra space, still finds something reasonable). Shows a
    // "No match" alert if nothing matches either way.
    private func goToMarkerByName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showGoToMarkerNoMatch = true
            return
        }
        let sorted = pistes[0].evenements.sorted { $0.time < $1.time }
        let exactMatch = sorted.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame })
        let partialMatch = sorted.first(where: { $0.label.range(of: trimmed, options: .caseInsensitive) != nil })
        guard let match = exactMatch ?? partialMatch else {
            showGoToMarkerNoMatch = true
            return
        }
        position = match.time
        sendOSCMessagesForPosition(position)
        centerOnPlayhead()
    }

    // Parses a "mm:ss" (or bare seconds) string and jumps the playhead
    // there, clamped to [0, duree]. Reuses the same parser as the duration
    // field.
    private func goToTime(_ text: String) {
        guard let parsed = parseDuration(text) else { return }
        position = min(max(parsed, 0), duree)
        sendOSCMessagesForPosition(position)
        centerOnPlayhead()
    }

    // Fold/unfold all tracks at once: if any track is currently unfolded,
    // fold everything; otherwise (everything already folded) unfold
    // everything. Mirrors the common "expand/collapse all" convention.
    private func toggleFoldAll() {
        let shouldFold = pistes.contains { !$0.isFolded }
        for i in pistes.indices {
            pistes[i].isFolded = shouldFold
        }
    }

    // Mute/unmute all tracks at once: if every track is already muted,
    // unmute everything; otherwise mute everything.
    private func muteUnmuteAll() {
        let shouldMute = !pistes.allSatisfy { $0.isMuted }
        for i in pistes.indices {
            pistes[i].isMuted = shouldMute
        }
    }

    // Removes every track except the pinned "/markers" track at index 0.
    private func deleteAllTracks() {
        guard !tracksLocked else { return }
        pistes = [pistes[0]]
        lastSentEvents.removeAll()
    }

    // Centralizes track creation (used by both the toolbar buttons and the
    // Tracks menu commands) so the lock guard only needs to live in one place.
    private func addTrack(couleur: Color, type: TrackType, height: CGFloat) {
        guard !tracksLocked else { return }
        pistes.append(TimelineTrack(nom: nextTrackName, couleur: couleur, evenements: [], type: type, height: height))
    }

    private func openAutofillPopup(for index: Int) {
        guard !tracksLocked else { return }
        if pistes[index].evenements.isEmpty {
            proceedWithAutofill(for: index)
        } else {
            pendingAutofillIndex = index
        }
    }

    private func proceedWithAutofill(for index: Int) {
        switch pistes[index].type {
        case .step:
            autofillTrackIndex = index
            autofillPeriodString = "1.0"
            autofillPhaseString = "0.0"
            autofillPulseWidthString = "0.5"
            autofillAmpMinString = String(format: "%.2f", pistes[index].minAmplitude)
            autofillAmpMaxString = String(format: "%.2f", pistes[index].maxAmplitude)
        case .curve:
            waveTrackIndex = index
            waveIsSine = true
            wavePeriodString = "1.0"
            wavePhaseString = "0.0"
            waveSkewString = "0.5"
            waveAmpMinString = String(format: "%.2f", pistes[index].minAmplitude)
            waveAmpMaxString = String(format: "%.2f", pistes[index].maxAmplitude)
        case .bang, .message:
            bangTrackIndex = index
            bangPeriodString = "1.0"
            bangPhaseString = "0.0"
            bangLabelPrefixString = pistes[index].type == .message ? "key" : "M"
        case .normal:
            break
        }
    }

    private func sendOSCMessagesForPosition(_ pos: Double) {
        for piste in pistes where !piste.isMuted {
            if piste.type == .bang {
                let tol = 0.01
                for event in piste.evenements {
                    if abs(pos - event.time) < tol {
                        if piste.nom == "/markers" {
                            let label = event.label.isEmpty ? "marker" : event.label
                            sendOSCMessage(piste.nom + " " + label, color: piste.couleur)
                        } else {
                            sendOSCMessage(piste.nom + " bang", color: piste.couleur)
                        }
                    }
                }
            } else if piste.type == .message {
                let tol = 0.01
                for event in piste.evenements {
                    if abs(pos - event.time) < tol {
                        sendOSCMessage(piste.nom + " " + event.label, color: piste.couleur)
                    }
                }
            } else if piste.type == .curve {
                // Only speaks where the curve is actually drawn — strictly
                // between its first and last point. Before the first point
                // or after the last one, the track stays silent instead of
                // continuously repeating the nearest endpoint's value.
                let sortedEvents = piste.evenements.sorted { $0.time < $1.time }
                if sortedEvents.isEmpty { continue }

                let lastEventBefore = sortedEvents.last(where: { $0.time <= pos })
                let nextEvent = sortedEvents.first(where: { $0.time > pos })

                if let lastEventBefore = lastEventBefore, let nextEvent = nextEvent, lastEventBefore.segmentEnabled {
                    let ratio = (pos - lastEventBefore.time) / (nextEvent.time - lastEventBefore.time)
                    let curvedRatio = combinedProgress(ratio, curvature: lastEventBefore.segmentCurve, bulge: lastEventBefore.segmentBulge)
                    let interpolatedY = lastEventBefore.y + (nextEvent.y - lastEventBefore.y) * curvedRatio
                    sendOSCMessage(piste.nom + " " + String(format: "%.2f", interpolatedY), color: piste.couleur)
                }
            } else if piste.type == .step {
                // Zero-order hold: send the last event's value as-is, never interpolated.
                let sortedEvents = piste.evenements.sorted { $0.time < $1.time }
                if sortedEvents.isEmpty { continue }

                if let lastEventBefore = sortedEvents.last(where: { $0.time <= pos }) {
                    sendOSCMessage(piste.nom + " " + String(format: "%.2f", lastEventBefore.y), color: piste.couleur)
                } else if let firstEvent = sortedEvents.first {
                    sendOSCMessage(piste.nom + " " + String(format: "%.2f", firstEvent.y), color: piste.couleur)
                }
            }
        }
    }

    // Called every 50ms by the playback timer. Pulled out into its own
    // function (rather than a large inline closure) so Swift type-checks it
    // on its own, instead of as part of one giant expression tree together
    // with the rest of the view body — which was timing out the compiler.
    private func advancePlaybackTick() {
        guard enLecture else {
            // Reset so that resuming later doesn't compute a delta spanning
            // the whole time playback was paused/stopped.
            lastTickTimestamp = nil
            return
        }

        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        // First tick after starting/resuming: fall back to the nominal 0.05
        // since there's no previous timestamp yet to compute a real delta from.
        let delta = lastTickTimestamp.map { now - $0 } ?? 0.05
        lastTickTimestamp = now

        let prev = position
        position += delta
        var justLooped = false
        if position >= duree {
            position = 0.0
            if !enBoucle { enLecture = false }
            lastSentEvents.removeAll()
            justLooped = true
        }
        // Right on the tick where playback wraps back to 0, `prev` still
        // holds the old (near-`duree`) position — comparing it directly
        // against early event times would make the crossing check
        // (prev < event.time <= position) fail for anything near the
        // start, since prev is much larger than those times. Substitute a
        // value below 0 for that one tick so events from the very start of
        // the loop are correctly treated as freshly crossed.
        let effectivePrev = justLooped ? -1.0 : prev

        for piste in pistes {
            guard piste.type == .bang, !piste.isMuted else { continue }
            let tol = 0.001
            for event in piste.evenements {
                guard effectivePrev < event.time - tol && position >= event.time - tol else { continue }
                let key = piste.nom + "-" + String(event.time)
                guard !lastSentEvents.contains(key) else { continue }
                lastSentEvents.insert(key)
                if piste.nom == "/markers" {
                    let label = event.label.isEmpty ? "marker" : event.label
                    sendOSCMessage(piste.nom + " " + label, color: piste.couleur)
                } else {
                    sendOSCMessage(piste.nom + " bang", color: piste.couleur)
                }
            }
        }

        for piste in pistes {
            guard piste.type == .message, !piste.isMuted else { continue }
            let tol = 0.001
            for event in piste.evenements {
                guard effectivePrev < event.time - tol && position >= event.time - tol else { continue }
                let key = piste.nom + "-message-" + String(event.time)
                guard !lastSentEvents.contains(key) else { continue }
                lastSentEvents.insert(key)
                sendOSCMessage(piste.nom + " " + event.label, color: piste.couleur)
            }
        }

        for piste in pistes {
            guard piste.type == .curve, !piste.isMuted else { continue }
            // Only speaks where the curve is actually drawn — see the same
            // comment in sendOSCMessagesForPosition.
            let sortedEvents = piste.evenements.sorted { $0.time < $1.time }
            if sortedEvents.isEmpty { continue }

            let lastEventBefore = sortedEvents.last(where: { $0.time <= position })
            let nextEvent = sortedEvents.first(where: { $0.time > position })

            if let lastEventBefore = lastEventBefore, let nextEvent = nextEvent, lastEventBefore.segmentEnabled {
                let ratio = (position - lastEventBefore.time) / (nextEvent.time - lastEventBefore.time)
                let curvedRatio = combinedProgress(ratio, curvature: lastEventBefore.segmentCurve, bulge: lastEventBefore.segmentBulge)
                let interpolatedY = lastEventBefore.y + (nextEvent.y - lastEventBefore.y) * curvedRatio
                sendOSCMessage(piste.nom + " " + String(format: "%.2f", interpolatedY), color: piste.couleur)
            }
        }

        for piste in pistes {
            guard piste.type == .step, !piste.isMuted else { continue }
            // Zero-order hold, but only send OSC when a new point is crossed —
            // the value doesn't change between two points, so continuous sending
            // (like every 50ms tick) would just flood the system uselessly.
            let tol = 0.001
            for event in piste.evenements {
                guard effectivePrev < event.time - tol && position >= event.time - tol else { continue }
                let key = piste.nom + "-step-" + String(event.time)
                guard !lastSentEvents.contains(key) else { continue }
                lastSentEvents.insert(key)
                sendOSCMessage(piste.nom + " " + String(format: "%.2f", event.y), color: piste.couleur)
            }
        }
    }

    // Everything that used to run inline in .onAppear's closure, pulled out
    // into its own function for the same reason as advancePlaybackTick():
    // large closures embedded directly in the view body get type-checked as
    // part of one giant expression tree together with the rest of `body`,
    // which was timing out the compiler.
    private func setupOnAppear() {
        // macOS assigns first responder to the first key-view-eligible
        // NSTextField right after the window appears, regardless of
        // FocusState's initial value — so we explicitly clear it again
        // a beat later to actually win that race.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedField = nil
        }

        dureeText = formattedDuration(duree)

        // Incoming OSC messages control transport from the outside.
        oscManager.onOSCMessageReceived = handleReceivedOSCMessage
        oscManager.startListening(port: oscReceivePort)

        // .onHover alone only fires on enter/exit; this keeps the point
        // cursor (shift/cmd) in sync if the modifier key changes while
        // the mouse stays over the same point.
        if flagsChangedMonitor == nil {
            flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                updatePointCursor()
                isOptionHeldForCursor = event.modifierFlags.contains(.option)
                return event
            }
        }

        if fullScreenEnterObserver == nil {
            fullScreenEnterObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
                isFullScreen = true
            }
        }
        if fullScreenExitObserver == nil {
            fullScreenExitObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
                isFullScreen = false
            }
        }

        startPlaybackTimer()
    }

    // (Re)creates the playback timer at the interval implied by the current
    // oscMessagesPerSecond setting (interval = 1 / rate). Called on setup and
    // again whenever the rate changes mid-session, so the new rate takes
    // effect immediately without needing to stop/restart playback.
    private func startPlaybackTimer() {
        timer?.invalidate()
        let rate = max(1, oscMessagesPerSecond)
        let interval = 1.0 / Double(rate)
        let playbackTimer = Timer(timeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                advancePlaybackTick()
            }
        }
        // .common (not just .default) so playback keeps ticking even while
        // some other drag (a point, a track resize, the duration handle...)
        // is actively being tracked elsewhere in the app.
        RunLoop.main.add(playbackTimer, forMode: .common)
        timer = playbackTimer
    }

    // Parses whatever is currently in the duration text field and applies it
    // to `duree`, then resyncs the text field to the canonical "mm:ss.cc" form
    // (so e.g. "1:5" becomes "01:05.00", and invalid text reverts cleanly).
    // Typed durations are rounded to whole seconds on purpose: sub-second
    // precision is only ever meant to come from the trim handle, so there's no
    // need to think about centiseconds when typing a duration in.
    private func commitDureeEdit() {
        if let parsed = parseDuration(dureeText) {
            duree = max(parsed.rounded(), 1)
        }
        dureeText = formattedDuration(duree)
    }

    private func handleReceivedOSCMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        switch normalized {
        case "play":
            enLecture = true
        case "pause":
            enLecture = false
        case "stop":
            enLecture = false
            position = 0
            lastSentEvents.removeAll()
        default:
            break
        }
    }

    private func tearDownOnDisappear() {
        timer?.invalidate()
        timer = nil
        oscManager.cancelConnection()
        oscManager.stopListening()
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        if let observer = fullScreenEnterObserver {
            NotificationCenter.default.removeObserver(observer)
            fullScreenEnterObserver = nil
        }
        if let observer = fullScreenExitObserver {
            NotificationCenter.default.removeObserver(observer)
            fullScreenExitObserver = nil
        }
        stopDurationDragTimer()
        oscFlashTimer?.invalidate()
        oscFlashTimer = nil
    }

    // Recenters the horizontal scroll so the playhead stays at the same
    // on-screen (viewport-relative) position before and after a zoom
    // change — i.e. the zoom appears to happen "around" the playhead.
    // (Pinch-zoom anchors on the mouse position instead, handled separately
    // in TimelineScrollView's Coordinator.)
    private func recenterOnZoomChange(oldZoom: Double, newZoom: Double, outerWidth: CGFloat) {
        guard !isPinchZooming else { return }
        let largeurAvant = outerWidth * CGFloat(oldZoom) - 140
        guard largeurAvant > 0 else { return }

        let anchorTime = min(max(position, 0), duree)
        let absoluteContentXBefore = 140 + CGFloat(anchorTime / duree) * largeurAvant
        let locationXInViewport = absoluteContentXBefore - scrollOffsetX

        let largeurApres = outerWidth * CGFloat(newZoom) - 140
        guard largeurApres > 0 else { return }
        let absoluteContentXAfter = 140 + CGFloat(anchorTime / duree) * largeurApres
        let maxX = max(0, outerWidth * CGFloat(newZoom) - outerWidth)
        let newOffsetX = max(0, min(absoluteContentXAfter - locationXInViewport, maxX))
        scrollOffsetX = newOffsetX
    }

    private func commitPointEdit() {
        if let (trackIndex, eventId) = pointAEditer,
           let newPosition = Double(nouvellePositionString),
           let eventIndex = pistes[trackIndex].evenements.firstIndex(where: { $0.id == eventId }) {
            pistes[trackIndex].evenements[eventIndex].time = min(max(newPosition, 0), duree)
            if (pistes[trackIndex].type == .curve || pistes[trackIndex].type == .step), let newY = Double(nouvelleYString) {
                let constrainedY = min(max(newY, pistes[trackIndex].minAmplitude), pistes[trackIndex].maxAmplitude)
                pistes[trackIndex].evenements[eventIndex].y = gateSnappedY(constrainedY, forTrackIndex: trackIndex)
            }
            if trackIndex == 0 || pistes[trackIndex].type == .message {
                pistes[trackIndex].evenements[eventIndex].label = nouveauLabel
            }
            pistes[trackIndex].evenements[eventIndex].comment = nouveauComment
            pistes[trackIndex].evenements.sort()
            lastSentEvents.removeAll()
        }
        pointAEditer = nil
    }

    // Actually performs the Float -> Gate switch: forces the 0...1 range and
    // snaps every existing point to strict boolean 0/1. Split out from
    // commitAmplitudeEdit so it can be deferred behind a confirmation when
    // there are existing points to redistribute.
    private func applyGateModeSwitch(forTrackIndex index: Int) {
        pistes[index].isGate = true
        pistes[index].minAmplitude = 0
        pistes[index].maxAmplitude = 1
        // Gate is itself a 0/1 quantization — any step value would be dead
        // state, and would come back if the track were switched to Float again.
        pistes[index].quantizeStep = 0
        for i in pistes[index].evenements.indices {
            pistes[index].evenements[i].y = gateSnappedY(pistes[index].evenements[i].y, forTrackIndex: index)
        }
        lastSentEvents.removeAll()
    }

    private func commitAmplitudeEdit() {
        guard let index = amplitudeEditorTrackIndex else {
            amplitudeEditorTrackIndex = nil
            return
        }
        if pistes[index].type == .step && tempIsGate {
            // Switching FROM Float TO Gate with existing points would
            // silently redistribute all their values to 0/1 — warn first
            // instead, and only apply once the user confirms.
            if !pistes[index].isGate && !pistes[index].evenements.isEmpty {
                pendingGateSwitchIndex = index
                amplitudeEditorTrackIndex = nil
                return
            }
            applyGateModeSwitch(forTrackIndex: index)
        } else {
            if pistes[index].type == .step {
                pistes[index].isGate = false
            }
            if let minVal = Double(tempMinAmplitude), let maxVal = Double(tempMaxAmplitude) {
                pistes[index].minAmplitude = minVal
                pistes[index].maxAmplitude = maxVal
            }
            // A step bigger than half the range would leave fewer than three
            // usable values (the track would collapse onto its endpoints), so
            // it's clamped — and the user is told, rather than silently getting
            // something other than what they typed.
            if !tempQuantizeEnabled {
                pistes[index].quantizeStep = 0
            } else if let stepVal = Double(tempQuantizeStep), stepVal > 0 {
                let range = pistes[index].maxAmplitude - pistes[index].minAmplitude
                let maxStep = range / 2
                if range > 0 && stepVal > maxStep {
                    pistes[index].quantizeStep = maxStep
                    invalidQuantizeStepMessage = String(
                        format: "A step of %g is too large for the range [%g, %g]. It must not exceed half the range, so it has been set to %g.",
                        stepVal, pistes[index].minAmplitude, pistes[index].maxAmplitude, maxStep
                    )
                } else {
                    pistes[index].quantizeStep = range > 0 ? stepVal : 0
                }
            }
            // Re-snap existing points onto the new grid, so the track's
            // contents actually match what the ticks now show.
            if pistes[index].quantizeStep > 0 {
                for i in pistes[index].evenements.indices {
                    pistes[index].evenements[i].y = quantizedY(pistes[index].evenements[i].y, forTrackIndex: index)
                }
                lastSentEvents.removeAll()
            }
        }
        amplitudeEditorTrackIndex = nil
    }

    private func commitAutofillRectangle() {
        if let index = autofillTrackIndex,
           let period = Double(autofillPeriodString),
           let phase = Double(autofillPhaseString),
           let pulseWidth = Double(autofillPulseWidthString),
           let ampMin = Double(autofillAmpMinString),
           let ampMax = Double(autofillAmpMaxString) {
            pistes[index].evenements = rectangleEvents(
                period: period,
                phase: phase,
                pulseWidth: pulseWidth,
                ampMin: ampMin,
                ampMax: ampMax,
                duree: duree
            )
            lastSentEvents.removeAll()
        }
        autofillTrackIndex = nil
    }

    private func commitAutofillWave() {
        if let index = waveTrackIndex,
           let period = Double(wavePeriodString),
           let phase = Double(wavePhaseString),
           let skew = Double(waveSkewString),
           let ampMin = Double(waveAmpMinString),
           let ampMax = Double(waveAmpMaxString) {
            pistes[index].evenements = waveEvents(
                isSine: waveIsSine,
                period: period,
                phase: phase,
                skew: skew,
                ampMin: ampMin,
                ampMax: ampMax,
                duree: duree
            )
            lastSentEvents.removeAll()
        }
        waveTrackIndex = nil
    }

    private func commitAutofillBang() {
        if let index = bangTrackIndex,
           let period = Double(bangPeriodString),
           let phase = Double(bangPhaseString) {
            let isMarkersTrack = index == 0
            let isMessageTrack = pistes[index].type == .message
            let trimmedPrefix = bangLabelPrefixString.trimmingCharacters(in: .whitespaces)
            let numberedLabelPrefix: String?
            if isMarkersTrack {
                numberedLabelPrefix = trimmedPrefix.isEmpty ? "M" : trimmedPrefix
            } else if isMessageTrack {
                numberedLabelPrefix = trimmedPrefix.isEmpty ? "key" : trimmedPrefix
            } else {
                numberedLabelPrefix = nil
            }
            pistes[index].evenements = bangEvents(
                period: period,
                phase: phase,
                duree: duree,
                numberedLabelPrefix: numberedLabelPrefix
            )
            lastSentEvents.removeAll()
        }
        bangTrackIndex = nil
    }

    // Compact alternative to the full toolbar (toggled via the View menu,
    // ⌘B): a full-width bar acting as an extended version of the position
    // display — same black/blue styling, but stretched across the window
    // with the position centered, a play/pause indicator ~50px to its left,
    // and a loop indicator on the right.
    // "Paused" vs "stopped" aren't separately tracked in the app's state
    // (both are just enLecture == false); we approximate "stopped" as
    // enLecture == false with position back at 0 (which Stop always does,
    // unlike Pause), and show nothing in that case per the spec ("rien si
    // stop").
    // Two-tone "Duration mm:ss" label for the compact command bar, built via
    // AttributedString rather than concatenating separate Text views with
    // `+` (deprecated since macOS 26 in favor of string interpolation /
    // AttributedString for per-segment styling).
    private var durationLabelText: Text {
        var attributed = AttributedString("Duration ")
        attributed.foregroundColor = .gray
        var value = AttributedString(formattedDuration(duree))
        value.foregroundColor = Color(red: 0.3, green: 0.6, blue: 1.0)
        attributed.append(value)
        return Text(attributed)
    }

    private var compactControlBar: some View {
        ZStack {
            Rectangle().fill(Color.black)
            Text(formattedPosition(position))
                .font(.system(size: 20, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    showCommandBar = true
                }
            Group {
                if enLecture {
                    Image(systemName: "play.fill")
                        .foregroundColor(Color(red: 0.5, green: 1.0, blue: 0.2))
                } else if position > 0.001 {
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
            .foregroundColor(isOSCFlashing ? .yellow : .clear)
            .offset(x: 220)
        }
        .frame(height: 32)
        .padding(.top, isFullScreen ? 0 : 30)
    }

    // A reserved margin strip pinned to the right edge of the window,
    // spanning the full height (ruler + tracks): background matching the
    // app's outer background, a thin vertical divider at its left edge, and
    // a triangle handle at the top. Dragging the whole strip horizontally
    // trims the track's total duration (right = longer, left = shorter),
    // independent of scroll position or zoom.
    // Starts the repeating timer that continuously applies the duration
    // drag's current rate of change (see durationDragCurrentDeltaX) for as
    // long as the drag is held — this is what makes it velocity-based
    // rather than a one-shot position mapping.
    private func startDurationDragTimer() {
        durationDragTimer?.invalidate()
        let tickInterval = 0.02
        let newTimer = Timer(timeInterval: tickInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                let dx = Double(durationDragCurrentDeltaX)
                let magnitude = pow(abs(dx), durationDragVelocityExponent) * durationDragVelocityScale
                let ratePerSecond = dx < 0 ? -magnitude : magnitude
                let rawDuree = duree + ratePerSecond * tickInterval
                let quantized = (rawDuree * 100).rounded() / 100
                duree = max(0.1, quantized)
                dureeText = formattedDuration(duree)
            }
        }
        // Timer.scheduledTimer only runs in the .default run loop mode,
        // which AppKit suspends while actively tracking a mouse drag (the
        // run loop switches to .eventTracking mode during that time) — so
        // the timer would silently never fire while the drag is held.
        // Adding it in .common mode instead keeps it running throughout.
        RunLoop.main.add(newTimer, forMode: .common)
        durationDragTimer = newTimer
    }

    private func stopDurationDragTimer() {
        durationDragTimer?.invalidate()
        durationDragTimer = nil
    }

    private var durationDragHandle: some View {
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
            if isDraggingDurationHandle {
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
                    if !isDraggingDurationHandle {
                        isDraggingDurationHandle = true
                        startDurationDragTimer()
                    }
                    durationDragCurrentDeltaX = value.translation.width
                }
                .onEnded { _ in
                    stopDurationDragTimer()
                    isDraggingDurationHandle = false
                    durationDragCurrentDeltaX = 0
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
    private var durationTooltip: some View {
        VStack(alignment: .trailing, spacing: 0) {
            UpPointingTriangle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 10, height: 6)
                .padding(.trailing, 8)
            Text(formattedPosition(duree))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.85))
                .cornerRadius(6)
        }
    }

    var body: some View {
        let baseContent = VStack(spacing: 0) {
            if showCommandBar {
            HStack {
                RotaryKnob(value: $zoomX, range: 1.0...maxZoomX, onDoubleTap: {
                    zoomX = 1.0
                }, sensitivity: zoomKnobSensitivity)
                .overlay(alignment: .bottom) {
                    Text("zoom")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 19)
                }
                .offset(x: -100)
                Button(action: { enLecture.toggle() }) {
                    Image(systemName: enLecture ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.black)
                        .frame(width: 60, height: 32)
                        .background(enLecture ? Color(red: 0.5, green: 1.0, blue: 0.2) : Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Button(action: { enLecture = false; position = 0.0; lastSentEvents.removeAll() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundColor(.black)
                        .frame(width: 60, height: 32)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Button(action: { enBoucle.toggle() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(enBoucle ? .black : .gray)
                        .frame(width: 60, height: 32)
                        .background(enBoucle ? Color.yellow : Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                TextField("Duration", text: $dureeText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 85, height: 22)
                    .focused($focusedField, equals: .duree)
                    .onSubmit {
                        commitDureeEdit()
                        if focusedField == .duree { focusedField = nil }
                    }
                    .onChange(of: focusedField) { oldValue, newValue in
                        if oldValue == .duree && newValue != .duree {
                            commitDureeEdit()
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Text("duration")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 23)
                    }
                Text(formattedPosition(position))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))
                    .frame(width: 120, height: 22)
                    .background(Color.black)
                    .cornerRadius(5)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        showCommandBar = false
                    }
                    .overlay(alignment: .bottom) {
                        Text("position")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 23)
                    }
                TextField("OSC", text: Binding(
                    get: { oscManager.address },
                    set: { newValue in
                        oscManager.address = newValue
                        oscManager.setupOSCConnection()
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 150, height: 22)
                .focused($focusedField, equals: .oscAddress)
                .onSubmit {
                    if focusedField == .oscAddress { focusedField = nil }
                }
                .overlay(alignment: .bottom) {
                    Text("OSC address")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 23)
                }
                HStack(spacing: 0) {
                    Button(action: {
                        addTrack(couleur: .blue, type: .bang, height: 45)
                    }) {
                        Image("button_bangTrack")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("bang")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 18)
                    }

                    Button(action: {
                        addTrack(couleur: .yellow, type: .curve, height: 60)
                    }) {
                        Image("button_curveTrack")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("curve")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 18)
                    }

                    Button(action: {
                        addTrack(couleur: Color(red: 0.6549019607843137, green: 0.6784313725490196, blue: 0.0), type: .message, height: 45)
                    }) {
                        Image("button_messageTrack")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("message")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 18)
                    }

                    Button(action: {
                        addTrack(couleur: Color(red: 0.608, green: 0.086, blue: 0.365), type: .step, height: 60)
                    }) {
                        Image("button_stepTrack")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("step")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .offset(y: 18)
                    }
                }
                Button(action: { showPointCoordinates.toggle() }) {
                    Text("x,y")
                        .font(.body)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 28)
                        .background(showPointCoordinates ? Color.yellow : Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Image(systemName: "grid")
                    .font(.body)
                    .foregroundColor(.black)
                    .frame(width: 44, height: 28)
                    .background(showGrid ? Color.yellow : Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    // Option+click opens the grid settings without touching
                    // showGrid; a plain click toggles the grid on/off. Single
                    // onTapGesture checking the modifier at click time (same
                    // pattern used elsewhere, e.g. shift-click to delete a
                    // point), rather than double-click, which doesn't affect
                    // the toggle state at all.
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.option) {
                            openGridSettingsPopup()
                        } else {
                            showGrid.toggle()
                        }
                    }
                Button(action: {
                    showClearAllConfirmation = true
                }) {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 28)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Button(action: openOSCMessagesWindow) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.body)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 28)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Show OSC messages")
                .overlay(alignment: .bottom) {
                    Text("OSC")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 20)
                }

                Button(action: openPointsListWindow) {
                    Image(systemName: "list.bullet")
                        .font(.body)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 28)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Show points list")
                .overlay(alignment: .bottom) {
                    Text("points")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                        .offset(y: 20)
                }

                Button(action: saveProject) {
                    Text("Save")
                }
                .buttonStyle(.bordered)
                .padding(.leading, 100)
                Button(action: loadProject) {
                    Text("Load")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, isFullScreen ? 0 : 30)
            .frame(height: isFullScreen ? 70 : 100)
            } else {
                compactControlBar
            }

            GeometryReader { outerGeometry in
                TimelineScrollView(
                    offsetX: $scrollOffsetX,
                    zoomX: $zoomX,
                    isPinchZooming: $isPinchZooming,
                    zoomRange: 1.0...maxZoomX,
                    duree: duree,
                    contentWidth: outerGeometry.size.width * CGFloat(zoomX),
                    contentHeight: max(outerGeometry.size.height, totalTracksHeight),
                    zoomSensitivity: zoomKnobSensitivity
                ) {
                        GeometryReader { geometry in
                            // NOTE: do NOT subtract durationHandleWidth here. The playhead,
                            // grid and marker lines are drawn in the outer coordinate space
                            // (offset by +140) while the points live inside each track's own
                            // space — both derive from this same largeurTimeline, so shrinking
                            // it here desynchronised them (playhead/grid drifted left of the
                            // points). The handle's 18px are reserved on the container
                            // instead, further down, which keeps a single consistent scale.
                            let largeurTimeline = geometry.size.width - 140
                            let totalHeight = 24 + visiblePistes.reduce(CGFloat(0)) { $0 + rowHeight(for: $1) } + CGFloat(visiblePistes.count * 5)

                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(Color.gray.opacity(0.1)).frame(height: 24)
                                        if tracksLocked {
                                            Rectangle().fill(Color.black).frame(width: 140, height: 24)
                                        }
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(height: 24)
                                            .onTapGesture { location in
                                                guard location.x > 140 else { return }
                                                let positionCliquee = (Double(location.x - 140) / Double(largeurTimeline)) * duree
                                                position = min(max(positionCliquee, 0), duree)
                                                sendOSCMessagesForPosition(position)
                                            }
                                        Button(action: { tracksLocked.toggle() }) {
                                            Image(systemName: tracksLocked ? "lock.fill" : "lock.open")
                                                .font(.system(size: 18))
                                                .foregroundColor(tracksLocked ? .red : .gray)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.leading, 10)
                                        .help(tracksLocked ? "Tracks are locked" : "Tracks are unlocked")
                                        // Dynamic tick interval: depends on pixels per second (so it already
                                        // accounts for zoom, via largeurTimeline), not just the total duration —
                                        // otherwise, zoomed in a lot on a long track, the interval would represent
                                        // thousands of pixels and no tick would fall within the visible area.
                                        let pixelsPerSecond = largeurTimeline / CGFloat(max(duree, 0.001))
                                        let minPixelSpacing: CGFloat = 100
                                        let niceIntervals: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
                                        let labelInterval = niceIntervals.first(where: { CGFloat($0) * pixelsPerSecond >= minPixelSpacing }) ?? (niceIntervals.last ?? 3600)

                                        // Only generate ticks for the currently visible portion (plus a small
                                        // buffer), not the whole duration: zoomed in a lot, computing ticks over
                                        // an entire long track would be both useless (invisible) and costly
                                        // (tens of thousands of elements).
                                        let outerWidth = outerGeometry.size.width
                                        let buffer: CGFloat = 200
                                        let visibleStartSeconde = max(0, Double((scrollOffsetX - buffer - 140) / largeurTimeline) * duree)
                                        let visibleEndSeconde = min(duree, Double((scrollOffsetX + outerWidth + buffer - 140) / largeurTimeline) * duree)
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
                                                .offset(x: CGFloat(seconde / duree) * largeurTimeline - 35)
                                            }
                                        }
                                        // Pinned to the full available width so the mask below lines
                                        // up with real coordinates — otherwise the ZStack would size
                                        // itself to its content and the mask's 140px would land
                                        // somewhere else entirely.
                                        .frame(width: geometry.size.width, alignment: .leading)
                                        .mask(
                                            HStack(spacing: 0) {
                                                Color.clear.frame(width: 140)
                                                Color.black
                                            }
                                        )
                                    }

                                    ForEach(Array(pistes.enumerated()), id: \.element.id) { index, _ in
                                        if index != 0 || showMarkersTrack {
                                        HStack(spacing: 0) {
                                            ZStack(alignment: .topLeading) {
                                                Rectangle()
                                                    .fill(pistes[index].couleur)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                                if index == 0 {
                                                    Text("/markers")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .padding(.leading, 10)
                                                        .offset(y: 5)
                                                        .onTapGesture(count: 2) { }
                                                } else {
                                                    Text(pistes[index].nom)
                                                        .font(.system(size: 12, weight: .bold))
                                                        .padding(.leading, 10)
                                                        .offset(y: 5)
                                                        .onTapGesture(count: 2) {
                                                            guard !tracksLocked else { return }
                                                            let piste = pistes[index]
                                                            indexPisteARenommer = index
                                                            nouveauNomPiste = piste.nom
                                                        }

                                                    // Drag handle for reordering this track among its siblings
                                                    // ("markers" at index 0 stays pinned, never reordered).
                                                    Image(systemName: "line.3.horizontal")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.black.opacity(0.35))
                                                        .padding(6)
                                                        .contentShape(Rectangle())
                                                        .offset(x: 116, y: 2)
                                                        .gesture(
                                                            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                                                                .onChanged { value in
                                                                    guard !tracksLocked else { return }
                                                                    if reorderingIndex == nil {
                                                                        reorderingIndex = index
                                                                        reorderBaselineOffset = 0
                                                                    }
                                                                    guard let currentIndex = reorderingIndex else { return }
                                                                    let effectiveTranslation = value.translation.height - reorderBaselineOffset

                                                                    if effectiveTranslation > 0, currentIndex < pistes.count - 1 {
                                                                        let belowHeight = rowHeight(for: pistes[currentIndex + 1]) + 5
                                                                        if effectiveTranslation > belowHeight / 2 {
                                                                            pistes.swapAt(currentIndex, currentIndex + 1)
                                                                            reorderBaselineOffset += belowHeight
                                                                            reorderingIndex = currentIndex + 1
                                                                        }
                                                                    } else if effectiveTranslation < 0, currentIndex > 1 {
                                                                        let aboveHeight = rowHeight(for: pistes[currentIndex - 1]) + 5
                                                                        if effectiveTranslation < -aboveHeight / 2 {
                                                                            pistes.swapAt(currentIndex, currentIndex - 1)
                                                                            reorderBaselineOffset -= aboveHeight
                                                                            reorderingIndex = currentIndex - 1
                                                                        }
                                                                    }

                                                                    reorderDragTranslation = value.translation.height - reorderBaselineOffset
                                                                }
                                                                .onEnded { _ in
                                                                    reorderingIndex = nil
                                                                    reorderDragTranslation = 0
                                                                    reorderBaselineOffset = 0
                                                                }
                                                        )
                                                        .onHover { isHovering in
                                                            if isHovering {
                                                                NSCursor.openHand.set()
                                                            } else {
                                                                NSCursor.arrow.set()
                                                            }
                                                        }
                                                        .help("Drag to reorder this track")
                                                }

                                                // Fold/unfold: collapses the track's header down to just its
                                                // name, this triangle, and the reorder handle, and hides its
                                                // points/curves in the timeline area.
                                                Button(action: {
                                                    pistes[index].isFolded.toggle()
                                                }) {
                                                    Image(systemName: pistes[index].isFolded ? "arrowtriangle.right.fill" : "arrowtriangle.down.fill")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(.black.opacity(0.5))
                                                }
                                                .buttonStyle(.borderless)
                                                .offset(x: 100, y: 6)
                                                .help(pistes[index].isFolded ? "Unfold track" : "Fold track")

                                                if !pistes[index].isFolded && (pistes[index].type == .curve || pistes[index].type == .step) {
                                                    let trackHeight = pistes[index].height
                                                    let topY = curveMargin
                                                    let midY = trackHeight / 2
                                                    let bottomY = trackHeight - curveMargin
                                                    let tickWidth: CGFloat = 6

                                                    if pistes[index].type == .step && pistes[index].isGate {
                                                        // Gate mode is strictly boolean — no middle value, so just
                                                        // show TRUE (top) / FALSE (bottom) instead of 3 numeric ticks.
                                                        ZStack(alignment: .topLeading) {
                                                            HStack(spacing: 3) {
                                                                // Hidden only when quantization is on, since the blue
                                                                // ticks then occupy this same column — no point having
                                                                // two tick scales stacked on each other. A clear spacer
                                                                // keeps the labels in place either way.
                                                                Rectangle()
                                                                    .fill(pistes[index].quantizeStep > 0 ? Color.clear : Color.gray.opacity(0.5))
                                                                    .frame(width: tickWidth, height: 1)
                                                                Text("OPEN")
                                                                    .font(.caption2)
                                                                    .foregroundColor(.gray.opacity(0.5))
                                                            }
                                                            .offset(y: topY - 6)

                                                            HStack(spacing: 3) {
                                                                // Hidden only when quantization is on, since the blue
                                                                // ticks then occupy this same column — no point having
                                                                // two tick scales stacked on each other. A clear spacer
                                                                // keeps the labels in place either way.
                                                                Rectangle()
                                                                    .fill(pistes[index].quantizeStep > 0 ? Color.clear : Color.gray.opacity(0.5))
                                                                    .frame(width: tickWidth, height: 1)
                                                                Text("CLOSED")
                                                                    .font(.caption2)
                                                                    .foregroundColor(.gray.opacity(0.5))
                                                            }
                                                            .offset(y: bottomY - 6)
                                                        }
                                                        .frame(width: 60, height: trackHeight, alignment: .topLeading)
                                                        .offset(x: 144)
                                                    } else {
                                                        ZStack(alignment: .topLeading) {
                                                            HStack(spacing: 3) {
                                                                // Hidden only when quantization is on, since the blue
                                                                // ticks then occupy this same column — no point having
                                                                // two tick scales stacked on each other. A clear spacer
                                                                // keeps the labels in place either way.
                                                                Rectangle()
                                                                    .fill(pistes[index].quantizeStep > 0 ? Color.clear : Color.gray.opacity(0.5))
                                                                    .frame(width: tickWidth, height: 1)
                                                                Text(String(format: "%.2f", pistes[index].maxAmplitude))
                                                                    .font(.caption2)
                                                                    .foregroundColor(.gray.opacity(0.5))
                                                            }
                                                            .offset(y: topY - 6)

                                                            HStack(spacing: 3) {
                                                                // Hidden only when quantization is on, since the blue
                                                                // ticks then occupy this same column — no point having
                                                                // two tick scales stacked on each other. A clear spacer
                                                                // keeps the labels in place either way.
                                                                Rectangle()
                                                                    .fill(pistes[index].quantizeStep > 0 ? Color.clear : Color.gray.opacity(0.5))
                                                                    .frame(width: tickWidth, height: 1)
                                                                Text(String(format: "%.2f", (pistes[index].minAmplitude + pistes[index].maxAmplitude) / 2))
                                                                    .font(.caption2)
                                                                    .foregroundColor(.gray.opacity(0.5))
                                                            }
                                                            .offset(y: midY - 6)

                                                            HStack(spacing: 3) {
                                                                // Hidden only when quantization is on, since the blue
                                                                // ticks then occupy this same column — no point having
                                                                // two tick scales stacked on each other. A clear spacer
                                                                // keeps the labels in place either way.
                                                                Rectangle()
                                                                    .fill(pistes[index].quantizeStep > 0 ? Color.clear : Color.gray.opacity(0.5))
                                                                    .frame(width: tickWidth, height: 1)
                                                                Text(String(format: "%.2f", pistes[index].minAmplitude))
                                                                    .font(.caption2)
                                                                    .foregroundColor(.gray.opacity(0.5))
                                                            }
                                                            .offset(y: bottomY - 6)
                                                        }
                                                        .frame(width: 60, height: trackHeight, alignment: .topLeading)
                                                        .offset(x: 144)
                                                    }

                                                    // Quantization ticks. They now occupy the column where the
                                                    // range labels' own gray ticks used to be (those are gone),
                                                    // so there's a single tick scale instead of two competing
                                                    // ones. Blue keeps them readable as the quantization grid.
                                                    // Only the visible subset (see visibleQuantizeTicks) is
                                                    // drawn, so a fine step on a short track doesn't turn into
                                                    // a solid block.
                                                    if !pistes[index].isGate {
                                                        let range = pistes[index].maxAmplitude - pistes[index].minAmplitude
                                                        ZStack(alignment: .topLeading) {
                                                            ForEach(visibleQuantizeTicks(forTrackIndex: index), id: \.self) { value in
                                                                let normalized = range > 0 ? (value - pistes[index].minAmplitude) / range : 0
                                                                let y = curveMargin + (trackHeight - 2 * curveMargin) * (1 - normalized)
                                                                Rectangle()
                                                                    .fill(Color.blue.opacity(0.55))
                                                                    .frame(width: 15, height: 1)
                                                                    .offset(y: y)
                                                            }
                                                        }
                                                        // Right edge stays at 150, level with where the gray ticks
                                                        // end (144 + tickWidth); the left edge is pulled back so
                                                        // they only just reach into the header (which ends at 140).
                                                        .frame(width: 15, height: trackHeight, alignment: .topLeading)
                                                        .offset(x: 135)
                                                        .allowsHitTesting(false)
                                                    }
                                                }

                                                if !pistes[index].isFolded {
                                                if index == 0 {
                                                    HStack(spacing: 5) {
                                                        Button(action: { pistes[index].isMuted.toggle() }) {
                                                            Image(systemName: pistes[index].isMuted ? "speaker.slash.fill" : "speaker.fill")
                                                                .foregroundColor(pistes[index].isMuted ? .gray : .green)
                                                        }
                                                        .buttonStyle(.borderless)
                                                        .help(pistes[index].isMuted ? "Unmute track" : "Mute track")

                                                        Button(action: { guard !tracksLocked else { return }; pistes[index].evenements.removeAll(); lastSentEvents.removeAll() }) {
                                                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                                                        }
                                                        .buttonStyle(.borderless)
                                                        .help("Clear all points on this track")
                                                    }
                                                    .offset(x: -20)
                                                    .padding(.trailing, 20)
                                                    .padding(.bottom, 6)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                                                    Button(action: {
                                                        openAutofillPopup(for: index)
                                                    }) {
                                                        Image(systemName: "pencil.tip.crop.circle.fill")
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .padding(.leading, 10)
                                                    .padding(.bottom, 6)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                                    .help("Autofill: generate evenly spaced markers")
                                                } else {
                                                    HStack(spacing: 5) {
                                                        if pistes[index].type == .curve || pistes[index].type == .step {
                                                            Button(action: {
                                                                amplitudeEditorTrackIndex = index
                                                                tempMinAmplitude = String(format: "%.2f", pistes[index].minAmplitude)
                                                                tempMaxAmplitude = String(format: "%.2f", pistes[index].maxAmplitude)
                                                                tempIsGate = pistes[index].isGate
                                                                tempQuantizeStep = String(format: "%g", pistes[index].quantizeStep)
                                                                tempQuantizeEnabled = pistes[index].quantizeStep > 0
                                                            }) {
                                                                Image(systemName: "slider.horizontal.3")
                                                            }
                                                            .buttonStyle(.borderless)
                                                            .help("Edit min/max amplitude range")
                                                        }

                                                        Button(action: { pistes[index].isMuted.toggle() }) {
                                                            Image(systemName: pistes[index].isMuted ? "speaker.slash.fill" : "speaker.fill")
                                                                .foregroundColor(pistes[index].isMuted ? .gray : .green)
                                                        }
                                                        .buttonStyle(.borderless)
                                                        .help(pistes[index].isMuted ? "Unmute track" : "Mute track")

                                                        Button(action: { guard !tracksLocked else { return }; pistes[index].evenements.removeAll(); lastSentEvents.removeAll() }) {
                                                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                                                        }
                                                        .buttonStyle(.borderless)
                                                        .help("Clear all points on this track")

                                                        Button(action: { guard !tracksLocked else { return }; pistes.remove(at: index); lastSentEvents.removeAll() }) {
                                                            Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                                        }
                                                        .buttonStyle(.borderless)
                                                        .help("Delete this track")
                                                    }
                                                    .padding(.trailing, 20)
                                                    .padding(.bottom, (pistes[index].type == .bang || pistes[index].type == .message) ? 6 : 10)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                                                    Button(action: {
                                                        openAutofillPopup(for: index)
                                                    }) {
                                                        Image(systemName: "pencil.tip.crop.circle.fill")
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .help("Autofill: generate a pattern for this track")
                                                    .padding(.leading, 10)
                                                    .padding(.bottom, (pistes[index].type == .bang || pistes[index].type == .message) ? 6 : 10)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                                }

                                                if pistes[index].type == .curve || pistes[index].type == .step {
                                                    VStack(spacing: 0) {
                                                        Spacer()
                                                        DiagonalStripes(stripeWidth: 2, spacing: 2)
                                                            .stroke(pistes[index].couleur, lineWidth: 2)
                                                            .background(
                                                                // Track color lightened: the color itself with a
                                                                // half-opaque white laid over it.
                                                                pistes[index].couleur.overlay(Color.white.opacity(0.5))
                                                            )
                                                            .frame(width: 140, height: 4)
                                                            .clipped()
                                                            .contentShape(Rectangle())
                                                            .gesture(
                                                                DragGesture(coordinateSpace: .global)
                                                                    .onChanged { value in
                                                                        if draggedTrackIndex != index {
                                                                            draggedTrackIndex = index
                                                                            dragStartHeight = pistes[index].height
                                                                        }
                                                                        let newHeight = max(30, dragStartHeight + value.translation.height)
                                                                        pistes[index].height = newHeight
                                                                    }
                                                                    .onEnded { _ in
                                                                        draggedTrackIndex = nil
                                                                    }
                                                            )
                                                            .onHover { isHovering in
                                                                if isHovering {
                                                                    NSCursor.resizeUpDown.set()
                                                                } else {
                                                                    NSCursor.arrow.set()
                                                                }
                                                            }
                                                            .onTapGesture(count: 2) {
                                                                pistes[index].height = 60
                                                            }
                                                    }
                                                }
                                                } // end if !pistes[index].isFolded
                                            }
                                            .frame(width: 140, height: rowHeight(for: pistes[index]))

                                            ZStack(alignment: .leading) {
                                                Rectangle()
                                                    .fill(pistes[index].type != .normal ? pistes[index].couleur.opacity(0.3) : Color.clear)
                                                    .frame(width: largeurTimeline, height: rowHeight(for: pistes[index]))

                                                if !pistes[index].isFolded {
                                                if pistes[index].type == .bang || pistes[index].type == .message {
                                                    Color.clear
                                                        .contentShape(Rectangle())
                                                        .frame(width: largeurTimeline, height: rowHeight(for: pistes[index]))
                                                        .onTapGesture { location in
                                                            guard !tracksLocked else { return }
                                                            let positionCliquee = (Double(location.x) / Double(largeurTimeline)) * duree
                                                            let defaultLabel = pistes[index].type == .message ? "key" : "M"
                                                            pistes[index].evenements.append(TimelineEvent(time: positionCliquee, label: defaultLabel, y: 0.5))
                                                            pistes[index].evenements.sort()
                                                            lastSentEvents.removeAll()
                                                        }
                                                } else if pistes[index].type == .curve {
                                                    Color.clear
                                                        .contentShape(Rectangle())
                                                        .frame(width: largeurTimeline, height: pistes[index].height)
                                                        .onTapGesture { location in
                                                            guard !tracksLocked else { return }
                                                            let time = (Double(location.x) / Double(largeurTimeline)) * duree
                                                            // Shift + click near the drawn (or hypothetical, if
                                                            // already a hole) curve line toggles that segment's
                                                            // hole instead of adding a new point.
                                                            if NSEvent.modifierFlags.contains(.shift),
                                                               let curveY = curveYPosition(forTime: time, trackIndex: index),
                                                               abs(Double(location.y) - Double(curveY)) < 12 {
                                                                toggleSegmentEnabled(forTime: time, trackIndex: index)
                                                                return
                                                            }
                                                            let positionCliquee = time
                                                            let normalizedY = min(max(1 - (Double(location.y) / Double(pistes[index].height)), 0), 1)
                                                            let yValue = pistes[index].minAmplitude + (normalizedY * (pistes[index].maxAmplitude - pistes[index].minAmplitude))
                                                            pistes[index].evenements.append(TimelineEvent(time: positionCliquee, label: "", y: gateSnappedY(yValue, forTrackIndex: index)))
                                                            pistes[index].evenements.sort()
                                                            lastSentEvents.removeAll()
                                                        }
                                                        .onContinuousHover { phase in
                                                            switch phase {
                                                            case .active(let location):
                                                                // Compute everything locally; only write @State when the
                                                                // value actually changes, so plain mouse movement doesn't
                                                                // trigger a body re-render per pixel (which is what broke
                                                                // the hover stream in a previous iteration).
                                                                let time = (Double(location.x) / Double(largeurTimeline)) * duree
                                                                let nearZone: Bool
                                                                if let curveY = curveYPosition(forTime: time, trackIndex: index) {
                                                                    nearZone = abs(Double(location.y) - Double(curveY)) < 12
                                                                } else {
                                                                    nearZone = false
                                                                }
                                                                if isNearCurveControlZone != nearZone {
                                                                    isNearCurveControlZone = nearZone
                                                                }
                                                                // Receiving this hover means the mouse is on the curve
                                                                // area itself, NOT on a point (points are separate
                                                                // subviews stacked above; they intercept hover) — so
                                                                // isHoveringPoint is stale if still true. That stale
                                                                // true was making updatePointCursor() impose the
                                                                // delete-point cursor (eraser.badge.xmark) here.
                                                                if isHoveringPoint {
                                                                    isHoveringPoint = false
                                                                }
                                                                // Direct, imperative cursor control tied to actual
                                                                // mouse movement — no @State involved, so it works
                                                                // regardless of SwiftUI's render cycle.
                                                                if NSEvent.modifierFlags.contains(.shift) {
                                                                    applyShiftSegmentCursor(at: location, trackIndex: index, largeurTimeline: largeurTimeline)
                                                                }
                                                            case .ended:
                                                                if isNearCurveControlZone {
                                                                    isNearCurveControlZone = false
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
                                                                    guard NSEvent.modifierFlags.contains(.option) else { return }
                                                                    // onContinuousHover stops firing once a real drag begins
                                                                    // (the mouse is "captured" by the gesture), so the
                                                                    // CursorOverlay's isActive state would otherwise freeze
                                                                    // or drop — keep reasserting the cursor manually for
                                                                    // the duration of the drag itself.
                                                                    cursor(fromSymbol: "point.bottomleft.forward.to.point.topright.filled.scurvepath").set()

                                                                    let sorted = pistes[index].evenements.sorted { $0.time < $1.time }
                                                                    guard sorted.count > 1 else { return }

                                                                    if curveDragSegmentID == nil {
                                                                        let startTime = (Double(value.startLocation.x) / Double(largeurTimeline)) * duree
                                                                        var chosenID = sorted[0].id
                                                                        for i in 0..<(sorted.count - 1) {
                                                                            if startTime >= sorted[i].time && startTime <= sorted[i + 1].time {
                                                                                chosenID = sorted[i].id
                                                                                break
                                                                            }
                                                                        }
                                                                        curveDragSegmentID = chosenID
                                                                        let chosenEvent = sorted.first(where: { $0.id == chosenID })
                                                                        curveDragBaseline = chosenEvent?.segmentCurve ?? 0
                                                                        curveDragBulgeBaseline = chosenEvent?.segmentBulge ?? 0
                                                                    }

                                                                    if let segmentID = curveDragSegmentID,
                                                                       let baseline = curveDragBaseline,
                                                                       let bulgeBaseline = curveDragBulgeBaseline,
                                                                       let eventIndex = pistes[index].evenements.firstIndex(where: { $0.id == segmentID }) {
                                                                        let newCurvature = min(max(baseline + Double(value.translation.width) * 0.0075, -6), 6)
                                                                        let newBulge = min(max(bulgeBaseline - Double(value.translation.height) * 0.0075, -6), 6)
                                                                        pistes[index].evenements[eventIndex].segmentCurve = newCurvature
                                                                        pistes[index].evenements[eventIndex].segmentBulge = newBulge
                                                                    }
                                                                }
                                                                .onEnded { _ in
                                                                    curveDragSegmentID = nil
                                                                    curveDragBaseline = nil
                                                                    curveDragBulgeBaseline = nil
                                                                }
                                                        )

                                                    // Purely cosmetic cursor layer: uses AppKit's own cursor-rect
                                                    // system (reliable even during plain hover, unlike NSCursor.set()
                                                    // calls) to show the bend cursor whenever near the curve with
                                                    // Option held. allowsHitTesting(false) so it never intercepts
                                                    // clicks/drags — those stay on the Color.clear view above.
                                                    CursorOverlay(
                                                        isActive: isNearCurveControlZone && isOptionHeldForCursor,
                                                        symbolName: "point.bottomleft.forward.to.point.topright.filled.scurvepath"
                                                    )
                                                    .frame(width: largeurTimeline, height: pistes[index].height)
                                                    .allowsHitTesting(false)
                                                } else if pistes[index].type == .step {
                                                    Color.clear
                                                        .contentShape(Rectangle())
                                                        .frame(width: largeurTimeline, height: pistes[index].height)
                                                        .onTapGesture { location in
                                                            guard !tracksLocked else { return }
                                                            let positionCliquee = (Double(location.x) / Double(largeurTimeline)) * duree
                                                            let normalizedY = min(max(1 - (Double(location.y) / Double(pistes[index].height)), 0), 1)
                                                            let yValue = pistes[index].minAmplitude + (normalizedY * (pistes[index].maxAmplitude - pistes[index].minAmplitude))
                                                            pistes[index].evenements.append(TimelineEvent(time: positionCliquee, label: "", y: gateSnappedY(yValue, forTrackIndex: index)))
                                                            pistes[index].evenements.sort()
                                                            lastSentEvents.removeAll()
                                                        }
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
                                                            let xPos = CGFloat(event.time / duree) * largeurTimeline
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
                                                                    let previousXPos = CGFloat(previous.time / duree) * largeurTimeline
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
                                                            let xPos = CGFloat(event.time / duree) * largeurTimeline
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
                                                    let xPos = CGFloat(event.time / duree) * largeurTimeline
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
                                                                    .fill(pistes[index].couleur)
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
                                                                        .foregroundColor(pistes[index].couleur)

                                                                    if showPointCoordinates {
                                                                        Text(String(format: "%.2f", event.time) + "s")
                                                                            .font(.caption2)
                                                                            .foregroundColor(.black)
                                                                            .offset(y: 12)
                                                                    }
                                                                }
                                                            } else if pistes[index].type == .bang {
                                                                Rectangle()
                                                                    .fill(pistes[index].couleur)
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
                                                                                .stroke(pistes[index].couleur, lineWidth: 2.5)
                                                                                .frame(width: 10, height: 10)
                                                                                .contentShape(Rectangle())
                                                                        } else {
                                                                            ZStack {
                                                                                Rectangle()
                                                                                    .fill(pistes[index].couleur)
                                                                                    .frame(width: 17, height: 3)
                                                                                    .rotationEffect(.degrees(45))
                                                                                Rectangle()
                                                                                    .fill(pistes[index].couleur)
                                                                                    .frame(width: 17, height: 3)
                                                                                    .rotationEffect(.degrees(-45))
                                                                            }
                                                                            .frame(width: 17, height: 17)
                                                                            .contentShape(Rectangle())
                                                                        }
                                                                    } else {
                                                                        Circle()
                                                                            .fill(pistes[index].couleur)
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
                                                        isHoveringPoint = hovering
                                                        // A point is a separate subview stacked above the curve
                                                        // line; moving onto it should stop the curve area from
                                                        // being considered "hovered" for cursor purposes.
                                                        if isNearCurveControlZone {
                                                            isNearCurveControlZone = false
                                                        }
                                                        if hovering {
                                                            isNearSnapZone = isNearMarker(xPos: Double(xPos), largeurTimeline: Double(largeurTimeline))
                                                            isNearGridSnapZone = nearestGridTime(xPos: Double(xPos), largeurTimeline: Double(largeurTimeline)) != nil
                                                            isNearestSnapGrid = isNearestSnapAGridLine(xPos: Double(xPos), largeurTimeline: Double(largeurTimeline))
                                                        }
                                                        updatePointCursor()
                                                    }
                                                    .gesture(
                                                        DragGesture(minimumDistance: 5)
                                                            .onChanged { value in
                                                                guard !tracksLocked else { return }
                                                                var newPosition = (Double(value.location.x) / Double(largeurTimeline)) * duree
                                                                isHoveringPoint = true

                                                                // Cmd + within 7px of a marker or grid line: snap to it.
                                                                // Without Cmd, if "magnetic grid" is on, still snap onto
                                                                // the nearest grid line alone (never a marker).
                                                                let dragXPos = (newPosition / duree) * Double(largeurTimeline)
                                                                isNearSnapZone = isNearMarker(xPos: dragXPos, largeurTimeline: Double(largeurTimeline))
                                                                isNearGridSnapZone = nearestGridTime(xPos: dragXPos, largeurTimeline: Double(largeurTimeline)) != nil
                                                                isNearestSnapGrid = isNearestSnapAGridLine(xPos: dragXPos, largeurTimeline: Double(largeurTimeline))
                                                                if NSEvent.modifierFlags.contains(.command),
                                                                   let snapTime = nearestSnapTime(xPos: dragXPos, largeurTimeline: Double(largeurTimeline)) {
                                                                    newPosition = snapTime
                                                                } else if magneticGridSnap,
                                                                          let gridSnapTime = nearestGridTime(xPos: dragXPos, largeurTimeline: Double(largeurTimeline)) {
                                                                    newPosition = gridSnapTime
                                                                }
                                                                updatePointCursor()

                                                                if let eventIndex = pistes[index].evenements.firstIndex(where: { $0.id == event.id }) {
                                                                    pistes[index].evenements[eventIndex].time = min(max(newPosition, 0), duree)
                                                                    if pistes[index].type == .curve || pistes[index].type == .step {
                                                                        let normalizedY = min(max(1 - (Double(value.location.y) / Double(pistes[index].height)), 0), 1)
                                                                        let yValue = pistes[index].minAmplitude + (normalizedY * (pistes[index].maxAmplitude - pistes[index].minAmplitude))
                                                                        pistes[index].evenements[eventIndex].y = gateSnappedY(yValue, forTrackIndex: index)
                                                                    }
                                                                }
                                                            }
                                                            .onEnded { _ in
                                                                pistes[index].evenements.sort()
                                                                lastSentEvents.removeAll()
                                                            }
                                                    )
                                                    .onTapGesture(count: 1) {
                                                        guard !tracksLocked else { return }
                                                        if NSEvent.modifierFlags.contains(.shift) {
                                                            if let eventIndex = pistes[index].evenements.firstIndex(where: { $0.id == event.id }) {
                                                                pistes[index].evenements.remove(at: eventIndex)
                                                                lastSentEvents.removeAll()
                                                            }
                                                        }
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
                                        }
                                        .offset(y: reorderingIndex == index ? reorderDragTranslation : 0)
                                        .zIndex(reorderingIndex == index ? 1 : 0)
                                        .opacity(reorderingIndex == index ? 0.85 : 1.0)
                                        .onHover { hovering in
                                            // Belt-and-suspenders: if the mouse leaves this entire track
                                            // row (e.g. straight onto a different track) without passing
                                            // back through the curve area's own hover handler, make sure
                                            // the segment-erase cursor state doesn't stay stuck on.
                                            if !hovering && isNearCurveControlZone {
                                                isNearCurveControlZone = false
                                                updatePointCursor()
                                            }
                                        }
                                        Rectangle().fill(Color.clear).frame(height: 5)
                                        } // end if index != 0 || showMarkersTrack
                                    }
                                }

                                // Gray vertical lines for each marker on the "markers" track,
                                // drawn here (outside the .clipped() area of each individual track)
                                // so they can span through all the tracks below.
                                ForEach(pistes[0].evenements) { event in
                                    let xPos = CGFloat(event.time / duree) * largeurTimeline + 140
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
                                    ForEach(visibleGridLineTimes(largeurTimeline: largeurTimeline), id: \.self) { time in
                                        let xPos = CGFloat(time / duree) * largeurTimeline + 140
                                        Path { path in
                                            path.move(to: CGPoint(x: xPos, y: 15))
                                            path.addLine(to: CGPoint(x: xPos, y: CGFloat(totalHeight)))
                                        }
                                        .stroke(Color.gray.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                                        .allowsHitTesting(false)
                                    }
                                }

                                ZStack(alignment: .topLeading) {
                                    Rectangle().fill(Color.red).frame(width: 2, height: CGFloat(totalHeight))
                                    Image(systemName: "triangle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                        .rotationEffect(.degrees(180))
                                        .offset(x: -6, y: -12)
                                }
                                .offset(x: CGFloat(position / duree) * largeurTimeline + 140)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            position = min(max((Double(value.location.x - 140) / Double(largeurTimeline)) * duree, 0), duree)
                                            sendOSCMessagesForPosition(position)
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
                            .padding(.top, 14) // room for the playhead triangle, which pokes above y=0
                        }
                        .frame(width: outerGeometry.size.width * CGFloat(zoomX))
                }
                .onChange(of: zoomX) { oldZoom, newZoom in
                    recenterOnZoomChange(oldZoom: oldZoom, newZoom: newZoom, outerWidth: outerGeometry.size.width)
                }
                .onAppear {
                    timelineAreaWidth = outerGeometry.size.width
                }
                .onChange(of: outerGeometry.size.width) { _, newWidth in
                    timelineAreaWidth = newWidth
                    zoomX = min(zoomX, maxZoomX)
                }
                .onChange(of: duree) { _, _ in
                    zoomX = min(zoomX, maxZoomX)
                }
            }
            // Shrinks the whole timeline area (and with it geometry.size.width,
            // hence largeurTimeline) by the handle's width, so the end of the
            // tracks lands exactly under the handle's vertical bar. Applied
            // here rather than inside largeurTimeline's own formula so that
            // EVERY coordinate space shrinks together — that's what keeps the
            // playhead/grid/marker lines aligned with the points.
            .padding(.trailing, durationHandleWidth)
            .overlay(alignment: .trailing) {
                durationDragHandle
            }

        }
        .frame(minWidth: 1500, minHeight: 500)
        .background(Color.gray.opacity(0.07))
        .navigationTitle(savedFileURL?.deletingPathExtension().lastPathComponent ?? "OSCcourier")
        .onAppear {
            setupOnAppear()
        }
        .onDisappear {
            tearDownOnDisappear()
        }
        .onChange(of: oscReceivePort) { _, newPort in
            oscManager.startListening(port: newPort)
        }
        .onChange(of: oscMessagesPerSecond) { _, _ in
            // Only rebuild the timer if it's currently running — otherwise
            // the new rate is picked up next time playback starts anyway.
            if enLecture {
                startPlaybackTimer()
            }
        }
        .onChange(of: enLecture) { _, isPlaying in
            // Rebuild the timer each time playback (re)starts, so it always
            // uses the current oscMessagesPerSecond value — the setting may
            // have been changed while stopped, in which case setupOnAppear's
            // one-time timer would still be running at the old rate.
            if isPlaying {
                startPlaybackTimer()
            }
        }
        .onChange(of: pistes) { _, _ in
            // Keep the points list window live: only rebuild the snapshot when
            // that window is actually open, so the (O(points)) flattening isn't
            // paid on every single edit the rest of the time.
            if isPointsListWindowVisible {
                refreshPointsList()
            }
        }

        let withReceives1 = baseContent
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierSave)) { _ in
            saveProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierSaveAs)) { _ in
            saveProjectAs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierLoad)) { _ in
            loadProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowHelp)) { _ in
            openPDFWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierPlayPause)) { _ in
            enLecture.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierStop)) { _ in
            enLecture = false
            position = 0.0
            lastSentEvents.removeAll()
        }

        let withReceives2 = withReceives1
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddBangTrack)) { _ in
            addTrack(couleur: .blue, type: .bang, height: 45)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddCurveTrack)) { _ in
            addTrack(couleur: .yellow, type: .curve, height: 60)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddMessageTrack)) { _ in
            addTrack(couleur: Color(red: 0.6549019607843137, green: 0.6784313725490196, blue: 0.0), type: .message, height: 45)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierAddStepTrack)) { _ in
            addTrack(couleur: Color(red: 0.608, green: 0.086, blue: 0.365), type: .step, height: 60)
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierClearAll)) { _ in
            showClearAllConfirmation = true
        }

        let withReceives3 = withReceives2
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToTime)) { _ in
            goToTimeString = formattedDuration(position)
            showGoToTimeDialog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToMarker)) { _ in
            goToNextMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToPreviousMarker)) { _ in
            goToPreviousMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierGoToMarkerByName)) { _ in
            goToMarkerNameString = ""
            showGoToMarkerNameDialog = true
        }

        let withReceives3b = withReceives3
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierResetZoom)) { _ in
            zoomX = 1.0
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierResetTrackHeight)) { _ in
            // Only curve/step tracks are resizable (they're the ones with the
            // striped drag handle), so only those get reset — 60 is the same
            // default the handle's double-click reset uses.
            guard !tracksLocked else { return }
            for index in pistes.indices where pistes[index].type == .curve || pistes[index].type == .step {
                pistes[index].height = 60
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowPointsList)) { _ in
            openPointsListWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierToggleFoldAll)) { _ in
            toggleFoldAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDefineGrid)) { _ in
            openGridSettingsPopup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierOpenOSCMessagesWindow)) { _ in
            openOSCMessagesWindow()
        }

        let withReceives = withReceives3b
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierMuteUnmuteAll)) { _ in
            muteUnmuteAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDeleteAllTracks)) { _ in
            showDeleteAllTracksConfirmation = true
        }

        let withAlerts = withReceives
        .alert("Clear all tracks?", isPresented: $showClearAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                guard !tracksLocked else { return }
                for i in pistes.indices {
                    pistes[i].evenements.removeAll()
                }
                lastSentEvents.removeAll()
            }
        } message: {
            Text("This will erase every point on every track. This can't be undone.")
        }
        .alert("Delete all tracks?", isPresented: $showDeleteAllTracksConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAllTracks()
            }
        } message: {
            Text("This will delete every track except /markers. This can't be undone.")
        }
        .alert("Go to time", isPresented: $showGoToTimeDialog) {
            TextField("mm:ss", text: $goToTimeString)
            Button("Cancel", role: .cancel) { }
            Button("Go") {
                goToTime(goToTimeString)
            }
        } message: {
            Text("Enter a time as mm:ss.")
        }
        .alert("Go to marker", isPresented: $showGoToMarkerNameDialog) {
            TextField("Marker name", text: $goToMarkerNameString)
            Button("Cancel", role: .cancel) { }
            Button("Go") {
                goToMarkerByName(goToMarkerNameString)
            }
        } message: {
            Text("Enter the name of a marker to jump to.")
        }
        .alert("No match", isPresented: $showGoToMarkerNoMatch) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("No marker with that name was found.")
        }

        let withAlerts2 = withAlerts
        .alert("Overwrite track?", isPresented: Binding<Bool>(
            get: { pendingAutofillIndex != nil },
            set: { if !$0 { pendingAutofillIndex = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingAutofillIndex = nil
            }
            Button("Continue", role: .destructive) {
                if let index = pendingAutofillIndex {
                    proceedWithAutofill(for: index)
                }
                pendingAutofillIndex = nil
            }
        } message: {
            Text("This track already has points. Autofill will replace them all.")
        }
        .alert("Switch to Gate?", isPresented: Binding<Bool>(
            get: { pendingGateSwitchIndex != nil },
            set: { if !$0 { pendingGateSwitchIndex = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingGateSwitchIndex = nil
            }
            Button("Continue", role: .destructive) {
                if let index = pendingGateSwitchIndex {
                    applyGateModeSwitch(forTrackIndex: index)
                }
                pendingGateSwitchIndex = nil
            }
        } message: {
            Text("This track already has points. Switching to Gate will redistribute all their values to 0 or 1.")
        }
        .alert("Quantization step adjusted", isPresented: Binding<Bool>(
            get: { invalidQuantizeStepMessage != nil },
            set: { if !$0 { invalidQuantizeStepMessage = nil } }
        )) {
            Button("OK") { invalidQuantizeStepMessage = nil }
        } message: {
            Text(invalidQuantizeStepMessage ?? "")
        }
        .alert("Rename track", isPresented: Binding<Bool>(
            get: { indexPisteARenommer != nil },
            set: { if !$0 { indexPisteARenommer = nil } }
        )) {
            TextField("New name", text: $nouveauNomPiste)
            Button("OK") {
                if let index = indexPisteARenommer {
                    pistes[index].nom = nouveauNomPiste
                }
                indexPisteARenommer = nil
            }
            Button("Cancel", role: .cancel) { indexPisteARenommer = nil }
        }
        return withAlerts2
        .sheet(isPresented: Binding<Bool>(
            get: { pointAEditer != nil },
            set: { if !$0 { pointAEditer = nil } }
        )) {
            editPointSheet
        }
        .sheet(isPresented: Binding<Bool>(
            get: { amplitudeEditorTrackIndex != nil },
            set: { if !$0 { amplitudeEditorTrackIndex = nil } }
        )) {
            rangeEditorSheet
        }
        .sheet(isPresented: Binding<Bool>(
            get: { autofillTrackIndex != nil },
            set: { if !$0 { autofillTrackIndex = nil } }
        )) {
            autofillRectangleSheet
        }
        .sheet(isPresented: Binding<Bool>(
            get: { waveTrackIndex != nil },
            set: { if !$0 { waveTrackIndex = nil } }
        )) {
            autofillWaveSheet
        }
        .sheet(isPresented: Binding<Bool>(
            get: { bangTrackIndex != nil },
            set: { if !$0 { bangTrackIndex = nil } }
        )) {
            autofillBangSheet
        }
        .sheet(isPresented: $showGridSettingsPopup) {
            gridSettingsSheet
        }
    }

    // Extracted out of `body` (rather than inline sheet closures) so the
    // Swift type-checker doesn't have to solve the whole giant `body`
    // expression as one unit — a large body with many chained modifiers and
    // deeply nested inline view trees can time out the type-checker;
    // pulling each sheet's content into its own typed computed property
    // gives it a much smaller, independent expression to check.
    private var autofillRectangleSheet: some View {
        let isGateTrack = autofillTrackIndex.map { pistes[$0].isGate } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            Text("Autofill Rectangle")
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                Text("T (s.)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofillPeriodString)
            }
            HStack {
                Text("Φ (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofillPhaseString)
            }
            HStack {
                Text("PW (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $autofillPulseWidthString)
            }
            HStack {
                Text("Range")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                Text("min")
                    .foregroundColor(.gray.opacity(0.7))
                TextField("", text: $autofillAmpMinString)
                    .disabled(isGateTrack)
                Text("max")
                    .foregroundColor(.gray.opacity(0.7))
                TextField("", text: $autofillAmpMaxString)
                    .disabled(isGateTrack)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    autofillTrackIndex = nil
                }
                Button("OK") {
                    commitAutofillRectangle()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    private var autofillWaveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Autofill Curve")
                .font(.headline)
                .padding(.bottom, 4)

            Picker("", selection: $waveIsSine) {
                Text("Sin").tag(true)
                Text("Saw").tag(false)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("T (s.)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $wavePeriodString)
            }
            HStack {
                Text("Φ (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $wavePhaseString)
            }
            HStack {
                Text("Skew")
                    .foregroundColor(waveIsSine ? .gray.opacity(0.3) : .gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $waveSkewString)
                    .disabled(waveIsSine)
            }
            HStack {
                Text("Range")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                Text("min")
                    .foregroundColor(.gray.opacity(0.7))
                TextField("", text: $waveAmpMinString)
                Text("max")
                    .foregroundColor(.gray.opacity(0.7))
                TextField("", text: $waveAmpMaxString)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    waveTrackIndex = nil
                }
                Button("OK") {
                    commitAutofillWave()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    // Point editor. A sheet rather than an alert, because alerts on macOS can
    // only host single-line TextFields — the multi-line comment box needs a
    // TextEditor, which an alert won't render.
    private var editPointSheet: some View {
        let trackIndex = pointAEditer?.trackIndex ?? 0
        let isMarkersTrack = trackIndex == 0
        let isMessageTrack = pistes.indices.contains(trackIndex) && pistes[trackIndex].type == .message
        let hasY = pistes.indices.contains(trackIndex) && (pistes[trackIndex].type == .curve || pistes[trackIndex].type == .step)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Edit point")
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                Text("Position (s)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $nouvellePositionString)
            }
            if hasY {
                HStack {
                    // The label reflects the track's actual amplitude range,
                    // which is customizable per track (and forced to 0/1 only
                    // in Gate mode) — not a hardcoded 0-1.
                    Text(String(format: "Y [%g, %g]", pistes[trackIndex].minAmplitude, pistes[trackIndex].maxAmplitude))
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 100, alignment: .trailing)
                    TextField("", text: $nouvelleYString)
                }
            }
            if isMarkersTrack || isMessageTrack {
                HStack {
                    Text("Label")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 100, alignment: .trailing)
                    TextField("", text: $nouveauLabel)
                }
            }

            HStack(alignment: .top) {
                Text("Comment")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 100, alignment: .trailing)
                TextEditor(text: $nouveauComment)
                    .font(.body)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    pointAEditer = nil
                }
                Button("OK") {
                    commitPointEdit()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 360)
    }

    private var autofillBangSheet: some View {
        let isMarkersTrack = bangTrackIndex == 0
        let isMessageTrack = bangTrackIndex.map { pistes[$0].type == .message } ?? false
        let title = isMarkersTrack ? "Autofill Markers" : (isMessageTrack ? "Autofill Message" : "Autofill Bang")
        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                Text("T (s.)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $bangPeriodString)
            }
            HStack {
                Text("Φ (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $bangPhaseString)
            }
            if isMarkersTrack || isMessageTrack {
                HStack {
                    Text("Prefix")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 80, alignment: .trailing)
                    TextField(isMarkersTrack ? "M" : "key", text: $bangLabelPrefixString)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    bangTrackIndex = nil
                }
                Button("OK") {
                    commitAutofillBang()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    private var gridSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grid")
                .font(.headline)
                .padding(.bottom, 4)

            HStack {
                Text("T mini (s.)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $gridPeriodString)
            }
            HStack {
                Text("Φ (0-1)")
                    .foregroundColor(.gray.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $gridPhaseString)
            }

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Snap to grid")
                    .foregroundColor(.gray.opacity(0.7))
                Picker("", selection: $magneticGridSnap) {
                    Text("⌘ + clic").tag(false)
                    Text("Magnetic").tag(true)
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showGridSettingsPopup = false
                }
                Button("OK") {
                    commitGridSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }

    // Range editor for curve/step tracks. Curve tracks only ever show the
    // min/max fields (Float behavior). Step tracks additionally get a
    // Float/Gate toggle: Gate locks the range to 0...1 (boolean on/off) and
    // hides the min/max fields entirely, since there's nothing to configure.
    private var rangeEditorSheet: some View {
        let isStepTrack = amplitudeEditorTrackIndex.map { pistes[$0].type == .step } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            Text("Range")
                .font(.headline)
                .padding(.bottom, 4)

            if isStepTrack {
                Picker("", selection: $tempIsGate) {
                    Text("Float").tag(false)
                    Text("Gate").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: tempIsGate) { _, nowGate in
                    // Gate locks the range to 0...1 — reflect that in the
                    // (now disabled) fields, rather than leaving them showing
                    // stale Float values that no longer apply.
                    if nowGate {
                        tempMinAmplitude = "0.00"
                        tempMaxAmplitude = "1.00"
                        tempQuantizeStep = "0"
                        tempQuantizeEnabled = false
                    }
                }
            }

            // Shown in every mode, but disabled in Gate: Gate locks the range
            // to 0/1 and is itself a quantization, so there's nothing to set —
            // greying the fields out (rather than hiding them) keeps the sheet
            // from changing size as you toggle Float/Gate.
            let isGateMode = isStepTrack && tempIsGate

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("max")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 40, alignment: .trailing)
                    TextField("max", text: $tempMaxAmplitude)
                }
                HStack {
                    Text("min")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 40, alignment: .trailing)
                    TextField("min", text: $tempMinAmplitude)
                }

                Divider()
                    .padding(.vertical, 2)

                Toggle("Quantize", isOn: $tempQuantizeEnabled)
                    .onChange(of: tempQuantizeEnabled) { _, enabled in
                        // Turning it on with a leftover "0" would be a no-op —
                        // seed a sensible step (a tenth of the range) so the
                        // toggle actually does something straight away.
                        if enabled, (Double(tempQuantizeStep) ?? 0) <= 0 {
                            let minV = Double(tempMinAmplitude) ?? 0
                            let maxV = Double(tempMaxAmplitude) ?? 1
                            let range = maxV - minV
                            tempQuantizeStep = String(format: "%g", range > 0 ? range / 10 : 0.1)
                        }
                    }

                HStack {
                    Text("quantif.")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 55, alignment: .trailing)
                    TextField("", text: $tempQuantizeStep)
                        .disabled(!tempQuantizeEnabled)
                }
                .opacity(tempQuantizeEnabled ? 1 : 0.45)

                Text("Point values snap to multiples of this step.")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(isGateMode)
            .opacity(isGateMode ? 0.45 : 1)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    amplitudeEditorTrackIndex = nil
                }
                Button("OK") {
                    commitAmplitudeEdit()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 280)
    }
}

// Small upward-pointing triangle used as the "tail" of the duration tooltip
// bubble, so the bubble visually points up at the drag handle above it.
struct UpPointingTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// Tracks whether the outgoing-OSC-messages window is actually still open,
// independent of NSWindow.isVisible (which can lag/misreport around
// close()/showWindow() calls) — explicit state set via this delegate is
// more reliable for the Open/Close toggle behavior.
class OSCWindowCloseDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

// Diagonal hazard-stripe pattern, used for the track resize handles at the
// bottom of curve/step headers. Draws a set of parallel 45° lines; stroking
// this shape over a colored background gives the classic striped look.
// The path is drawn wider than the frame (and clipped) so the slanted lines
// reach the edges cleanly instead of leaving triangular gaps at the corners.
struct DiagonalStripes: Shape {
    var stripeWidth: CGFloat = 4
    var spacing: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = stripeWidth + spacing
        // Start far enough left that the slanted lines still cover the top-left
        // corner, and run past the right edge for the same reason.
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return path
    }
}

struct Polygon: Shape {
    let sides: Int
    let size: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = size / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = (2 * .pi) / CGFloat(sides)
        for i in 0..<sides {
            let point = CGPoint(
                x: center.x + radius * cos(angle * CGFloat(i) - .pi / 2),
                y: center.y + radius * sin(angle * CGFloat(i) - .pi / 2)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
