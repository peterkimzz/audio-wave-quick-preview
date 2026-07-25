import Foundation
import Testing

@testable import AudioWaveQuickPreviewCore

/// The loader streams the file in chunks instead of holding every sample, so the
/// streamed pyramid and envelope must match what a single full-array pass
/// produces — otherwise the gain and loudness readouts drift silently.
///
/// Both references below are the original full-array expressions, kept here on
/// purpose: `WaveformDownsampler.downsample` is untouched by the streaming work,
/// and the envelope reference is the window loop `AudioAnalysisEngine` used to run.
struct StreamingEquivalenceTests {
    /// Chunk sizes deliberately unaligned with bucket and window boundaries.
    private static let chunkSizes = [1, 7, 1_000, 65_536]

    @Test(arguments: [4_096, 131_072, 300_000])
    func streamedPyramidMatchesFullArrayBuild(sampleCount: Int) {
        let samples = Self.makeSamples(count: sampleCount)
        let reference = WaveformDownsampler.downsample(
            samples: samples,
            bucketCount: min(samples.count, 131_072)
        )

        for chunkSize in Self.chunkSizes {
            var builder = WaveformPyramid.Builder(totalSampleCount: samples.count)
            for chunk in Self.chunks(of: samples, size: chunkSize) {
                builder.append(chunk)
            }
            let pyramid = builder.finish()

            #expect(pyramid.totalSampleCount == samples.count)
            #expect(pyramid.levels.first?.peaks == reference, "chunk size \(chunkSize)")
            // Coarser levels derive from the root, so matching roots is enough —
            // but assert the shape so a regression in finish() is still caught.
            #expect(pyramid.levels.count == WaveformPyramid.build(from: samples).levels.count)
        }
    }

    @Test(arguments: [4_096, 131_072, 300_000])
    func streamedEnvelopeMatchesFullArrayScan(sampleCount: Int) {
        let sampleRate = 48_000.0
        let samples = Self.makeSamples(count: sampleCount)
        let reference = Self.referenceEnvelope(samples: samples, sampleRate: sampleRate)

        for chunkSize in Self.chunkSizes {
            var builder = RMSEnvelope.Builder(sampleRate: sampleRate)
            for chunk in Self.chunks(of: samples, size: chunkSize) {
                builder.append(chunk)
            }
            let envelope = builder.finish()

            #expect(envelope.values == reference, "chunk size \(chunkSize)")
            #expect(envelope.totalSampleCount == samples.count)
        }
    }

    @Test
    func envelopeWindowTimesMatchSampleIndexArithmetic() {
        let sampleRate = 44_100.0
        let samples = Self.makeSamples(count: 100_000)
        let envelope = RMSEnvelope.build(samples: samples, sampleRate: sampleRate)
        let windowSize = envelope.hopSize

        for index in envelope.values.indices {
            let startIndex = index * windowSize
            let endIndex = min(startIndex + windowSize, samples.count)
            #expect(envelope.startTime(ofWindow: index) == Double(startIndex) / sampleRate)
            #expect(envelope.endTime(ofWindow: index) == Double(endIndex) / sampleRate)
        }
    }

    @Test
    func emptyInputProducesEmptyResults() {
        let empty = [Float]()[...]

        var pyramid = WaveformPyramid.Builder(totalSampleCount: 0)
        pyramid.append(empty)
        #expect(pyramid.finish().levels.isEmpty)

        var envelope = RMSEnvelope.Builder(sampleRate: 48_000)
        envelope.append(empty)
        #expect(envelope.finish().values.isEmpty)
    }

    // MARK: - Fixtures

    /// Deterministic signal with transients, so bucket peaks land inside buckets
    /// rather than on their edges.
    private static func makeSamples(count: Int) -> [Float] {
        (0..<count).map { index in
            let phase = Double(index) * 0.01
            let base = sin(phase) * 0.4
            let transient = index % 997 == 0 ? 0.55 : 0
            return Float(base + transient)
        }
    }

    private static func chunks(of samples: [Float], size: Int) -> [ArraySlice<Float>] {
        stride(from: 0, to: samples.count, by: size).map {
            samples[$0..<min($0 + size, samples.count)]
        }
    }

    private static func referenceEnvelope(samples: [Float], sampleRate: Double) -> [Float] {
        let windowSize = max(1, Int((RMSEnvelope.defaultWindowDuration * sampleRate).rounded(.up)))
        return stride(from: 0, to: samples.count, by: windowSize).map { startIndex in
            let window = samples[startIndex..<min(startIndex + windowSize, samples.count)]
            return (window.reduce(0) { $0 + ($1 * $1) } / Float(window.count)).squareRoot()
        }
    }
}
