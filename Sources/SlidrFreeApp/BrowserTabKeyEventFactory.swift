import CoreGraphics
import SlidrFreeCore

enum BrowserTabKeyEventFactory {
    private static let supportedBrowserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome"
    ]

    private static let rightBracketKeyCode: CGKeyCode = 30
    private static let leftBracketKeyCode: CGKeyCode = 33

    static func isSupportedBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return supportedBrowserBundleIdentifiers.contains(bundleIdentifier)
    }

    static func events(for direction: BrowserTabDirection) -> [CGEvent]? {
        let keyCode: CGKeyCode = direction == .next ? rightBracketKeyCode : leftBracketKeyCode
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return nil
        }

        keyDown.flags = [.maskCommand, .maskShift]
        keyUp.flags = [.maskCommand, .maskShift]
        return [keyDown, keyUp]
    }
}
