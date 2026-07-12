import CoreGraphics
import SlidrFreeCore
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

    func testConsecutiveDisableNotificationsQuiesceAndStartRecoveryOnlyOnceThenFailOpen() throws {
        let bridge = MiddleClickSessionBridge(generation: 1, now: { 10 })
        bridge.applyTouchUpdate(
            MiddleClickTouchUpdate(
                sessionID: 7,
                chordActive: true,
                tapCandidate: false,
                generation: 1,
                sequence: 1,
                receivedAt: 10,
                terminalReason: nil
            )
        )
        let reducer = MouseButtonEventReducer(
            bridge: bridge,
            generation: 1,
            ownMarker: MiddleClickEventIdentity.marker
        )
        var scheduledRecoveryCount = 0
        let recovery = MouseButtonEventTapRecoveryCoordinator(
            enable: {},
            isEnabled: { false },
            schedule: { _, _ in scheduledRecoveryCount += 1 },
            status: { _ in }
        )
        var releases: [MiddleClickPendingRelease] = []
        let context = MouseButtonEventTapContext(
            reducer: reducer,
            releaseHandler: { releases.append($0) },
            statusHandler: { _ in },
            recovery: recovery
        )

        let down = try XCTUnwrap(CGEvent(source: nil))
        down.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        down.setIntegerValueField(.mouseEventNumber, value: 42)
        _ = context.handle(type: .leftMouseDown, event: down)

        let firstDisable = try XCTUnwrap(CGEvent(source: nil))
        XCTAssertNil(context.handle(type: .tapDisabledByTimeout, event: firstDisable))
        XCTAssertEqual(bridge.generation, 2)
        XCTAssertEqual(scheduledRecoveryCount, 1)
        XCTAssertEqual(releases.count, 1)

        let secondDisable = try XCTUnwrap(CGEvent(source: nil))
        XCTAssertNil(context.handle(type: .tapDisabledByUserInput, event: secondDisable))
        XCTAssertEqual(bridge.generation, 2, "later disable sentinels must not re-enter the reducer")
        XCTAssertEqual(scheduledRecoveryCount, 1, "later disable sentinels must not schedule recovery again")
        XCTAssertEqual(releases.count, 1)

        let ordinary = try XCTUnwrap(CGEvent(source: nil))
        ordinary.type = .rightMouseDown
        let returned = context.handle(type: .rightMouseDown, event: ordinary)?.takeUnretainedValue()
        XCTAssertTrue(returned === ordinary, "ordinary mouse input must fail open after quiesce")
        XCTAssertEqual(bridge.generation, 2)
        XCTAssertEqual(scheduledRecoveryCount, 1)
    }

    func testDoubleStopCompletesBothCallers() {
        let tap = makeUnstartedTap(generation: 10)
        let first = expectation(description: "first stop")
        let second = expectation(description: "second stop")

        tap.stop { first.fulfill() }
        tap.stop { second.fulfill() }

        wait(for: [first, second], timeout: 1)
    }

    func testStopCompletionCanReleaseLastReferenceWithoutDeadlock() {
        var tap: MouseButtonEventTap? = makeUnstartedTap(generation: 20)
        let releasedTap = WeakReference(tap)
        let stopped = expectation(description: "stop completion")

        tap?.stop {
            tap = nil
            stopped.fulfill()
        }

        wait(for: [stopped], timeout: 1)
        XCTAssertNil(releasedTap.value)
    }

    private func makeUnstartedTap(generation: UInt64) -> MouseButtonEventTap {
        let bridge = MiddleClickSessionBridge(generation: generation, now: { 0 })
        let reducer = MouseButtonEventReducer(
            bridge: bridge,
            generation: generation,
            ownMarker: MiddleClickEventIdentity.marker
        )
        return MouseButtonEventTap(reducer: reducer)
    }
}

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}
