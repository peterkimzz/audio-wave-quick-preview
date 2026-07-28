/// Locks a scroll gesture to one axis for its whole duration, momentum included.
/// Trackpad vertical scrolling carries horizontal drift, so re-measuring the
/// dominant axis per event leaks into waveform panning mid-scroll — and one such
/// leak redraws every lane. Decide once, then keep it.
public struct ScrollAxisLatch: Sendable {
    /// What this event means for the decision, not the raw `NSEvent.phase`. A
    /// plain wheel click has no gesture around it, so it `begins` one of its own.
    public enum Phase: Sendable {
        /// A fresh decision: forget the previous gesture's axis.
        case begins
        /// The same gesture as the last event, including the momentum that coasts
        /// on after the fingers lift. Keep the axis already chosen.
        case continues
    }

    private var latched: Bool?

    public init() {}

    /// Whether this event should pan the waveform horizontally.
    public mutating func isHorizontal(deltaX: Double, deltaY: Double, phase: Phase) -> Bool {
        if phase == .begins { latched = nil }

        // Equal deltas decide nothing — a horizontal swipe whose first event ties
        // (or is all zeroes, as `.ended` events are) must not get locked vertical
        // for the rest of the gesture. Leave the latch open and let the first
        // event that actually favours an axis set it.
        if latched == nil, abs(deltaX) != abs(deltaY) {
            latched = abs(deltaX) > abs(deltaY)
        }

        // Still undecided: leave the event to the enclosing scroll view.
        return latched ?? false
    }
}
