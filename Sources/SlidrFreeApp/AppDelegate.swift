import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let permissionManager = PermissionManager()
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsWindowController = SettingsWindowController(store: settingsStore, permissionManager: permissionManager)
        menuBarController = MenuBarController(settingsStore: settingsStore, permissionManager: permissionManager) { [weak self] in
            self?.settingsWindowController?.show()
        }

        cancellable = settingsStore.$settings.sink { [weak self] _ in
            self?.menuBarController?.refresh()
        }
    }
}
