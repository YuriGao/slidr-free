import AppKit
import Combine
import SlidrFreeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let permissionManager = PermissionManager()
    private let pipelineStatus = InputPipelineStatus()
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    private let systemControl = SystemControl()
    private let terminationWaiter = PipelineTerminationWaiter(timeout: 2)

    private lazy var pipelineFactory = ProductionInputPipelineFactory { [weak self] gesture in
        self?.dispatch(gesture: gesture)
    }
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
            pipelineStatus: pipelineStatus
        )
        menuBarController = MenuBarController(
            settingsStore: settingsStore,
            showSettings: { [weak self] in self?.settingsWindowController?.show() }
        )

        settingsStore.$settings.sink { [weak self] _ in
            self?.menuBarController?.refresh()
            self?.updateInputPipeline(refreshPermission: false)
        }.store(in: &cancellables)

        permissionManager.$snapshot.dropFirst().sink { [weak self] _ in
            self?.updateInputPipeline(refreshPermission: false)
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            self?.updateInputPipeline(refreshPermission: true)
        }.store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            self?.pipelineCoordinator.willSleep()
        }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            self?.pipelineCoordinator.didWake()
        }.store(in: &cancellables)

        updateInputPipeline(refreshPermission: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let stopped = terminationWaiter.waitForStop { [pipelineCoordinator] completion in
            pipelineCoordinator.terminate(completion: completion)
        }
        if !stopped {
            pipelineStatus.update(failure: "Input pipeline stop timed out during termination.")
        }
    }

    private func updateInputPipeline(refreshPermission: Bool) {
        let snapshot = refreshPermission ? permissionManager.currentSnapshot() : permissionManager.snapshot
        pipelineCoordinator.update(settings: settingsStore.settings, permission: snapshot.accessibility)
    }

    private func dispatch(gesture: RecognizedGesture) {
        let actions = ActionDispatcher(settings: settingsStore.settings).actions(for: gesture)
        actions.forEach(execute(action:))
    }

    private func execute(action: SystemAction) {
        let result: SystemActionResult
        switch action {
        case .adjustVolume(let delta): result = systemControl.adjustVolume(delta: delta)
        case .adjustBrightness(let delta): result = systemControl.adjustBrightness(delta: delta)
        case .switchBrowserTab(let direction): result = systemControl.switchBrowserTab(direction: direction)
        case .middleClick: result = systemControl.middleClick()
        }
        guard case .success = result else { return }
        switch action {
        case .adjustVolume, .adjustBrightness, .switchBrowserTab:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        case .middleClick:
            break
        }
    }
}
