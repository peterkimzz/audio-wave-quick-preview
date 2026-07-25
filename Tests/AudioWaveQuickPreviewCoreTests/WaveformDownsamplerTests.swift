import Foundation
import Testing

@testable import AudioWaveQuickPreviewCore

struct WaveformDownsamplerTests {
    @Test
    func downsamplesWaveformEnvelopeToRequestedResolution() {
        let samples: [Float] = [0.1, -0.3, 0.25, -0.4, 0.9, -0.6, 0.2, -0.1]

        let buckets = WaveformDownsampler.downsample(samples: samples, bucketCount: 4)

        #expect(buckets == [0.3, 0.4, 0.9, 0.2])
    }
}
