import Combine
import SwiftUI

/// Owns the temporary text-field/toggle state for the track amplitude
/// range & quantize-step editor popup, edited before being committed
/// back onto the track model.
final class TrackAmplitudeEditState: ObservableObject {
    @Published var tempMinAmplitude: String = "0"
    @Published var tempMaxAmplitude: String = "1"
    @Published var tempIsGate: Bool = false
    @Published var tempQuantizeStep: String = "0"
    @Published var tempQuantizeEnabled: Bool = false
}
