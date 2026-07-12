struct MouseButtonEventMetadata: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case down
        case dragged
        case up
        case tapDisabledByTimeout
        case tapDisabledByUserInput
        case other
    }

    var kind: Kind
    var sourceButton: Int64
    var eventNumber: Int64
    var marker: Int64
}

struct MouseButtonEventTransform: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case down
        case dragged
        case up
    }

    let kind: Kind
    let targetButton: Int64
    let eventNumber: Int64
    let clickState: Int64
}

enum MouseButtonEventTapRecovery: Equatable, Sendable {
    case reenableEventTap
}

enum MouseButtonEventDecision: Equatable, Sendable {
    case passUnchanged
    case transform(MouseButtonEventTransform)
    case requestSyntheticUp(MiddleClickPendingRelease, then: MouseButtonEventTapRecovery)
    case reenableEventTap
    case enterDegradedState
}

struct MouseButtonEventReducer: Sendable {
    private static let maximumReenableAttempts = 3
    private static let middleButton: Int64 = 2
    private static let clickState: Int64 = 1

    private let bridge: MiddleClickSessionBridge
    private let generation: UInt64
    private let ownMarker: Int64

    init(bridge: MiddleClickSessionBridge, generation: UInt64, ownMarker: Int64) {
        self.bridge = bridge
        self.generation = generation
        self.ownMarker = ownMarker
    }

    func reduce(_ event: MouseButtonEventMetadata) -> MouseButtonEventDecision {
        guard event.marker != ownMarker else {
            return .passUnchanged
        }

        switch event.kind {
        case .down:
            guard isSupportedSourceButton(event.sourceButton),
                  bridge.beginPhysical(
                      sourceButton: event.sourceButton,
                      eventNumber: event.eventNumber,
                      generation: generation
                  ) else {
                return .passUnchanged
            }
            return transform(.down, eventNumber: event.eventNumber)

        case .dragged:
            guard isSupportedSourceButton(event.sourceButton),
                  bridge.continueDrag(
                      sourceButton: event.sourceButton,
                      eventNumber: event.eventNumber,
                      generation: generation
                  ) else {
                return .passUnchanged
            }
            return transform(.dragged, eventNumber: event.eventNumber)

        case .up:
            guard isSupportedSourceButton(event.sourceButton),
                  bridge.finishPhysical(
                      sourceButton: event.sourceButton,
                      eventNumber: event.eventNumber,
                      generation: generation
                  ) else {
                return .passUnchanged
            }
            return transform(.up, eventNumber: event.eventNumber)

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let release = bridge.quiesce() {
                return .requestSyntheticUp(release, then: .reenableEventTap)
            }
            return .reenableEventTap

        case .other:
            return .passUnchanged
        }
    }

    func quiesce() -> MiddleClickPendingRelease? {
        bridge.quiesce()
    }

    static func decision(afterFailedReenableAttempt attempt: Int) -> MouseButtonEventDecision {
        attempt < maximumReenableAttempts ? .reenableEventTap : .enterDegradedState
    }

    private func transform(
        _ kind: MouseButtonEventTransform.Kind,
        eventNumber: Int64
    ) -> MouseButtonEventDecision {
        .transform(
            MouseButtonEventTransform(
                kind: kind,
                targetButton: Self.middleButton,
                eventNumber: eventNumber,
                clickState: Self.clickState
            )
        )
    }

    private func isSupportedSourceButton(_ button: Int64) -> Bool {
        button == 0 || button == 1
    }
}
