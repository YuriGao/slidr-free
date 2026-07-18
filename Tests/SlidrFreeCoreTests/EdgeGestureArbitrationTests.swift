import SlidrFreeCore
import XCTest

final class EdgeGestureArbitrationTests: XCTestCase {
    func testNormalSingleFingerEdgeStepStillEmits() {
        var recognizer = GestureRecognizer(settings: .default)

        XCTAssertNil(recognizer.process(frame([touch(1, y: 0.20)], timestamp: 1.0)))
        XCTAssertEqual(
            recognizer.process(frame([touch(1, y: 0.31)], timestamp: 1.1)),
            .brightness(direction: .increase, magnitude: 1.0)
        )
    }

    func testEachEdgeUsesItsOwnConfiguredStepDistance() {
        var settings = AppSettings.default
        settings.gesture.leftPhysicalStepDistance = 0.04
        settings.gesture.rightPhysicalStepDistance = 0.10
        settings.gesture.topPhysicalStepDistance = 0.15

        var leftRecognizer = GestureRecognizer(settings: settings)
        XCTAssertNil(leftRecognizer.process(frame([touch(1, x: 0.05, y: 0.20)], timestamp: 1.0)))
        XCTAssertEqual(
            leftRecognizer.process(frame([touch(1, x: 0.05, y: 0.25)], timestamp: 1.1)),
            .brightness(direction: .increase, magnitude: 1.0)
        )

        var rightRecognizer = GestureRecognizer(settings: settings)
        XCTAssertNil(rightRecognizer.process(frame([touch(2, x: 0.95, y: 0.20)], timestamp: 2.0)))
        XCTAssertNil(rightRecognizer.process(frame([touch(2, x: 0.95, y: 0.26)], timestamp: 2.1)))
        XCTAssertEqual(
            rightRecognizer.process(frame([touch(2, x: 0.95, y: 0.31)], timestamp: 2.2)),
            .volume(direction: .increase, magnitude: 1.0)
        )

        var topRecognizer = GestureRecognizer(settings: settings)
        XCTAssertNil(topRecognizer.process(frame([touch(3, x: 0.30, y: 0.95)], timestamp: 3.0)))
        XCTAssertNil(topRecognizer.process(frame([touch(3, x: 0.41, y: 0.95)], timestamp: 3.21)))
        XCTAssertEqual(
            topRecognizer.process(frame([touch(3, x: 0.46, y: 0.95)], timestamp: 3.42)),
            .browserTab(direction: .next)
        )
    }

    func testTwoTouchFrameSuppressesLaterSingleFingerFramesUntilEmpty() {
        assertMultitouchLatch(touchCount: 2)
    }

    func testThreeTouchFrameSuppressesLaterSingleFingerFramesUntilEmpty() {
        assertMultitouchLatch(touchCount: 3)
    }

    func testCancellationClearsMultitouchLatchAndContinuity() {
        var recognizer = GestureRecognizer(settings: .default)

        XCTAssertNil(recognizer.process(frame([touch(1, y: 0.20)], timestamp: 1.0)))
        XCTAssertNil(
            recognizer.process(
                frame(
                    [touch(1, y: 0.22), touch(2, x: 0.50, y: 0.50)],
                    timestamp: 1.1
                )
            )
        )
        XCTAssertNil(recognizer.process(.physicalTouchCancelled))
        XCTAssertNil(
            recognizer.process(frame([touch(1, y: 0.20)], timestamp: 1.2)),
            "cancellation must clear the latch without preserving old continuity"
        )
        XCTAssertEqual(
            recognizer.process(frame([touch(1, y: 0.31)], timestamp: 1.3)),
            .brightness(direction: .increase, magnitude: 1.0)
        )
    }

    func testTouchStartingOutsideSideEdgeStaysBlockedUntilEmpty() {
        var recognizer = GestureRecognizer(settings: .default)

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.50, y: 0.20)], timestamp: 1.0)))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.20)], timestamp: 1.1)))
        XCTAssertNil(
            recognizer.process(frame([touch(1, x: 0.05, y: 0.31)], timestamp: 1.2)),
            "entering the edge after a center start must not arm the gesture"
        )
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.42)], timestamp: 1.3)))

        XCTAssertNil(recognizer.process(frame([], timestamp: 1.4)))
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.20)], timestamp: 1.5)))
        XCTAssertEqual(
            recognizer.process(frame([touch(2, x: 0.05, y: 0.31)], timestamp: 1.6)),
            .brightness(direction: .increase, magnitude: 1.0),
            "empty must allow the next edge-originating contact to arm normally"
        )
    }

    func testTouchStartingOutsideTopEdgeCannotSwitchBrowserTabsAfterEntering() {
        var recognizer = GestureRecognizer(settings: .default)

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.30, y: 0.50)], timestamp: 1.0)))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.30, y: 0.95)], timestamp: 1.1)))
        XCTAssertNil(
            recognizer.process(frame([touch(1, x: 0.41, y: 0.95)], timestamp: 1.2)),
            "top-edge tab switching must use the same contact-origin gate"
        )
    }

    func testEdgeOriginLocksContactToItsStartingEdge() {
        var recognizer = GestureRecognizer(settings: .default)

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.20)], timestamp: 1.0)))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.22)], timestamp: 1.1)))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.30, y: 0.95)], timestamp: 1.2)))
        XCTAssertNil(
            recognizer.process(frame([touch(1, x: 0.41, y: 0.95)], timestamp: 1.3)),
            "a left-edge contact must not become a top-edge gesture without lifting"
        )

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.30)], timestamp: 1.4)))
        XCTAssertEqual(
            recognizer.process(frame([touch(1, x: 0.05, y: 0.41)], timestamp: 1.5)),
            .brightness(direction: .increase, magnitude: 1.0),
            "returning to the original edge may resume after continuity is re-established"
        )
    }

    private func assertMultitouchLatch(touchCount: Int) {
        var recognizer = GestureRecognizer(settings: .default)
        let multipleTouches = (1...touchCount).map { id in
            touch(id, x: id == 1 ? 0.05 : 0.50, y: id == 1 ? 0.22 : 0.50)
        }

        XCTAssertNil(recognizer.process(frame([touch(1, y: 0.20)], timestamp: 1.0)))
        XCTAssertNil(recognizer.process(frame(multipleTouches, timestamp: 1.1)))
        XCTAssertNil(
            recognizer.process(frame([touch(1, y: 0.40)], timestamp: 1.2)),
            "single-touch input must stay suppressed after observing \(touchCount) touches"
        )

        XCTAssertNil(recognizer.process(frame([], timestamp: 1.3)))
        XCTAssertNil(
            recognizer.process(frame([touch(1, y: 0.20)], timestamp: 1.4)),
            "empty must clear the latch without preserving old continuity"
        )
        XCTAssertEqual(
            recognizer.process(frame([touch(1, y: 0.31)], timestamp: 1.5)),
            .brightness(direction: .increase, magnitude: 1.0)
        )
    }

    private func frame(_ touches: [PhysicalTouch], timestamp: Double) -> NormalizedInputEvent {
        .physicalTouchFrame(touches: touches, timestamp: timestamp)
    }

    private func touch(_ id: Int, x: Double = 0.05, y: Double) -> PhysicalTouch {
        PhysicalTouch(id: id, x: x, y: y)
    }
}
