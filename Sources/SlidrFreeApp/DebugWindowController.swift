import AppKit
import SwiftUI

final class DebugWindowController: NSWindowController {
    init(state: DebugState) {
        let hostingController = NSHostingController(rootView: DebugView(state: state))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Debug"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 640))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
