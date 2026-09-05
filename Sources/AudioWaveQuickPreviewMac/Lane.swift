import AudioWaveQuickPreviewCore
import Foundation

/// One audio file loaded from the active folder. Everything numeric delegates to
/// `GainCalculations` — a lane adds no new math, only per-file state.
struct Lane: Identifiable {
    /// Zoom-in limit as a fraction of the file. A fixed 5 s floor (what the
    /// single-file editor used) makes a 0.2 s effect unzoomable, so the limit
    /// scales with the clip and always leaves room for 4× zoom.
    private static let maxZoomFactor = 4.0

    let entry: AudioFileEntry
    /// Nil until the streaming analysis finishes.
    var document: AudioDocument?
    /// Analysis progress, or nil when nothing is in flight. `WaveformView` renders it.
    var loadProgress: Double?
    /// Base gain written by Apply.
    var normalizeBaseDB: Double = 0
    /// Per-lane trim from the ± steppers, layered on top of the base.
    var offsetDB: Double = 0
    var viewport: WaveformViewport?
    /// Bars for the lane strip, refreshed when the viewport moves.
    var waveform: [Float] = []
    /// Full-file bars for the minimap, computed once on adopt.
    var minimapWaveform: [Float] = []

    var id: URL { entry.url }
    var url: URL { entry.url }
    var name: String { entry.name }
    var duration: Double { document?.duration ?? entry.duration }

    static func minimumVisibleDuration(for duration: Double) -> Double {
        max(duration / maxZoomFactor, 0.001)
    }

    var gainDB: Double { GainCalculations.snap(normalizeBaseDB + offsetDB) }

    /// One stepper press. The only place that knows what a press produces.
    ///
    /// The offset is clamped twice: to its own ±12 dB range, and again so that
    /// `base + offset` stays inside the total gain range. Without the second
    /// clamp a lane normalized to the +12 dB ceiling banks offset the readout
    /// cannot show — press `+` five times and `−` five times does nothing, since
    /// the hidden surplus has to unwind before the total moves.
    func nudged(by delta: Double) -> Lane {
        var next = self
        let candidate = GainCalculations.snapOffset(offsetDB + delta)
        let lowest = GainCalculations.minGainDB - normalizeBaseDB
        let highest = GainCalculations.maxGainDB - normalizeBaseDB
        next.offsetDB = min(max(candidate, lowest), highest)
        return next
    }

    /// False once a press would change nothing, so the stepper can be disabled
    /// instead of looking live while doing nothing. A lane normalized into the
    /// +12 dB ceiling hits this immediately.
    func canNudge(by delta: Double) -> Bool {
        nudged(by: delta).gainDB != gainDB
    }

    var waveformGainScale: Float {
        Float(GainCalculations.linearScale(forDB: gainDB))
    }

    var estimatedPeakDBFS: Double {
        GainCalculations.estimatedPeakDBFS(originalPeak: document?.peak ?? 0, gainDB: gainDB)
    }

    var estimatedLoudnessDBFS: Double {
        guard let document else { return -.infinity }
        return GainCalculations.dBFS(document.rms) + gainDB
    }

    var isClipping: Bool {
        // Attenuation cannot introduce clipping, so an already-hot source stays
        // exportable at or below unity.
        guard let document, gainDB > 0 else { return false }
        return GainCalculations.isClipping(originalPeak: document.peak, gainDB: gainDB)
    }
}
