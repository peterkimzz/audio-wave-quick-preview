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

private struct SpecFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}
