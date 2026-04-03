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
        guard !samples.isEmpty else {
            return WaveformPyramid(totalSampleCount: 0, levels: [])
        }

        let normalizedMaximum = max(1, maximumBucketCount)
        let cappedRootBucketCount = min(samples.count, normalizedMaximum)
        let normalizedMinimum = min(max(1, minimumBucketCount), cappedRootBucketCount)

        var rootPeaks = WaveformDownsampler.downsample(
            samples: samples[0..<samples.count],
            bucketCount: cappedRootBucketCount
        )
        var levels = [Level(bucketCount: rootPeaks.count, peaks: rootPeaks)]

        while rootPeaks.count > normalizedMinimum {
            let nextBucketCount = max(rootPeaks.count / 2, normalizedMinimum)
            if nextBucketCount == rootPeaks.count {
                break
            }

            rootPeaks = WaveformDownsampler.downsample(
                samples: rootPeaks[0..<rootPeaks.count],
                bucketCount: nextBucketCount
            )
            levels.append(Level(bucketCount: rootPeaks.count, peaks: rootPeaks))
        }

        return WaveformPyramid(totalSampleCount: samples.count, levels: levels)
    }

    public func samples(for viewport: WaveformViewport, targetBucketCount: Int) -> [Float] {
        guard totalSampleCount > 0, !levels.isEmpty, viewport.totalDuration > 0, targetBucketCount > 0 else {
            return []
        }

        let visibleRatio = min(max(viewport.visibleDuration / viewport.totalDuration, 0), 1)
        let selectedLevel = levels.first(where: {
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
