import AudioWaveQuickPreviewCore
import AVFoundation
import Foundation

enum AudioExportError: LocalizedError {
    case sameAsSource
    case unreadableSource
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .sameAsSource:
            return "Choose a different file so the original is preserved."
        case .unreadableSource:
            return "The original file could not be read for export."
        case .bufferAllocationFailed:
            return "Not enough memory to export this file."
        }
    }
}

/// Writes a gain-adjusted copy of the original as signed 16-bit PCM WAV,
/// preserving sample rate and channel count. Non-destructive: writes to a temp
/// file in the destination folder and only swaps it in on success.
///
/// Gain and clamping are applied in the float processing buffer; AVAudioFile
/// performs the float→int16 conversion for the on-disk format.
enum AudioExportService {
    private static let chunkFrames: AVAudioFrameCount = 65_536

    /// Runs synchronously; call from a detached task and honor cancellation via
    /// the enclosing `Task`. `onProgress` reports 0…1 and may run off-main.
    static func export(
        source: URL,
        destination: URL,
        gainDB: Double,
        onProgress: @Sendable (Double) -> Void
    ) throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw AudioExportError.sameAsSource
        }

        let input: AVAudioFile
        do {
            input = try AVAudioFile(forReading: source)
        } catch {
            throw AudioExportError.unreadableSource
        }

        let format = input.processingFormat          // float32, deinterleaved
        let channelCount = Int(format.channelCount)
        let scale = Float(GainCalculations.linearScale(forDB: gainDB))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let fileManager = FileManager.default
        let tempURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).wav")

        do {
            // Inner scope so the output file deinits (flush + close) before the swap.
            do {
                let output = try AVAudioFile(forWriting: tempURL, settings: settings)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
                    throw AudioExportError.bufferAllocationFailed
                }

                let total = input.length
                onProgress(0)
                // AVAudioFile throws (not returns 0) when read past EOF, so drive
                // the loop by frame position rather than a zero-length read.
                while input.framePosition < total {
                    try Task.checkCancellation()
                    let remaining = AVAudioFrameCount(total - input.framePosition)
                    try input.read(into: buffer, frameCount: min(chunkFrames, remaining))
                    let frames = Int(buffer.frameLength)
                    if frames == 0 { break }

                    guard let channels = buffer.floatChannelData else {
                        throw AudioExportError.unreadableSource
                    }
                    for channel in 0..<channelCount {
                        let samples = channels[channel]
                        for frame in 0..<frames {
                            samples[frame] = max(-1, min(1, samples[frame] * scale))
                        }
                    }

                    try output.write(from: buffer)
                    onProgress(total > 0 ? Double(input.framePosition) / Double(total) : 1)
                }
                onProgress(1)
            }
            try commit(tempURL: tempURL, to: destination, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    private static func commit(tempURL: URL, to destination: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: destination)
        }
    }
}
