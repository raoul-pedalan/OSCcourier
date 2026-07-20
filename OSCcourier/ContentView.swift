import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var oscManager = OSCManager()
    @StateObject var messageStore = OSCMessageStore()
    @StateObject var pointListStore = PointListStore()
    @State var duree: Double = 30.0
    @State var dureeText: String = "00:30.00"
    @State var position: Double = 0.0
    @State var enLecture: Bool = false
    @AppStorage("enBoucle") var enBoucle: Bool = false
    // A loop zone, drawn as a yellow band in the ruler. When set, looping
    // wraps between these two times instead of the whole timeline. nil/nil
    // means "no zone" — Loop then loops the entire timeline as before.
    @State var loopZoneStart: Double?
    @State var loopZoneEnd: Double?
    // Tracks an in-progress ruler drag so the zone previews live as the
    // user drags, rather than only appearing once they release.
    @State var rulerDragStartTime: Double?
    @State var rulerDragCurrentTime: Double?
    enum LoopZoneEdge { case start, end }
    // Set once a drag is confirmed to have started near an existing zone's
    // edge — from then on that same drag resizes the zone instead of
    // drawing a new one or moving the playhead.
    @State var resizingLoopZoneEdge: LoopZoneEdge?
    // Hover-only (not dragging) proximity, purely for the cursor.
    @State var isNearLoopZoneEdge: Bool = false
    // Dragging the zone's body (not an edge) translates the whole zone.
    // The anchor is the time under the mouse at drag start, so the zone
    // moves by the same delta as the cursor rather than snapping its start
    // to the cursor position.
    @State var isDraggingLoopZoneBody: Bool = false
    @State var loopZoneDragOriginalStart: Double?
    @State var loopZoneDragOriginalEnd: Double?
    @State var loopZoneDragAnchorTime: Double?
    // Double-click on the ruler opens this to edit start/end precisely.
    @State var showLoopZoneEditor: Bool = false
    @State var loopZoneEditStartString: String = ""
    @State var loopZoneEditEndString: String = ""
    @State var timer: Timer?
    // Real wall-clock timestamp of the previous playback tick (monotonic
    // clock, in seconds). Used to advance `position` by the actual elapsed
    // time between ticks instead of an assumed fixed 0.05 — Timer doesn't
    // guarantee exact intervals, so assuming a fixed delta would let small
    // per-tick errors accumulate into real drift over a long playback session.
    @State var lastTickTimestamp: Double?
    @State var zoomX: Double = 1.0
    @StateObject var timelineStore = TimelineStore()
    @Environment(\.undoManager) var undoManager

    var pistes: [TimelineTrack] {
        get { timelineStore.pistes }
        nonmutating set { timelineStore.setPistes(newValue) }
    }
    @State var lastSentEvents: Set<String> = []
    @State var indexPisteARenommer: Int?
    @State var nouveauNomPiste = ""
    @State var pointAEditer: (trackIndex: Int, eventId: UUID)?
    @State var nouvellePositionString = ""
    @State var nouveauLabel = "M"
    @State var nouveauComment = ""
    @State var nouvelleYString = "0.5"
    @State var amplitudeEditorTrackIndex: Int?
    // Autofill Rectangle popup (step tracks): generates a rectangular/pulse
    // pattern of step events across the track.
    @State var autofillTrackIndex: Int?
    @State var autofillPeriodString: String = "1.0"
    @State var autofillPhaseString: String = "0.0"
    @State var autofillPulseWidthString: String = "0.5"
    @State var autofillAmpMinString: String = "0.0"
    @State var autofillAmpMaxString: String = "1.0"

    // Autofill Wave popup (curve tracks): generates a sine or (skewed) sawtooth wave.
    @State var waveTrackIndex: Int?
    @State var waveIsSine: Bool = true // true = Sin, false = Saw
    @State var wavePeriodString: String = "1.0"
    @State var wavePhaseString: String = "0.0"
    @State var waveSkewString: String = "0.5"
    @State var waveAmpMinString: String = "0.0"
    @State var waveAmpMaxString: String = "1.0"

    // Autofill Bang popup (bang/markers tracks): generates evenly spaced bangs.
    @State var bangTrackIndex: Int?
    @State var bangPeriodString: String = "1.0"
    @State var bangPhaseString: String = "0.0"
    // Message tracks only: prefix used for generated labels ("prefix_1",
    // "prefix_2", ...), replacing the previously hardcoded "key".
    @State var bangLabelPrefixString: String = "key"
    // Set when the pencil button is pressed on a track that already has
    // points, to show an "Overwrite track?" confirmation before opening
    // the actual autofill popup.
    @State var pendingAutofillIndex: Int?
    @State var showClearAllConfirmation = false
    @State var showDeleteAllTracksConfirmation = false
    // Modifier-aware cursor over points: shift = delete cursor, cmd = snap cursor.
    // Tracks whether the mouse is currently over any point, and listens for
    // modifier key changes while hovering (since .onHover alone only fires on
    // enter/exit, not when a modifier key is pressed mid-hover).
    @State var isHoveringPoint: Bool = false
    // Option-drag on a curve segment (Logic Pro automation-curve style).
    // Whether the cursor is currently within the erase/bend zone (12px) of
    // this hovered curve track's line. Boolean on purpose: it only changes
    // on zone transitions (rare), unlike storing the raw hover position in
    // @State, which changed every single pixel of mouse movement and forced
    // a full body re-render per pixel — constantly rebuilding the hover
    // stream and tracking areas, which is what silently broke both the
    // Option and Shift hover cursors.
    @State var isNearCurveControlZone: Bool = false
    @State var isOptionHeldForCursor: Bool = false
    // Mirrors isOptionHeldForCursor for Shift, live-updated by the same
    // flagsChanged monitor — needed so Shift+Option (the lasso trigger) can
    // be told apart from plain Shift (erase-point cursor / toggle segment)
    // in view-level (non-gesture-closure) contexts.
    @State var isShiftHeldForCursor: Bool = false
    // Points currently selected via the lasso, rendered white. Cleared by
    // any ordinary click/drag elsewhere (creating a point, dragging or
    // tapping an existing point).
    @State var selectedPointIDs: Set<UUID> = []
    // Lasso in progress: which track it started on (only that track's
    // points are eligible — a lasso never spans multiple tracks), and its
    // start/current location in that track's own local coordinate space.
    @State var lassoTrackIndex: Int?
    @State var lassoStartLocation: CGPoint?
    @State var lassoCurrentLocation: CGPoint?
    // Group-drag of a selection: original time of every selected point,
    // captured on the first tick of a drag that starts on an already-
    // selected point. Every point then moves by the same X delta as the
    // dragged one — Y is untouched, only time shifts.
    @State var groupDragBaseline: [UUID: Double] = [:]
    @State var groupDragAnchorOriginalTime: Double?
    // Same idea as the time baseline above, but for Y — lets a group drag
    // move vertically too (curve/step only), with the delta shrunk (not
    // each point clamped independently) if it would push any selected
    // point out of range, so relative spacing between values is preserved.
    @State var groupDragYBaseline: [UUID: Double] = [:]
    @State var groupDragAnchorOriginalY: Double?
    @State var keyDownMonitor: Any?
    // Copy/paste of a point selection. The clipboard remembers the source
    // track's type, since paste is only allowed onto a same-type track.
    @State var pointClipboard: [PointClipboardEntry] = []
    @State var pointClipboardTrackType: TrackType?
    @State var isPasteModeActive: Bool = false
    @State var showDifferentTypePasteAlert: Bool = false
    @State var showPlayheadPositionChoice: Bool = false
    // The source track's amplitude range, remembered alongside the clipboard
    // so paste can detect a mismatch with the destination track and offer to
    // rescale (curve/step tracks only — the only types where Y is meaningful).
    @State var pointClipboardSourceMinAmplitude: Double?
    @State var pointClipboardSourceMaxAmplitude: Double?
    // The earliest original time among the copied points (before they were
    // ever pasted anywhere) — combined with where the most recent paste
    // landed, this gives ⌘D the offset to repeat.
    @State var pointClipboardOriginalEarliestTime: Double?
    @State var lastPasteAnchorTime: Double?
    @State var lastPasteTrackIndex: Int?
    // Fixed the first time ⌘D is pressed (derived from the manual paste
    // that preceded it), then reused as-is for every subsequent press —
    // recomputing it from lastPasteAnchorTime each time would compound
    // into a geometric progression (2, 4, 8, 16...) instead of a constant
    // step (2, 4, 6, 8...), since the anchor keeps advancing.
    @State var lastPasteOffset: Double?
    @State var pendingPasteAnchorTime: Double?
    @State var pendingPasteTrackIndex: Int?
    @State var showPasteScaleRangeAlert: Bool = false
    @State var curveDragSegmentID: UUID?
    @State var curveDragBaseline: Double?
    @State var curveDragBulgeBaseline: Double?
    @State var isNearSnapZone: Bool = false
    // Tracks proximity to a grid line specifically (not markers) — used to
    // show the snap cursor for "magnetic grid" auto-snap even without ⌘ held.
    @State var isNearGridSnapZone: Bool = false
    // Whether the closest ⌘-snap target (marker or grid line combined) is
    // specifically the grid line — used only to color the snap cursor.
    @State var isNearestSnapGrid: Bool = false
    @State var flagsChangedMonitor: Any?
    // Tracks whether the window is currently full screen, so the top
    // padding reserved to clear the title bar can be dropped once that
    // title bar itself is hidden (full screen has no title bar to avoid).
    @State var isFullScreen: Bool = false
    @State var fullScreenEnterObserver: Any?
    @State var fullScreenExitObserver: Any?
    @State var tempMinAmplitude: String = "0"
    @State var tempMaxAmplitude: String = "1"
    @State var tempIsGate: Bool = false
    @State var tempQuantizeStep: String = "0"
    @State var tempQuantizeEnabled: Bool = false
    @Environment(\.colorScheme) var colorScheme

    // Track background tint. The same 0.3 that looks right on a light
    // background reads as too saturated against a dark one, so it's pulled
    // back in dark mode.
    var trackBackgroundOpacity: Double {
        colorScheme == .dark ? 0.18 : 0.3
    }
    // Point currently being placed by a press-drag-release on empty track
    // space: created on mouse-down, dragged while held, committed on release.
    @State var creatingPointId: UUID?
    @State var creatingPointTrackIndex: Int?
    // Set when the user commits a quantize step that had to be clamped, so we
    // can tell them rather than silently changing what they typed.
    @State var invalidQuantizeStepMessage: String? = nil
    @State var pendingGateSwitchIndex: Int? = nil
    @State var messagesWindowController: NSWindowController?
    // Explicit visibility tracking for the OSC messages window's Open/Close
    // toggle — more reliable than reading NSWindow.isVisible directly.
    @State var isOSCWindowVisible: Bool = false
    @State var oscWindowCloseDelegate: OSCWindowCloseDelegate?
    // Points list window (same open/close toggle pattern as the OSC one).
    @State var pointListWindowController: NSWindowController?
    @State var isPointListWindowVisible: Bool = false
    @State var pointListCloseDelegate: OSCWindowCloseDelegate?
    @State var pdfWindowController: NSWindowController?
    // Modifier Keys quick-reference window (same open/close toggle pattern).
    @State var modifierKeysWindowController: NSWindowController?
    @State var isModifierKeysWindowVisible: Bool = false
    @State var modifierKeysCloseDelegate: OSCWindowCloseDelegate?
    // Remembers the file chosen on the first Save, so subsequent saves
    // silently overwrite it instead of prompting again.
    @State var savedFileURL: URL?
    // Managing focus explicitly (defaulting to nil) stops macOS from
    // automatically giving keyboard focus to the first text field at launch.
    enum ToolbarField: Hashable {
        case duree, oscAddress
    }
    @FocusState var focusedField: ToolbarField?
    enum PlayheadPositionField: Hashable {
        case time, marker
    }
    @FocusState var playheadPositionFocusedField: PlayheadPositionField?
    @State var playheadMarkerNotFound: Bool = false
    // The time field always has a pre-filled default (the current
    // position), so "has content" alone can't signal that the user
    // actually means to use it — captured on open, compared against the
    // live value to tell "still the default" from "the user typed here".
    @State var goToTimeInitialValue: String = ""
    @State var draggedTrackIndex: Int?
    // Which track's Clear/Duplicate button the cursor is currently over —
    // ⌥ only swaps that specific button to "duplicate", not every track's
    // button at once just because ⌥ happens to be held somewhere.
    @State var duplicateHoverTrackIndex: Int?
    @State var dragStartHeight: CGFloat = 0
    // Duration trim handle, pinned to the right edge of the window: drag
    // horizontally to grow/shrink the track's total duration.
    @State var isDraggingDurationHandle: Bool = false
    // Velocity-based drag: the horizontal offset from where the drag
    // started controls the *rate* of change (seconds of duree per second
    // held), rather than directly mapping to a duree delta. A repeating
    // timer applies that rate continuously while the drag is held.
    @State var durationDragCurrentDeltaX: CGFloat = 0
    @State var durationDragTimer: Timer?
    // Brief flash indicator for the compact command bar's "OSC" label,
    // lit up for a short moment each time an OSC message actually goes out.
    @State var isOSCFlashing: Bool = false
    @State var oscFlashTimer: Timer?
    // How fast duree changes per second, per pixel of horizontal offset
    // from the drag's start point.
    // Non-linear speed curve: rate = sign(dx) * |dx|^exponent * scale.
    // exponent > 1 makes small offsets noticeably slower (more precise) and
    // large offsets noticeably faster than a plain linear mapping would.
    let durationDragVelocityExponent: Double = 1.8
    let durationDragVelocityScale: Double = 0.00126
    // Track reordering (drag handle in the header). "markers" (index 0) stays pinned.
    @State var reorderingIndex: Int?
    @State var reorderDragTranslation: CGFloat = 0
    // Accumulates by ± the swapped neighbor's height each time a swap happens during
    // the same drag, so the raw (cumulative-since-start) gesture translation can be
    // corrected into the right visual offset without ever being overwritten wrong.
    @State var reorderBaselineOffset: CGFloat = 0

    // Vertical margin (= circle radius) reserved at the top/bottom of a curve
    // track so that points at the extreme values (0 or 1) aren't half-clipped.
    // Shared by the ruler labels, the path, and the point positions so they
    // all stay consistent with each other.
    let curveMargin: CGFloat = 6

    // Height a folded track's row is reduced to: just enough for the name,
    // fold triangle, and reorder handle.
    let foldedTrackHeight: CGFloat = 24

    // Width of the duration trim handle strip pinned to the window's right
    // edge. Shared so the timeline drawing width can reserve exactly this
    // much, keeping the end of the tracks aligned with the handle's bar.
    let durationHandleWidth: CGFloat = 18

    // The actual row height to use for a given track: folded tracks always
    // collapse to foldedTrackHeight, regardless of type; otherwise bang/message
    // tracks are a fixed 45, and curve/step tracks use their own `height`.

    // Applies whatever vertical constraint the track has to a raw y value.
    // Called from every point-creating/point-moving path (click, drag, editor),
    // so both Gate mode and quantization behave consistently everywhere.
    //
    // Gate takes priority: it's already a strict 0/1 quantization, so a step
    // value on top of it would be meaningless (and is hidden in the UI).

    // Snaps y to the nearest multiple of the track's quantizeStep, measured
    // from minAmplitude (so the range's own bounds are always reachable), then
    // clamps back into range — rounding could otherwise land just outside it.

    // The y values every quantization tick sits on, for a track. Empty when
    // quantization is off. Capped so an absurdly small step can't generate
    // thousands of ticks (the UI thins them out further; this is the hard
    // safety limit on the underlying set).

    // Which of those ticks to actually draw at the track's current height:
    // keeps every Nth one (N from a "nice" progression) so they never get
    // closer than a legible minimum, exactly like the horizontal grid does.

    // A lightweight, non-interactive "ghost" preview of a folded track's
    // content — no point markers, no coordinate labels, no gestures, just a
    // faint trace so the track's shape/pattern stays recognizable while
    // collapsed. Curve/step segments are drawn as straight lines here
    // (ignoring segmentCurve/segmentBulge) since the folded row is too thin
    // for the curvature to read anyway.

    // MARK: - Zoom-centering state
    @State var scrollOffsetX: CGFloat = 0
    // True while a pinch gesture is in progress: TimelineScrollView's Coordinator
    // handles its own mouse-anchored centering during a pinch, so the viewport-center
    // recentering below (used for the RotaryKnob) should stand down while this is true.
    @State var isPinchZooming: Bool = false
    // Toggle for showing/hiding the "time, value" coordinate labels next to points.
    @AppStorage("showPointCoordinates") var showPointCoordinates: Bool = true
    // Toggle for showing/hiding the timeline grid overlay.
    @AppStorage("showGrid") var showGrid: Bool = false
    @AppStorage("oscMessagesPerSecond") var oscMessagesPerSecond: Int = 20
    // Toggles between the full command bar (toolbar with all controls) and
    // a compact, full-width control line (position + play/loop indicators).
    @AppStorage("showCommandBar") var showCommandBar: Bool = true
    // Shared with OSCcourierApp's menu commands via the same @AppStorage keys.
    @AppStorage("showMarkersTrack") var showMarkersTrack: Bool = true
    @AppStorage("tracksLocked") var tracksLocked: Bool = false
    // "Go to (mm:ss)" dialog, triggered from the Play menu.
    @State var showGoToTimeDialog: Bool = false
    @State var goToTimeString: String = "00:00"
    @State var showGoToMarkerNameDialog: Bool = false
    @State var goToMarkerNameString: String = ""
    @State var showGoToMarkerNoMatch: Bool = false
    // Grid line generation: evenly spaced dashed vertical lines across all
    // tracks, same period/phase model as the bang autofill.
    @State var showGridSettingsPopup: Bool = false
    @State var gridPeriodString: String = "1.0"
    @State var gridPhaseString: String = "0.0"
    @State var gridPeriod: Double = 1.0
    @State var gridPhase: Double = 0.0
    // Width of the timeline viewport (updated from the outer GeometryReader), used to
    // compute how much zoom is needed to reach the 1s = 1000px target regardless of `duree`.
    @State var timelineAreaWidth: CGFloat = 1500

    // Maximum zoom factor such that at max zoom, 1 second of timeline = 1000px,
    // no matter how long the track (`duree`) is. Without this, a fixed max zoom
    // (e.g. 10x) isn't enough to reach that resolution once `duree` gets large.
    var maxZoomX: Double {
        let outerWidth = max(timelineAreaWidth, 1)
        let desiredLargeur = 1000.0 * duree // pixels needed so that 1s = 1000px
        let zoom = (desiredLargeur + 140) / outerWidth
        return max(1.0, zoom)
    }

    // maxZoomX computed as if duree were pinned at 30s (same outerWidth) —
    // used purely as a reference span for calibrating the zoom knob's
    // sensitivity below, not for the actual zoom range.
    var referenceMaxZoomX: Double {
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
    var zoomKnobSensitivity: Double {
        let referenceSpan = max(referenceMaxZoomX - 1.0, 0.0001)
        let currentSpan = max(maxZoomX - 1.0, 0.0001)
        return 0.05 * (currentSpan / referenceSpan)
    }

    // Tracks actually shown in the timeline — all of them, unless the
    // "/markers" track (always index 0) is hidden via showMarkersTrack.
    var visiblePistes: [TimelineTrack] {
        showMarkersTrack ? pistes : Array(pistes.dropFirst())
    }

    // Real total height of the ruler + all tracks (mirrors the `totalHeight` computed
    // inside the inner GeometryReader), plus the top padding reserved for the playhead
    // triangle. Used as the document's actual height so vertical scrolling can reveal
    // tracks that would otherwise be clipped below the visible viewport.
    var totalTracksHeight: CGFloat {
        24 + visiblePistes.reduce(CGFloat(0)) { $0 + rowHeight(for: $1) } + CGFloat(visiblePistes.count * 5) + 14
    }

    // Shared naming counter across all track types (bang or curve), so a new
    // track never reuses a number already taken by a track of the other color.
    // Based on the highest existing /track_N suffix rather than a raw count,
    // so it stays correct even after tracks have been deleted or reordered.
    var nextTrackName: String {
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

    // Parses a duration back into seconds. Deliberately permissive, so typing
    // a duration stays simple even though the display is precise: "30",
    // "30.5", "00:30" and "00:30.47" are all accepted.

    // Formats a ruler tick label. Ticks spaced 1s apart or more show plain
    // "mm:ss"; ticks spaced under 1s apart (zoomed in a lot) additionally
    // show centiseconds ("mm:ss.cc"), since otherwise consecutive sub-second
    // ticks would render identically.

    // Formats a duration in seconds as "mm:ss:cc" (minutes:seconds:centiseconds).



    // Always prompts for a new location, regardless of any previously saved file.




    // Shared with SettingsView via the same @AppStorage key.
    @AppStorage("oscAddressPrefix") var oscAddressPrefix: String = ""
    @AppStorage("oscReceivePort") var oscReceivePort: Int = 7500
    // Grid snap mode: false = grid lines only snap like markers do, via
    // ⌘+drag; true = "magnetic grid", points snap to the nearest grid line
    // automatically while dragging, no ⌘ needed. Markers themselves always
    // require ⌘ either way — this setting only affects grid-line snapping.
    @AppStorage("magneticGridSnap") var magneticGridSnap: Bool = false



    // Rebuilds the points list snapshot into the shared store. Called whenever
    // the tracks change, so the (observing) list window stays live.

    // Applies an edit made in the points list window. Routed through the same
    // clamping and gateSnappedY the timeline uses, so a value typed there is
    // constrained exactly like one dragged here (range bounds, quantization,
    // Gate mode).

    // Opens the point editor for a given event, wherever it lives. Shared by
    // the timeline's double-click and the points list window, so both go
    // through exactly the same editing path.

    // Press-drag-release point creation, shared by every track type. The point
    // is created on mouse-down and then follows the cursor until release, so
    // it can be positioned in one gesture instead of click-then-drag-again.
    // Snapping/quantization go through the same paths a normal drag uses, so
    // behaviour is identical whether a point is being created or moved.

    // Moves the in-progress point as the cursor is dragged, applying the same
    // constraints (timeline bounds, ⌘/magnetic snapping, vertical
    // quantization) that dragging an existing point applies.




    // Generates a rectangular/pulse-train pattern of step events across [0, duree].
    // period: T in seconds. phase: fraction of the period (0...1) the pattern is
    // shifted by. pulseWidth: fraction of the period (0...1) spent at ampMax.

    // Generates a sine or skewed-sawtooth wave for curve tracks (piecewise-linear
    // interpolation between the generated points, so a Sin wave needs many
    // samples per period to look smooth; a Saw only needs 2 points per cycle
    // since it's already piecewise-linear).
    // Warps a normalized progress value t (0...1) into a symmetric S-curve
    // shape based on a single curvature parameter, matching Logic Pro's
    // automation curve tool. curvature == 0 leaves t unchanged (straight line).

    // A simple power-curve warp with no inflection point (single concave or
    // convex bow throughout, unlike curvedProgress's symmetric S-shape).
    // bulge == 0 leaves t unchanged (straight line).

    // Combines both warps: horizontal drag (segmentCurve, S-shape) and
    // vertical drag (segmentBulge, simple bow) apply together.

    // The curve's rendered y-position (in track-local pixels), at a given
    // time, accounting for each segment's curvature. Returns nil if the time
    // falls outside the track's own point range (no curve there).

    // Whether the segment containing `time` is currently a hole
    // (segmentEnabled == false). Used to pick the erase vs. reconnect
    // cursor symbol while hovering. Defaults to true (no hole) if there's
    // no such segment.

    // Directly applies the Shift segment-erase/reconnect cursor for a given
    // mouse location, imperatively — called from the curve area's
    // onContinuousHover on every real mouse movement. No @State involved,
    // so it works regardless of SwiftUI's render cycle.

    // Toggles segmentEnabled on whichever segment (curve tracks only)
    // contains `time`, punching or filling a silent "hole" in the curve.
    // Both endpoints stay untouched — only the interpolation/OSC output
    // between them is switched on or off.


    // Generates evenly spaced bang events for bang/markers tracks.
    // defaultLabel is empty by design: plain bang tracks have no meaningful
    // label (only markers and message tracks do, and those pass an explicit
    // numberedLabelPrefix). It used to default to "M", which silently stamped
    // every autofilled bang with a stray marker-style label.

    // Called by the pencil button. Warns first if the track already has
    // points (since autofill replaces them entirely), otherwise opens the
    // relevant popup directly.
    // Builds an NSCursor from an SF Symbol image, tinted the given color.

    // All snap-target times currently available: marker positions, plus grid
    // lines when the grid is visible. Uses the same thinned-out set that's
    // actually rendered (visibleGridLineTimes), so snapping never lands on
    // a grid line that isn't visible on screen.

    // Finds the closest time to xPos among a given set of candidates, if any
    // falls within the 7px snap zone — nil otherwise.

    // The closest snap-target time to xPos (in timeline pixels), if any
    // falls within the 7px snap zone — nil otherwise. Combines markers and
    // grid lines (used for the ⌘-driven snap, and the hover snap-cursor
    // indicator, which treat both the same way).

    // Markers only (no grid lines) — the counterpart to nearestGridTime,
    // used to tell which of the two a combined ⌘-snap actually landed on.

    // Grid lines only (no markers) — used for "magnetic grid" auto-snap,
    // which should never pull a point onto a marker without ⌘. Matches the
    // thinned-out set actually rendered on screen (visibleGridLineTimes),
    // so you can never snap to a line you can't see.

    // When both a marker and a grid line are within the snap zone, which one
    // is actually closer to xPos? Used purely to pick the cursor color
    // (marker snap stays black, grid snap turns gray) — the actual snapping
    // logic elsewhere already picks the true closest via nearestSnapTime.

    // Is xPos (in timeline pixels) within the 7px snap zone of the nearest
    // marker line or grid line?

    // Applies the right cursor for the current hover + modifier-key state
    // while hovering an actual point. Curve-segment hover (Option-bend,
    // Shift-erase/reconnect) is handled separately by CursorOverlay
    // instances, which use AppKit's cursor-rect/tracking-area system —
    // more reliable than ad-hoc NSCursor.set() calls during plain hover
    // (macOS silently overrides those outside an active drag), which is
    // why that logic doesn't live here.


    // Generates evenly spaced grid line times across [0, duree] — same
    // period/phase model as bangEvents, but returning bare times (no labels
    // needed since grid lines are purely visual, not OSC-emitting events).

    // For DISPLAY only (never for snapping, which stays at full granularity):
    // thins out the grid lines when their pixel spacing would be too dense
    // to read — e.g. a 1s grid period over a 5-minute track at fit-to-window
    // zoom would otherwise pack hundreds of dashed lines into a tiny space.
    // Keeps every Nth line (N = smallest power-of-two-ish multiplier that
    // brings the spacing above a legible minimum) instead of changing the
    // actual period itself.



    // Scrolls the timeline horizontally so the playhead is centered in the
    // viewport, regardless of the current zoom level. Used after any "go to"
    // jump (time, next marker, marker by name) so the result is always
    // actually visible, not just updated off-screen.

    // Jumps the playhead to the next marker strictly after the current
    // position; wraps around to the earliest marker if there is none, or
    // does nothing if there are no markers at all.

    // Jumps the playhead to the previous marker strictly before the current
    // position; wraps around to the latest marker if there is none, or does
    // nothing if there are no markers at all.

    // Jumps the playhead to the marker whose label matches `name`.
    // Tries an exact case-insensitive match first, then falls back to a
    // case-insensitive substring match (so a partial name, or one with a
    // stray extra space, still finds something reasonable). Shows a
    // "No match" alert if nothing matches either way.

    // Parses a "mm:ss" (or bare seconds) string and jumps the playhead
    // there, clamped to [0, duree]. Reuses the same parser as the duration
    // field.

    // Fold/unfold all tracks at once: if any track is currently unfolded,
    // fold everything; otherwise (everything already folded) unfold
    // everything. Mirrors the common "expand/collapse all" convention.

    // Mute/unmute all tracks at once: if every track is already muted,
    // unmute everything; otherwise mute everything.

    // Removes every track except the pinned "/markers" track at index 0.

    // Centralizes track creation (used by both the toolbar buttons and the
    // Tracks menu commands) so the lock guard only needs to live in one place.




    // Called every 50ms by the playback timer. Pulled out into its own
    // function (rather than a large inline closure) so Swift type-checks it
    // on its own, instead of as part of one giant expression tree together
    // with the rest of the view body — which was timing out the compiler.

    // Everything that used to run inline in .onAppear's closure, pulled out
    // into its own function for the same reason as advancePlaybackTick():
    // large closures embedded directly in the view body get type-checked as
    // part of one giant expression tree together with the rest of `body`,
    // which was timing out the compiler.

    // (Re)creates the playback timer at the interval implied by the current
    // oscMessagesPerSecond setting (interval = 1 / rate). Called on setup and
    // again whenever the rate changes mid-session, so the new rate takes
    // effect immediately without needing to stop/restart playback.

    // Parses whatever is currently in the duration text field and applies it
    // to `duree`, then resyncs the text field to the canonical "mm:ss.cc" form
    // (so e.g. "1:5" becomes "01:05.00", and invalid text reverts cleanly).
    // Typed durations are rounded to whole seconds on purpose: sub-second
    // precision is only ever meant to come from the trim handle, so there's no
    // need to think about centiseconds when typing a duration in.



    // Recenters the horizontal scroll so the playhead stays at the same
    // on-screen (viewport-relative) position before and after a zoom
    // change — i.e. the zoom appears to happen "around" the playhead.
    // (Pinch-zoom anchors on the mouse position instead, handled separately
    // in TimelineScrollView's Coordinator.)


    // Actually performs the Float -> Gate switch: forces the 0...1 range and
    // snaps every existing point to strict boolean 0/1. Split out from
    // commitAmplitudeEdit so it can be deferred behind a confirmation when
    // there are existing points to redistribute.





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
    var durationLabelText: Text {
        var attributed = AttributedString("Duration ")
        attributed.foregroundColor = .gray
        var value = AttributedString(formattedDuration(duree))
        value.foregroundColor = Color(red: 0.3, green: 0.6, blue: 1.0)
        attributed.append(value)
        return Text(attributed)
    }

    var compactControlBar: some View {
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
    var durationTooltip: some View {
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
                Button(action: { togglePlayback() }) {
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

                Button(action: openPointListWindow) {
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

            Spacer().frame(height: 10)
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
                                        // The loop zone band: matches the Loop button's own colors
                                        // exactly (solid yellow active, gray when off), so the zone
                                        // and the button read as one and the same "loop" state.
                                        if let start = loopZoneStart, let end = loopZoneEnd {
                                            let x1 = CGFloat(min(start, end) / duree) * largeurTimeline
                                            let x2 = CGFloat(max(start, end) / duree) * largeurTimeline
                                            Rectangle()
                                                .fill(enBoucle ? Color.yellow : Color.gray.opacity(0.15))
                                                .frame(width: max(x2 - x1, 1), height: 24)
                                                .offset(x: 140 + x1)
                                        } else if let dragStart = rulerDragStartTime, let dragCurrent = rulerDragCurrentTime {
                                            // Live preview while dragging out a brand new zone.
                                            let x1 = CGFloat(min(dragStart, dragCurrent) / duree) * largeurTimeline
                                            let x2 = CGFloat(max(dragStart, dragCurrent) / duree) * largeurTimeline
                                            Rectangle()
                                                .fill(Color.yellow)
                                                .frame(width: max(x2 - x1, 1), height: 24)
                                                .offset(x: 140 + x1)
                                        }
                                        if tracksLocked {
                                            Rectangle().fill(Color.black).frame(width: 140, height: 24)
                                        }
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .frame(height: 24)
                                            .onContinuousHover { phase in
                                                handleRulerHover(phase: phase, largeurTimeline: largeurTimeline)
                                            }
                                            .gesture(
                                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                                    .onChanged { value in
                                                        handleRulerDragChanged(value, largeurTimeline: largeurTimeline)
                                                    }
                                                    .onEnded { value in
                                                        handleRulerDragEnded(value, largeurTimeline: largeurTimeline)
                                                    }
                                            )
                                            .simultaneousGesture(
                                                TapGesture(count: 2).onEnded {
                                                    handleRulerDoubleClick()
                                                }
                                            )
                                            .overlay {
                                                CursorOverlay(
                                                    isActive: isNearLoopZoneEdge || resizingLoopZoneEdge != nil,
                                                    symbolName: "chevron.left.chevron.right"
                                                )
                                                .allowsHitTesting(false)
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
                                                        // Dimmed when tracks are locked: the gesture below is a
                                                        // no-op then, so the handle shouldn't look draggable.
                                                        .foregroundColor(.black.opacity(tracksLocked ? 0.12 : 0.35))
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
                                                                    .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
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
                                                                    .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
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
                                                                    .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
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
                                                                    .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
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
                                                                    .fill(pistes[index].quantizeActive ? Color.clear : Color.gray.opacity(0.5))
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

                                                        Button(action: {
                                                            guard !tracksLocked else { return }
                                                            // The /markers track can't be duplicated (or deleted) —
                                                            // only hidden by folding — so ⌥-hover here never switches
                                                            // this button into duplicate mode; it always just clears.
                                                            pistes[index].evenements.removeAll()
                                                            lastSentEvents.removeAll()
                                                        }) {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .foregroundColor(.gray)
                                                                .frame(width: 16, height: 16)
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
                                                                tempQuantizeEnabled = pistes[index].quantizeEnabled
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

                                                        Button(action: {
                                                            guard !tracksLocked else { return }
                                                            if isOptionHeldForCursor && duplicateHoverTrackIndex == index {
                                                                duplicateTrack(at: index)
                                                            } else {
                                                                pistes[index].evenements.removeAll()
                                                                lastSentEvents.removeAll()
                                                            }
                                                        }) {
                                                            // Fixed frame: swapping between the two SF Symbols (they have
                                                            // slightly different intrinsic widths) must not nudge the
                                                            // neighboring buttons in this row — only the icon inside
                                                            // this fixed box changes, never the row's layout.
                                                            // Color stays gray in both modes — only the symbol itself
                                                            // changes (plus the tooltip) — so there's no color to pick
                                                            // that has to fight the track's own color for contrast.
                                                            Image(systemName: (isOptionHeldForCursor && duplicateHoverTrackIndex == index) ? "doc.on.doc.fill" : "xmark.circle.fill")
                                                                .foregroundColor(.gray)
                                                                .frame(width: 16, height: 16)
                                                        }
                                                        .buttonStyle(.borderless)
                                                        .onHover { hovering in
                                                            duplicateHoverTrackIndex = hovering ? index : (duplicateHoverTrackIndex == index ? nil : duplicateHoverTrackIndex)
                                                        }
                                                        .help((isOptionHeldForCursor && duplicateHoverTrackIndex == index) ? "Duplicate track" : "Clear all points on this track (hold ⌥ while hovering this button to duplicate the track instead)")

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
                                                        DiagonalStripes(stripeWidth: 1.5, spacing: 1.5)
                                                            .stroke(
                                                                // Curve gets a fixed, more-orange-leaning yellow for
                                                                // the stripes themselves (rather than the track's own
                                                                // pure yellow) — background stays as-is below. Step
                                                                // keeps the dynamic track color for its stripes.
                                                                pistes[index].type == .curve
                                                                    ? Color(red: 1.0, green: 0.75, blue: 0.1)
                                                                    : pistes[index].couleur,
                                                                lineWidth: 1.5
                                                            )
                                                            .background(
                                                                // Fixed background per type, independent of the track's
                                                                // own color — both branches must be the same concrete
                                                                // type (plain Color) or the compiler chokes trying to
                                                                // type-check this ternary inside such a deeply nested
                                                                // modifier chain. Curve gets a warm orange, step a
                                                                // magenta/pink — user-picked to read clearly at this
                                                                // 4px height regardless of the track's own color.
                                                                pistes[index].type == .curve
                                                                    ? Color(red: 1.0, green: 0.58, blue: 0.004)
                                                                    : Color(red: 1.0, green: 0.196, blue: 0.988)
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
                                                                    guard !(NSEvent.modifierFlags.contains(.shift) && NSEvent.modifierFlags.contains(.option)), !isPasteModeActive else { return }
                                                                    if creatingPointId == nil {
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
                                                                    if isPasteModeActive { return }
                                                                    if creatingPointId == nil {
                                                                        beginCreatingPoint(at: value.startLocation, trackIndex: index, largeurTimeline: largeurTimeline)
                                                                    }
                                                                    updateCreatingPoint(at: value.location, largeurTimeline: largeurTimeline)
                                                                }
                                                                .onEnded { value in
                                                                    guard !tracksLocked else { return }
                                                                    if creatingPointId != nil {
                                                                        finishCreatingPoint()
                                                                        return
                                                                    }
                                                                    // No point was being created: this was a Shift
                                                                    // click on (or near) the curve line.
                                                                    let time = (Double(value.location.x) / Double(largeurTimeline)) * duree
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
                                                                if NSEvent.modifierFlags.contains(.shift) && !NSEvent.modifierFlags.contains(.option) {
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
                                                        isActive: isNearCurveControlZone && isOptionHeldForCursor && !isShiftHeldForCursor,
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
                                                                    guard !(NSEvent.modifierFlags.contains(.shift) && NSEvent.modifierFlags.contains(.option)), !isPasteModeActive else { return }
                                                                    if creatingPointId == nil {
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
                                                    .fill(selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
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
                                                                        .foregroundColor(selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)

                                                                    if showPointCoordinates {
                                                                        Text(String(format: "%.2f", event.time) + "s")
                                                                            .font(.caption2)
                                                                            .foregroundColor(.black)
                                                                            .offset(y: 12)
                                                                    }
                                                                }
                                                            } else if pistes[index].type == .bang {
                                                                Rectangle()
                                                                .fill(selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
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
                                                                            .stroke(selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur, lineWidth: 2.5)
                                                                                .frame(width: 10, height: 10)
                                                                                .contentShape(Rectangle())
                                                                        } else {
                                                                            ZStack {
                                                                                Rectangle()
                                                                                .fill(selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
                                                                                    .frame(width: 17, height: 3)
                                                                                    .rotationEffect(.degrees(45))
                                                                                Rectangle()
                                                                                .fill(selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
                                                                                    .frame(width: 17, height: 3)
                                                                                    .rotationEffect(.degrees(-45))
                                                                            }
                                                                            .frame(width: 17, height: 17)
                                                                            .contentShape(Rectangle())
                                                                        }
                                                                    } else {
                                                                        Circle()
                                                            .fill(selectedPointIDs.contains(event.id) ? Color.white : pistes[index].couleur)
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
                                                if lassoTrackIndex == index,
                                                   let start = lassoStartLocation,
                                                   let current = lassoCurrentLocation {
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
                                                    isActive: (isShiftHeldForCursor && isOptionHeldForCursor && !tracksLocked) || isPasteModeActive,
                                                    symbolName: isPasteModeActive && (isNearSnapZone || isNearGridSnapZone)
                                                        ? "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left"
                                                        : "dot.crosshair",
                                                    color: isPasteModeActive ? .red : .black
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
                                        let clicked = (Double(location.x - 140) / Double(largeurTimeline)) * duree
                                        position = min(max(clicked, 0), duree)
                                        sendOSCMessagesForPosition(position)
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
                                .offset(x: CGFloat(position / duree) * largeurTimeline + 140)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let xPos = Double(value.location.x - 140)
                                            var newPosition = (xPos / Double(largeurTimeline)) * duree
                                            // ⌘ snaps the playhead to the nearest marker/grid
                                            // line — the same snap zone and candidates a point
                                            // drag uses, so the two behave identically.
                                            if NSEvent.modifierFlags.contains(.command),
                                               let snapped = nearestSnapTime(xPos: xPos, largeurTimeline: Double(largeurTimeline)) {
                                                newPosition = snapped
                                            }
                                            position = min(max(newPosition, 0), duree)
                                            sendOSCMessagesForPosition(position)
                                        }
                                )
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        // simultaneousGesture (not .onTapGesture): the drag
                                        // above uses minimumDistance 0, which would otherwise
                                        // win exclusive recognition and swallow every tap
                                        // before a double-tap could ever be detected.
                                        goToTimeString = formattedDuration(position)
                                        goToMarkerNameString = ""
                                        showPlayheadPositionChoice = true
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
            timelineStore.undoManager = undoManager
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
            if isPointListWindowVisible {
                refreshPointList()
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
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowModifierKeysHelp)) { _ in
            openModifierKeysHelpWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierPlayPause)) { _ in
            togglePlayback()
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
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierEditLoopZone)) { _ in
            loopZoneEditStartString = formattedDuration(loopZoneStart ?? 0)
            loopZoneEditEndString = formattedDuration(loopZoneEnd ?? 0)
            showLoopZoneEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierClearLoopZone)) { _ in
            loopZoneStart = nil
            loopZoneEnd = nil
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
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierShowPointList)) { _ in
            openPointListWindow()
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
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDeleteSelectedPoints)) { _ in
            deleteSelectedPoints()
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierCut)) { _ in
            // The menu's Cut item: cut = copy the point selection then
            // delete it (same guard as Copy/Paste — only when there's a
            // selection and we're not mid-edit in some other text field);
            // otherwise fall back to the standard system text cut.
            if !selectedPointIDs.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                copySelectedPoints()
                deleteSelectedPoints()
            } else {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierCopy)) { _ in
            // The menu's Copy item: copy the point selection if there is
            // one (and we're not mid-edit in some other text field);
            // otherwise fall back to the standard system text copy.
            if !selectedPointIDs.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                copySelectedPoints()
            } else {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierPaste)) { _ in
            // The menu's Paste item: enter point paste mode if the point
            // clipboard has something (and we're not mid-edit elsewhere);
            // otherwise fall back to the standard system text paste.
            if !pointClipboard.isEmpty, !(NSApp.keyWindow?.firstResponder is NSTextView) {
                isPasteModeActive = true
            } else {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .OSCcourierDuplicateSelection)) { _ in
            // Silently does nothing if there's no offset to repeat yet
            // (no clipboard, or no paste since the last copy) — same as
            // pressing ⌘D itself in that situation.
            guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return }
            duplicateSelectionWithSameOffset()
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
        .sheet(isPresented: $showPlayheadPositionChoice) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Go to Position")
                    .font(.headline)

                TextField("mm:ss", text: $goToTimeString)
                    .textFieldStyle(.roundedBorder)
                    .focused($playheadPositionFocusedField, equals: .time)
                    .onSubmit { goToChosenPlayheadPosition() }
                    .disabled(!goToMarkerNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                TextField("Marker name", text: $goToMarkerNameString)
                    .textFieldStyle(.roundedBorder)
                    .focused($playheadPositionFocusedField, equals: .marker)
                    .onSubmit { goToChosenPlayheadPosition() }
                    .onChange(of: goToMarkerNameString) { _, _ in
                        playheadMarkerNotFound = false
                    }
                    .disabled(goToMarkerNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && goToTimeString != goToTimeInitialValue)
                if playheadMarkerNotFound {
                    Text("No marker with that name was found.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Divider()

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        showPlayheadPositionChoice = false
                    }
                    .keyboardShortcut(.escape)
                    Button("Go") {
                        goToChosenPlayheadPosition()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 300)
            .onAppear {
                playheadPositionFocusedField = .time
                playheadMarkerNotFound = false
                goToTimeInitialValue = goToTimeString
            }
        }
        .sheet(isPresented: $showLoopZoneEditor) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Loop Zone")
                    .font(.headline)

                HStack {
                    Text("Start")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("mm:ss", text: $loopZoneEditStartString)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("End")
                        .frame(width: 50, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("mm:ss", text: $loopZoneEditEndString)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        showLoopZoneEditor = false
                    }
                    .keyboardShortcut(.escape)
                    Button("Apply") {
                        if let s = parseDuration(loopZoneEditStartString),
                           let e = parseDuration(loopZoneEditEndString) {
                            let clampedS = min(max(s, 0), duree)
                            let clampedE = min(max(e, 0), duree)
                            loopZoneStart = min(clampedS, clampedE)
                            loopZoneEnd = max(clampedS, clampedE)
                        }
                        showLoopZoneEditor = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 280)
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
        .alert("Different track type", isPresented: $showDifferentTypePasteAlert) {
            Button("Adapt (Scale to Fit)") {
                if let t = pendingPasteAnchorTime, let idx = pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: true)
                    lastPasteOffset = nil
                }
                isPasteModeActive = false
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
            Button("Cancel", role: .cancel) {
                // Dismiss only — stays in paste mode so the user can try a
                // different spot, or press Escape to back out entirely.
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
        } message: {
            Text("The copied points come from a different track type. Adapt them to this track (converting labels, rescaling values), or cancel?")
        }
        .alert("Different amplitude range", isPresented: $showPasteScaleRangeAlert) {
            Button("Scale to Fit") {
                if let t = pendingPasteAnchorTime, let idx = pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: true)
                    lastPasteOffset = nil
                }
                isPasteModeActive = false
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
            Button("Keep As-Is") {
                if let t = pendingPasteAnchorTime, let idx = pendingPasteTrackIndex {
                    _ = pasteClipboard(at: t, trackIndex: idx, scaleToRange: false)
                    lastPasteOffset = nil
                }
                isPasteModeActive = false
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
            Button("Cancel", role: .cancel) {
                // Dismiss only — stays in paste mode so the user can try a
                // different spot, or press Escape to back out entirely.
                pendingPasteAnchorTime = nil
                pendingPasteTrackIndex = nil
            }
        } message: {
            Text("The copied points come from a track with a different amplitude range. Scale their values to fit this track's range, or paste them unchanged (clamped if out of range)?")
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
    var autofillRectangleSheet: some View {
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

    var autofillWaveSheet: some View {
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
    var editPointSheet: some View {
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
                TextField("", text: $nouveauComment)
                    // A plain single-line field: no newlines to type in the
                    // first place, and Return submits (like every other
                    // field in this sheet) instead of inserting a line break.
                    .onSubmit { commitPointEdit() }
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

    var autofillBangSheet: some View {
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

    var gridSettingsSheet: some View {
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
    var rangeEditorSheet: some View {
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
                        // Step value kept — only switched off — so returning to
                        // Float brings it back.
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
                        // Only seed a value if there isn't one yet: an existing
                        // step is kept (shown greyed while off) so toggling
                        // back on restores exactly what was there.
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


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
