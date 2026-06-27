import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(store: SettingsStore) {
        let view = SettingsView(store: store)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Slidr-Free Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
