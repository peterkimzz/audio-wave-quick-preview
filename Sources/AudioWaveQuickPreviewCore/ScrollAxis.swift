/// Locks a scroll gesture to one axis for its whole duration. Trackpad vertical
/// scrolling carries horizontal drift, so re-measuring the dominant axis per
/// event leaks into waveform panning mid-scroll — and one such leak redraws
/// every lane. Decide once when the gesture begins, then keep it.
public struct ScrollAxisLatch: Sendable {
    /// Mapped from `NSEvent.phase`. Momentum and old-style wheel events, which
    /// carry no phase, arrive as `.changed`.
    public enum Phase: Sendable {
        case began
        case changed
        case ended
    }

    private var latched: Bool?

    public init() {}

    /// Whether this event should pan the waveform horizontally.
    public mutating func isHorizontal(deltaX: Double, deltaY: Double, phase: Phase) -> Bool {
        let dominant = abs(deltaX) > abs(deltaY)
        switch phase {
        case .began: latched = dominant
        case .ended: latched = nil
        case .changed: break
        }
        // No latch means a wheel event with no gesture around it: judge it alone.
        return latched ?? dominant
    }
}
