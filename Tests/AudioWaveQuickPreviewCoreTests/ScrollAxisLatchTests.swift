import Testing

@testable import AudioWaveQuickPreviewCore

/// `#expect` cannot call a mutating member inline, so each event is stepped
/// through this helper and the verdict is checked as a plain value.
private struct ScrollGesture {
    private var latch = ScrollAxisLatch()

    mutating func send(
        deltaX: Double,
        deltaY: Double,
        _ phase: ScrollAxisLatch.Phase
    ) -> Bool {
        latch.isHorizontal(deltaX: deltaX, deltaY: deltaY, phase: phase)
    }
}

struct ScrollAxisLatchTests {
    @Test
    func keepsAVerticalGestureVerticalDespiteSidewaysDrift() {
        var gesture = ScrollGesture()

        let start = gesture.send(deltaX: 0.4, deltaY: -12, .begins)
        // Mid-scroll drift, and the tail of a fling where vertical decays first.
        let drift = gesture.send(deltaX: 3, deltaY: -2, .continues)
        let tail = gesture.send(deltaX: 0.9, deltaY: -0.1, .continues)

        #expect([start, drift, tail] == [false, false, false])
    }

    @Test
    func aHorizontalGestureStaysHorizontalThroughVerticalDrift() {
        var gesture = ScrollGesture()

        let start = gesture.send(deltaX: -14, deltaY: 0.6, .begins)
        let drift = gesture.send(deltaX: -1, deltaY: 2, .continues)

        #expect([start, drift] == [true, true])
    }

    /// Momentum coasts on under the gesture's latch. It used to be judged event by
    /// event, which put the sideways leak right back into every vertical fling.
    @Test
    func momentumCoastsOnTheGesturesAxis() {
        var gesture = ScrollGesture()

        let fling = gesture.send(deltaX: 0.2, deltaY: -30, .begins)
        // The zero-delta event that ends the finger movement decides nothing.
        let lift = gesture.send(deltaX: 0, deltaY: 0, .continues)
        let coast = gesture.send(deltaX: 2, deltaY: -1, .continues)
        let settle = gesture.send(deltaX: 0.5, deltaY: -0.05, .continues)

        #expect([fling, lift, coast, settle] == [false, false, false, false])
    }

    /// A tie must not commit the gesture. Locking on the first event alone killed
    /// panning outright when a horizontal swipe opened with equal deltas.
    @Test
    func anAmbiguousStartLetsTheFirstDecisiveEventChooseTheAxis() {
        var gesture = ScrollGesture()

        let tie = gesture.send(deltaX: 4, deltaY: 4, .begins)
        let decisive = gesture.send(deltaX: 9, deltaY: 1, .continues)
        let drift = gesture.send(deltaX: 1, deltaY: 3, .continues)

        #expect([tie, decisive, drift] == [false, true, true])
    }

    /// Covers both a new gesture and a standalone wheel click, which the view maps
    /// to `.begins` precisely so each one is judged on its own deltas.
    @Test
    func aFreshStartDiscardsThePreviousAxis() {
        var gesture = ScrollGesture()

        let vertical = gesture.send(deltaX: 0, deltaY: -10, .begins)
        let horizontal = gesture.send(deltaX: -10, deltaY: 0, .begins)

        #expect([vertical, horizontal] == [false, true])
    }
}
