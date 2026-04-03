import AudioWaveQuickPreviewCore
import Foundation

@main
struct AudioWaveQuickPreviewSpecs {
    static func main() {
        run("zoom keeps the pointer-anchored time stable") {
            let viewport = WaveformViewport.full(duration: 100, minimumVisibleDuration: 5)
            let zoomed = viewport.zoomed(scale: 2, anchorRatio: 0.25)

            try expectEqual(zoomed.visibleDuration, 50, accuracy: 0.0001)
            try expectEqual(zoomed.visibleStartTime, 12.5, accuracy: 0.0001)
        }

        run("seek mapping uses the visible window instead of the full file") {
            let viewport = WaveformViewport(
                totalDuration: 100,
                visibleStartTime: 40,
                visibleDuration: 10,
                minimumVisibleDuration: 5
            )

            try expectEqual(viewport.time(forViewRatio: 0), 40, accuracy: 0.0001)
            try expectEqual(viewport.time(forViewRatio: 0.5), 45, accuracy: 0.0001)
            try expectEqual(viewport.time(forViewRatio: 1), 50, accuracy: 0.0001)
        }

        run("offscreen indicator points toward the hidden playhead and go-to-playhead reveals it") {
            let viewport = WaveformViewport(
                totalDuration: 100,
                visibleStartTime: 40,
                visibleDuration: 10,
                minimumVisibleDuration: 5
            )

            try expectEqual(viewport.offscreenIndicatorDirection(for: 35), .left)
            try expectEqual(viewport.offscreenIndicatorDirection(for: 55), .right)
            try expectNil(viewport.offscreenIndicatorDirection(for: 45))

            let centered = viewport.centeredOnTime(55)
            try expectEqual(centered.visibleStartTime, 50, accuracy: 0.0001)
            try expectEqual(centered.visibleDuration, 10, accuracy: 0.0001)
        }

        run("reset zoom returns to the full file window") {
            let viewport = WaveformViewport(
                totalDuration: 100,
                visibleStartTime: 40,
                visibleDuration: 10,
                minimumVisibleDuration: 5
            )

            let reset = viewport.reset()
            try expectEqual(reset.visibleStartTime, 0, accuracy: 0.0001)
            try expectEqual(reset.visibleDuration, 100, accuracy: 0.0001)
        }

        run("panning moves the visible window but clamps to file edges") {
            let viewport = WaveformViewport(
                totalDuration: 100,
                visibleStartTime: 40,
                visibleDuration: 10,
                minimumVisibleDuration: 5
            )

            let pannedRight = viewport.panned(by: 12)
            try expectEqual(pannedRight.visibleStartTime, 52, accuracy: 0.0001)

            let pannedPastEnd = viewport.panned(by: 100)
            try expectEqual(pannedPastEnd.visibleStartTime, 90, accuracy: 0.0001)

            let pannedPastStart = viewport.panned(by: -100)
            try expectEqual(pannedPastStart.visibleStartTime, 0, accuracy: 0.0001)
        }

        run("space without modifiers maps to playback toggle") {
            try expectEqual(
                KeyboardShortcutResolver.action(for: " ", hasModifiers: false),
                .togglePlayback
            )
            try expectNil(KeyboardShortcutResolver.action(for: " ", hasModifiers: true))
            try expectNil(KeyboardShortcutResolver.action(for: "k", hasModifiers: false))
        }

        run("arrow keys without modifiers map to 10-second seek actions") {
            try expectEqual(
                KeyboardShortcutResolver.action(forKeyCode: 123, hasModifiers: false),
                .seekBackward
            )
            try expectEqual(
                KeyboardShortcutResolver.action(forKeyCode: 124, hasModifiers: false),
                .seekForward
            )
            try expectNil(KeyboardShortcutResolver.action(forKeyCode: 123, hasModifiers: true))
            try expectNil(KeyboardShortcutResolver.action(forKeyCode: 999, hasModifiers: false))
        }

        run("minimap interactions recenter the viewport around any global ratio") {
            let viewport = WaveformViewport(
                totalDuration: 100,
                visibleStartTime: 40,
                visibleDuration: 10,
                minimumVisibleDuration: 5
            )

            let moved = viewport.centeredOnGlobalRatio(0.8)
            try expectEqual(moved.visibleStartTime, 75, accuracy: 0.0001)
            try expectEqual(moved.visibleDuration, 10, accuracy: 0.0001)

            let dragged = moved.centeredOnGlobalRatio(0.25)
            try expectEqual(dragged.visibleStartTime, 20, accuracy: 0.0001)
            try expectEqual(dragged.visibleDuration, 10, accuracy: 0.0001)

            let clampedStart = viewport.centeredOnGlobalRatio(0.01)
            try expectEqual(clampedStart.visibleStartTime, 0, accuracy: 0.0001)
        }

        run("waveform pyramid returns the full file at the requested density") {
            let samples: [Float] = [0, 1, 0, 2, 0, 3, 0, 4]
            let pyramid = WaveformPyramid.build(
                from: samples,
                maximumBucketCount: 8,
                minimumBucketCount: 2
            )
            let viewport = WaveformViewport.full(duration: 8, minimumVisibleDuration: 1)

            let displayed = pyramid.samples(for: viewport, targetBucketCount: 4)
            try expectEqual(displayed, [1, 2, 3, 4], accuracy: 0.0001)
        }

        run("waveform pyramid returns only the visible time range") {
            let samples: [Float] = [0, 1, 0, 2, 0, 3, 0, 4]
            let pyramid = WaveformPyramid.build(
                from: samples,
                maximumBucketCount: 8,
                minimumBucketCount: 2
            )
            let viewport = WaveformViewport(
                totalDuration: 8,
                visibleStartTime: 4,
                visibleDuration: 4,
                minimumVisibleDuration: 1
            )

            let displayed = pyramid.samples(for: viewport, targetBucketCount: 2)
            try expectEqual(displayed, [3, 4], accuracy: 0.0001)
        }

        run("waveform pyramid preserves visible peaks across zoom levels") {
            let samples: [Float] = [0, 0.1, 0, 0.9, 0, 0.2, 0, 0.8]
            let pyramid = WaveformPyramid.build(
                from: samples,
                maximumBucketCount: 8,
                minimumBucketCount: 2
            )

            let fullViewport = WaveformViewport.full(duration: 8, minimumVisibleDuration: 1)
            let zoomedViewport = WaveformViewport(
                totalDuration: 8,
                visibleStartTime: 2,
                visibleDuration: 2,
                minimumVisibleDuration: 1
            )

            let fullDisplayed = pyramid.samples(for: fullViewport, targetBucketCount: 4)
            try expectEqual(fullDisplayed, [0.1, 0.9, 0.2, 0.8], accuracy: 0.0001)

            let zoomedDisplayed = pyramid.samples(for: zoomedViewport, targetBucketCount: 2)
            try expectEqual(zoomedDisplayed, [0, 0.9], accuracy: 0.0001)
        }

        run("playback navigation moves in 10-second style jumps and clamps to file bounds") {
            try expectEqual(
                PlaybackNavigation.shiftedTime(currentTime: 15, duration: 100, delta: 10),
                25,
                accuracy: 0.0001
            )
            try expectEqual(
                PlaybackNavigation.shiftedTime(currentTime: 15, duration: 100, delta: -10),
                5,
                accuracy: 0.0001
            )
            try expectEqual(
                PlaybackNavigation.shiftedTime(currentTime: 4, duration: 100, delta: -10),
                0,
                accuracy: 0.0001
            )
            try expectEqual(
                PlaybackNavigation.shiftedTime(currentTime: 97, duration: 100, delta: 10),
                100,
                accuracy: 0.0001
            )
        }

        run("playback control presentation uses stable icons and labels") {
            try expectEqual(
                PlaybackControlPresentation.primaryControl(isPlaying: false),
                PlaybackControlPresentation(
                    systemImageName: "play.fill",
                    accessibilityLabel: "Play",
                    toolTip: "Play"
                )
            )
            try expectEqual(
                PlaybackControlPresentation.primaryControl(isPlaying: true),
                PlaybackControlPresentation(
                    systemImageName: "pause.fill",
                    accessibilityLabel: "Pause",
                    toolTip: "Pause"
                )
            )
        }

        print("All specs passed")
    }
}

private func run(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("PASS: \(name)")
    } catch {
        fputs("FAIL: \(name)\n\(error)\n", stderr)
        Foundation.exit(1)
    }
}

private func expectEqual(_ actual: Double, _ expected: Double, accuracy: Double) throws {
    if abs(actual - expected) > accuracy {
        throw SpecFailure(message: "Expected \(expected), got \(actual)")
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    if actual != expected {
        throw SpecFailure(message: "Expected \(expected), got \(actual)")
    }
}

private func expectNil<T>(_ value: T?) throws {
    if value != nil {
        throw SpecFailure(message: "Expected nil, got \(String(describing: value))")
    }
}

private func expectEqual(_ actual: [Float], _ expected: [Float], accuracy: Float) throws {
    if actual.count != expected.count {
        throw SpecFailure(message: "Expected count \(expected.count), got \(actual.count)")
    }

    for (actualValue, expectedValue) in zip(actual, expected) {
        if abs(actualValue - expectedValue) > accuracy {
            throw SpecFailure(message: "Expected \(expected), got \(actual)")
        }
    }
}

private struct SpecFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}
