import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class MouseButtonEventReducerTests: XCTestCase {
    private let ownMarker: Int64 = 0x534C_4944_5246_5245

    func testOrdinaryEventPassesWithoutFreshChord() {
        let (reducer, _) = makeReducer()

        XCTAssertEqual(reducer.reduce(event(.down, button: 0, number: 1)), .passUnchanged)
    }

    func testMatchingDownDraggedAndUpTransformToMiddleButtonWithClickStateOne() {
        let (reducer, bridge) = makeReducer()
        bridge.applyTouchUpdate(active(session: 7))

        XCTAssertEqual(
            reducer.reduce(event(.down, button: 0, number: 42)),
            .transform(.init(kind: .down, targetButton: 2, eventNumber: 42, clickState: 1))
        )
        XCTAssertEqual(
            reducer.reduce(event(.dragged, button: 0, number: 42)),
            .transform(.init(kind: .dragged, targetButton: 2, eventNumber: 42, clickState: 1))
        )
        XCTAssertEqual(
            reducer.reduce(event(.up, button: 0, number: 42)),
            .transform(.init(kind: .up, targetButton: 2, eventNumber: 42, clickState: 1))
        )
        XCTAssertEqual(reducer.reduce(event(.up, button: 0, number: 42)), .passUnchanged)
    }

    func testTaggedSlidrFreeEventAlwaysPassesThrough() {
        let (reducer, bridge) = makeReducer()
        bridge.applyTouchUpdate(active(session: 7))

        XCTAssertEqual(
            reducer.reduce(event(.down, button: 0, number: 42, marker: ownMarker)),
            .passUnchanged
        )

        XCTAssertEqual(
            reducer.reduce(event(.down, button: 0, number: 42)),
            .transform(.init(kind: .down, targetButton: 2, eventNumber: 42, clickState: 1))
        )
    }

    func testMixedButtonAndEventNumberDoNotConsumePendingStream() {
        let (reducer, bridge) = makeReducer()
        bridge.applyTouchUpdate(active(session: 10))
        XCTAssertEqual(
            reducer.reduce(event(.down, button: 1, number: 90)),
            .transform(.init(kind: .down, targetButton: 2, eventNumber: 90, clickState: 1))
        )

        XCTAssertEqual(reducer.reduce(event(.dragged, button: 0, number: 90)), .passUnchanged)
        XCTAssertEqual(reducer.reduce(event(.up, button: 1, number: 91)), .passUnchanged)
        XCTAssertEqual(
            reducer.reduce(event(.up, button: 1, number: 90)),
            .transform(.init(kind: .up, targetButton: 2, eventNumber: 90, clickState: 1))
        )
    }

    func testSecondDownPassesAndOriginalPendingStreamStillCompletes() {
        let (reducer, bridge) = makeReducer()
        bridge.applyTouchUpdate(active(session: 15))
        XCTAssertNotEqual(reducer.reduce(event(.down, button: 0, number: 100)), .passUnchanged)

        XCTAssertEqual(reducer.reduce(event(.down, button: 1, number: 101)), .passUnchanged)
        XCTAssertNotEqual(reducer.reduce(event(.up, button: 0, number: 100)), .passUnchanged)
    }

    func testTimeoutRequestsOnePendingReleaseThenEventTapReenable() {
        let (reducer, bridge) = makeReducer()
        bridge.applyTouchUpdate(active(session: 20))
        _ = reducer.reduce(event(.down, button: 0, number: 200))

        XCTAssertEqual(
            reducer.reduce(event(.tapDisabledByTimeout, button: -1, number: 0)),
            .requestSyntheticUp(
                MiddleClickPendingRelease(sourceButton: 0, eventNumber: 200, generation: 4),
                then: .reenableEventTap
            )
        )
        XCTAssertEqual(
            reducer.reduce(event(.tapDisabledByTimeout, button: -1, number: 0)),
            .reenableEventTap
        )
    }

    func testUserInputDisableAlsoQuiescesAndRequestsReenable() {
        let (reducer, _) = makeReducer()

        XCTAssertEqual(
            reducer.reduce(event(.tapDisabledByUserInput, button: -1, number: 0)),
            .reenableEventTap
        )
    }

    func testExplicitQuiesceExtractsPendingReleaseWithoutRequestingRecovery() {
        let (reducer, bridge) = makeReducer()
        bridge.applyTouchUpdate(active(session: 21))
        _ = reducer.reduce(event(.down, button: 1, number: 201))

        XCTAssertEqual(
            reducer.quiesce(),
            MiddleClickPendingRelease(sourceButton: 1, eventNumber: 201, generation: 4)
        )
        XCTAssertNil(reducer.quiesce())
    }

    func testFailedReenableAttemptsEnterDegradedStateAfterThirdTry() {
        XCTAssertEqual(MouseButtonEventReducer.decision(afterFailedReenableAttempt: 1), .reenableEventTap)
        XCTAssertEqual(MouseButtonEventReducer.decision(afterFailedReenableAttempt: 2), .reenableEventTap)
        XCTAssertEqual(MouseButtonEventReducer.decision(afterFailedReenableAttempt: 3), .enterDegradedState)
        XCTAssertEqual(MouseButtonEventReducer.decision(afterFailedReenableAttempt: 4), .enterDegradedState)
    }

    func testUnrecognizedKindPassesThrough() {
        let (reducer, _) = makeReducer()

        XCTAssertEqual(reducer.reduce(event(.other, button: 0, number: 1)), .passUnchanged)
    }

    private func makeReducer() -> (MouseButtonEventReducer, MiddleClickSessionBridge) {
        let bridge = MiddleClickSessionBridge(generation: 4, now: { 10.0 })
        return (
            MouseButtonEventReducer(bridge: bridge, generation: 4, ownMarker: ownMarker),
            bridge
        )
    }

    private func event(
        _ kind: MouseButtonEventMetadata.Kind,
        button: Int64,
        number: Int64,
        marker: Int64 = 0
    ) -> MouseButtonEventMetadata {
        MouseButtonEventMetadata(
            kind: kind,
            sourceButton: button,
            eventNumber: number,
            marker: marker
        )
    }

    private func active(session: UInt64) -> MiddleClickTouchUpdate {
        MiddleClickTouchUpdate(
            sessionID: session,
            chordActive: true,
            tapCandidate: false,
            generation: 4,
            sequence: 1,
            receivedAt: 10.0,
            terminalReason: nil
        )
    }
}
