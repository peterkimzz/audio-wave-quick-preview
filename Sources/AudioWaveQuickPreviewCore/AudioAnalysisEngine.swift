import Foundation

public struct AnalysisConfiguration: Sendable, Equatable {
    public var threshold: Float
    public var minimumSoundDuration: Double
    public var mergeSilenceDuration: Double
    public var windowDuration: Double
    public var waveformBucketCount: Int

    public init(
        threshold: Float,
        minimumSoundDuration: Double,
        mergeSilenceDuration: Double,
        windowDuration: Double = 0.01,
        waveformBucketCount: Int = 600
    ) {
        self.threshold = threshold
        self.minimumSoundDuration = minimumSoundDuration
        self.mergeSilenceDuration = mergeSilenceDuration
        self.windowDuration = windowDuration
        self.waveformBucketCount = waveformBucketCount
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

public struct AudioAnalysisResult: Sendable, Equatable {
    public let waveform: [Float]
    public let segments: [SoundSegment]

    public init(waveform: [Float], segments: [SoundSegment]) {
        self.waveform = waveform
        self.segments = segments
    }
}

public enum AudioAnalysisEngine {
    public static func analyze(
        samples: [Float],
        sampleRate: Double,
        configuration: AnalysisConfiguration
    ) -> AudioAnalysisResult {
        guard !samples.isEmpty, sampleRate > 0 else {
            return AudioAnalysisResult(waveform: [], segments: [])
        }

        let windowSize = max(1, Int((configuration.windowDuration * sampleRate).rounded(.up)))
        let windows = stride(from: 0, to: samples.count, by: windowSize).map { startIndex -> WindowEnergy in
            let endIndex = min(startIndex + windowSize, samples.count)
            let window = samples[startIndex..<endIndex]
            let energy = sqrt(window.reduce(0) { partialResult, sample in
                partialResult + (sample * sample)
            } / Float(window.count))

            return WindowEnergy(
                startTime: Double(startIndex) / sampleRate,
                endTime: Double(endIndex) / sampleRate,
                rms: energy
            )
        }

        let rawSegments = buildSegments(from: windows, threshold: configuration.threshold)
        let filteredSegments = rawSegments.filter {
            ($0.endTime - $0.startTime) >= configuration.minimumSoundDuration
        }
        let mergedSegments = merge(segments: filteredSegments, gapTolerance: configuration.mergeSilenceDuration)
        let waveform = WaveformDownsampler.downsample(
            samples: samples,
            bucketCount: configuration.waveformBucketCount
        )

        return AudioAnalysisResult(waveform: waveform, segments: mergedSegments)
    }

    private static func buildSegments(from windows: [WindowEnergy], threshold: Float) -> [SoundSegment] {
        var segments: [SoundSegment] = []
        var currentStart: Double?
        var currentEnd: Double?

        for window in windows {
            if window.rms >= threshold {
                currentStart = currentStart ?? window.startTime
                currentEnd = window.endTime
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

private struct WindowEnergy {
    let startTime: Double
    let endTime: Double
    let rms: Float
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
