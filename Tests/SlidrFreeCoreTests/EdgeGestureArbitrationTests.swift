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
