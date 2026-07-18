import SlidrFreeCore
import XCTest

final class CornerDoubleTapRecognizerTests: XCTestCase {
    func testRecognizesEveryCornerOnSecondReleaseOnly() {
        let cases: [(TrackpadCorner, Double, Double)] = [
            (.topLeft, 0.05, 0.95),
            (.topRight, 0.95, 0.95),
            (.bottomLeft, 0.05, 0.05),
            (.bottomRight, 0.95, 0.05)
        ]

        for (corner, x, y) in cases {
            var recognizer = CornerDoubleTapRecognizer()
            XCTAssertNil(recognizer.process(frame([touch(1, x: x, y: y)], 1.00), cornerWidthPercent: 0.10))
            XCTAssertNil(recognizer.process(frame([], 1.10), cornerWidthPercent: 0.10))
            XCTAssertNil(recognizer.process(frame([touch(2, x: x, y: y)], 1.25), cornerWidthPercent: 0.10))
            XCTAssertEqual(recognizer.process(frame([], 1.35), cornerWidthPercent: 0.10), corner)
            XCTAssertNil(recognizer.process(frame([], 1.36), cornerWidthPercent: 0.10))
        }
    }

    func testSmallMovementWithinTapStillRecognizes() {
        var recognizer = CornerDoubleTapRecognizer()

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.95)], 1.00), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.06, y: 0.96)], 1.05), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], 1.10), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.06, y: 0.94)], 1.20), cornerWidthPercent: 0.10))
        XCTAssertEqual(recognizer.process(frame([], 1.28), cornerWidthPercent: 0.10), .topLeft)
    }

    func testMovementAboveLimitInvalidatesEvenAfterReturning() {
        var recognizer = CornerDoubleTapRecognizer()

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.95)], 1.00), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.09, y: 0.95)], 1.05), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.95)], 1.10), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], 1.15), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.95)], 1.20), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], 1.25), cornerWidthPercent: 0.10))
    }

    func testTapStartingOutsideCornerCannotEnterAndQualify() {
        var recognizer = CornerDoubleTapRecognizer()

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.50, y: 0.50)], 1.00), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.95)], 1.05), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], 1.10), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.95)], 1.20), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], 1.25), cornerWidthPercent: 0.10))
    }

    func testDifferentCornersDoNotFormDoubleTap() {
        var recognizer = CornerDoubleTapRecognizer()

        performSingleTap(&recognizer, id: 1, x: 0.05, y: 0.95, start: 1.00)
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.95, y: 0.95)], 1.20), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], 1.25), cornerWidthPercent: 0.10))
    }

    func testLateOrLongSecondTapDoesNotTrigger() {
        var late = CornerDoubleTapRecognizer()
        performSingleTap(&late, id: 1, x: 0.05, y: 0.95, start: 1.00)
        XCTAssertNil(late.process(frame([touch(2, x: 0.05, y: 0.95)], 1.90), cornerWidthPercent: 0.10))
        XCTAssertNil(late.process(frame([], 2.00), cornerWidthPercent: 0.10))

        var long = CornerDoubleTapRecognizer()
        performSingleTap(&long, id: 1, x: 0.05, y: 0.95, start: 2.00)
        XCTAssertNil(long.process(frame([touch(2, x: 0.05, y: 0.95)], 2.20), cornerWidthPercent: 0.10))
        XCTAssertNil(long.process(frame([], 2.66), cornerWidthPercent: 0.10))
    }

    func testSlightlyLongerTapsAndGapStillTrigger() {
        var recognizer = CornerDoubleTapRecognizer()

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.95)], 1.00), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], 1.40), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.95)], 1.90), cornerWidthPercent: 0.10))
        XCTAssertEqual(recognizer.process(frame([], 2.30), cornerWidthPercent: 0.10), .topLeft)
    }

    func testDefaultInterTapIntervalMatchesUserSettingDefault() {
        XCTAssertEqual(
            CornerDoubleTapRecognizer.defaultMaximumInterTapInterval,
            GestureSettings.defaultCornerDoubleTapIntervalSeconds,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            CornerDoubleTapRecognizer.defaultMaximumMovement,
            GestureSettings.defaultCornerMovementTolerancePercent,
            accuracy: 0.000_001
        )
    }

    func testConfiguredMovementLimitIncludesBoundaryAndRejectsLargerMovement() {
        var boundary = CornerDoubleTapRecognizer(maximumMovement: 0.05)
        XCTAssertNil(boundary.process(frame([touch(1, x: 0.05, y: 0.95)], 1.00), cornerWidthPercent: 0.10))
        XCTAssertNil(boundary.process(frame([touch(1, x: 0.10, y: 0.95)], 1.05), cornerWidthPercent: 0.10))
        XCTAssertNil(boundary.process(frame([], 1.10), cornerWidthPercent: 0.10))
        XCTAssertNil(boundary.process(frame([touch(2, x: 0.05, y: 0.95)], 1.20), cornerWidthPercent: 0.10))
        XCTAssertEqual(boundary.process(frame([], 1.30), cornerWidthPercent: 0.10), .topLeft)

        var above = CornerDoubleTapRecognizer(maximumMovement: 0.05)
        XCTAssertNil(above.process(frame([touch(1, x: 0.05, y: 0.95)], 2.00), cornerWidthPercent: 0.10))
        XCTAssertNil(above.process(frame([touch(1, x: 0.101, y: 0.95)], 2.05), cornerWidthPercent: 0.10))
        XCTAssertNil(above.process(frame([], 2.10), cornerWidthPercent: 0.10))
        performSingleTap(&above, id: 2, x: 0.05, y: 0.95, start: 2.20)
    }

    func testConfiguredInterTapIntervalIncludesBoundaryAndRejectsNextValue() {
        let interval = 0.20
        let firstTapEndedAt = 1.10
        let boundaryStart = firstTapEndedAt + interval
        var boundary = CornerDoubleTapRecognizer(maximumInterTapInterval: interval)
        performSingleTap(&boundary, id: 1, x: 0.05, y: 0.95, start: 1.00)
        XCTAssertNil(boundary.process(frame([touch(2, x: 0.05, y: 0.95)], boundaryStart), cornerWidthPercent: 0.10))
        XCTAssertEqual(boundary.process(frame([], boundaryStart + 0.05), cornerWidthPercent: 0.10), .topLeft)

        var aboveBoundary = CornerDoubleTapRecognizer(maximumInterTapInterval: interval)
        performSingleTap(&aboveBoundary, id: 1, x: 0.05, y: 0.95, start: 1.00)
        XCTAssertNil(
            aboveBoundary.process(
                frame([touch(2, x: 0.05, y: 0.95)], boundaryStart + 0.000_001),
                cornerWidthPercent: 0.10
            )
        )
        XCTAssertNil(aboveBoundary.process(frame([], boundaryStart + 0.05), cornerWidthPercent: 0.10))
    }

    func testInvalidInterTapIntervalFallsBackToSafeDefault() {
        for interval in [0, -1, .infinity, .nan] {
            var recognizer = CornerDoubleTapRecognizer(maximumInterTapInterval: interval)
            performSingleTap(&recognizer, id: 1, x: 0.05, y: 0.95, start: 1.00)
            XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.95)], 1.45), cornerWidthPercent: 0.10))
            XCTAssertEqual(recognizer.process(frame([], 1.50), cornerWidthPercent: 0.10), .topLeft)
        }
    }

    func testMultitouchReplacementCancellationAndDisableResetPendingTap() {
        assertInvalidatingEvent(
            .physicalTouchFrame(
                touches: [touch(2, x: 0.05, y: 0.95), touch(3, x: 0.06, y: 0.94)],
                timestamp: 1.22
            )
        )
        assertInvalidatingEvent(frame([touch(99, x: 0.05, y: 0.95)], 1.22))
        assertInvalidatingEvent(.physicalTouchCancelled)

        var recognizer = CornerDoubleTapRecognizer()
        performSingleTap(&recognizer, id: 1, x: 0.05, y: 0.95, start: 1.00)
        XCTAssertNil(
            recognizer.process(frame([touch(2, x: 0.05, y: 0.95)], 1.20), cornerWidthPercent: 0.10, isEnabled: false)
        )
        XCTAssertNil(recognizer.process(frame([], 1.25), cornerWidthPercent: 0.10))
    }

    func testGestureRecognizerKeepsCornerSwipeAsEdgeGesture() {
        var recognizer = GestureRecognizer(settings: .default)

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.05)], 1.00)))
        XCTAssertEqual(
            recognizer.process(frame([touch(1, x: 0.05, y: 0.16)], 1.10)),
            .brightness(direction: .increase, magnitude: 1.0)
        )
        XCTAssertNil(recognizer.process(frame([], 1.20)))
    }

    func testCornerCandidateDefersEdgeUntilMovementExceedsConfiguredLimit() {
        var settings = AppSettings.default
        settings.gesture.cornerMovementTolerancePercent = 0.03
        settings.gesture.leftPhysicalStepDistance = 0.02
        var recognizer = GestureRecognizer(settings: settings)

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.05)], 1.00)))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.075)], 1.05)))
        XCTAssertEqual(
            recognizer.process(frame([touch(1, x: 0.05, y: 0.085)], 1.10)),
            .brightness(direction: .increase, magnitude: 1.0)
        )
    }

    func testQualifyingCornerDoubleTapCannotAlsoEmitMinimumDistanceEdgeStep() {
        var settings = AppSettings.default
        settings.gesture.leftPhysicalStepDistance = 0.02
        var recognizer = GestureRecognizer(settings: settings)

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.05)], 1.00)))
        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.075)], 1.05)))
        XCTAssertNil(recognizer.process(frame([], 1.10)))
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.05)], 1.20)))
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.075)], 1.25)))
        XCTAssertEqual(recognizer.process(frame([], 1.28)), .cornerDoubleTap(corner: .bottomLeft))
    }

    func testSettingsUpdateInvalidatesPendingTap() {
        var recognizer = GestureRecognizer(settings: .default)

        XCTAssertNil(recognizer.process(frame([touch(1, x: 0.05, y: 0.95)], 1.00)))
        XCTAssertNil(recognizer.process(frame([], 1.10)))
        recognizer.updateSettings(.default)
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.95)], 1.20)))
        XCTAssertNil(recognizer.process(frame([], 1.28)))
    }

    func testGestureRecognizerUsesDedicatedCornerTriggerPercent() {
        var narrowCornerSettings = AppSettings.default
        narrowCornerSettings.gesture.edgeWidthPercent = 0.20
        narrowCornerSettings.gesture.cornerTriggerPercent = 0.05
        var narrowCornerRecognizer = GestureRecognizer(settings: narrowCornerSettings)

        XCTAssertNil(narrowCornerRecognizer.process(frame([touch(1, x: 0.12, y: 0.88)], 1.00)))
        XCTAssertNil(narrowCornerRecognizer.process(frame([], 1.10)))
        XCTAssertNil(narrowCornerRecognizer.process(frame([touch(2, x: 0.12, y: 0.88)], 1.20)))
        XCTAssertNil(narrowCornerRecognizer.process(frame([], 1.30)))

        var wideCornerSettings = AppSettings.default
        wideCornerSettings.gesture.edgeWidthPercent = 0.05
        wideCornerSettings.gesture.cornerTriggerPercent = 0.15
        var wideCornerRecognizer = GestureRecognizer(settings: wideCornerSettings)

        XCTAssertNil(wideCornerRecognizer.process(frame([touch(1, x: 0.12, y: 0.88)], 2.00)))
        XCTAssertNil(wideCornerRecognizer.process(frame([], 2.10)))
        XCTAssertNil(wideCornerRecognizer.process(frame([touch(2, x: 0.12, y: 0.88)], 2.20)))
        XCTAssertEqual(wideCornerRecognizer.process(frame([], 2.30)), .cornerDoubleTap(corner: .topLeft))
    }

    private func assertInvalidatingEvent(_ event: NormalizedInputEvent) {
        var recognizer = CornerDoubleTapRecognizer()
        performSingleTap(&recognizer, id: 1, x: 0.05, y: 0.95, start: 1.00)
        XCTAssertNil(recognizer.process(frame([touch(2, x: 0.05, y: 0.95)], 1.20), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(event, cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], 1.25), cornerWidthPercent: 0.10))
    }

    private func performSingleTap(
        _ recognizer: inout CornerDoubleTapRecognizer,
        id: Int,
        x: Double,
        y: Double,
        start: Double
    ) {
        XCTAssertNil(recognizer.process(frame([touch(id, x: x, y: y)], start), cornerWidthPercent: 0.10))
        XCTAssertNil(recognizer.process(frame([], start + 0.10), cornerWidthPercent: 0.10))
    }

    private func frame(_ touches: [PhysicalTouch], _ timestamp: Double) -> NormalizedInputEvent {
        .physicalTouchFrame(touches: touches, timestamp: timestamp)
    }

    private func touch(_ id: Int, x: Double, y: Double) -> PhysicalTouch {
        PhysicalTouch(id: id, x: x, y: y)
    }
}
