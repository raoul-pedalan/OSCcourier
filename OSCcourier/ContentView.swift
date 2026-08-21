import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    // Play is the toolbar's first item, so its distance from the toolbar's
    // own leading edge never changes with window width — nothing sits
    // before it that could push it around. That makes "the zoom knob, at
    // the midpoint between the edge and Play" just as constant: no need to
    // measure Play's actual on-screen transport.position at runtime, half of its
    // fixed target distance IS that midpoint, always.
    let playButtonLeadingDistance: CGFloat = 140
    var zoomKnobLeadingDistance: CGFloat { playButtonLeadingDistance / 2 }
    @StateObject var oscManager = OSCManager()
    @StateObject var messageStore = OSCMessageStore()
    @StateObject var pointListStore = PointListStore()
    // Per-window (not @AppStorage, and not a @State here either): these
    // six used to be shared across every OSCcourier window via
    // UserDefaults, so toggling Loop or Show Grid in one window silently
    // toggled it in every other open window too. The four that other
    // views (RulerBar, TrackContentColumn, TrackHeaderColumn, TrackRow)
    // also need to read now live on uiChrome/transport instead — the
    // per-window ObservableObjects already threaded down to those views —
    // with these as thin proxies so the rest of ContentView's own code
    // (spread across its extension files) didn't need to change at all.
    // Routed to/from the App-level menu (which has no ContentView instance
    // of its own) via focusedSceneValue — see FocusedDocumentValues.swift.
    var enBoucle: Bool {
        get { transport.enBoucle }
        nonmutating set { transport.enBoucle = newValue }
    }
    // A loop zone, drawn as a yellow band in the ruler. When set, looping
    // wraps between these two times instead of the whole timeline. nil/nil
    // means "no zone" — Loop then loops the entire timeline as before.
    // Tracks an in-progress ruler drag so the zone previews live as the
    // user drags, rather than only appearing once they release.
    // Set once a drag is confirmed to have started near an existing zone's
    // edge — from then on that same drag resizes the zone instead of
    // drawing a new one or moving the playhead.
    // Hover-only (not dragging) proximity, purely for the cursor.
    // Dragging the zone's body (not an edge) translates the whole zone.
    // The anchor is the time under the mouse at drag start, so the zone
    // moves by the same delta as the cursor rather than snapping its start
    // to the cursor transport.position.
    // Double-click on the ruler opens this to edit start/end precisely.
    // Real wall-clock timestamp of the previous playback tick (monotonic
    // clock, in seconds). Used to advance `transport.position` by the actual elapsed
    // time between ticks instead of an assumed fixed 0.05 — Timer doesn't
    // guarantee exact intervals, so assuming a fixed delta would let small
    // per-tick errors accumulate into real drift over a long playback session.
    @StateObject var timelineStore = TimelineStore()
    @StateObject var windowManagement = WindowManagementState()
    @StateObject var durationHandle = DurationHandleState()
    @StateObject var trackDragReorder = TrackDragReorderState()
    @StateObject var loopZone = LoopZoneState()
    @StateObject var uiChrome = UIChromeState()
    @StateObject var transport = TransportState()
    @StateObject var trackAmplitudeEdit = TrackAmplitudeEditState()
    @StateObject var pointEditing = PointEditingState()
    @StateObject var autofill = AutofillState()
    @StateObject var selection = SelectionState()
    @StateObject var pasteClipboard = PasteClipboardState()
    @StateObject var pointDrag = PointDragState()
    @Environment(\.undoManager) var undoManager

    // Autofill Rectangle popup (step tracks): generates a rectangular/pulse
    // pattern of step events across the track.

    // Autofill Wave popup (curve tracks): generates a sine or (skewed) sawtooth wave.

    // Autofill Bang popup (bang/markers tracks): generates evenly spaced bangs.
    // Message tracks only: prefix used for generated labels ("prefix_1",
    // "prefix_2", ...), replacing the previously hardcoded "key".
    // Set when the pencil button is pressed on a track that already has
    // points, to show an "Overwrite track?" confirmation before opening
    // the actual autofill popup.
    // Modifier-aware cursor over points: shift = delete cursor, cmd = snap cursor.
    // Tracks whether the mouse is currently over any point, and listens for
    // modifier key changes while hovering (since .onHover alone only fires on
    // enter/exit, not when a modifier key is pressed mid-hover).
    // Option-drag on a curve segment (Logic Pro automation-curve style).
    // Whether the cursor is currently within the erase/bend zone (12px) of
    // this hovered curve track's line. Boolean on purpose: it only changes
    // on zone transitions (rare), unlike storing the raw hover transport.position in
    // @State, which changed every single pixel of mouse movement and forced
    // a full body re-render per pixel — constantly rebuilding the hover
    // stream and tracking areas, which is what silently broke both the
    // Option and Shift hover cursors.
    // Mirrors pointDrag.isOptionHeldForCursor for Shift, live-updated by the same
    // flagsChanged monitor — needed so Shift+Option (the lasso trigger) can
    // be told apart from plain Shift (erase-point cursor / toggle segment)
    // in view-level (non-gesture-closure) contexts.
    // Points currently selected via the lasso, rendered white. Cleared by
    // any ordinary click/drag elsewhere (creating a point, dragging or
    // tapping an existing point).
    // Lasso in progress: which track it started on (only that track's
    // points are eligible — a lasso never spans multiple tracks), and its
    // start/current location in that track's own local coordinate space.
    // Group-drag of a selection: original time of every selected point,
    // captured on the first tick of a drag that starts on an already-
    // selected point. Every point then moves by the same X delta as the
    // dragged one — Y is untouched, only time shifts.
    // Same idea as the time baseline above, but for Y — lets a group drag
    // move vertically too (curve/step only), with the delta shrunk (not
    // each point clamped independently) if it would push any selected
    // point out of range, so relative spacing between values is preserved.
    // Copy/paste of a point selection. The clipboard remembers the source
    // track's type, since paste is only allowed onto a same-type track.
    // The source track's amplitude range, remembered alongside the clipboard
    // so paste can detect a mismatch with the destination track and offer to
    // rescale (curve/step tracks only — the only types where Y is meaningful).
    // The earliest original time among the copied points (before they were
    // ever pasted anywhere) — combined with where the most recent paste
    // landed, this gives ⌘D the offset to repeat.
    // Fixed the first time ⌘D is pressed (derived from the manual paste
    // that preceded it), then reused as-is for every subsequent press —
    // recomputing it from pasteClipboard.lastPasteAnchorTime each time would compound
    // into a geometric progression (2, 4, 8, 16...) instead of a constant
    // step (2, 4, 6, 8...), since the anchor keeps advancing.
    // Tracks proximity to a grid line specifically (not markers) — used to
    // show the snap cursor for "magnetic grid" auto-snap even without ⌘ held.
    // Whether the closest ⌘-snap target (marker or grid line combined) is
    // specifically the grid line — used only to color the snap cursor.
    // Tracks whether the window is currently full screen, so the top
    // padding reserved to clear the title bar can be dropped once that
    // title bar itself is hidden (full screen has no title bar to avoid).
    @Environment(\.colorScheme) var colorScheme

    // Point currently being placed by a press-drag-release on empty track
    // space: created on mouse-down, dragged while held, committed on release.
    // Set when the user commits a quantize step that had to be clamped, so we
    // can tell them rather than silently changing what they typed.
    // Explicit visibility tracking for the OSC messages window's Open/Close
    // toggle — more reliable than reading NSWindow.isVisible directly.
    // Points list window (same open/close toggle pattern as the OSC one).
    // Modifier Keys quick-reference window (same open/close toggle pattern).
    // Remembers the file chosen on the first Save, so subsequent saves
    // silently overwrite it instead of prompting again.
    @State var savedFileURL: URL?
    // This ContentView instance's own hosting NSWindow, captured via
    // WindowAccessor — lets menu-command notification handlers tell
    // whether THIS window is the frontmost one (see isFrontmostWindowGroup
    // in ContentView+NotificationHandling), since several OSCcourier
    // windows can be open and each gets the same broadcast notification.
    @State var hostWindow: NSWindow?
    // Extracted out of the modifier chain below — the type-checker choked
    // ("unable to type-check this expression in reasonable time") once this
    // constructor call was inlined directly inside .focusedSceneValue(...).
    private var focusedDocumentValue: OSCcourierFocusedDocument {
        OSCcourierFocusedDocument(transport: transport, uiChrome: uiChrome)
    }
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
    // The time field always has a pre-filled default (the current
    // transport.position), so "has content" alone can't signal that the user
    // actually means to use it — captured on open, compared against the
    // live value to tell "still the default" from "the user typed here".
    // Which track's Clear/Duplicate button the cursor is currently over —
    // ⌥ only swaps that specific button to "duplicate", not every track's
    // button at once just because ⌥ happens to be held somewhere.
    // Duration trim handle, pinned to the right edge of the window: drag
    // horizontally to grow/shrink the track's total duration.
    // Velocity-based drag: the horizontal offset from where the drag
    // started controls the *rate* of change (seconds of transport.duree per second
    // held), rather than directly mapping to a transport.duree delta. A repeating
    // transport.timer applies that rate continuously while the drag is held.
    // Brief flash indicator for the compact command bar's "OSC" label,
    // lit up for a short moment each time an OSC message actually goes out.
    // How fast transport.duree changes per second, per pixel of horizontal offset
    // from the drag's start point.
    // Non-linear speed curve: rate = sign(dx) * |dx|^exponent * scale.
    // exponent > 1 makes small offsets noticeably slower (more precise) and
    // large offsets noticeably faster than a plain linear mapping would.
    let durationDragVelocityExponent: Double = 1.8
    let durationDragVelocityScale: Double = 0.00126
    // Track reordering (drag handle in the header). "markers" (index 0) stays pinned.
    // Accumulates by ± the swapped neighbor's height each time a swap happens during
    // the same drag, so the raw (cumulative-since-start) gesture translation can be
    // corrected into the right visual offset without ever being overwritten wrong.

    // Vertical margin (= circle radius) reserved at the top/bottom of a curve
    // track so that points at the extreme values (0 or 1) aren't half-clipped.
    // Shared by the ruler labels, the path, and the point positions so they
    // all stay consistent with each other.

    // Width of the duration trim handle strip pinned to the window's right
    // edge. Shared so the timeline drawing width can reserve exactly this
    // much, keeping the end of the tracks aligned with the handle's bar.
    let durationHandleWidth: CGFloat = 18

    // MARK: - Zoom-centering state
    // True while a pinch gesture is in progress: TimelineScrollView's Coordinator
    // handles its own mouse-anchored centering during a pinch, so the viewport-center
    // recentering below (used for the RotaryKnob) should stand down while this is true.
    // Toggle for showing/hiding the "time, value" coordinate labels next to points.
    var showPointCoordinates: Bool {
        get { uiChrome.showPointCoordinates }
        nonmutating set { uiChrome.showPointCoordinates = newValue }
    }
    // Toggle for showing/hiding the timeline grid overlay.
    var showGrid: Bool {
        get { uiChrome.showGrid }
        nonmutating set { uiChrome.showGrid = newValue }
    }
    @AppStorage("oscMessagesPerSecond") var oscMessagesPerSecond: Int = 20
    // Toggles between the full command bar (toolbar with all controls) and
    // a compact, full-width control line (transport.position + play/loop indicators).
    var showCommandBar: Bool {
        get { uiChrome.showCommandBar }
        nonmutating set { uiChrome.showCommandBar = newValue }
    }
    var showMarkersTrack: Bool {
        get { uiChrome.showMarkersTrack }
        nonmutating set { uiChrome.showMarkersTrack = newValue }
    }
    var tracksLocked: Bool {
        get { uiChrome.tracksLocked }
        nonmutating set { uiChrome.tracksLocked = newValue }
    }
    // "Go to (mm:ss)" dialog, triggered from the Play menu.
    // Grid line generation: evenly spaced dashed vertical lines across all
    // tracks, same period/phase model as the bang autofill.
    // Width of the timeline viewport (updated from the outer GeometryReader), used to
    // compute how much zoom is needed to reach the 1s = 1000px target regardless of `transport.duree`.







    // Per-window (not @AppStorage): each OSCcourier window/project has its
    // own OSC receive port and address prefix, so multiple windows can each
    // talk to/listen from a different OSC endpoint without colliding.
    // Persisted in the project file itself (see SaveData) rather than
    // UserDefaults, same as oscManager.address already is.
    @State var oscAddressPrefix: String = ""
    @State var oscReceivePort: Int

    // Bumped once per new ContentView instance (i.e. per window) so that
    // brand-new/untitled documents each start with a different default
    // receive port instead of all colliding on 7500. Opening an existing
    // project overrides this with the port saved in that file (see
    // loadProject), so the counter only matters for fresh windows.
    private static var nextReceivePortOffset = 0

    init() {
        let offset = ContentView.nextReceivePortOffset
        ContentView.nextReceivePortOffset += 1
        _oscReceivePort = State(initialValue: 7500 + offset)
    }
    // Grid snap mode: false = grid lines only snap like markers do, via
    // ⌘+drag; true = "magnetic grid", points snap to the nearest grid line
    // automatically while dragging, no ⌘ needed. Markers themselves always
    // require ⌘ either way — this setting only affects grid-line snapping.
    @AppStorage("magneticGridSnap") var magneticGridSnap: Bool = false
    @AppStorage("includeMarkersInOffset") var includeMarkersInOffset: Bool = false




















    var body: some View {
        let baseContent = VStack(spacing: 0) {
            toolbarBar


            GeometryReader { outerGeometry in
                TimelineScrollView(
                    offsetX: $transport.scrollOffsetX,
                    zoomX: $transport.zoomX,
                    isPinchZooming: $transport.isPinchZooming,
                    zoomRange: 1.0...maxZoomX,
                    duree: transport.duree,
                    contentWidth: outerGeometry.size.width * CGFloat(transport.zoomX),
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
                        .frame(width: outerGeometry.size.width * CGFloat(transport.zoomX))
                }
                .onChange(of: transport.zoomX) { oldZoom, newZoom in
                    recenterOnZoomChange(oldZoom: oldZoom, newZoom: newZoom, outerWidth: outerGeometry.size.width)
                }
                .onAppear {
                    transport.timelineAreaWidth = outerGeometry.size.width
                }
                .onChange(of: outerGeometry.size.width) { _, newWidth in
                    transport.timelineAreaWidth = newWidth
                    transport.zoomX = min(transport.zoomX, maxZoomX)
                }
                .onChange(of: transport.duree) { _, _ in
                    transport.zoomX = min(transport.zoomX, maxZoomX)
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
        .background(WindowAccessor { window in
            hostWindow = window
        })
        .focusedSceneValue(\.oscCourierDocument, focusedDocumentValue)
        .navigationTitle(savedFileURL?.deletingPathExtension().lastPathComponent ?? "OSCcourier")
        // Keeps the separate Point List window's title (which repeats the
        // file name so it's clear which document it belongs to, since
        // several OSCcourier windows can be open at once) in sync whenever
        // this window's file changes — load, Save As, etc.
        .onChange(of: savedFileURL) { _, _ in
            updatePointListWindowTitle()
        }
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
            // Only rebuild the transport.timer if it's currently running — otherwise
            // the new rate is picked up next time playback starts anyway.
            if transport.enLecture {
                startPlaybackTimer()
            }
        }
        .onChange(of: transport.enLecture) { _, isPlaying in
            // Rebuild the transport.timer each time playback (re)starts, so it always
            // uses the current oscMessagesPerSecond value — the setting may
            // have been changed while stopped, in which case setupOnAppear's
            // one-time transport.timer would still be running at the old rate.
            if isPlaying {
                startPlaybackTimer()
            }
        }
        .onChange(of: pistes) { _, _ in
            // Keep the points list window live: only rebuild the snapshot when
            // that window is actually open, so the (O(points)) flattening isn't
            // paid on every single edit the rest of the time.
            if windowManagement.isPointListWindowVisible {
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
