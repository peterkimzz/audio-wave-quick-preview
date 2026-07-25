import Foundation

struct AudioDocument: Sendable {
    let url: URL
    let fileName: String
    let duration: Double
    let sampleRate: Double
    let samples: [Float]
    /// Largest absolute sample across all original channels (pre-downmix).
    /// Used to judge clipping and the maximum safe gain for export.
    let peak: Float
    /// Full-file RMS of the mono downmix — a rough perceived-loudness measure
    /// used by the Normalize action.
    let rms: Float
}
