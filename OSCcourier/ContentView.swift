import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    // Play is the toolbar's first item, so its distance from the toolbar's
    // own leading edge never changes with window width — nothing sits
    // before it that could push it around. That makes "the zoom knob, at
    // the midpoint between the edge and Play" just as constant: no need to
    // measure Play's actual on-screen position at runtime, half of its
    // fixed target distance IS that midpoint, always.
    let playButtonLeadingDistance: CGFloat = 140
    var zoomKnobLeadingDistance: CGFloat { playButtonLeadingDistance / 2 }
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
    // Shared with OSCcourierApp via the same @AppStorage key, so its "Open
    // Recent" submenu updates reactively whenever this list changes here.
    @AppStorage("recentFilePaths") var recentFilePathsData: String = ""
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







    // Shared with SettingsView via the same @AppStorage key.
    @AppStorage("oscAddressPrefix") var oscAddressPrefix: String = ""
    @AppStorage("oscReceivePort") var oscReceivePort: Int = 7500
    // Grid snap mode: false = grid lines only snap like markers do, via
    // ⌘+drag; true = "magnetic grid", points snap to the nearest grid line
    // automatically while dragging, no ⌘ needed. Markers themselves always
    // require ⌘ either way — this setting only affects grid-line snapping.
    @AppStorage("magneticGridSnap") var magneticGridSnap: Bool = false




















    var body: some View {
        let baseContent = VStack(spacing: 0) {
            toolbarBar


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
                                    rulerBar(largeurTimeline: largeurTimeline, outerWidth: outerGeometry.size.width, geometryWidth: geometry.size.width)

                                    ForEach(Array(pistes.enumerated()), id: \.element.id) { index, _ in
                                        trackRow(index: index, largeurTimeline: largeurTimeline)
                                    }
                                }

                                markersGridAndPlayhead(largeurTimeline: largeurTimeline, totalHeight: totalHeight)
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

        return applySheetPresentation(
            applyAlertsAndConfirmations(
                applyNotificationReceivers(baseContent)
            )
        )
    }

}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
