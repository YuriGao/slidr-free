import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settingsStore: SettingsStore
    private let showSettings: () -> Void
    private let showDebug: () -> Void

    init(settingsStore: SettingsStore, showSettings: @escaping () -> Void, showDebug: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.showSettings = showSettings
        self.showDebug = showDebug
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(named: "AppIcon")
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image?.isTemplate = true
        refresh()
    }

    func refresh() {
        let menu = NSMenu()
        let enabledTitle = settingsStore.settings.isAppEnabled
            ? NSLocalizedString("disable_app", comment: "")
            : NSLocalizedString("enable_app", comment: "")
        menu.addItem(NSMenuItem(title: enabledTitle, action: #selector(toggleEnabled), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("settings", comment: ""), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: NSLocalizedString("debug", comment: ""), action: #selector(openDebug), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("quit", comment: ""), action: #selector(quit), keyEquivalent: "q"))

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

    @objc private func openDebug() {
        showDebug()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
