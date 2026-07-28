#if DEBUG
    import AVFoundation
    import AppKit
    import AudioWaveQuickPreviewCore
    import Combine
    import SwiftUI

    /// Headless self-check for the paths that write files or cross actors, which
    /// the Core test target cannot reach: batch export, per-lane analysis and
    /// normalize, the library round-trip through UserDefaults.
    ///
    /// The Mac target has no test target and needs a real run loop for the
    /// detached analysis tasks, so this runs as the app:
    ///
    ///     AWQP_SELF_CHECK=/path/to/a/dir/of/wavs swift run AudioWaveQuickPreviewMac
    ///
    /// Exits non-zero on the first failure.
    @MainActor
    enum DebugSelfCheck {
        static func runIfRequested(model: AppModel) {
            guard let fixtureDir = ProcessInfo.processInfo.environment["AWQP_SELF_CHECK"] else { return }
            Task { @MainActor in
                do {
                    try await check(model: model, fixtureDir: URL(fileURLWithPath: fixtureDir))
                    print("All self-checks passed")
                    NSApp.terminate(nil)
                } catch {
                    fputs("SELF-CHECK FAILED: \(error)\n", stderr)
                    exit(1)
                }
            }
        }

        private struct Failure: Error, CustomStringConvertible {
            let description: String
        }

        private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
            guard condition else { throw Failure(description: message()) }
        }

        private static func waitForLanes(_ model: AppModel) async throws {
            for _ in 0..<400 {
                if !model.lanes.isEmpty, model.lanes.allSatisfy({ $0.document != nil }) { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw Failure(description: "lanes never finished analyzing")
        }

        private static func peak(of url: URL) throws -> Float {
            let file = try AVAudioFile(forReading: url)
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length)
                )
            else {
                throw Failure(description: "could not allocate a read buffer for \(url.lastPathComponent)")
            }
            try file.read(into: buffer)
            var highest: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = buffer.floatChannelData![channel]
                for frame in 0..<Int(buffer.frameLength) {
                    highest = max(highest, abs(samples[frame]))
                }
            }
            return highest
        }

        // swiftlint:disable:next function_body_length
        private static func check(model: AppModel, fixtureDir: URL) async throws {
            let fixtures = try FileManager.default
                .contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil)
                .filter { SupportedTypes.isSupported($0) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            try expect(fixtures.count >= 2, "need at least 2 fixture files, found \(fixtures.count)")

            // --- restore merges with whatever arrived first ---
            // The restore read is slow enough that a launch argument or a Finder
            // open usually wins the race; assigning instead of merging dropped it.
            let sample = fixtures.map { LibraryEntry(url: $0, duration: 1, sampleRate: 48000) }
            let older = Array(sample.prefix(1))
            let newer = Array(sample.dropFirst())
            try expect(
                LibraryEntry.merged(restored: older, with: []).map(\.url) == older.map(\.url),
                "merging into an empty library should be the restored list verbatim")
            try expect(
                LibraryEntry.merged(restored: older, with: newer).map(\.url)
                    == (older + newer).map(\.url),
                "files added before the restore landed must survive, appended after it")
            try expect(
                LibraryEntry.merged(restored: sample, with: newer).map(\.url) == sample.map(\.url),
                "a file present in both lists must not be duplicated")

            // --- library ---
            model.add(urls: fixtures)
            try expect(
                model.entries.count == fixtures.count,
                "expected \(fixtures.count) entries, got \(model.entries.count)")
            try expect(model.checked.count == fixtures.count, "added files should arrive checked")
            model.add(urls: fixtures)
            try expect(model.entries.count == fixtures.count, "re-adding the same files must not duplicate rows")
            try expect(
                LibraryStore.loadPaths().count == fixtures.count,
                "library did not persist to UserDefaults")

            try await waitForLanes(model)

            // --- normalize ---
            let beforeGains = model.lanes.map(\.gainDB)
            try expect(beforeGains.allSatisfy { $0 == 0 }, "lanes should start at unity, got \(beforeGains)")

            model.targetLoudnessDBFS = -14
            model.toggleNormalize()
            try expect(model.isNormalizeApplied, "Apply did not stick")
            for lane in model.lanes {
                try expect(
                    !lane.isClipping,
                    "\(lane.name) clips after Normalize — the peak cap did not hold")
                // Either the lane reached the target, or the peak ceiling stopped it.
                let reached = abs(lane.estimatedLoudnessDBFS - (-14)) < 0.6
                let capped = lane.gainDB >= GainCalculations.maxSafeGainDB(originalPeak: lane.document!.peak)
                try expect(
                    reached || capped,
                    "\(lane.name) landed at \(lane.estimatedLoudnessDBFS) dBFS with gain \(lane.gainDB)")
            }

            // Changing the target must invalidate gains computed for the old one.
            model.targetLoudnessDBFS = -6
            try expect(!model.isNormalizeApplied, "changing the target left stale gains applied")
            try expect(model.lanes.allSatisfy { $0.gainDB == 0 }, "stale base gains survived a target change")

            // --- per-lane trim ---
            model.toggleNormalize()
            let trimTarget = model.lanes[0].url
            let baseline = model.lanes[0].gainDB
            // Down first: the floor is -24 dB, so there is always room that way,
            // while a normalized lane often sits pinned at the +12 dB ceiling.
            model.nudge(trimTarget, by: -1)
            try expect(
                model.lanes[0].gainDB == baseline - 1,
                "one nudge should move exactly 1 dB, got \(model.lanes[0].gainDB) from \(baseline)")
            model.nudge(trimTarget, by: 1)
            try expect(model.lanes[0].gainDB == baseline, "nudging back should return to the base gain")

            // The trim is bounded twice: the offset itself to ±12 dB, and the total
            // to [-24, +12]. Whichever binds first, `canNudge` must agree with what
            // nudging actually does — otherwise the stepper looks live while dead.
            for direction in [1.0, -1.0] {
                for _ in 0..<60 { model.nudge(trimTarget, by: direction) }
                let pinned = model.lanes[0].gainDB
                try expect(
                    pinned <= GainCalculations.maxGainDB && pinned >= GainCalculations.minGainDB,
                    "gain \(pinned) escaped the [-24, +12] range")
                try expect(
                    !model.lanes[0].canNudge(by: direction),
                    "stepper still reports headroom at \(pinned) dB going \(direction)")
                model.nudge(trimTarget, by: direction)
                try expect(
                    model.lanes[0].gainDB == pinned,
                    "a press past the limit moved the gain from \(pinned) to \(model.lanes[0].gainDB)")
                try expect(
                    model.lanes[0].canNudge(by: -direction),
                    "the opposite stepper should still have room at \(pinned) dB")
            }
            model.resetGain(trimTarget)
            try expect(model.lanes[0].gainDB == 0, "reset should return the lane to unity")

            // --- uncheck keeps the analysis cached ---
            let recheckURL = model.lanes[0].url
            model.toggle(recheckURL)
            try expect(model.lanes.count == fixtures.count - 1, "uncheck did not drop the lane")
            model.toggle(recheckURL)
            try expect(
                model.lanes.contains { $0.url == recheckURL && $0.document != nil },
                "re-checking should reuse the cached analysis, not re-analyze")

            // --- viewport: a no-op pan must not republish ---
            // A vertical trackpad scroll drifts sideways, and each leaked pan used to
            // redownsample and redraw every lane — even at full view, where panning
            // clamps to nothing. That was the scroll stutter.
            let panTarget = model.lanes[0].url
            var republishCount = 0
            let observer = model.objectWillChange.sink { _ in republishCount += 1 }
            model.pan(panTarget, byViewRatio: 0.1)
            model.pan(panTarget, byViewRatio: -0.1)
            try expect(
                republishCount == 0,
                "panning a lane at full view republished the lanes \(republishCount) time(s)")
            observer.cancel()

            // A real zoom still lands, and panning inside it still moves.
            model.zoom(panTarget, scale: 4, anchorRatio: 0.5)
            let zoomed = model.lanes[0].viewport!
            try expect(zoomed.visibleDuration < zoomed.totalDuration, "pinch did not zoom in")
            model.pan(panTarget, byViewRatio: 0.25)
            try expect(
                model.lanes[0].viewport!.visibleStartTime > zoomed.visibleStartTime,
                "panning a zoomed lane did not move the visible span")
            model.resetZoom(panTarget)
            try expect(
                model.lanes[0].viewport!.visibleDuration == zoomed.totalDuration,
                "double-click did not reset the zoom")

            // --- playback state reaches the UI ---
            // Both regressions here were the same root cause: `playingURL` means
            // "loaded", and the lane's icon was reading it as "sounding".
            let shortest = model.lanes.min { $0.duration < $1.duration }!.url
            model.audition(shortest)
            try expect(model.isPlaying, "audition did not start playback")

            model.audition(shortest)
            try expect(!model.isPlaying, "pressing the playing lane again left the UI showing playing")
            try expect(model.playingURL == shortest, "a pause should keep the lane loaded and highlighted")

            model.audition(shortest)
            try expect(model.isPlaying, "resuming a paused lane did not restart playback")
            for _ in 0..<400 {
                if !model.isPlaying { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try expect(
                !model.isPlaying,
                "the file ran to its end but the UI still reports playing")

            // Replaying a finished lane has to rewind, or play() finishes instantly.
            model.audition(shortest)
            try expect(model.isPlaying, "replaying a finished lane did not start over")
            model.audition(shortest)

            // --- batch export ---
            let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("awqp-self-check-out")
            try? FileManager.default.removeItem(at: outputDir)
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            let sourcePeaksBefore = try model.lanes.map { try peak(of: $0.url) }
            let jobs = model.lanes.map { (url: $0.url, name: $0.name, gainDB: $0.gainDB) }
            try await exportForTest(model: model, to: outputDir)

            let written = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)
            try expect(
                written.count == jobs.count,
                "expected \(jobs.count) exported copies, found \(written.count)")

            for (index, job) in jobs.enumerated() {
                let expectedName = GainCalculations.outputFileName(originalName: job.name, gainDB: job.gainDB)
                let output = outputDir.appendingPathComponent(expectedName)
                try expect(
                    FileManager.default.fileExists(atPath: output.path),
                    "missing exported copy \(expectedName)")

                // The gain actually landed in the samples, not just in the filename.
                let expectedPeak = sourcePeaksBefore[index] * Float(GainCalculations.linearScale(forDB: job.gainDB))
                let actualPeak = try peak(of: output)
                try expect(
                    abs(actualPeak - min(expectedPeak, 1)) < 0.02,
                    "\(expectedName) peak \(actualPeak), expected ~\(expectedPeak) for \(job.gainDB) dB")

                // Non-destructive: the source is byte-for-byte what it was.
                try expect(
                    abs(try peak(of: job.url) - sourcePeaksBefore[index]) < 0.0001,
                    "export mutated the original \(job.name)")
            }

            try? FileManager.default.removeItem(at: outputDir)
        }

        /// `exportLanes()` opens a panel, which cannot run headless. This drives the
        /// same export path with the folder supplied directly.
        private static func exportForTest(model: AppModel, to folder: URL) async throws {
            model.startExport(to: folder)
            for _ in 0..<600 {
                if model.exportProgress == nil, model.lastExportFolder != nil { return }
                if let error = model.errorMessage { throw Failure(description: "export failed: \(error)") }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw Failure(description: "export never finished")
        }
    }
#endif
