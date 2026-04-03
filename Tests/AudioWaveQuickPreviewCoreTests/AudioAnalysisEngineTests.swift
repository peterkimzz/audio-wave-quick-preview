import Foundation
import Testing
@testable import AudioWaveQuickPreviewCore

struct AudioAnalysisEngineTests {
    @Test
    func detectsSoundSegmentsWithMinimumDurationAndGapMerging() {
        let samples = Array(repeating: Float(0), count: 10)
            + Array(repeating: Float(0.8), count: 20)
            + Array(repeating: Float(0), count: 5)
            + Array(repeating: Float(0.7), count: 15)
            + Array(repeating: Float(0), count: 20)
        let configuration = AnalysisConfiguration(
            threshold: 0.2,
            minimumSoundDuration: 0.015,
            mergeSilenceDuration: 0.01,
            windowDuration: 0.005,
            waveformBucketCount: 8
        )

        let result = AudioAnalysisEngine.analyze(
            samples: samples,
            sampleRate: 1_000,
            configuration: configuration
        )

        #expect(result.segments.count == 1)
        #expect(abs(result.segments[0].startTime - 0.01) < 0.0001)
        #expect(abs(result.segments[0].endTime - 0.05) < 0.0001)
        #expect(result.waveform.count == 8)
    }

    @Test
    func filtersOutBurstsShorterThanMinimumDuration() {
        let samples = Array(repeating: Float(0), count: 10)
            + Array(repeating: Float(0.9), count: 4)
            + Array(repeating: Float(0), count: 20)

        let result = AudioAnalysisEngine.analyze(
            samples: samples,
            sampleRate: 1_000,
            configuration: AnalysisConfiguration(
                threshold: 0.2,
                minimumSoundDuration: 0.01,
                mergeSilenceDuration: 0.01,
                windowDuration: 0.002,
                waveformBucketCount: 6
            )
        )

        #expect(result.segments.isEmpty)
    }

    @Test
    func downsamplesWaveformEnvelopeToRequestedResolution() {
        let samples: [Float] = [0.1, -0.3, 0.25, -0.4, 0.9, -0.6, 0.2, -0.1]

        let buckets = WaveformDownsampler.downsample(samples: samples, bucketCount: 4)

        #expect(buckets == [0.3, 0.4, 0.9, 0.2])
    }
}
