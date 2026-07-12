import CoreGraphics
import XCTest
@testable import SlidrFreeApp

final class MouseButtonEventFactoryTests: XCTestCase {
    func testTransformDecisionChangesOnlyMouseIdentityFields() throws {
        let original = try XCTUnwrap(CGEvent(source: nil))
        original.type = .leftMouseDown
        original.location = CGPoint(x: 140, y: 280)
        original.timestamp = 123_456
        original.flags = [.maskShift, .maskCommand]
        original.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        original.setIntegerValueField(.mouseEventNumber, value: 77)
        original.setIntegerValueField(.mouseEventDeltaX, value: 31)

        let returned = MouseButtonEventFactory.event(
            for: .transform(.init(kind: .down, targetButton: 2, eventNumber: 77, clickState: 1)),
            original: original
        )

        XCTAssertTrue(returned === original)
        XCTAssertEqual(original.type, .otherMouseDown)
        XCTAssertEqual(original.getIntegerValueField(.mouseEventButtonNumber), 2)
        XCTAssertEqual(original.getIntegerValueField(.mouseEventClickState), 1)
        XCTAssertEqual(original.getIntegerValueField(.mouseEventNumber), 77)
        XCTAssertEqual(original.location, CGPoint(x: 140, y: 280))
        XCTAssertEqual(original.timestamp, 123_456)
        XCTAssertEqual(original.flags, [.maskShift, .maskCommand])
        XCTAssertEqual(original.getIntegerValueField(.mouseEventDeltaX), 31)
    }

    func testTransformMapsAllStreamKindsToOtherMouseEvents() throws {
        let cases: [(MouseButtonEventTransform.Kind, CGEventType)] = [
            (.down, .otherMouseDown),
            (.dragged, .otherMouseDragged),
            (.up, .otherMouseUp)
        ]

        for (kind, expectedType) in cases {
            let event = try XCTUnwrap(CGEvent(source: nil))
            _ = MouseButtonEventFactory.event(
                for: .transform(.init(kind: kind, targetButton: 2, eventNumber: 9, clickState: 1)),
                original: event
            )
            XCTAssertEqual(event.type, expectedType)
        }
    }

    func testPassDecisionPreservesTaggedEventUnchanged() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.type = .leftMouseDown
        event.setIntegerValueField(.eventSourceUserData, value: MiddleClickEventIdentity.marker)

        let returned = MouseButtonEventFactory.event(for: .passUnchanged, original: event)

        XCTAssertTrue(returned === event)
        XCTAssertEqual(event.type, .leftMouseDown)
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), MiddleClickEventIdentity.marker)
    }

    func testRecoveryDecisionDoesNotReturnSyntheticReplacementForDisabledNotification() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))

        XCTAssertNil(MouseButtonEventFactory.event(for: .reenableEventTap, original: event))
        XCTAssertNil(MouseButtonEventFactory.event(for: .enterDegradedState, original: event))
    }
}
