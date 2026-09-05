import AVFoundation
import AudioWaveQuickPreviewCore
import Foundation

/// Lightweight metadata for one audio file in the active folder.
///
/// Opening an `AVAudioFile` reads the format and frame count without decoding
/// every sample, so the folder can populate its lanes quickly. Peak, RMS, and
/// waveform data arrive later in `AudioDocument`.
struct AudioFileEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let duration: Double
    let sampleRate: Double

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension }

    var subtitle: String {
        AudioRowFormatter.subtitle(
            duration: duration,
            fileExtension: fileExtension,
            sampleRate: sampleRate
        )
    }

    static func read(_ url: URL) throws -> AudioFileEntry {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.fileFormat.sampleRate
        return AudioFileEntry(
            url: url,
            duration: sampleRate > 0 ? Double(file.length) / sampleRate : 0,
            sampleRate: sampleRate
        )
    }
}
