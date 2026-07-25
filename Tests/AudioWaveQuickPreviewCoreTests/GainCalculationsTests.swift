import Foundation
import Testing

@testable import AudioWaveQuickPreviewCore

struct GainCalculationsTests {
    @Test
    func dbAndLinearScaleRoundTrip() {
        #expect(abs(GainCalculations.linearScale(forDB: 0) - 1) < 0.0001)
        #expect(abs(GainCalculations.linearScale(forDB: 6) - 1.99526) < 0.0001)
        #expect(abs(GainCalculations.linearScale(forDB: -6) - 0.501187) < 0.0001)
    }

    @Test
    func snapsToHalfDecibelGridAndClamps() {
        #expect(GainCalculations.snap(3.2) == 3)
        #expect(GainCalculations.snap(3.3) == 3.5)
        #expect(GainCalculations.snap(-100) == -24)
        #expect(GainCalculations.snap(100) == 12)
    }

    @Test
    func clippingUsesMinusPointOneDBFSCeiling() {
        #expect(GainCalculations.isClipping(originalPeak: 0.98, gainDB: 0) == false)
        #expect(GainCalculations.isClipping(originalPeak: 0.99, gainDB: 0) == true)
        #expect(GainCalculations.isClipping(originalPeak: 1.0, gainDB: 0) == true)
        #expect(GainCalculations.isClipping(originalPeak: 0.5, gainDB: 6) == true)
    }

    @Test
    func maxSafeGainFloorsToGridAndAllowsSilence() {
        #expect(GainCalculations.maxSafeGainDB(originalPeak: 0) == 12)
        #expect(GainCalculations.maxSafeGainDB(originalPeak: 0.5) == 5.5)
        #expect(GainCalculations.maxSafeGainDB(originalPeak: 1.0) <= 0)
    }

    @Test
    func outputFileNameCarriesSignedGainAndWavExtension() {
        #expect(GainCalculations.outputFileName(originalName: "song.mp3", gainDB: 3) == "song_gain+3.0dB.wav")
        #expect(GainCalculations.outputFileName(originalName: "song.flac", gainDB: -6) == "song_gain-6.0dB.wav")
        #expect(GainCalculations.outputFileName(originalName: "clip.wav", gainDB: 0) == "clip_gain+0.0dB.wav")
    }

    @Test
    func dBFSConvertsLevelsAndSilence() {
        #expect(abs(GainCalculations.dBFS(0.5) - (-6.0206)) < 0.001)
        #expect(abs(GainCalculations.dBFS(1.0)) < 0.001)
        #expect(GainCalculations.dBFS(0) == -.infinity)
    }

    @Test
    func normalizeGainHitsTargetWithHeadroom() {
        #expect(
            abs(GainCalculations.gainForTargetLoudness(currentRMS: 0.1, originalPeak: 0.2, targetDBFS: -14) - 6) < 0.001
        )
    }

    @Test
    func normalizeGainIsCappedByClippingCeiling() {
        let capped = GainCalculations.gainForTargetLoudness(currentRMS: 0.1, originalPeak: 0.5, targetDBFS: 0)
        #expect(capped == GainCalculations.maxSafeGainDB(originalPeak: 0.5))
    }

    @Test
    func normalizeGainIsZeroForSilence() {
        #expect(GainCalculations.gainForTargetLoudness(currentRMS: 0, originalPeak: 0, targetDBFS: -18) == 0)
    }

    @Test
    func loudnessTargetClampsToNegativeRange() {
        #expect(GainCalculations.clampTarget(-18) == -18)
        #expect(GainCalculations.clampTarget(5) == 0)
        #expect(GainCalculations.clampTarget(-999) == -60)
    }

    @Test
    func peakLimitedOnlyWhenTheCeilingIsWhatBlocksTheTarget() {
        // Safe gain floors to exactly 0 dB, so Normalize can't move at all.
        let atCeiling = Float(pow(10.0, -0.3 / 20.0))
        #expect(
            GainCalculations.isPeakLimited(currentRMS: 0.03, originalPeak: atCeiling, targetDBFS: -18))

        // 5.5 dB of headroom and only 0.2 dB needed: not peak-limited. The 0.5 dB
        // snap inside `gainForTargetLoudness` used to make this look limited.
        let justBelowTarget = Float(pow(10.0, -18.2 / 20.0))
        #expect(
            !GainCalculations.isPeakLimited(
                currentRMS: justBelowTarget, originalPeak: 0.5, targetDBFS: -18))

        // Target below the current loudness needs attenuation, never limited.
        #expect(!GainCalculations.isPeakLimited(currentRMS: 0.05, originalPeak: 0.99, targetDBFS: -40))

        // Silence has no measurable loudness to lift.
        #expect(!GainCalculations.isPeakLimited(currentRMS: 0, originalPeak: 0, targetDBFS: -18))
    }

    @Test
    func fineTuneOffsetSnapsAndClamps() {
        #expect(GainCalculations.snapOffset(2.2) == 2)
        #expect(GainCalculations.snapOffset(2.3) == 2.5)
        #expect(GainCalculations.snapOffset(50) == 12)
        #expect(GainCalculations.snapOffset(-50) == -12)
    }
}
