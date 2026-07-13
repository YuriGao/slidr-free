import CoreGraphics
import XCTest
@testable import SlidrFreeApp

final class MiddleClickEmitterTests: XCTestCase {
    func testSuccessfulClickPostsDownAndUpBeforeRequestingHapticOnce() {
        let source = EventSourceSpy(location: CGPoint(x: 123, y: 456))
        let feedback = MiddleClickHapticFeedbackSpy { source.log.append("haptic") }
        let emitter = MiddleClickEmitter(
            eventSource: source,
            marker: 9_001,
            hapticFeedback: feedback
        )

        XCTAssertEqual(emitter.emitClick(), .success)
        XCTAssertEqual(source.created.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(source.created.map(\.location), [CGPoint(x: 123, y: 456), CGPoint(x: 123, y: 456)])
        XCTAssertEqual(source.created.map(\.button), [.center, .center])
        XCTAssertEqual(source.created[0].fields[.mouseEventButtonNumber], 2)
        XCTAssertEqual(source.created[1].fields[.mouseEventButtonNumber], 2)
        XCTAssertEqual(source.created[0].fields[.mouseEventClickState], 1)
        XCTAssertEqual(source.created[1].fields[.mouseEventClickState], 1)
        XCTAssertEqual(source.created[0].fields[.eventSourceUserData], 9_001)
        XCTAssertEqual(source.created[1].fields[.eventSourceUserData], 9_001)
        XCTAssertEqual(source.log.suffix(3), ["post-down", "post-up", "haptic"])
        XCTAssertEqual(source.log.firstIndex(of: "post-down"), source.log.count - 3)
        XCTAssertEqual(feedback.performCount, 1)
    }

    func testPostsNeitherEventWhenDownCreationFails() {
        let source = EventSourceSpy(location: .zero, failingCreation: 1)
        let feedback = MiddleClickHapticFeedbackSpy()
        let emitter = MiddleClickEmitter(eventSource: source, marker: 1, hapticFeedback: feedback)

        guard case .failed = emitter.emitClick() else {
            return XCTFail("Expected emitter failure")
        }
        XCTAssertFalse(source.log.contains(where: { $0.hasPrefix("post-") }))
        XCTAssertEqual(feedback.performCount, 0)
    }

    func testPostsNeitherEventWhenUpCreationFails() {
        let source = EventSourceSpy(location: .zero, failingCreation: 2)
        let feedback = MiddleClickHapticFeedbackSpy()
        let emitter = MiddleClickEmitter(eventSource: source, marker: 1, hapticFeedback: feedback)

        guard case .failed = emitter.emitClick() else {
            return XCTFail("Expected emitter failure")
        }
        XCTAssertFalse(source.log.contains(where: { $0.hasPrefix("post-") }))
        XCTAssertEqual(feedback.performCount, 0)
    }

    func testPostsNeitherEventWhenPointerLocationIsUnavailable() {
        let source = EventSourceSpy(location: nil)
        let feedback = MiddleClickHapticFeedbackSpy()
        let emitter = MiddleClickEmitter(eventSource: source, marker: 1, hapticFeedback: feedback)

        guard case .failed = emitter.emitClick() else {
            return XCTFail("Expected emitter failure")
        }
        XCTAssertTrue(source.created.isEmpty)
        XCTAssertEqual(feedback.performCount, 0)
    }

    func testPendingReleasePostsOneTaggedMiddleUpWithoutRequestingHaptic() {
        let source = EventSourceSpy(location: CGPoint(x: 10, y: 20))
        let feedback = MiddleClickHapticFeedbackSpy()
        let emitter = MiddleClickEmitter(eventSource: source, marker: 77, hapticFeedback: feedback)

        XCTAssertEqual(emitter.emitRelease(eventNumber: 404), .success)
        XCTAssertEqual(source.created.map(\.type), [.otherMouseUp])
        XCTAssertEqual(source.created[0].button, .center)
        XCTAssertEqual(source.created[0].fields[.mouseEventButtonNumber], 2)
        XCTAssertEqual(source.created[0].fields[.mouseEventClickState], 1)
        XCTAssertEqual(source.created[0].fields[.eventSourceUserData], 77)
        XCTAssertEqual(source.created[0].fields[.mouseEventNumber], 404)
        XCTAssertEqual(source.log.last, "post-up")
        XCTAssertEqual(feedback.performCount, 0)
    }
}

private final class MiddleClickHapticFeedbackSpy: MiddleClickHapticFeedbackPerforming {
    private let onPerform: () -> Void
    private(set) var performCount = 0

    init(onPerform: @escaping () -> Void = {}) {
        self.onPerform = onPerform
    }

    func performSuccess() {
        performCount += 1
        onPerform()
    }
}

private final class EventSourceSpy: MiddleClickEventSource {
    let location: CGPoint?
    let failingCreation: Int?
    var created: [EventSpy] = []
    var log: [String] = []
    private var creationCount = 0

    init(location: CGPoint?, failingCreation: Int? = nil) {
        self.location = location
        self.failingCreation = failingCreation
    }

    func currentPointerLocation() -> CGPoint? {
        location
    }

    func makeMouseEvent(
        type: CGEventType,
        location: CGPoint,
        button: CGMouseButton
    ) -> (any MiddleClickPostingEvent)? {
        creationCount += 1
        log.append("create-\(type == .otherMouseDown ? "down" : "up")")
        guard creationCount != failingCreation else { return nil }
        let event = EventSpy(
            type: type,
            location: location,
            button: button,
            label: type == .otherMouseDown ? "down" : "up",
            source: self
        )
        created.append(event)
        return event
    }
}

private final class EventSpy: MiddleClickPostingEvent {
    let type: CGEventType
    let location: CGPoint
    let button: CGMouseButton
    let label: String
    weak var source: EventSourceSpy?
    var fields: [CGEventField: Int64] = [:]

    init(type: CGEventType, location: CGPoint, button: CGMouseButton, label: String, source: EventSourceSpy) {
        self.type = type
        self.location = location
        self.button = button
        self.label = label
        self.source = source
    }

    func setIntegerValueField(_ field: CGEventField, value: Int64) {
        fields[field] = value
        source?.log.append("configure-\(label)-\(field.rawValue)")
    }

    func post() {
        source?.log.append("post-\(label)")
    }
}
