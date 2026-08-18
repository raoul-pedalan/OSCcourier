import SwiftUI

// Thin adapter: builds the extracted `TrackRow` view.
extension ContentView {
    func trackRow(index: Int, largeurTimeline: CGFloat) -> some View {
        TrackRow(
            timelineStore: timelineStore,
            pointDrag: pointDrag,
            pointEditing: pointEditing,
            trackAmplitudeEdit: trackAmplitudeEdit,
            trackDragReorder: trackDragReorder,
            autofill: autofill,
            selection: selection,
            pasteClipboard: pasteClipboard,
            transport: transport,
            uiChrome: uiChrome,
            index: index,
            largeurTimeline: largeurTimeline,
            onBeginCreatingPoint: { location, trackIndex, width in
                beginCreatingPoint(at: location, trackIndex: trackIndex, largeurTimeline: width)
            },
            onUpdateCreatingPoint: { location, width in
                updateCreatingPoint(at: location, largeurTimeline: width)
            },
            onFinishCreatingPoint: {
                finishCreatingPoint()
            },
            onToggleSegmentEnabled: { time, trackIndex in
                toggleSegmentEnabled(forTime: time, trackIndex: trackIndex)
            },
            onBeginEditingPoint: { eventId in
                beginEditingPoint(eventId: eventId)
            },
            onPasteDragEnded: { value, trackIndex, width in
                handlePasteDragEnded(value, trackIndex: trackIndex, largeurTimeline: width)
            }
        )
    }
}
