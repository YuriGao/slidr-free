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
    static func toggleFrontWindow(processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        if let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: application),
           toggle(focusedWindow) {
            return true
        }
        if let mainWindow = elementAttribute(kAXMainWindowAttribute, from: application),
           toggle(mainWindow) {
            return true
        }
        for window in elementArrayAttribute(kAXWindowsAttribute, from: application)
        where boolAttribute(kAXMinimizedAttribute, from: window) == true {
            if restore(window) { return true }
        }
        return false
    }

    static func action(forIsMinimized isMinimized: Bool) -> ApplicationWindowToggleAction {
        isMinimized ? .restore : .minimize
    }

    private static func toggle(_ window: AXUIElement) -> Bool {
        switch action(forIsMinimized: boolAttribute(kAXMinimizedAttribute, from: window) ?? false) {
        case .restore:
            return restore(window)

        case .minimize:
            if let button = elementAttribute(kAXMinimizeButtonAttribute, from: window),
               AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                return true
            }
            return AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            ) == .success
        }
    }

    private static func restore(_ window: AXUIElement) -> Bool {
        guard AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        ) == .success else { return false }
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }

    private static func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private static func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
}
