import Foundation

enum TimeFormatter {
    static func string(from duration: Double) -> String {
        let totalSeconds = max(Int(duration.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
