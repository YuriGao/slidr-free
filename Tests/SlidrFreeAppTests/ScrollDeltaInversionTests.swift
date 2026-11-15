import AppKit
import CoreGraphics
import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

/// Exercises the real Quartz field writes. The three scroll-delta views are
/// coupled (writing the line delta recomputes the point and fixed-point
/// deltas), so these tests exist to keep that ordering from regressing into a
/// half-inverted event.
final class ScrollDeltaInversionTests: XCTestCase {
    private func makeEvent(continuous: Bool, line: Int64, point: Int64, fixed: Double) -> CGEvent {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        )!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        // Line first: it recomputes the other two, which the next writes correct.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: point)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 2)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 9)
        return event
    }

    private func fields(_ event: CGEvent) -> (line: Int64, point: Int64, fixed: Double) {
        (
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        )
    }

    private func horizontalFields(_ event: CGEvent) -> (line: Int64, point: Int64, fixed: Double) {
        (
            event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
            event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        )
    }

    func testVerticalInversionFlipsEveryDeltaViewAndLeavesHorizontalAlone() {
        for continuous in [false, true] {
            let event = makeEvent(continuous: continuous, line: -3, point: -12, fixed: -3)
            XCTAssertEqual(fields(event).line, -3)
            XCTAssertEqual(fields(event).point, -12)
            XCTAssertEqual(fields(event).fixed, -3)

            ScrollDirectionTapContext.invert(
                ScrollDirectionDecision(invertsVertical: true, invertsHorizontal: false),
                in: event
            )

            XCTAssertEqual(fields(event).line, 3)
            XCTAssertEqual(fields(event).point, 12)
            XCTAssertEqual(fields(event).fixed, 3)
            XCTAssertEqual(horizontalFields(event).line, 2)
            XCTAssertEqual(horizontalFields(event).point, 9)

            let nsEvent = NSEvent(cgEvent: event)!
            XCTAssertEqual(nsEvent.deltaY, 3)
            XCTAssertEqual(nsEvent.scrollingDeltaY, continuous ? 12 : 3)
        }
    }

    func testHorizontalInversionOnlyTouchesTheHorizontalAxis() {
        let event = makeEvent(continuous: false, line: -3, point: -12, fixed: -3)

        ScrollDirectionTapContext.invert(
            ScrollDirectionDecision(invertsVertical: false, invertsHorizontal: true),
            in: event
        )

        XCTAssertEqual(fields(event).line, -3)
        XCTAssertEqual(fields(event).point, -12)
        XCTAssertEqual(horizontalFields(event).line, -2)
        XCTAssertEqual(horizontalFields(event).point, -9)
        XCTAssertEqual(horizontalFields(event).fixed, -2)
    }

    func testInvertingBothAxesFlipsBoth() {
        let event = makeEvent(continuous: true, line: -3, point: -12, fixed: -3)

        ScrollDirectionTapContext.invert(
            ScrollDirectionDecision(invertsVertical: true, invertsHorizontal: true),
            in: event
        )

        XCTAssertEqual(fields(event).line, 3)
        XCTAssertEqual(fields(event).point, 12)
        XCTAssertEqual(horizontalFields(event).line, -2)
        XCTAssertEqual(horizontalFields(event).point, -9)
    }

    func testDoubleInversionRestoresTheOriginalEvent() {
        let event = makeEvent(continuous: true, line: -3, point: -12, fixed: -3)
        let before = fields(event)
        let beforeHorizontal = horizontalFields(event)
        let decision = ScrollDirectionDecision(invertsVertical: true, invertsHorizontal: true)

        ScrollDirectionTapContext.invert(decision, in: event)
        ScrollDirectionTapContext.invert(decision, in: event)

        XCTAssertEqual(fields(event).line, before.line)
        XCTAssertEqual(fields(event).point, before.point)
        XCTAssertEqual(fields(event).fixed, before.fixed)
        XCTAssertEqual(horizontalFields(event).line, beforeHorizontal.line)
        XCTAssertEqual(horizontalFields(event).point, beforeHorizontal.point)
    }

    func testIdentityDecisionLeavesTheEventUntouched() {
        let event = makeEvent(continuous: false, line: -3, point: -12, fixed: -3)

        ScrollDirectionTapContext.invert(.identity, in: event)

        XCTAssertEqual(fields(event).line, -3)
        XCTAssertEqual(fields(event).point, -12)
        XCTAssertEqual(fields(event).fixed, -3)
    }

    func testPhaseOnlyFramesHaveNothingToInvert() {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)!

        ScrollDirectionTapContext.invert(
            ScrollDirectionDecision(invertsVertical: true, invertsHorizontal: true),
            in: event
        )

        XCTAssertEqual(fields(event).line, 0)
        XCTAssertEqual(fields(event).point, 0)
        XCTAssertEqual(fields(event).fixed, 0)
        XCTAssertEqual(horizontalFields(event).line, 0)
        XCTAssertEqual(horizontalFields(event).point, 0)
    }
}
