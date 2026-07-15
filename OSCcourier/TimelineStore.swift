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
}

