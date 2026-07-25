import Foundation

public struct AnalysisConfiguration: Sendable, Equatable {
    public var threshold: Float
    public var minimumSoundDuration: Double
    public var mergeSilenceDuration: Double

    public init(
        threshold: Float,
        minimumSoundDuration: Double,
        mergeSilenceDuration: Double
    ) {
        self.threshold = threshold
        self.minimumSoundDuration = minimumSoundDuration
        self.mergeSilenceDuration = mergeSilenceDuration
    }
}

public struct SoundSegment: Sendable, Equatable {
    public let startTime: Double
    public let endTime: Double

    public init(startTime: Double, endTime: Double) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

public enum AudioAnalysisEngine {
    public static func analyze(
        envelope: RMSEnvelope,
        configuration: AnalysisConfiguration
    ) -> [SoundSegment] {
        guard !envelope.values.isEmpty, envelope.sampleRate > 0 else { return [] }

        let rawSegments = buildSegments(from: envelope, threshold: configuration.threshold)
        let filteredSegments = rawSegments.filter {
            ($0.endTime - $0.startTime) >= configuration.minimumSoundDuration
        }

        return merge(segments: filteredSegments, gapTolerance: configuration.mergeSilenceDuration)
    }

    /// Walks the envelope in place. Materialising a per-window array here would
    /// reintroduce the file-length-proportional allocation this module just shed
    /// — ~1.2M entries for a 200 minute file, rebuilt on every sensitivity
    /// slider tick.
    private static func buildSegments(from envelope: RMSEnvelope, threshold: Float) -> [SoundSegment] {
        var segments: [SoundSegment] = []
        var currentStart: Double?
        var currentEnd: Double?

        for (index, rms) in envelope.values.enumerated() {
            if rms >= threshold {
                currentStart = currentStart ?? envelope.startTime(ofWindow: index)
                currentEnd = envelope.endTime(ofWindow: index)
            } else if let start = currentStart, let end = currentEnd {
                segments.append(SoundSegment(startTime: start, endTime: end))
                currentStart = nil
                currentEnd = nil
            }
        }

        if let start = currentStart, let end = currentEnd {
            segments.append(SoundSegment(startTime: start, endTime: end))
        }

        return segments
    }

    private static func merge(segments: [SoundSegment], gapTolerance: Double) -> [SoundSegment] {
        guard var current = segments.first else { return [] }
        var merged: [SoundSegment] = []

        for segment in segments.dropFirst() {
            if segment.startTime - current.endTime <= gapTolerance {
                current = SoundSegment(startTime: current.startTime, endTime: segment.endTime)
            } else {
                merged.append(current)
                current = segment
            }
        }

        merged.append(current)
        return merged
    }
}

public enum WaveformDownsampler {
    public static func downsample<C>(samples: C, bucketCount: Int) -> [Float]
    where C: RandomAccessCollection, C.Element == Float {
        guard !samples.isEmpty, bucketCount > 0 else { return [] }

        if bucketCount >= samples.count {
            return samples.map { abs($0) }
        }

        let bucketSize = Double(samples.count) / Double(bucketCount)

        return (0..<bucketCount).compactMap { bucketIndex in
            let start = Int((Double(bucketIndex) * bucketSize).rounded(.down))
            let end = Int((Double(bucketIndex + 1) * bucketSize).rounded(.down))
            let clampedEnd = max(start + 1, min(end, samples.count))
            let lowerBound = samples.index(samples.startIndex, offsetBy: start)
            let upperBound = samples.index(samples.startIndex, offsetBy: clampedEnd)
            let slice = samples[lowerBound..<upperBound]
            var peak: Float = 0
            for sample in slice {
                peak = max(peak, abs(sample))
            }

            return peak
        }
    }
}
