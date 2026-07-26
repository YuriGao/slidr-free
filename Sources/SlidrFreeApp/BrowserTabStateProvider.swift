import AppKit
import SlidrFreeCore

struct BrowserTabState: Equatable {
    let activeIndex: Int
    let tabCount: Int

    init?(activeIndex: Int, tabCount: Int) {
        guard tabCount > 0, (1...tabCount).contains(activeIndex) else { return nil }
        self.activeIndex = activeIndex
        self.tabCount = tabCount
    }

    func permitsSwitch(_ direction: BrowserTabDirection) -> Bool {
        switch direction {
        case .next:
            return activeIndex < tabCount
        case .previous:
            return activeIndex > 1
        }
    }
}

enum BrowserTabStateProvider {
    static func state(bundleIdentifier: String) -> BrowserTabState? {
        guard let source = scriptSource(bundleIdentifier: bundleIdentifier),
              let script = NSAppleScript(source: source) else { return nil }

        var error: NSDictionary?
        guard let value = script.executeAndReturnError(&error).stringValue else {
            if let error {
                print("[SlidrFree] BrowserTabStateProvider: \(error)")
            }
            return nil
        }

        let components = value.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 2,
              let activeIndex = Int(components[0]),
              let tabCount = Int(components[1]) else { return nil }
        return BrowserTabState(activeIndex: activeIndex, tabCount: tabCount)
    }

    private static func scriptSource(bundleIdentifier: String) -> String? {
        switch bundleIdentifier {
        case "com.apple.Safari":
            return """
            tell application id "com.apple.Safari"
                if (count of windows) is 0 then return ""
                set targetWindow to front window
                set activeIndex to index of current tab of targetWindow
                set tabCount to count of tabs of targetWindow
                return (activeIndex as text) & "|" & (tabCount as text)
            end tell
            """
        case "com.google.Chrome", "com.microsoft.edgemac":
            return """
            tell application id "\(bundleIdentifier)"
                if (count of windows) is 0 then return ""
                set targetWindow to front window
                set activeIndex to active tab index of targetWindow
                set tabCount to count of tabs of targetWindow
                return (activeIndex as text) & "|" & (tabCount as text)
            end tell
            """
        default:
            return nil
        }
    }
}
