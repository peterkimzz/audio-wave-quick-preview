import AudioWaveQuickPreviewCore
import Foundation

/// Everything the UI needs about a file, without the samples themselves. The raw
/// PCM is streamed once at load and discarded: the pyramid covers drawing, and
/// export re-reads from disk.
struct AudioDocument: Sendable {
    let url: URL
    let fileName: String
    let duration: Double
    /// Multi-resolution peak levels backing the waveform and minimap.
    let pyramid: WaveformPyramid
    /// Largest absolute sample across all original channels (pre-downmix).
    /// Used to judge clipping and the maximum safe gain for export.
    let peak: Float
    /// Full-file RMS of the mono downmix — a rough perceived-loudness measure
    /// used by the Normalize action.
    let rms: Float
}
