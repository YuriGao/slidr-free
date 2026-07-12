import CoreGraphics
import XCTest
@testable import SlidrFreeApp

final class MouseButtonEventTapTests: XCTestCase {
    func testMaskIncludesRequiredMouseStreamAndDisableNotifications() {
        let mouseTypes: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged
        ]

        for type in mouseTypes {
            XCTAssertNotEqual(MouseButtonEventTap.eventMask & (1 << type.rawValue), 0)
        }
        XCTAssertTrue(MouseButtonEventTap.handledEventTypes.contains(.tapDisabledByTimeout))
        XCTAssertTrue(MouseButtonEventTap.handledEventTypes.contains(.tapDisabledByUserInput))
    }

    func testRecoveryRetriesAtOneHundredMillisecondsAndRequiresExternalRestartOnSuccess() {
        var enableCount = 0
        var enabledResults = [false, true]
        var scheduledDelays: [TimeInterval] = []
        var scheduled: [() -> Void] = []
        var statuses: [MouseButtonEventTapStatus] = []
        let coordinator = MouseButtonEventTapRecoveryCoordinator(
            enable: { enableCount += 1 },
            isEnabled: { enabledResults.removeFirst() },
            schedule: { delay, work in
                scheduledDelays.append(delay)
                scheduled.append(work)
            },
            status: { statuses.append($0) }
        )

        coordinator.recover()
        XCTAssertEqual(scheduledDelays, [0.1])
        scheduled.removeFirst()()
        XCTAssertEqual(enableCount, 1)
        XCTAssertEqual(scheduledDelays, [0.1, 0.1])
        scheduled.removeFirst()()

        XCTAssertEqual(enableCount, 2)
        XCTAssertEqual(statuses, [.recoveryRequiresPipelineRestart])
    }

    func testRecoveryEntersDegradedAfterThirdFailedVerifiedAttempt() {
        var enableCount = 0
        var scheduled: [() -> Void] = []
        var statuses: [MouseButtonEventTapStatus] = []
        let coordinator = MouseButtonEventTapRecoveryCoordinator(
            enable: { enableCount += 1 },
            isEnabled: { false },
            schedule: { _, work in scheduled.append(work) },
            status: { statuses.append($0) }
        )

        coordinator.recover()
        while !scheduled.isEmpty {
            scheduled.removeFirst()()
        }

        XCTAssertEqual(enableCount, 3)
        XCTAssertEqual(statuses, [.degraded])
    }

    func testQuiesceAndStopCompleteWithoutCreatingLiveEventTap() {
        let bridge = MiddleClickSessionBridge(generation: 1, now: { 0 })
        let reducer = MouseButtonEventReducer(
            bridge: bridge,
            generation: 1,
            ownMarker: MiddleClickEventIdentity.marker
        )
        let tap = MouseButtonEventTap(reducer: reducer)
        let quiesced = expectation(description: "quiesced")
        let stopped = expectation(description: "stopped")

        tap.quiesce {
            XCTAssertEqual(bridge.generation, 2)
            quiesced.fulfill()
            tap.stop {
                XCTAssertEqual(bridge.generation, 2, "stop after quiesce must not advance twice")
                stopped.fulfill()
            }
        }

        wait(for: [quiesced, stopped], timeout: 1)
    }

    func testDeinitSafelyQuiescesWithoutExplicitStop() {
        let bridge = MiddleClickSessionBridge(generation: 5, now: { 0 })
        weak var releasedTap: MouseButtonEventTap?

        autoreleasepool {
            let reducer = MouseButtonEventReducer(
                bridge: bridge,
                generation: 5,
                ownMarker: MiddleClickEventIdentity.marker
            )
            let tap = MouseButtonEventTap(reducer: reducer)
            releasedTap = tap
        }

        XCTAssertNil(releasedTap)
        XCTAssertEqual(bridge.generation, 6)
    }
}
