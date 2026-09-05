import Foundation
import Testing

@testable import AudioWaveQuickPreviewCore

struct AudioRowFormatterTests {
    @Test
    func shortTimeKeepsTenthsForSubSecondClips() {
        #expect(AudioRowFormatter.shortTime(0.2) == "0:00.2")
        #expect(AudioRowFormatter.shortTime(1.24) == "0:01.2")
        #expect(AudioRowFormatter.shortTime(8) == "0:08.0")
        #expect(AudioRowFormatter.shortTime(63.5) == "1:03.5")
    }

    @Test
    func shortTimeCarriesInsteadOfPrintingSixtySeconds() {
        #expect(AudioRowFormatter.shortTime(59.98) == "1:00.0")
        #expect(AudioRowFormatter.shortTime(-1) == "0:00.0")
    }

    @Test
    func shortSampleRateDropsTrailingZero() {
        #expect(AudioRowFormatter.shortSampleRate(48000) == "48k")
        #expect(AudioRowFormatter.shortSampleRate(44100) == "44.1k")
        #expect(AudioRowFormatter.shortSampleRate(96000) == "96k")
        #expect(AudioRowFormatter.shortSampleRate(0) == "—")
    }

    @Test
    func subtitleJoinsWithMiddleDots() {
        #expect(
            AudioRowFormatter.subtitle(duration: 1.24, fileExtension: "WAV", sampleRate: 48000)
                == "0:01.2 · wav · 48k")
    }
}
