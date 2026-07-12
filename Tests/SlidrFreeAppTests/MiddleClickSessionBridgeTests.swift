import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class MiddleClickSessionBridgeTests: XCTestCase {
    func testCompletedTapClaimsBeforePhysicalDownAndExcludesPhysical() {
        let time = 10.0
        let bridge = MiddleClickSessionBridge(generation: 7, now: { time })
        bridge.applyTouchUpdate(active(session: 41, generation: 7, sequence: 1, receivedAt: time))
        bridge.applyTouchUpdate(completedTap(session: 41, generation: 7, sequence: 2, receivedAt: time))

        XCTAssertTrue(bridge.claimTap(sessionID: 41, generation: 7))
        XCTAssertFalse(bridge.claimTap(sessionID: 41, generation: 7))
        XCTAssertFalse(bridge.beginPhysical(sourceButton: 0, eventNumber: 90, generation: 7))
    }

    func testPhysicalDownClaimsBeforeTapAndExcludesTap() {
        let bridge = MiddleClickSessionBridge(generation: 3, now: { 4.0 })
        bridge.applyTouchUpdate(active(session: 8, generation: 3, sequence: 1, receivedAt: 3.9))

        XCTAssertTrue(bridge.beginPhysical(sourceButton: 1, eventNumber: 55, generation: 3))
        bridge.applyTouchUpdate(completedTap(session: 8, generation: 3, sequence: 2, receivedAt: 4.0))

        XCTAssertFalse(bridge.claimTap(sessionID: 8, generation: 3))
        XCTAssertTrue(bridge.finishPhysical(sourceButton: 1, eventNumber: 55, generation: 3))
    }

    func testChordOlderThanFreshnessWindowDoesNotBeginPhysical() {
        var time = 1.0
        let bridge = MiddleClickSessionBridge(generation: 2, now: { time })
        bridge.applyTouchUpdate(active(session: 1, generation: 2, sequence: 1, receivedAt: 1.0))

        time = 1.150_001

        XCTAssertFalse(bridge.beginPhysical(sourceButton: 0, eventNumber: 1, generation: 2))
    }

    func testFreshnessBoundaryAllowsPhysicalDown() {
        let bridge = MiddleClickSessionBridge(generation: 2, now: { 1.15 })
        bridge.applyTouchUpdate(active(session: 1, generation: 2, sequence: 1, receivedAt: 1.0))

        XCTAssertTrue(bridge.beginPhysical(sourceButton: 0, eventNumber: 1, generation: 2))
    }

    func testPendingStreamRequiresMatchingButtonEventNumberAndGeneration() {
        let bridge = MiddleClickSessionBridge(generation: 9, now: { 2.0 })
        bridge.applyTouchUpdate(active(session: 12, generation: 9, sequence: 1, receivedAt: 2.0))
        XCTAssertTrue(bridge.beginPhysical(sourceButton: 0, eventNumber: 101, generation: 9))

        XCTAssertFalse(bridge.continueDrag(sourceButton: 1, eventNumber: 101, generation: 9))
        XCTAssertFalse(bridge.continueDrag(sourceButton: 0, eventNumber: 102, generation: 9))
        XCTAssertFalse(bridge.continueDrag(sourceButton: 0, eventNumber: 101, generation: 8))
        XCTAssertTrue(bridge.continueDrag(sourceButton: 0, eventNumber: 101, generation: 9))

        XCTAssertFalse(bridge.finishPhysical(sourceButton: 1, eventNumber: 101, generation: 9))
        XCTAssertFalse(bridge.finishPhysical(sourceButton: 0, eventNumber: 102, generation: 9))
        XCTAssertFalse(bridge.finishPhysical(sourceButton: 0, eventNumber: 101, generation: 8))
        XCTAssertTrue(bridge.finishPhysical(sourceButton: 0, eventNumber: 101, generation: 9))
        XCTAssertFalse(bridge.finishPhysical(sourceButton: 0, eventNumber: 101, generation: 9))
    }

    func testSecondDownPassesWhileFirstDownRemainsPending() {
        let bridge = MiddleClickSessionBridge(generation: 5, now: { 8.0 })
        bridge.applyTouchUpdate(active(session: 3, generation: 5, sequence: 1, receivedAt: 8.0))
        XCTAssertTrue(bridge.beginPhysical(sourceButton: 0, eventNumber: 70, generation: 5))

        XCTAssertFalse(bridge.beginPhysical(sourceButton: 1, eventNumber: 71, generation: 5))
        XCTAssertTrue(bridge.finishPhysical(sourceButton: 0, eventNumber: 70, generation: 5))
    }

    func testCompletedPhysicalSessionAllowsNewSessionToBegin() {
        let bridge = MiddleClickSessionBridge(generation: 5, now: { 8.0 })
        bridge.applyTouchUpdate(active(session: 3, generation: 5, sequence: 1, receivedAt: 8.0))
        XCTAssertTrue(bridge.beginPhysical(sourceButton: 0, eventNumber: 70, generation: 5))
        XCTAssertTrue(bridge.finishPhysical(sourceButton: 0, eventNumber: 70, generation: 5))

        bridge.applyTouchUpdate(active(session: 4, generation: 5, sequence: 2, receivedAt: 8.0))

        XCTAssertTrue(bridge.beginPhysical(sourceButton: 1, eventNumber: 71, generation: 5))
    }

    func testClaimedTapSessionCannotBeReopenedByLaterUpdateForSameSession() {
        let bridge = MiddleClickSessionBridge(generation: 7, now: { 10.0 })
        bridge.applyTouchUpdate(active(session: 41, generation: 7, sequence: 1, receivedAt: 10.0))
        bridge.applyTouchUpdate(completedTap(session: 41, generation: 7, sequence: 2, receivedAt: 10.0))
        XCTAssertTrue(bridge.claimTap(sessionID: 41, generation: 7))

        bridge.applyTouchUpdate(active(session: 41, generation: 7, sequence: 3, receivedAt: 10.0))

        XCTAssertFalse(bridge.beginPhysical(sourceButton: 0, eventNumber: 90, generation: 7))
    }

    func testObsoleteAndNonIncreasingTouchUpdatesCannotReplaceOpenSession() {
        let bridge = MiddleClickSessionBridge(generation: 4, now: { 3.0 })
        bridge.applyTouchUpdate(active(session: 2, generation: 4, sequence: 2, receivedAt: 3.0))
        bridge.applyTouchUpdate(active(session: 9, generation: 3, sequence: 3, receivedAt: 3.0))
        bridge.applyTouchUpdate(active(session: 9, generation: 4, sequence: 2, receivedAt: 3.0))

        XCTAssertTrue(bridge.beginPhysical(sourceButton: 0, eventNumber: 10, generation: 4))
    }

    func testQuiesceExtractsPendingReleaseOnceAndAdvancesGeneration() {
        let bridge = MiddleClickSessionBridge(generation: 11, now: { 5.0 })
        bridge.applyTouchUpdate(active(session: 6, generation: 11, sequence: 1, receivedAt: 5.0))
        XCTAssertTrue(bridge.beginPhysical(sourceButton: 1, eventNumber: 88, generation: 11))

        XCTAssertEqual(
            bridge.quiesce(),
            MiddleClickPendingRelease(sourceButton: 1, eventNumber: 88, generation: 11)
        )
        XCTAssertNil(bridge.quiesce())
        XCTAssertFalse(bridge.finishPhysical(sourceButton: 1, eventNumber: 88, generation: 11))
        XCTAssertFalse(bridge.beginPhysical(sourceButton: 0, eventNumber: 89, generation: 11))
        XCTAssertEqual(bridge.generation, 12)
    }

    private func active(
        session: UInt64,
        generation: UInt64,
        sequence: UInt64,
        receivedAt: Double
    ) -> MiddleClickTouchUpdate {
        MiddleClickTouchUpdate(
            sessionID: session,
            chordActive: true,
            tapCandidate: false,
            generation: generation,
            sequence: sequence,
            receivedAt: receivedAt,
            terminalReason: nil
        )
    }

    private func completedTap(
        session: UInt64,
        generation: UInt64,
        sequence: UInt64,
        receivedAt: Double
    ) -> MiddleClickTouchUpdate {
        MiddleClickTouchUpdate(
            sessionID: session,
            chordActive: false,
            tapCandidate: true,
            generation: generation,
            sequence: sequence,
            receivedAt: receivedAt,
            terminalReason: .completed
        )
    }
}
