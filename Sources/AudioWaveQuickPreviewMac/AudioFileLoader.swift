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

        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for frameIndex in 0..<frameLength {
                monoSamples[frameIndex] += channel[frameIndex]
            }
        }

        let divisor = max(Float(channelCount), 1)
        monoSamples = monoSamples.map { $0 / divisor }

        return AudioDocument(
            url: url,
            fileName: url.lastPathComponent,
            duration: Double(frameLength) / format.sampleRate,
            sampleRate: format.sampleRate,
            samples: monoSamples
        )
    }
}
