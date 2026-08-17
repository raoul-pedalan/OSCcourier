import SwiftUI

// Small derived/computed properties: the `pistes` bridge onto
// timelineStore, dark-mode track tint, zoom-range math (maxZoomX,
// referenceMaxZoomX, zoomKnobSensitivity), the markers-track visibility
// filter, total content height, and the next auto-generated track name.
// Split out of ContentView.swift verbatim — no logic changes.
extension ContentView {

    var pistes: [TimelineTrack] {
        get { timelineStore.pistes }
        nonmutating set { timelineStore.setPistes(newValue) }
    }

    // Track background tint. The same 0.3 that looks right on a light
    // background reads as too saturated against a dark one, so it's pulled
    // back in dark mode.
    var trackBackgroundOpacity: Double {
        colorScheme == .dark ? 0.18 : 0.3
    }

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

}
