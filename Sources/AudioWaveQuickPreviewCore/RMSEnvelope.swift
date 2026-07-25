import Foundation

/// Per-window RMS of a file, at the resolution segment detection needs.
///
/// This replaces holding the raw samples: a 200 minute file is ~1.2M windows
/// (about 5 MB) instead of 240 MB, and re-running detection when the sensitivity
/// sliders move only walks the envelope.
public struct RMSEnvelope: Sendable, Equatable {
    public let values: [Float]
    /// Samples per window. Also the hop — windows do not overlap.
    public let hopSize: Int
    public let sampleRate: Double
    public let totalSampleCount: Int

    public init(values: [Float], hopSize: Int, sampleRate: Double, totalSampleCount: Int) {
        self.values = values
        self.hopSize = max(1, hopSize)
        self.sampleRate = sampleRate
        self.totalSampleCount = totalSampleCount
    }

    public static let defaultWindowDuration = 0.01

    public static func hopSize(sampleRate: Double, windowDuration: Double = defaultWindowDuration) -> Int {
        max(1, Int((windowDuration * sampleRate).rounded(.up)))
    }

    /// Start time of window `index`, derived from the sample index so the result
    /// matches a full-resolution scan bit for bit.
    public func startTime(ofWindow index: Int) -> Double {
        Double(index * hopSize) / sampleRate
    }

    public func endTime(ofWindow index: Int) -> Double {
        Double(min((index + 1) * hopSize, totalSampleCount)) / sampleRate
    }

    public static func build(
        samples: [Float],
        sampleRate: Double,
        windowDuration: Double = defaultWindowDuration
    ) -> RMSEnvelope {
        var builder = Builder(sampleRate: sampleRate, windowDuration: windowDuration)
        samples.withUnsafeBufferPointer { builder.append($0) }
        return builder.finish()
    }

    /// Accumulates the envelope from sequential chunks. Squared samples are summed
    /// in `Float`, matching what a single full-array pass produces.
    public struct Builder {
        public let hopSize: Int
        private let sampleRate: Double
        private var values: [Float] = []
        private var windowSum: Float = 0
        private var windowCount = 0
        private var totalSampleCount = 0

        public init(sampleRate: Double, windowDuration: Double = RMSEnvelope.defaultWindowDuration) {
            self.sampleRate = sampleRate
            hopSize = RMSEnvelope.hopSize(sampleRate: sampleRate, windowDuration: windowDuration)
        }

        public mutating func append(_ chunk: ArraySlice<Float>) {
            chunk.withUnsafeBufferPointer { append($0) }
        }

        /// Concrete pointer for the same reason as `WaveformPyramid.Builder.append`:
        /// a generic `Sequence` loop here dominated the whole load.
        public mutating func append(_ chunk: UnsafeBufferPointer<Float>) {
            for sample in chunk {
                windowSum += sample * sample
                windowCount += 1
                totalSampleCount += 1

                if windowCount == hopSize {
                    values.append(flushWindow())
                }
            }
        }

        public consuming func finish() -> RMSEnvelope {
            // The trailing partial window divides by its real length, as a
            // full-array scan does.
            if windowCount > 0 {
                values.append(flushWindow())
            }

            return RMSEnvelope(
                values: values,
                hopSize: hopSize,
                sampleRate: sampleRate,
                totalSampleCount: totalSampleCount
            )
        }

        private mutating func flushWindow() -> Float {
            let rms = (windowSum / Float(windowCount)).squareRoot()
            windowSum = 0
            windowCount = 0
            return rms
        }
    }
}
