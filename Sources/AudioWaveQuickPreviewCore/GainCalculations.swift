import Foundation

/// Pure dB/linear gain math for the manual-gain WAV export feature.
///
/// All values are file-wide: a single gain applied uniformly. Sample data stays
/// `Float` (matching the decoder), while dB math runs in `Double` for precision.
public enum GainCalculations {
    public static let minGainDB = -24.0
    public static let maxGainDB = 12.0
    public static let stepDB = 0.5

    /// Highest peak allowed in the output, `-0.1 dBFS`. Anything above clips.
    public static let maxOutputPeak = pow(10.0, -0.1 / 20.0)

    /// Default loudness target for the Normalize action. Arbitrary; user-editable.
    public static let defaultTargetLoudnessDBFS = -18.0

    /// Sensible bounds for the loudness target. Loudness is always below the
    /// `0 dBFS` digital ceiling, so the target is negative-only.
    public static let minTargetLoudnessDBFS = -60.0
    public static let maxTargetLoudnessDBFS = 0.0

    /// Clamps a user-entered loudness target to `[min, max]TargetLoudnessDBFS`.
    public static func clampTarget(_ dbfs: Double) -> Double {
        min(maxTargetLoudnessDBFS, max(minTargetLoudnessDBFS, dbfs))
    }

    /// Range of the manual fine-tune offset added on top of the Normalize base.
    public static let minOffsetDB = -12.0
    public static let maxOffsetDB = 12.0

    /// Snaps a fine-tune offset to the 0.5 dB grid and clamps to its range.
    public static func snapOffset(_ db: Double) -> Double {
        let snapped = (db / stepDB).rounded() * stepDB
        return min(maxOffsetDB, max(minOffsetDB, snapped))
    }

    public static func linearScale(forDB db: Double) -> Double {
        pow(10.0, db / 20.0)
    }

    /// Snaps an arbitrary dB value to the 0.5 dB grid and clamps to range.
    public static func snap(_ db: Double) -> Double {
        let snapped = (db / stepDB).rounded() * stepDB
        return min(max(snapped, minGainDB), maxGainDB)
    }

    /// Estimated output peak in dBFS. Returns `-.infinity` for pure silence.
    public static func estimatedPeakDBFS(originalPeak: Float, gainDB: Double) -> Double {
        let peak = Double(originalPeak) * linearScale(forDB: gainDB)
        guard peak > 0 else { return -.infinity }
        return 20.0 * log10(peak)
    }

    public static func isClipping(originalPeak: Float, gainDB: Double) -> Bool {
        Double(originalPeak) * linearScale(forDB: gainDB) > maxOutputPeak
    }

    /// Largest gain (snapped down to the 0.5 dB grid) that keeps the output at or
    /// below `-0.1 dBFS`. Silence never clips, so it returns `maxGainDB`.
    public static func maxSafeGainDB(originalPeak: Float) -> Double {
        guard originalPeak > 0 else { return maxGainDB }
        let rawDB = 20.0 * log10(maxOutputPeak / Double(originalPeak))
        // Floor to the grid so the returned value is always safe to apply.
        let floored = (rawDB / stepDB).rounded(.down) * stepDB
        return min(max(floored, minGainDB), maxGainDB)
    }

    /// Level (peak or RMS) as dBFS. Returns `-.infinity` for silence.
    public static func dBFS(_ level: Float) -> Double {
        guard level > 0 else { return -.infinity }
        return 20.0 * log10(Double(level))
    }

    /// Gain (snapped, clamped) that brings the current RMS to `targetDBFS`,
    /// but never so much that the peak would exceed the clipping ceiling.
    /// Returns 0 for silence (nothing to normalize).
    public static func gainForTargetLoudness(
        currentRMS: Float,
        originalPeak: Float,
        targetDBFS: Double
    ) -> Double {
        guard currentRMS > 0 else { return 0 }
        let needed = targetDBFS - dBFS(currentRMS)
        let capped = min(needed, maxSafeGainDB(originalPeak: originalPeak))
        return snap(capped)
    }

    /// True when the clipping ceiling — not the user — is what keeps `currentRMS`
    /// from reaching `targetDBFS`.
    ///
    /// Compares the gain actually *needed* against the largest safe gain. Judging
    /// it from `gainForTargetLoudness` instead would misfire: that result is
    /// snapped to the 0.5 dB grid, so it can land up to 0.25 dB below the target
    /// even with plenty of headroom, which reads as a peak limit that isn't there.
    public static func isPeakLimited(
        currentRMS: Float,
        originalPeak: Float,
        targetDBFS: Double
    ) -> Bool {
        guard currentRMS > 0 else { return false }
        let needed = targetDBFS - dBFS(currentRMS)
        return needed > maxSafeGainDB(originalPeak: originalPeak) + 0.05
    }

    /// `song.mp3` + `+3.0 dB` → `song_gain+3.0dB.wav`. Sign is always shown.
    public static func outputFileName(originalName: String, gainDB: Double) -> String {
        let base = (originalName as NSString).deletingPathExtension
        return base + "_gain" + String(format: "%+.1f", gainDB) + "dB.wav"
    }
}
