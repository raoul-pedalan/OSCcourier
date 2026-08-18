// Point-drag/curve-bend gesture handlers now live directly on
// PointDragState (see PointDragState.swift) and are called straight from
// TrackContentColumn — no ContentView adapter needed anymore, since
// nothing else called them.
