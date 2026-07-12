import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class PhysicalTouchAdapterTests: XCTestCase {
    func testNilBufferZeroCountBecomesEmptyUpdate() {
        let adapter = PhysicalTouchAdapter()

        let update = adapter.adapt(
            count: 0,
            touches: nil,
            generation: 7,
            sequence: 11,
            timestamp: 2.0,
            receivedAt: 20.0
        )

        XCTAssertEqual(
            update,
            .empty(generation: 7, sequence: 11, timestamp: 2.0, receivedAt: 20.0)
        )
    }

    func testMissingNonEmptyBufferBecomesCancellation() {
        let adapter = PhysicalTouchAdapter()

        let update = adapter.adapt(
            count: 1,
            touches: nil,
            generation: 7,
            sequence: 12,
            timestamp: 2.1,
            receivedAt: 20.1
        )

        XCTAssertEqual(
            update,
            .cancel(generation: 7, sequence: 12, receivedAt: 20.1, reason: .missingBuffer)
        )
    }

    func testNegativeCountBecomesInvalidCountCancellation() {
        let adapter = PhysicalTouchAdapter()

        let update = adapter.adapt(
            count: -1,
            touches: nil,
            generation: 8,
            sequence: 1,
            timestamp: 3.0,
            receivedAt: 30.0
        )

        XCTAssertEqual(
            update,
            .cancel(generation: 8, sequence: 1, receivedAt: 30.0, reason: .invalidTouchCount)
        )
    }

    func testCountAboveMaximumBecomesInvalidCountCancellation() {
        let adapter = PhysicalTouchAdapter(maximumTouchCount: 4)

        let update = adapter.adapt(
            count: 5,
            touches: [],
            generation: 8,
            sequence: 2,
            timestamp: 3.1,
            receivedAt: 30.1
        )

        XCTAssertEqual(
            update,
            .cancel(generation: 8, sequence: 2, receivedAt: 30.1, reason: .invalidTouchCount)
        )
    }

    func testTouchValueCountMismatchBecomesInvalidCountCancellation() {
        let adapter = PhysicalTouchAdapter()

        let update = adapter.adapt(
            count: 2,
            touches: [touch(1)],
            generation: 8,
            sequence: 3,
            timestamp: 3.2,
            receivedAt: 30.2
        )

        XCTAssertEqual(
            update,
            .cancel(generation: 8, sequence: 3, receivedAt: 30.2, reason: .invalidTouchCount)
        )
    }

    func testValidFramePreservesValuesAndMetadata() {
        let adapter = PhysicalTouchAdapter()
        let touches = [
            touch(10, x: 0.1, y: 0.2, pressure: 0.3, state: 4),
            touch(11, x: 0.4, y: 0.5, pressure: 0.6, state: 5)
        ]

        let update = adapter.adapt(
            count: 2,
            touches: touches,
            generation: 9,
            sequence: 99,
            timestamp: 4.5,
            receivedAt: 40.5
        )

        XCTAssertEqual(
            update,
            .frame(
                generation: 9,
                sequence: 99,
                timestamp: 4.5,
                receivedAt: 40.5,
                touches: touches
            )
        )
    }

    private func touch(
        _ id: Int,
        x: Double = 0.2,
        y: Double = 0.3,
        pressure: Double? = nil,
        state: Int? = nil
    ) -> PhysicalTouch {
        PhysicalTouch(id: id, x: x, y: y, pressure: pressure, state: state)
    }
}
