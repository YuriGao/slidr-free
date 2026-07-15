import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(store: SettingsStore, permissionManager: PermissionManager, pipelineStatus: InputPipelineStatus, gestureTestController: GestureTestController) {
        let view = SettingsView(store: store, permissionManager: permissionManager, pipelineStatus: pipelineStatus, gestureTestController: gestureTestController)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = NSLocalizedString("settings_title", comment: "")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 560)
        window.setContentSize(NSSize(width: 720, height: 600))
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
