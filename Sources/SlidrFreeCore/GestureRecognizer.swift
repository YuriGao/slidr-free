import Foundation

public enum RecognizedGesture: Equatable, Sendable {
    case brightness(direction: GestureDirection, magnitude: Double)
    case volume(direction: GestureDirection, magnitude: Double)
    case browserTab(direction: BrowserTabDirection)
    case middleClickTap
}

public enum GestureDirection: Equatable, Sendable {
    case increase
    case decrease
}

public enum BrowserTabDirection: Equatable, Sendable {
    case next
    case previous
}

public struct GestureRecognizer: Sendable {
    public var settings: AppSettings
    private var previousPrimaryPhysicalTouch: PhysicalTouch?
    private var activePhysicalStep: PhysicalStepState?
    private var isSuppressingEdgesUntilEmpty: Bool
    private var physicalEdgeSession: PhysicalEdgeSession

    public init(settings: AppSettings = .default) {
        self.settings = settings.validated()
        self.previousPrimaryPhysicalTouch = nil
        self.activePhysicalStep = nil
        self.isSuppressingEdgesUntilEmpty = false
        self.physicalEdgeSession = .idle
    }

    public mutating func process(_ event: NormalizedInputEvent) -> RecognizedGesture? {
        switch event {
        case .physicalTouchCancelled:
            isSuppressingEdgesUntilEmpty = false
            resetPhysicalContact()
            return nil
        case .physicalTouchFrame(let touches, let timestamp):
            guard !touches.isEmpty else {
                isSuppressingEdgesUntilEmpty = false
                resetPhysicalContact()
                return nil
            }

            if touches.count > 1 {
                isSuppressingEdgesUntilEmpty = true
                physicalEdgeSession = .blocked
                resetPhysicalContinuity()
                return nil
            }

            guard !isSuppressingEdgesUntilEmpty else { return nil }
            let current = touches[0]

            if physicalEdgeSession == .idle {
                if let originEdge = physicalEdgeHit(for: current), settings.isAppEnabled {
                    physicalEdgeSession = .eligible(touchID: current.id, edge: originEdge)
                } else {
                    physicalEdgeSession = .blocked
                }
            }

            guard settings.isAppEnabled else {
                physicalEdgeSession = .blocked
                resetPhysicalContinuity()
                return nil
            }

            guard case .eligible(let originTouchID, let originEdge) = physicalEdgeSession,
                  originTouchID == current.id else {
                physicalEdgeSession = .blocked
                resetPhysicalContinuity()
                return nil
            }

            guard physicalEdgeHit(for: current) == originEdge else {
                resetPhysicalContinuity()
                return nil
            }
            let edgeHit = originEdge

            guard let previous = previousPrimaryPhysicalTouch, previous.id == current.id else {
                resetPhysicalStepState()
                previousPrimaryPhysicalTouch = current
                return nil
            }

            guard physicalEdgeHit(for: previous) == edgeHit else {
                resetPhysicalStepState()
                previousPrimaryPhysicalTouch = current
                return nil
            }

            let deltaX = current.x - previous.x
            let deltaY = current.y - previous.y
            guard deltaX != 0 || deltaY != 0 else {
                previousPrimaryPhysicalTouch = current
                return nil
            }

            previousPrimaryPhysicalTouch = current

            if edgeHit == .top {
                guard settings.edgeAssignments.top == .browserTabs else {
                    resetPhysicalStepState()
                    return nil
                }
                guard abs(deltaX) >= abs(deltaY) * settings.gesture.horizontalDominanceRatio else {
                    return nil
                }
                guard let step = physicalStep(
                    delta: deltaX,
                    touchID: current.id,
                    edge: edgeHit,
                    timestamp: timestamp,
                    intervalSeconds: settings.gesture.tabSwitchStepIntervalSeconds
                ) else {
                    return nil
                }
                return .browserTab(direction: step == .increase ? .next : .previous)
            }

            let assignment = edgeHit == .left ? settings.edgeAssignments.left : settings.edgeAssignments.right
            guard assignment != .none else {
                resetPhysicalStepState()
                return nil
            }

            guard let step = physicalStep(
                delta: deltaY,
                touchID: current.id,
                edge: edgeHit,
                timestamp: timestamp,
                intervalSeconds: settings.gesture.physicalStepIntervalSeconds
            ) else {
                return nil
            }

            switch assignment {
            case .brightness:
                return .brightness(direction: step, magnitude: 1.0)
            case .volume:
                return .volume(direction: step, magnitude: 1.0)
            case .none:
                return nil
            }
        }
    }

    private func physicalEdgeHit(for touch: PhysicalTouch) -> PhysicalEdgeHit? {
        if touch.x <= settings.gesture.edgeWidthPercent {
            return .left
        }
        if touch.x >= 1 - settings.gesture.edgeWidthPercent {
            return .right
        }
        if touch.y >= 1 - settings.gesture.edgeWidthPercent {
            return .top
        }
        return nil
    }

    private mutating func resetPhysicalStepState() {
        activePhysicalStep = nil
    }

    private mutating func resetPhysicalContinuity() {
        previousPrimaryPhysicalTouch = nil
        resetPhysicalStepState()
    }

    private mutating func resetPhysicalContact() {
        physicalEdgeSession = .idle
        resetPhysicalContinuity()
    }

    private mutating func physicalStep(
        delta: Double,
        touchID: Int,
        edge: PhysicalEdgeHit,
        timestamp: Double,
        intervalSeconds: Double
    ) -> GestureDirection? {
        let stepDistance = settings.gesture.physicalStepDistance
        if activePhysicalStep?.touchID != touchID || activePhysicalStep?.edge != edge {
            activePhysicalStep = PhysicalStepState(touchID: touchID, edge: edge, accumulatedDistance: 0, lastEmitTimestamp: nil)
        }

        activePhysicalStep?.accumulatedDistance += delta
        guard let state = activePhysicalStep else { return nil }

        let direction: GestureDirection
        if state.accumulatedDistance >= stepDistance {
            direction = .increase
        } else if state.accumulatedDistance <= -stepDistance {
            direction = .decrease
        } else {
            return nil
        }

        if let lastEmitTimestamp = state.lastEmitTimestamp,
           timestamp - lastEmitTimestamp < intervalSeconds {
            return nil
        }

        let consumed = direction == .increase ? stepDistance : -stepDistance
        activePhysicalStep?.accumulatedDistance -= consumed
        activePhysicalStep?.lastEmitTimestamp = timestamp
        return direction
    }
}

private struct PhysicalStepState: Sendable {
    var touchID: Int
    var edge: PhysicalEdgeHit
    var accumulatedDistance: Double
    var lastEmitTimestamp: Double?
}

private enum PhysicalEdgeSession: Equatable, Sendable {
    case idle
    case blocked
    case eligible(touchID: Int, edge: PhysicalEdgeHit)
}
