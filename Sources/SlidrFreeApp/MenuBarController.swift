import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settingsStore: SettingsStore
    private let permissionManager: PermissionManager
    private let showSettings: () -> Void

    init(settingsStore: SettingsStore, permissionManager: PermissionManager, showSettings: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.permissionManager = permissionManager
        self.showSettings = showSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.title = "SF"
        refresh()
    }

    func refresh() {
        let menu = NSMenu()
        let enabledTitle = settingsStore.settings.isAppEnabled ? "Disable App" : "Enable App"
        menu.addItem(NSMenuItem(title: enabledTitle, action: #selector(toggleEnabled), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Permissions…", action: #selector(openPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        var settings = settingsStore.settings
        settings.isAppEnabled.toggle()
        settingsStore.save(settings)
        refresh()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func openPermissions() {
        permissionManager.openPrivacySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
