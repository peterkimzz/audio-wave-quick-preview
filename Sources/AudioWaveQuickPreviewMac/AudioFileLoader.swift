import AVFoundation
import AudioWaveQuickPreviewCore
import Foundation

enum AudioFileLoaderError: LocalizedError {
    case unreadableFile
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected file could not be decoded."
        case .bufferAllocationFailed:
            return "Not enough memory to analyze this file."
        }
    }
}

/// Streams the file once, in chunks, accumulating only what the UI needs:
/// peak, RMS, and the waveform pyramid. Nothing proportional to file length is
/// retained, so a 230 MB WAV costs a few MB instead of ~1 GB.
enum AudioFileLoader {
    private static let chunkFrames: AVAudioFrameCount = 65_536

    /// Runs synchronously; call from a detached task and honor cancellation via
    /// the enclosing `Task`. `onProgress` reports 0…1 and may run off-main, at
    /// most once per whole percent — a 200 minute file has ~8800 chunks, and
    /// hopping to the main actor for each one would stall the UI it is meant to
    /// keep responsive.
    static func loadAudioDocument(
        from url: URL,
        onProgress: @Sendable (Double) -> Void = { _ in }
    ) throws -> AudioDocument {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat  // float32, deinterleaved
        let totalFrames = Int(file.length)
        let channelCount = Int(format.channelCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw AudioFileLoaderError.bufferAllocationFailed
        }

        var pyramidBuilder = WaveformPyramid.Builder(totalSampleCount: totalFrames)
        var peak: Float = 0
        var sumOfSquares = 0.0
        // Counted from what was actually read, not from `file.length`: a
        // truncated file reports more than it yields, and this drives both the
        // duration and the RMS divisor.
        var frameLength = 0
        let divisor = max(Float(channelCount), 1)
        var mono = [Float](repeating: 0, count: Int(chunkFrames))
        var reportedPercent = 0

        onProgress(0)
        // AVAudioFile throws (not returns 0) when read past EOF, so drive the
        // loop by frame position rather than a zero-length read.
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            try file.read(into: buffer, frameCount: min(chunkFrames, remaining))
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            frameLength += frames

            guard let channels = buffer.floatChannelData else {
                throw AudioFileLoaderError.unreadableFile
            }

            for frame in 0..<frames {
                mono[frame] = 0
            }
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frames {
                    let sample = samples[frame]
                    mono[frame] += sample
                    peak = max(peak, abs(sample))
                }
            }
            // Divide rather than multiply by a reciprocal: 1/3 is inexact, and the
            // published gain and loudness readouts must not drift.
            for frame in 0..<frames {
                let value = mono[frame] / divisor
                mono[frame] = value
                sumOfSquares += Double(value) * Double(value)
            }

            mono.withUnsafeBufferPointer { buffer in
                pyramidBuilder.append(UnsafeBufferPointer(rebasing: buffer[0..<frames]))
            }

            let progress = totalFrames > 0 ? Double(file.framePosition) / Double(totalFrames) : 1
            let percent = Int(progress * 100)
            if percent > reportedPercent {
                reportedPercent = percent
                onProgress(progress)
            }
        }
        onProgress(1)

        return AudioDocument(
            url: url,
            fileName: url.lastPathComponent,
            duration: Double(frameLength) / format.sampleRate,
            pyramid: pyramidBuilder.finish(),
            peak: peak,
            rms: frameLength > 0 ? Float((sumOfSquares / Double(frameLength)).squareRoot()) : 0
        )
    }
}
