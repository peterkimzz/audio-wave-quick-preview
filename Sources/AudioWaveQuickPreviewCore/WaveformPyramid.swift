import Foundation

public struct WaveformPyramid: Sendable, Equatable {
    public struct Level: Sendable, Equatable {
        public let bucketCount: Int
        public let peaks: [Float]

        public init(bucketCount: Int, peaks: [Float]) {
            self.bucketCount = bucketCount
            self.peaks = peaks
        }
    }

    public let totalSampleCount: Int
    public let levels: [Level]

    public init(totalSampleCount: Int, levels: [Level]) {
        self.totalSampleCount = totalSampleCount
        self.levels = levels
    }

    public static func build(
        from samples: [Float],
        maximumBucketCount: Int = 131_072,
        minimumBucketCount: Int = 512
    ) -> WaveformPyramid {
        var builder = Builder(
            totalSampleCount: samples.count,
            maximumBucketCount: maximumBucketCount,
            minimumBucketCount: minimumBucketCount
        )
        samples.withUnsafeBufferPointer { builder.append($0) }
        return builder.finish()
    }

    /// Builds the pyramid from sequential chunks so callers never have to hold
    /// the whole file in memory. The total sample count is known up front (from
    /// `AVAudioFile.length`), which fixes the root bucket boundaries at the
    /// start and makes the streamed result identical to the one-shot `build`.
    public struct Builder {
        private let totalSampleCount: Int
        private let minimumBucketCount: Int
        private let bucketSize: Double
        private var rootPeaks: [Float]
        private var bucketIndex = 0
        private var bucketEnd: Int
        private var bucketPeak: Float = 0
        private var consumed = 0

        public init(
            totalSampleCount: Int,
            maximumBucketCount: Int = 131_072,
            minimumBucketCount: Int = 512
        ) {
            let count = max(totalSampleCount, 0)
            let rootBucketCount = min(count, max(1, maximumBucketCount))
            self.totalSampleCount = count
            self.minimumBucketCount = min(max(1, minimumBucketCount), max(rootBucketCount, 1))
            bucketSize = rootBucketCount > 0 ? Double(count) / Double(rootBucketCount) : 1
            rootPeaks = []
            rootPeaks.reserveCapacity(rootBucketCount)
            // Same boundary arithmetic as WaveformDownsampler.downsample, so the
            // buckets line up sample-for-sample with the one-shot path.
            bucketEnd = rootBucketCount > 0 ? max(1, Int(bucketSize.rounded(.down))) : 0
        }

        public mutating func append(_ chunk: ArraySlice<Float>) {
            chunk.withUnsafeBufferPointer { append($0) }
        }

        /// Takes a concrete pointer rather than a generic `Sequence`: iterating a
        /// slice through the generic constraint costs ~28× more on a 200 minute
        /// file, because the per-element loop cannot be specialized across module
        /// boundaries.
        public mutating func append(_ chunk: UnsafeBufferPointer<Float>) {
            for sample in chunk {
                guard consumed < totalSampleCount else { return }

                bucketPeak = max(bucketPeak, abs(sample))
                consumed += 1

                if consumed >= bucketEnd {
                    rootPeaks.append(bucketPeak)
                    bucketPeak = 0
                    bucketIndex += 1
                    let nextEnd = Int((Double(bucketIndex + 1) * bucketSize).rounded(.down))
                    bucketEnd = min(max(nextEnd, consumed + 1), totalSampleCount)
                }
            }
        }

        public consuming func finish() -> WaveformPyramid {
            guard totalSampleCount > 0, !rootPeaks.isEmpty else {
                return WaveformPyramid(totalSampleCount: 0, levels: [])
            }

            var peaks = rootPeaks
            var levels = [Level(bucketCount: peaks.count, peaks: peaks)]

            while peaks.count > minimumBucketCount {
                let nextBucketCount = max(peaks.count / 2, minimumBucketCount)
                if nextBucketCount == peaks.count {
                    break
                }

                peaks = WaveformDownsampler.downsample(
                    samples: peaks[0..<peaks.count],
                    bucketCount: nextBucketCount
                )
                levels.append(Level(bucketCount: peaks.count, peaks: peaks))
            }

            return WaveformPyramid(totalSampleCount: totalSampleCount, levels: levels)
        }
    }

    public func samples(for viewport: WaveformViewport, targetBucketCount: Int) -> [Float] {
        guard totalSampleCount > 0, !levels.isEmpty, viewport.totalDuration > 0, targetBucketCount > 0 else {
            return []
        }

        let visibleRatio = min(max(viewport.visibleDuration / viewport.totalDuration, 0), 1)
        let selectedLevel =
            levels.first(where: {
                Double($0.bucketCount) * visibleRatio <= Double(targetBucketCount * 4)
            }) ?? levels.last ?? levels[0]

        let visibleStartRatio = min(max(viewport.visibleStartTime / viewport.totalDuration, 0), 1)
        let visibleEndTime = min(viewport.visibleStartTime + viewport.visibleDuration, viewport.totalDuration)
        let visibleEndRatio = min(max(visibleEndTime / viewport.totalDuration, visibleStartRatio), 1)

        let startIndex = min(
            max(Int((Double(selectedLevel.bucketCount) * visibleStartRatio).rounded(.down)), 0),
            max(selectedLevel.peaks.count - 1, 0)
        )
        let endIndex = min(
            max(Int((Double(selectedLevel.bucketCount) * visibleEndRatio).rounded(.up)), startIndex + 1),
            selectedLevel.peaks.count
        )

        return WaveformDownsampler.downsample(
            samples: selectedLevel.peaks[startIndex..<endIndex],
            bucketCount: min(targetBucketCount, max(endIndex - startIndex, 1))
        )
    }
}
