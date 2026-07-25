import AVFoundation
import Foundation

enum AudioFileLoaderError: LocalizedError {
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected file could not be decoded."
        }
    }
}

enum AudioFileLoader {
    static func loadAudioDocument(from url: URL) throws -> AudioDocument {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioFileLoaderError.unreadableFile
        }

        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            throw AudioFileLoaderError.unreadableFile
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var monoSamples = Array(repeating: Float(0), count: frameLength)
        var peak: Float = 0

        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for frameIndex in 0..<frameLength {
                let sample = channel[frameIndex]
                monoSamples[frameIndex] += sample
                peak = max(peak, abs(sample))
            }
        }

        let divisor = max(Float(channelCount), 1)
        monoSamples = monoSamples.map { $0 / divisor }

        var sumOfSquares = 0.0
        for sample in monoSamples {
            sumOfSquares += Double(sample) * Double(sample)
        }
        let rms = frameLength > 0 ? Float((sumOfSquares / Double(frameLength)).squareRoot()) : 0

        return AudioDocument(
            url: url,
            fileName: url.lastPathComponent,
            duration: Double(frameLength) / format.sampleRate,
            sampleRate: format.sampleRate,
            samples: monoSamples,
            peak: peak,
            rms: rms
        )
    }
}
