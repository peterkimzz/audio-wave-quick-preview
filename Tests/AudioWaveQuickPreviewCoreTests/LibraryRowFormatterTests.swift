import Foundation
import Testing

@testable import AudioWaveQuickPreviewCore

struct LibraryRowFormatterTests {
    @Test
    func shortTimeKeepsTenthsForSubSecondClips() {
        #expect(LibraryRowFormatter.shortTime(0.2) == "0:00.2")
        #expect(LibraryRowFormatter.shortTime(1.24) == "0:01.2")
        #expect(LibraryRowFormatter.shortTime(8) == "0:08.0")
        #expect(LibraryRowFormatter.shortTime(63.5) == "1:03.5")
    }

    @Test
    func shortTimeCarriesInsteadOfPrintingSixtySeconds() {
        #expect(LibraryRowFormatter.shortTime(59.98) == "1:00.0")
        #expect(LibraryRowFormatter.shortTime(-1) == "0:00.0")
    }

    @Test
    func shortSampleRateDropsTrailingZero() {
        #expect(LibraryRowFormatter.shortSampleRate(48000) == "48k")
        #expect(LibraryRowFormatter.shortSampleRate(44100) == "44.1k")
        #expect(LibraryRowFormatter.shortSampleRate(96000) == "96k")
        #expect(LibraryRowFormatter.shortSampleRate(0) == "—")
    }

    @Test
    func subtitleJoinsWithMiddleDots() {
        #expect(
            LibraryRowFormatter.subtitle(duration: 1.24, fileExtension: "WAV", sampleRate: 48000)
                == "0:01.2 · wav · 48k")
    }
}
