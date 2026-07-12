import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(store: SettingsStore, permissionManager: PermissionManager, pipelineStatus: InputPipelineStatus) {
        let view = SettingsView(store: store, permissionManager: permissionManager, pipelineStatus: pipelineStatus)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = NSLocalizedString("settings_title", comment: "")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        // Size window to fit SwiftUI content
        let fittingSize = hostingController.view.fittingSize
        window.setContentSize(NSSize(width: max(fittingSize.width, 480), height: max(fittingSize.height, 600)))
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
