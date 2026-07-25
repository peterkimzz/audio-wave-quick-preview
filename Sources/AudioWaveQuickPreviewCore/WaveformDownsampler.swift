import Foundation

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
