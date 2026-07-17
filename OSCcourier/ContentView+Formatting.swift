import SwiftUI
import AppKit

extension ContentView {

    func formattedDuration(_ seconds: Double) -> String {
        let totalCentiseconds = Int((seconds * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let secs = (totalCentiseconds / 100) % 60
        let centis = totalCentiseconds % 100
        return String(format: "%02d:%02d.%02d", minutes, secs, centis)
    }

    func parseDuration(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
            return minutes * 60 + seconds
        } else if parts.count == 1, let seconds = Double(parts[0]) {
            return seconds
        }
        return nil
    }

    func formattedTick(_ seconds: Double, labelInterval: Double) -> String {
        let totalCentiseconds = Int((seconds * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let secs = (totalCentiseconds / 100) % 60
        let centis = totalCentiseconds % 100
        if labelInterval < 1 {
            return String(format: "%02d:%02d.%02d", minutes, secs, centis)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    func formattedPosition(_ seconds: Double) -> String {
        let totalCentiseconds = Int((seconds * 100).rounded())
        let minutes = totalCentiseconds / 6000
        let secs = (totalCentiseconds / 100) % 60
        let centis = totalCentiseconds % 100
        return String(format: "%02d:%02d:%02d", minutes, secs, centis)
    }

}
