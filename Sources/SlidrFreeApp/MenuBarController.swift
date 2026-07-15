import AppKit
import SlidrFreeCore

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settingsStore: SettingsStore
    private let permissionManager: PermissionManager
    private let pipelineStatus: InputPipelineStatus
    private let showSettings: () -> Void
    private let healthResolver = AppHealthResolver()
    private var currentHealth: AppHealthState = .starting

    init(
        settingsStore: SettingsStore,
        permissionManager: PermissionManager,
        pipelineStatus: InputPipelineStatus,
        showSettings: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.permissionManager = permissionManager
        self.pipelineStatus = pipelineStatus
        self.showSettings = showSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        refresh()
    }

    func refresh() {
        currentHealth = healthResolver.resolve(
            settings: settingsStore.settings,
            permission: permissionManager.snapshot,
            pipeline: pipelineStatus
        )
        updateIcon(for: currentHealth)

        let menu = NSMenu()
        let summary = NSMenuItem(
            title: String(
                format: NSLocalizedString("menu_status_format", comment: ""),
                NSLocalizedString(currentHealth.localizationKey, comment: "")
            ),
            action: nil,
            keyEquivalent: ""
        )
        summary.isEnabled = false
        menu.addItem(summary)

        if let actionKey = currentHealth.actionLocalizationKey {
            menu.addItem(NSMenuItem(title: NSLocalizedString(actionKey, comment: ""), action: #selector(primaryAction), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())

        let enabledTitle = settingsStore.settings.isAppEnabled
            ? NSLocalizedString("pause_app", comment: "")
            : NSLocalizedString("enable_app", comment: "")
        let toggle = NSMenuItem(title: enabledTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.isEnabled = settingsStore.settings.experience.onboardingVersion >= ExperienceSettings.currentOnboardingVersion
        menu.addItem(toggle)
        menu.addItem(NSMenuItem(title: NSLocalizedString("settings", comment: ""), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("quit", comment: ""), action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func updateIcon(for health: AppHealthState) {
        let symbolName: String
        switch health {
        case .ready: symbolName = "hand.draw"
        case .disabledByUser: symbolName = "pause.circle"
        case .noGesturesConfigured: symbolName = "slider.horizontal.3"
        case .starting, .recovering: symbolName = "arrow.triangle.2.circlepath"
        case .setupRequired, .permissionRequired, .hardwareUnavailable, .degraded:
            symbolName = "exclamationmark.triangle"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: NSLocalizedString(health.localizationKey, comment: ""))
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = image == nil ? "SF" : ""
        statusItem.button?.toolTip = NSLocalizedString(health.localizationKey, comment: "")
    }

    @objc private func primaryAction() {
        if currentHealth == .permissionRequired { permissionManager.promptForAccessibility() }
        showSettings()
    }

    @objc private func toggleEnabled() {
        var settings = settingsStore.settings
        settings.isAppEnabled.toggle()
        settingsStore.save(settings)
    }

    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
