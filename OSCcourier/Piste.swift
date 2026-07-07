// Piste.swift
import SwiftUI

enum TypePiste {
    case normal
    case bang
    case curve
}

struct Piste: Identifiable {
    let id = UUID()
    var nom: String
    var couleur: Color
    var evenements: [Double]
    var type: TypePiste = .normal
    var isMuted: Bool = false
}
