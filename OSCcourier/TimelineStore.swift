import SwiftUI
import Combine

class TimelineStore: ObservableObject {
    @Published var pistes: [TimelineTrack] = [
        TimelineTrack(nom: "/markers", couleur: Color(red: 0.45, green: 0.4, blue: 0.4), evenements: [], type: .bang, height: 45),
        TimelineTrack(nom: "/track_1", couleur: .blue, evenements: [], type: .bang, height: 45),
        TimelineTrack(nom: "/track_2", couleur: .yellow, evenements: [], type: .curve, height: 60),
        TimelineTrack(nom: "/track_3", couleur: .yellow, evenements: [], type: .curve, height: 60),
        TimelineTrack(nom: "/track_4", couleur: Color(red: 0.608, green: 0.086, blue: 0.365), evenements: [], type: .step, height: 60)
    ]

    weak var undoManager: UndoManager?

    // Point d'entrée unique pour toute mutation de `pistes`. Le pattern
    // "registerUndo appelle la même méthode récursivement" est ce qui fait
    // apparaître le redo automatiquement — pas besoin de gérer une pile séparée.
    func setPistes(_ newValue: [TimelineTrack]) {
        guard newValue != pistes else { return }
        let oldValue = pistes
        pistes = newValue
        undoManager?.registerUndo(withTarget: self) { target in
            target.setPistes(oldValue)
        }
    }

    // Finds the next free "<base>.N" name for a duplicate. Strips any
    // existing ".N" suffix from the source name first, so duplicating a
    // duplicate keeps incrementing off the same base instead of nesting
    // suffixes ("/track_4.1" -> "/track_4.2", never "/track_4.1.1").
    func nextDuplicateName(basedOn name: String) -> String {
        var base = name
        if let dotRange = base.range(of: #"\.\d+$"#, options: .regularExpression) {
            base.removeSubrange(dotRange)
        }
        let existingNames = Set(pistes.map { $0.nom })
        var n = 1
        while existingNames.contains("\(base).\(n)") {
            n += 1
        }
        return "\(base).\(n)"
    }

    // Inserts a copy of the track at `index` right after it. Fresh UUIDs for
    // both the track and every one of its points — reusing the originals
    // would create duplicate ids across tracks, which breaks anything keyed
    // by id across the whole timeline (e.g. the Points List table, whose rows
    // are flattened from every track into one id-keyed list). Lock-checking
    // stays the caller's responsibility (same as every other mutation here).
    func duplicateTrack(at index: Int) {
        guard pistes.indices.contains(index) else { return }
        let original = pistes[index]
        let copy = TimelineTrack(
            nom: nextDuplicateName(basedOn: original.nom),
            couleur: original.couleur,
            evenements: original.evenements.map { event in
                TimelineEvent(time: event.time, label: event.label, y: event.y,
                               segmentCurve: event.segmentCurve, segmentBulge: event.segmentBulge,
                               segmentEnabled: event.segmentEnabled, comment: event.comment)
            },
            type: original.type,
            isMuted: original.isMuted,
            minAmplitude: original.minAmplitude,
            maxAmplitude: original.maxAmplitude,
            height: original.height,
            isFolded: original.isFolded,
            isGate: original.isGate,
            quantizeStep: original.quantizeStep,
            quantizeEnabled: original.quantizeEnabled
        )
        var newPistes = pistes
        newPistes.insert(copy, at: index + 1)
        setPistes(newPistes)
    }
}

