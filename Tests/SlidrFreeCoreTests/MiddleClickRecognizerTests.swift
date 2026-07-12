import XCTest
@testable import SlidrFreeCore

final class MiddleClickRecognizerTests: XCTestCase {
    func testEachSupportedConfigurationAcceptsItsExactTouchCount() {
        for fingerCount in MiddleClickSettings.supportedFingerCounts {
            XCTAssertTrue(
                tapResult(configuredFingerCount: fingerCount, touchCount: fingerCount).tapCandidate,
                "Expected exact \(fingerCount)-finger Tap to qualify"
            )
        }
    }

    func testFourFingerConfigurationRejectsThreeAndFiveTouches() {
        XCTAssertFalse(tapResult(configuredFingerCount: 4, touchCount: 3).tapCandidate)
        XCTAssertFalse(tapResult(configuredFingerCount: 4, touchCount: 5).tapCandidate)
    }

    func testTapDisabledStillTracksConfiguredFourFingerChord() {
        var recognizer = MiddleClickRecognizer(tapEnabled: false, fingerCount: 4)

        let qualified = recognizer.process(frame(
            sequence: 1,
            timestamp: 0.00,
            touches: touches(count: 4)
        ))
        let finished = recognizer.process(empty(sequence: 2, timestamp: 0.20))

        XCTAssertTrue(qualified.chordActive)
        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, MiddleClickTerminalReason.completed)
    }

    func testExactThreePlacementQualificationAndReleaseProducesOneTapCandidate() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        let first = recognizer.process(.frame(
            generation: 1,
            sequence: 1,
            timestamp: 1.00,
            receivedAt: 10.00,
            touches: [touch(1)]
        ))
        let qualified = recognizer.process(.frame(
            generation: 1,
            sequence: 2,
            timestamp: 1.05,
            receivedAt: 10.05,
            touches: [touch(1), touch(2), touch(3)]
        ))
        let releasing = recognizer.process(.frame(
            generation: 1,
            sequence: 3,
            timestamp: 1.10,
            receivedAt: 10.10,
            touches: [touch(1), touch(2)]
        ))
        let finished = recognizer.process(.empty(
            generation: 1,
            sequence: 4,
            timestamp: 1.20,
            receivedAt: 10.20
        ))
        let duplicateEmpty = recognizer.process(.empty(
            generation: 1,
            sequence: 5,
            timestamp: 1.21,
            receivedAt: 10.21
        ))

        XCTAssertFalse(first.chordActive)
        XCTAssertTrue(qualified.chordActive)
        XCTAssertFalse(releasing.chordActive)
        XCTAssertFalse(releasing.tapCandidate)
        XCTAssertTrue(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .completed)
        XCTAssertFalse(duplicateEmpty.tapCandidate)
        XCTAssertNil(duplicateEmpty.sessionID)
    }

    func testPlacementEndingBeforeQualificationDoesNotProduceTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1)]))
        _ = recognizer.process(frame(sequence: 2, timestamp: 0.05, touches: [touch(1), touch(2)]))
        let finished = recognizer.process(empty(sequence: 3, timestamp: 0.10))

        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testCountAboveThreeInvalidatesSessionAndDeactivatesChord() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        let qualified = recognizer.process(frame(
            sequence: 1,
            timestamp: 0.00,
            touches: [touch(1), touch(2), touch(3)]
        ))
        let tooMany = recognizer.process(frame(
            sequence: 2,
            timestamp: 0.05,
            touches: [touch(1), touch(2), touch(3), touch(4)]
        ))
        let backToThree = recognizer.process(frame(
            sequence: 3,
            timestamp: 0.10,
            touches: [touch(1), touch(2), touch(3)]
        ))
        let finished = recognizer.process(empty(sequence: 4, timestamp: 0.15))

        XCTAssertTrue(qualified.chordActive)
        XCTAssertFalse(tooMany.chordActive)
        XCTAssertFalse(backToThree.chordActive)
        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testLaterIncreaseAfterReleaseInvalidatesTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1), touch(2), touch(3)]))
        _ = recognizer.process(frame(sequence: 2, timestamp: 0.05, touches: [touch(1), touch(2)]))
        let increased = recognizer.process(frame(sequence: 3, timestamp: 0.10, touches: [touch(1), touch(2), touch(3)]))
        let finished = recognizer.process(empty(sequence: 4, timestamp: 0.15))

        XCTAssertFalse(increased.chordActive)
        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testLaterIncreaseBelowThreeAfterReleaseAlsoInvalidatesTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1), touch(2), touch(3)]))
        _ = recognizer.process(frame(sequence: 2, timestamp: 0.05, touches: [touch(1), touch(2)]))
        _ = recognizer.process(frame(sequence: 3, timestamp: 0.10, touches: [touch(1)]))
        _ = recognizer.process(frame(sequence: 4, timestamp: 0.15, touches: [touch(1), touch(2)]))
        let finished = recognizer.process(empty(sequence: 5, timestamp: 0.20))

        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testDurationAtInclusiveBoundaryProducesTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1), touch(2), touch(3)]))
        let finished = recognizer.process(empty(sequence: 2, timestamp: 0.30))

        XCTAssertTrue(finished.tapCandidate)
    }

    func testDurationAboveBoundaryDoesNotProduceTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1), touch(2), touch(3)]))
        let finished = recognizer.process(empty(sequence: 2, timestamp: 0.300_001))

        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testDurationAtNextRepresentableValueAboveBoundaryDoesNotProduceTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1), touch(2), touch(3)]))
        let finished = recognizer.process(empty(sequence: 2, timestamp: Double(0.30).nextUp))

        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testDurationStartsAtFirstPlacementFrame() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1)]))
        _ = recognizer.process(frame(sequence: 2, timestamp: 0.25, touches: [touch(1), touch(2), touch(3)]))
        let finished = recognizer.process(empty(sequence: 3, timestamp: 0.31))

        XCTAssertFalse(finished.tapCandidate)
    }

    func testCentroidMovementAtInclusiveBoundaryProducesTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: coincidentTouches(x: 0.00)))
        _ = recognizer.process(frame(sequence: 2, timestamp: 0.10, touches: coincidentTouches(x: 0.05)))
        let finished = recognizer.process(empty(sequence: 3, timestamp: 0.20))

        XCTAssertTrue(finished.tapCandidate)
    }

    func testMaximumCentroidMovementAboveBoundaryInvalidatesEvenAfterReturning() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: coincidentTouches(x: 0.00)))
        _ = recognizer.process(frame(sequence: 2, timestamp: 0.05, touches: coincidentTouches(x: 0.050_001)))
        _ = recognizer.process(frame(sequence: 3, timestamp: 0.10, touches: coincidentTouches(x: 0.00)))
        let finished = recognizer.process(empty(sequence: 4, timestamp: 0.20))

        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testCentroidMovementAtNextRepresentableValueAboveBoundaryDoesNotProduceTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: coincidentTouches(x: 0.00)))
        _ = recognizer.process(frame(sequence: 2, timestamp: 0.10, touches: coincidentTouches(x: Double(0.05).nextUp)))
        let finished = recognizer.process(empty(sequence: 3, timestamp: 0.20))

        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testTouchIDReorderingKeepsQualifiedChordActive() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(
            sequence: 1,
            timestamp: 0.00,
            touches: [touch(1, x: 0.10), touch(2, x: 0.20), touch(3, x: 0.30)]
        ))
        let reordered = recognizer.process(frame(
            sequence: 2,
            timestamp: 0.10,
            touches: [touch(3, x: 0.30), touch(1, x: 0.10), touch(2, x: 0.20)]
        ))
        let finished = recognizer.process(empty(sequence: 3, timestamp: 0.20))

        XCTAssertTrue(reordered.chordActive)
        XCTAssertTrue(finished.tapCandidate)
    }

    func testTouchIDReplacementInvalidatesTapAndChord() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1), touch(2), touch(3)]))
        let replaced = recognizer.process(frame(sequence: 2, timestamp: 0.10, touches: [touch(1), touch(2), touch(4)]))
        let finished = recognizer.process(empty(sequence: 3, timestamp: 0.20))

        XCTAssertFalse(replaced.chordActive)
        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testNonIncreasingTimestampInvalidatesTapButKeepsStableChordActive() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 1.00, touches: [touch(1), touch(2), touch(3)]))
        let repeatedTimestamp = recognizer.process(frame(sequence: 2, timestamp: 1.00, touches: [touch(1), touch(2), touch(3)]))
        let finished = recognizer.process(empty(sequence: 3, timestamp: 1.10))

        XCTAssertTrue(repeatedTimestamp.chordActive)
        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testEmptyAtEqualTimestampInvalidatesTap() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        _ = recognizer.process(frame(sequence: 1, timestamp: 1.00, touches: [touch(1), touch(2), touch(3)]))
        let finished = recognizer.process(empty(sequence: 2, timestamp: 1.00))

        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .invalidated)
    }

    func testCancellationClosesSessionWithoutTapAndClearsState() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        let opened = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1), touch(2), touch(3)]))
        let cancelled = recognizer.process(.cancel(
            generation: 1,
            sequence: 2,
            receivedAt: 10.10,
            reason: .monitorStopped
        ))
        let emptyAfterCancellation = recognizer.process(empty(sequence: 3, timestamp: 0.20))

        XCTAssertEqual(cancelled.sessionID, opened.sessionID)
        XCTAssertFalse(cancelled.chordActive)
        XCTAssertFalse(cancelled.tapCandidate)
        XCTAssertEqual(cancelled.terminalReason, .cancelled(.monitorStopped))
        XCTAssertNil(emptyAfterCancellation.sessionID)
        XCTAssertNil(emptyAfterCancellation.terminalReason)
    }

    func testTapDisabledStillTracksChordButNeverProducesCandidate() {
        var recognizer = MiddleClickRecognizer(tapEnabled: false, fingerCount: 3)

        let qualified = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: [touch(1), touch(2), touch(3)]))
        let finished = recognizer.process(empty(sequence: 2, timestamp: 0.20))

        XCTAssertTrue(qualified.chordActive)
        XCTAssertFalse(finished.tapCandidate)
        XCTAssertEqual(finished.terminalReason, .completed)
    }

    func testSessionIDIncrementsOnlyWhenNewNonEmptySessionOpens() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        let idleEmpty = recognizer.process(empty(sequence: 1, timestamp: 0.00))
        let first = recognizer.process(frame(sequence: 2, timestamp: 0.10, touches: [touch(1)]))
        let continued = recognizer.process(frame(sequence: 3, timestamp: 0.20, touches: [touch(1), touch(2)]))
        let firstFinished = recognizer.process(empty(sequence: 4, timestamp: 0.25))
        let second = recognizer.process(frame(sequence: 5, timestamp: 0.30, touches: [touch(4)]))

        XCTAssertNil(idleEmpty.sessionID)
        XCTAssertEqual(continued.sessionID, first.sessionID)
        XCTAssertEqual(firstFinished.sessionID, first.sessionID)
        XCTAssertEqual(second.sessionID, first.sessionID.map { $0 + 1 })
    }

    func testOutputCarriesInputSequencingMetadata() {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 3)

        let output = recognizer.process(.frame(
            generation: 42,
            sequence: 99,
            timestamp: 1.00,
            receivedAt: 123.45,
            touches: [touch(1)]
        ))

        XCTAssertEqual(output.generation, 42)
        XCTAssertEqual(output.sequence, 99)
        XCTAssertEqual(output.receivedAt, 123.45)
    }

    private func frame(
        sequence: UInt64,
        timestamp: Double,
        touches: [PhysicalTouch]
    ) -> MiddleClickInputUpdate {
        .frame(
            generation: 1,
            sequence: sequence,
            timestamp: timestamp,
            receivedAt: 10.00 + timestamp,
            touches: touches
        )
    }

    private func empty(sequence: UInt64, timestamp: Double) -> MiddleClickInputUpdate {
        .empty(
            generation: 1,
            sequence: sequence,
            timestamp: timestamp,
            receivedAt: 10.00 + timestamp
        )
    }

    private func touch(_ id: Int, x: Double = 0.20, y: Double = 0.20) -> PhysicalTouch {
        PhysicalTouch(id: id, x: x, y: y)
    }

    private func touches(count: Int) -> [PhysicalTouch] {
        (1...count).map { touch($0) }
    }

    private func tapResult(configuredFingerCount: Int, touchCount: Int) -> MiddleClickTouchUpdate {
        var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: configuredFingerCount)
        _ = recognizer.process(frame(sequence: 1, timestamp: 0.00, touches: touches(count: touchCount)))
        return recognizer.process(empty(sequence: 2, timestamp: 0.20))
    }

    private func coincidentTouches(x: Double) -> [PhysicalTouch] {
        [touch(1, x: x), touch(2, x: x), touch(3, x: x)]
    }
}
