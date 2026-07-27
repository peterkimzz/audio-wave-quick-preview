import Foundation

/// Text for a file-inspector row: `door-close.wav` / `0:01.2 · wav · 48k`.
public enum LibraryRowFormatter {
    /// `m:ss.t`. Sound effects are routinely under a second, where the
    /// transport's `mm:ss` collapses every one of them to `00:00`.
    public static func shortTime(_ duration: Double) -> String {
        let clamped = max(duration, 0)
        // Round once, in tenths, so 59.98 s carries into 1:00.0 instead of
        // printing 0:60.0.
        let tenths = (clamped * 10).rounded()
        let minutes = Int(tenths / 600)
        let seconds = (tenths - Double(minutes * 600)) / 10
        return String(format: "%d:%04.1f", minutes, seconds)
    }

    /// `48000` → `48k`, `44100` → `44.1k`. Trailing `.0` is dropped.
    public static func shortSampleRate(_ sampleRate: Double) -> String {
        guard sampleRate > 0 else { return "—" }
        let kilohertz = sampleRate / 1000
        let rounded = (kilohertz * 10).rounded() / 10
        let format = rounded == rounded.rounded() ? "%.0fk" : "%.1fk"
        return String(format: format, rounded)
    }

    public static func subtitle(duration: Double, fileExtension: String, sampleRate: Double) -> String {
        [shortTime(duration), fileExtension.lowercased(), shortSampleRate(sampleRate)]
            .joined(separator: " · ")
    }
}
