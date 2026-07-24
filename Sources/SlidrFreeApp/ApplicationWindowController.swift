import ApplicationServices
import Foundation

struct FrontmostApplicationIdentity: Equatable {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
}

enum ApplicationWindowToggleAction: Equatable {
    case minimize
    case restore
}

enum ApplicationWindowController {
    private static let policy = ApplicationWindowTogglePolicy(
        perMessageTimeout: 0.20,
        operationBudget: 0.75
    )

    static func toggleFrontWindow(processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        let operation = AXWindowToggleOperation(policy: policy)
        if let focusedWindow = operation.elementAttribute(kAXFocusedWindowAttribute, from: application),
           operation.toggle(focusedWindow) {
            return true
        }
        if let mainWindow = operation.elementAttribute(kAXMainWindowAttribute, from: application),
           operation.toggle(mainWindow) {
            return true
        }
        for window in operation.elementArrayAttribute(kAXWindowsAttribute, from: application)
        where operation.boolAttribute(kAXMinimizedAttribute, from: window) == true {
            if operation.restore(window) { return true }
        }
        return false
    }

    static func action(forIsMinimized isMinimized: Bool) -> ApplicationWindowToggleAction {
        isMinimized ? .restore : .minimize
    }

}

struct ApplicationWindowTogglePolicy {
    let perMessageTimeout: Float
    let operationBudget: TimeInterval

    func hasTimeRemaining(startedAt: TimeInterval, now: TimeInterval) -> Bool {
        now - startedAt < operationBudget
    }
}

private final class AXWindowToggleOperation {
    private let policy: ApplicationWindowTogglePolicy
    private let startedAt: TimeInterval
    private let now: () -> TimeInterval

    init(
        policy: ApplicationWindowTogglePolicy,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.policy = policy
        self.now = now
        self.startedAt = now()
    }

    func toggle(_ window: AXUIElement) -> Bool {
        switch ApplicationWindowController.action(
            forIsMinimized: boolAttribute(kAXMinimizedAttribute, from: window) ?? false
        ) {
        case .restore:
            return restore(window)

        case .minimize:
            if let button = elementAttribute(kAXMinimizeButtonAttribute, from: window),
               performAction(kAXPressAction, on: button) {
                return true
            }
            return setAttribute(kAXMinimizedAttribute, value: kCFBooleanTrue, on: window)
        }
    }

    func restore(_ window: AXUIElement) -> Bool {
        guard setAttribute(kAXMinimizedAttribute, value: kCFBooleanFalse, on: window) else {
            return false
        }
        _ = performAction(kAXRaiseAction, on: window)
        return true
    }

    func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard prepare(element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        guard prepare(element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        guard prepare(element) else { return [] }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func setAttribute(_ attribute: String, value: CFTypeRef, on element: AXUIElement) -> Bool {
        guard prepare(element) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    private func performAction(_ action: String, on element: AXUIElement) -> Bool {
        guard prepare(element) else { return false }
        return AXUIElementPerformAction(element, action as CFString) == .success
    }

    private func prepare(_ element: AXUIElement) -> Bool {
        guard policy.hasTimeRemaining(startedAt: startedAt, now: now()) else { return false }
        return AXUIElementSetMessagingTimeout(element, policy.perMessageTimeout) == .success
    }
}
