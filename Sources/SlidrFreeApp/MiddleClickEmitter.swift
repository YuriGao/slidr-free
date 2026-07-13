import CoreGraphics

enum MiddleClickEventIdentity {
    static let marker: Int64 = 0x534C_4944_5246_5245
}

protocol MiddleClickPostingEvent: AnyObject {
    func setIntegerValueField(_ field: CGEventField, value: Int64)
    func post()
}

protocol MiddleClickEventSource {
    func currentPointerLocation() -> CGPoint?
    func makeMouseEvent(
        type: CGEventType,
        location: CGPoint,
        button: CGMouseButton
    ) -> (any MiddleClickPostingEvent)?
}

private final class QuartzMiddleClickEvent: MiddleClickPostingEvent {
    private let event: CGEvent

    init(event: CGEvent) {
        self.event = event
    }

    func setIntegerValueField(_ field: CGEventField, value: Int64) {
        event.setIntegerValueField(field, value: value)
    }

    func post() {
        event.post(tap: .cghidEventTap)
    }
}

struct QuartzMiddleClickEventSource: MiddleClickEventSource {
    func currentPointerLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    func makeMouseEvent(
        type: CGEventType,
        location: CGPoint,
        button: CGMouseButton
    ) -> (any MiddleClickPostingEvent)? {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else {
            return nil
        }
        return QuartzMiddleClickEvent(event: event)
    }
}

protocol MiddleClickEmitting: AnyObject {
    func emitClick() -> SystemActionResult
}

protocol MiddleClickReleaseEmitting: AnyObject {
    func emitRelease(eventNumber: Int64) -> SystemActionResult
}

final class MiddleClickEmitter: MiddleClickEmitting, MiddleClickReleaseEmitting {
    private let eventSource: any MiddleClickEventSource
    private let marker: Int64
    private let hapticFeedback: (any MiddleClickHapticFeedbackPerforming)?

    init(
        eventSource: any MiddleClickEventSource = QuartzMiddleClickEventSource(),
        marker: Int64 = MiddleClickEventIdentity.marker,
        hapticFeedback: (any MiddleClickHapticFeedbackPerforming)? = nil
    ) {
        self.eventSource = eventSource
        self.marker = marker
        self.hapticFeedback = hapticFeedback
    }

    func emitClick() -> SystemActionResult {
        guard let location = eventSource.currentPointerLocation() else {
            return .failed("Failed to read current pointer location")
        }
        guard let down = eventSource.makeMouseEvent(
            type: .otherMouseDown,
            location: location,
            button: .center
        ) else {
            return .failed("Failed to create middle-button down event")
        }
        guard let up = eventSource.makeMouseEvent(
            type: .otherMouseUp,
            location: location,
            button: .center
        ) else {
            return .failed("Failed to create middle-button up event")
        }

        configure(down)
        configure(up)
        down.post()
        up.post()
        hapticFeedback?.performSuccess()
        return .success
    }

    func emitRelease(eventNumber: Int64) -> SystemActionResult {
        guard let location = eventSource.currentPointerLocation() else {
            return .failed("Failed to read current pointer location")
        }
        guard let up = eventSource.makeMouseEvent(
            type: .otherMouseUp,
            location: location,
            button: .center
        ) else {
            return .failed("Failed to create pending middle-button up event")
        }

        configure(up)
        up.setIntegerValueField(.mouseEventNumber, value: eventNumber)
        up.post()
        return .success
    }

    private func configure(_ event: any MiddleClickPostingEvent) {
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }
}

enum MouseButtonEventFactory {
    static func event(
        for decision: MouseButtonEventDecision,
        original: CGEvent
    ) -> CGEvent? {
        switch decision {
        case .passUnchanged:
            return original
        case .transform(let transform):
            original.type = eventType(for: transform.kind)
            original.setIntegerValueField(.mouseEventButtonNumber, value: transform.targetButton)
            original.setIntegerValueField(.mouseEventClickState, value: transform.clickState)
            original.setIntegerValueField(.mouseEventNumber, value: transform.eventNumber)
            return original
        case .requestSyntheticUp, .reenableEventTap, .enterDegradedState:
            return nil
        }
    }

    private static func eventType(for kind: MouseButtonEventTransform.Kind) -> CGEventType {
        switch kind {
        case .down:
            return .otherMouseDown
        case .dragged:
            return .otherMouseDragged
        case .up:
            return .otherMouseUp
        }
    }
}
