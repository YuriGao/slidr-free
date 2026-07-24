import AppKit
import SlidrFreeCore

struct MenuBarPresentation: Equatable {
    let health: AppHealthState
    let isAppEnabled: Bool
    let canToggle: Bool
}

struct MenuBarRefreshGate {
    private var previous: MenuBarPresentation?

    mutating func shouldRefresh(_ presentation: MenuBarPresentation) -> Bool {
        guard presentation != previous else { return false }
        previous = presentation
        return true
    }
}

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settingsStore: SettingsStore
    private let permissionManager: PermissionManager
    private let pipelineStatus: InputPipelineStatus
    private let showSettings: () -> Void
    private let healthResolver = AppHealthResolver()
    private var currentHealth: AppHealthState = .starting
    private var refreshGate = MenuBarRefreshGate()

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

    func refresh(settings: AppSettings? = nil, permission: PermissionSnapshot? = nil) {
        let settings = settings ?? settingsStore.settings
        let permission = permission ?? permissionManager.snapshot
        let health = healthResolver.resolve(
            settings: settings,
            permission: permission,
            pipeline: pipelineStatus
        )
        let presentation = MenuBarPresentation(
            health: health,
            isAppEnabled: settings.isAppEnabled,
            canToggle: settings.experience.onboardingVersion >= ExperienceSettings.currentOnboardingVersion
        )
        guard refreshGate.shouldRefresh(presentation) else { return }
        currentHealth = health
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

        let enabledTitle = settings.isAppEnabled
            ? NSLocalizedString("pause_app", comment: "")
            : NSLocalizedString("enable_app", comment: "")
        let toggle = NSMenuItem(title: enabledTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.isEnabled = presentation.canToggle
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
