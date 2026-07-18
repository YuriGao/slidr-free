import AppKit
import Combine
import SlidrFreeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let permissionManager = PermissionManager()
    private let pipelineStatus = InputPipelineStatus()
    private let gestureTestController = GestureTestController()
    private lazy var gestureDispatchRouter = GestureDispatchRouter(preview: gestureTestController)
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    private let systemControl = SystemControl()
    private let terminationWaiter = PipelineTerminationWaiter(timeout: 2)
    private let healthResolver = AppHealthResolver()
    private var lastAnnouncedHealth: AppHealthState?

    private lazy var pipelineFactory = ProductionInputPipelineFactory(
        actionHandler: { [weak self] gesture in self?.dispatch(gesture: gesture) },
        inputObserver: { [weak self] event, settings in self?.gestureTestController.observe(event, settings: settings) }
    )
    private lazy var pipelineCoordinator = InputPipelineCoordinator(
        factory: pipelineFactory,
        status: pipelineStatus,
        refreshPermission: { PermissionManager.currentSnapshot().accessibility },
        schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settingsWindowController = SettingsWindowController(
            store: settingsStore,
            permissionManager: permissionManager,
            pipelineStatus: pipelineStatus,
            gestureTestController: gestureTestController
        )
        menuBarController = MenuBarController(
            settingsStore: settingsStore,
            permissionManager: permissionManager,
            pipelineStatus: pipelineStatus,
            showSettings: { [weak self] in self?.settingsWindowController?.show() }
        )

        gestureTestController.onStateChange = { [weak self] in
            self?.updateInputPipeline(refreshPermission: false)
        }

        settingsStore.$settings.sink { [weak self] _ in
            self?.refreshHealthPresentation()
            self?.updateInputPipeline(refreshPermission: false)
        }.store(in: &cancellables)

        permissionManager.$snapshot.dropFirst().sink { [weak self] _ in
            if self?.permissionManager.snapshot.accessibility != .granted {
                self?.gestureTestController.stop()
            }
            self?.refreshHealthPresentation()
            self?.updateInputPipeline(refreshPermission: false)
        }.store(in: &cancellables)

        pipelineStatus.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshHealthPresentation() }
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            self?.updateInputPipeline(refreshPermission: true)
        }.store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            self?.gestureTestController.stop()
            self?.pipelineCoordinator.willSleep()
        }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            self?.pipelineCoordinator.didWake()
        }.store(in: &cancellables)

        updateInputPipeline(refreshPermission: false)
        if settingsStore.settings.experience.onboardingVersion < ExperienceSettings.currentOnboardingVersion ||
            CommandLine.arguments.contains("--show-settings") {
            settingsWindowController?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureTestController.stop()
        let stopped = terminationWaiter.waitForStop { [pipelineCoordinator] completion in
            pipelineCoordinator.terminate(completion: completion)
        }
        if !stopped {
            pipelineStatus.update(failure: "Input pipeline stop timed out during termination.")
        }
    }

    private func updateInputPipeline(refreshPermission: Bool) {
        let snapshot = refreshPermission ? permissionManager.currentSnapshot() : permissionManager.snapshot
        pipelineCoordinator.update(
            settings: settingsStore.settings,
            permission: snapshot.accessibility,
            previewMode: gestureTestController.isTesting
        )
    }

    private func dispatch(gesture: RecognizedGesture) {
        let actions = gestureDispatchRouter.actions(for: gesture, settings: settingsStore.settings)
        actions.forEach(execute(action:))
    }

    private func refreshHealthPresentation() {
        menuBarController?.refresh()
        let health = healthResolver.resolve(
            settings: settingsStore.settings,
            permission: permissionManager.snapshot,
            pipeline: pipelineStatus
        )
        defer { lastAnnouncedHealth = health }
        guard let previous = lastAnnouncedHealth, previous != health else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: NSLocalizedString(health.localizationKey, comment: ""),
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func execute(action: SystemAction) {
        let result: SystemActionResult
        switch action {
        case .adjustVolume(let delta): result = systemControl.adjustVolume(delta: delta)
        case .adjustBrightness(let delta): result = systemControl.adjustBrightness(delta: delta)
        case .switchBrowserTab(let direction): result = systemControl.switchBrowserTab(direction: direction)
        case .toggleApplication(let binding): result = systemControl.activateOrMinimizeApplication(binding)
        case .middleClick: result = systemControl.middleClick()
        }
        guard case .success = result else { return }
        switch action {
        case .adjustVolume, .adjustBrightness, .switchBrowserTab:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        case .toggleApplication:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        case .middleClick:
            break
        }
    }
}
