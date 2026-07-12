import AppKit
import Combine
import SlidrFreeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let permissionManager = PermissionManager()
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    private let systemControl = SystemControl()
    private var physicalTrackpadMonitor: PhysicalTrackpadMonitor?
    private var gestureRecognizer = GestureRecognizer(settings: .default.validated())

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsWindowController = SettingsWindowController(store: settingsStore, permissionManager: permissionManager)
        menuBarController = MenuBarController(
            settingsStore: settingsStore,
            showSettings: { [weak self] in self?.settingsWindowController?.show() }
        )

        // Rebuild recognizer and manage event tap lifecycle on settings changes
        settingsStore.$settings.sink { [weak self] settings in
            guard let self = self else { return }
            self.gestureRecognizer = GestureRecognizer(settings: settings)
            self.menuBarController?.refresh()
            self.updateEventTap()
        }.store(in: &cancellables)

        // React to permission changes at runtime
        permissionManager.$snapshot.sink { [weak self] _ in
            self?.updateEventTap()
        }.store(in: &cancellables)

        // Refresh permission status when returning from System Settings.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            self?.permissionManager.currentSnapshot()
        }.store(in: &cancellables)

        // Initial setup
        gestureRecognizer = GestureRecognizer(settings: settingsStore.settings)
        updateEventTap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        physicalTrackpadMonitor?.stop()
    }

    // MARK: - Event Pipeline

    private func updateEventTap() {
        let settings = settingsStore.settings
        let permissions = permissionManager.snapshot

        if settings.isAppEnabled && permissions.canListen {
            if physicalTrackpadMonitor == nil {
                physicalTrackpadMonitor = PhysicalTrackpadMonitor { [weak self] event in
                    self?.handleInputEvent(event)
                }
            }
            physicalTrackpadMonitor?.start()
        } else {
            physicalTrackpadMonitor?.stop()
        }
    }

    private func handleInputEvent(_ event: NormalizedInputEvent) {
        guard let recognized = gestureRecognizer.process(event) else { return }
        let actions = ActionDispatcher(settings: settingsStore.settings).actions(for: recognized)
        for action in actions {
            execute(action: action)
        }
    }

    private func execute(action: SystemAction) {
        let result: SystemActionResult
        switch action {
        case .adjustVolume(let delta):
            result = systemControl.adjustVolume(delta: delta)
        case .adjustBrightness(let delta):
            result = systemControl.adjustBrightness(delta: delta)
        case .switchBrowserTab(let direction):
            result = systemControl.switchBrowserTab(direction: direction)
        case .middleClick:
            result = systemControl.middleClick()
        }
        if case .success = result, case .adjustVolume = action {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if case .success = result, case .adjustBrightness = action {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if case .success = result, case .switchBrowserTab = action {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
}
