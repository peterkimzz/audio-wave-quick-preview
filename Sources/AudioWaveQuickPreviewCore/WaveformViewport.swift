public enum OffscreenIndicatorDirection: Sendable, Equatable {
    case left
    case right
}

public struct WaveformViewport: Sendable, Equatable {
    public let totalDuration: Double
    public let visibleStartTime: Double
    public let visibleDuration: Double
    public let minimumVisibleDuration: Double

    public init(
        totalDuration: Double,
        visibleStartTime: Double,
        visibleDuration: Double,
        minimumVisibleDuration: Double
    ) {
        self.totalDuration = totalDuration
        self.visibleStartTime = visibleStartTime
        self.visibleDuration = visibleDuration
        self.minimumVisibleDuration = minimumVisibleDuration
    }

    public static func full(duration: Double, minimumVisibleDuration: Double) -> WaveformViewport {
        WaveformViewport(
            totalDuration: duration,
            visibleStartTime: 0,
            visibleDuration: duration,
            minimumVisibleDuration: minimumVisibleDuration
        )
    }

    public func zoomed(scale: Double, anchorRatio: Double) -> WaveformViewport {
        guard totalDuration > 0, scale > 0 else { return self }

        let clampedAnchor = min(max(anchorRatio, 0), 1)
        let anchorTime = visibleStartTime + (visibleDuration * clampedAnchor)
        let candidateDuration = visibleDuration / scale
        let clampedDuration = min(
            max(candidateDuration, minimumVisibleDuration),
            totalDuration
        )
        let candidateStart = anchorTime - (clampedDuration * clampedAnchor)
        let maxStart = max(totalDuration - clampedDuration, 0)
        let clampedStart = min(max(candidateStart, 0), maxStart)

        return WaveformViewport(
            totalDuration: totalDuration,
            visibleStartTime: clampedStart,
            visibleDuration: clampedDuration,
            minimumVisibleDuration: minimumVisibleDuration
        )
    }

    public func time(forViewRatio ratio: Double) -> Double {
        let clampedRatio = min(max(ratio, 0), 1)
        return visibleStartTime + (visibleDuration * clampedRatio)
    }

    public func centeredOnTime(_ time: Double) -> WaveformViewport {
        let clampedTime = min(max(time, 0), totalDuration)
        let candidateStart = clampedTime - (visibleDuration / 2)
        let maxStart = max(totalDuration - visibleDuration, 0)
        let clampedStart = min(max(candidateStart, 0), maxStart)

        return WaveformViewport(
            totalDuration: totalDuration,
            visibleStartTime: clampedStart,
            visibleDuration: visibleDuration,
            minimumVisibleDuration: minimumVisibleDuration
        )
    }

    public func centeredOnGlobalRatio(_ ratio: Double) -> WaveformViewport {
        let clampedRatio = min(max(ratio, 0), 1)
        let targetTime = totalDuration * clampedRatio
        return centeredOnTime(targetTime)
    }

    public func panned(by deltaTime: Double) -> WaveformViewport {
        let candidateStart = visibleStartTime + deltaTime
        let maxStart = max(totalDuration - visibleDuration, 0)
        let clampedStart = min(max(candidateStart, 0), maxStart)

        return WaveformViewport(
            totalDuration: totalDuration,
            visibleStartTime: clampedStart,
            visibleDuration: visibleDuration,
            minimumVisibleDuration: minimumVisibleDuration
        )
    }

    public func reset() -> WaveformViewport {
        .full(duration: totalDuration, minimumVisibleDuration: minimumVisibleDuration)
    }

    public func offscreenIndicatorDirection(for time: Double) -> OffscreenIndicatorDirection? {
        if time < visibleStartTime {
            return .left
        }

        if time > visibleStartTime + visibleDuration {
            return .right
        }

        return nil
    }

    public func updatingMinimumVisibleDuration(_ minimumVisibleDuration: Double) -> WaveformViewport {
        let updatedMinimum = min(max(minimumVisibleDuration, 0.001), max(totalDuration, 0.001))

        guard visibleDuration < updatedMinimum else {
            return WaveformViewport(
                totalDuration: totalDuration,
                visibleStartTime: visibleStartTime,
                visibleDuration: visibleDuration,
                minimumVisibleDuration: updatedMinimum
            )
        }

        let centerTime = visibleStartTime + (visibleDuration / 2)
        let expandedDuration = min(updatedMinimum, totalDuration)
        let candidateStart = centerTime - (expandedDuration / 2)
        let maxStart = max(totalDuration - expandedDuration, 0)
        let clampedStart = min(max(candidateStart, 0), maxStart)

        return WaveformViewport(
            totalDuration: totalDuration,
            visibleStartTime: clampedStart,
            visibleDuration: expandedDuration,
            minimumVisibleDuration: updatedMinimum
        )
    }

    public func viewRatio(for time: Double) -> Double? {
        guard visibleDuration > 0 else { return nil }
        guard time >= visibleStartTime, time <= visibleStartTime + visibleDuration else { return nil }
        return (time - visibleStartTime) / visibleDuration
    }
}
