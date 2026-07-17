import SwiftUI

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
    // Kept separate from quantizeStep so switching quantization off preserves
    // the step the user had dialled in — turning it back on restores it,
    // instead of starting from zero every time.
    var quantizeEnabled: Bool = false

    // Quantization only actually applies when it's switched on AND has a
    // usable step. Everything (snapping, ticks) keys off this.
    var quantizeActive: Bool {
        quantizeEnabled && quantizeStep > 0
    }

    init(id: UUID = UUID(), nom: String, couleur: Color, evenements: [TimelineEvent], type: TrackType, isMuted: Bool = false, minAmplitude: Double = 0.0, maxAmplitude: Double = 1.0, height: CGFloat = 60, isFolded: Bool = false, isGate: Bool = false, quantizeStep: Double = 0, quantizeEnabled: Bool = false) {
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
        self.quantizeEnabled = quantizeEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, couleur, evenements, type, isMuted, minAmplitude, maxAmplitude, height, isFolded, isGate, quantizeStep, quantizeEnabled
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
        // Projects saved before this flag existed used "step > 0" to mean "on".
        quantizeEnabled = try container.decodeIfPresent(Bool.self, forKey: .quantizeEnabled) ?? (quantizeStep > 0)
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
        try container.encode(quantizeEnabled, forKey: .quantizeEnabled)
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

// A copied point, positioned relative to the earliest point in the copied
// selection — lets paste re-anchor the whole group at wherever the user
// clicks, while preserving their original spacing.
struct PointClipboardEntry {
    let deltaTime: Double
    let label: String
    let y: Double
    let segmentCurve: Double
    let segmentBulge: Double
    let segmentEnabled: Bool
    let comment: String
}
