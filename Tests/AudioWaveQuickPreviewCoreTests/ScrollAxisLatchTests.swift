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

        let start = gesture.send(deltaX: 0.4, deltaY: -12, .began)
        // Mid-scroll drift, and the tail of a fling where vertical decays first.
        let drift = gesture.send(deltaX: 3, deltaY: -2, .changed)
        let tail = gesture.send(deltaX: 0.9, deltaY: -0.1, .changed)

        #expect([start, drift, tail] == [false, false, false])
    }

    @Test
    func aHorizontalGestureStaysHorizontalThroughVerticalDrift() {
        var gesture = ScrollGesture()

        let start = gesture.send(deltaX: -14, deltaY: 0.6, .began)
        let drift = gesture.send(deltaX: -1, deltaY: 2, .changed)

        #expect([start, drift] == [true, true])
    }

    @Test
    func theNextGestureIsJudgedAfresh() {
        var gesture = ScrollGesture()

        let vertical = gesture.send(deltaX: 0, deltaY: -10, .began)
        _ = gesture.send(deltaX: 0, deltaY: 0, .ended)
        let horizontal = gesture.send(deltaX: -10, deltaY: 0, .began)

        #expect([vertical, horizontal] == [false, true])
    }

    @Test
    func aWheelEventWithNoGestureFollowsItsOwnDominantAxis() {
        var gesture = ScrollGesture()

        let vertical = gesture.send(deltaX: 0, deltaY: -3, .changed)
        let horizontal = gesture.send(deltaX: -3, deltaY: 0, .changed)

        #expect([vertical, horizontal] == [false, true])
    }
}
