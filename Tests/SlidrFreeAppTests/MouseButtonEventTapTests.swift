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
        let feedback = EventTapHapticFeedbackSpy()
        let context = MouseButtonEventTapContext(
            reducer: reducer,
            releaseHandler: { releases.append($0) },
            statusHandler: { _ in },
            recovery: recovery,
            hapticFeedback: feedback
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
        XCTAssertEqual(feedback.performCount, 0)

        let secondDisable = try XCTUnwrap(CGEvent(source: nil))
        XCTAssertNil(context.handle(type: .tapDisabledByUserInput, event: secondDisable))
        XCTAssertEqual(bridge.generation, 2, "later disable sentinels must not re-enter the reducer")
        XCTAssertEqual(scheduledRecoveryCount, 1, "later disable sentinels must not schedule recovery again")
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(feedback.performCount, 0)

        let ordinary = try XCTUnwrap(CGEvent(source: nil))
        ordinary.type = .rightMouseDown
        let returned = context.handle(type: .rightMouseDown, event: ordinary)?.takeUnretainedValue()
        XCTAssertTrue(returned === ordinary, "ordinary mouse input must fail open after quiesce")
        XCTAssertEqual(bridge.generation, 2)
        XCTAssertEqual(scheduledRecoveryCount, 1)
        XCTAssertEqual(feedback.performCount, 0)
    }

    func testMatchingPhysicalDownAndDragRequestNoHapticAndFirstTransformedUpRequestsOnce() throws {
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
        let feedback = EventTapHapticFeedbackSpy()
        let context = MouseButtonEventTapContext(
            reducer: MouseButtonEventReducer(
                bridge: bridge,
                generation: 1,
                ownMarker: MiddleClickEventIdentity.marker
            ),
            releaseHandler: { _ in },
            statusHandler: { _ in },
            hapticFeedback: feedback
        )

        let down = try makeMouseEvent(button: 0, eventNumber: 42)
        let transformedDown = context.handle(type: .leftMouseDown, event: down)?.takeUnretainedValue()
        XCTAssertEqual(transformedDown?.type, .otherMouseDown)
        XCTAssertEqual(feedback.performCount, 0)

        let dragged = try makeMouseEvent(button: 0, eventNumber: 42)
        let transformedDrag = context.handle(type: .leftMouseDragged, event: dragged)?.takeUnretainedValue()
        XCTAssertEqual(transformedDrag?.type, .otherMouseDragged)
        XCTAssertEqual(feedback.performCount, 0)

        let up = try makeMouseEvent(button: 0, eventNumber: 42)
        let transformedUp = context.handle(type: .leftMouseUp, event: up)?.takeUnretainedValue()
        XCTAssertEqual(transformedUp?.type, .otherMouseUp)
        XCTAssertEqual(feedback.performCount, 1)

        let duplicateUp = try makeMouseEvent(button: 0, eventNumber: 42)
        let unchangedDuplicate = context.handle(type: .leftMouseUp, event: duplicateUp)?.takeUnretainedValue()
        XCTAssertTrue(unchangedDuplicate === duplicateUp)
        XCTAssertEqual(feedback.performCount, 1)
    }

    func testOrdinaryPhysicalClickWithoutChordPassesUnchangedWithoutHaptic() throws {
        let feedback = EventTapHapticFeedbackSpy()
        let context = makeContext(
            bridge: MiddleClickSessionBridge(generation: 1, now: { 10 }),
            feedback: feedback
        )

        let down = try makeMouseEvent(button: 0, eventNumber: 43)
        let unchangedDown = context.handle(type: .leftMouseDown, event: down)?.takeUnretainedValue()
        XCTAssertTrue(unchangedDown === down)

        let up = try makeMouseEvent(button: 0, eventNumber: 43)
        let unchangedUp = context.handle(type: .leftMouseUp, event: up)?.takeUnretainedValue()
        XCTAssertTrue(unchangedUp === up)
        XCTAssertEqual(feedback.performCount, 0)
    }

    func testStaleChordPassesPhysicalClickUnchangedWithoutHaptic() throws {
        let bridge = MiddleClickSessionBridge(generation: 1, now: { 10.2 })
        bridge.applyTouchUpdate(
            MiddleClickTouchUpdate(
                sessionID: 8,
                chordActive: true,
                tapCandidate: false,
                generation: 1,
                sequence: 1,
                receivedAt: 10,
                terminalReason: nil
            )
        )
        let feedback = EventTapHapticFeedbackSpy()
        let context = makeContext(bridge: bridge, feedback: feedback)

        let down = try makeMouseEvent(button: 0, eventNumber: 44)
        let unchangedDown = context.handle(type: .leftMouseDown, event: down)?.takeUnretainedValue()
        XCTAssertTrue(unchangedDown === down)

        let up = try makeMouseEvent(button: 0, eventNumber: 44)
        let unchangedUp = context.handle(type: .leftMouseUp, event: up)?.takeUnretainedValue()
        XCTAssertTrue(unchangedUp === up)
        XCTAssertEqual(feedback.performCount, 0)
    }

    func testCancelledTouchSessionPassesPhysicalClickUnchangedWithoutHaptic() throws {
        let bridge = MiddleClickSessionBridge(generation: 1, now: { 10 })
        bridge.applyTouchUpdate(
            MiddleClickTouchUpdate(
                sessionID: 9,
                chordActive: false,
                tapCandidate: false,
                generation: 1,
                sequence: 1,
                receivedAt: 10,
                terminalReason: .cancelled(.monitorStopped)
            )
        )
        let feedback = EventTapHapticFeedbackSpy()
        let context = makeContext(bridge: bridge, feedback: feedback)

        let down = try makeMouseEvent(button: 1, eventNumber: 45)
        let unchangedDown = context.handle(type: .rightMouseDown, event: down)?.takeUnretainedValue()
        XCTAssertTrue(unchangedDown === down)

        let up = try makeMouseEvent(button: 1, eventNumber: 45)
        let unchangedUp = context.handle(type: .rightMouseUp, event: up)?.takeUnretainedValue()
        XCTAssertTrue(unchangedUp === up)
        XCTAssertEqual(feedback.performCount, 0)
    }

    func testTaggedSyntheticTapEventPassesUnchangedWithoutHaptic() throws {
        let feedback = EventTapHapticFeedbackSpy()
        let context = MouseButtonEventTapContext(
            reducer: MouseButtonEventReducer(
                bridge: MiddleClickSessionBridge(generation: 1, now: { 0 }),
                generation: 1,
                ownMarker: MiddleClickEventIdentity.marker
            ),
            releaseHandler: { _ in },
            statusHandler: { _ in },
            hapticFeedback: feedback
        )
        let event = try makeMouseEvent(
            button: 2,
            eventNumber: 99,
            marker: MiddleClickEventIdentity.marker
        )

        let output = context.handle(type: .otherMouseUp, event: event)?.takeUnretainedValue()

        XCTAssertTrue(output === event)
        XCTAssertEqual(feedback.performCount, 0)
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

    private func makeContext(
        bridge: MiddleClickSessionBridge,
        feedback: EventTapHapticFeedbackSpy
    ) -> MouseButtonEventTapContext {
        MouseButtonEventTapContext(
            reducer: MouseButtonEventReducer(
                bridge: bridge,
                generation: 1,
                ownMarker: MiddleClickEventIdentity.marker
            ),
            releaseHandler: { _ in },
            statusHandler: { _ in },
            hapticFeedback: feedback
        )
    }

    private func makeMouseEvent(
        button: Int64,
        eventNumber: Int64,
        marker: Int64 = 0
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        return event
    }
}

private final class EventTapHapticFeedbackSpy: MiddleClickHapticFeedbackPerforming {
    private(set) var performCount = 0

    func performSuccess() {
        performCount += 1
    }
}

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}
