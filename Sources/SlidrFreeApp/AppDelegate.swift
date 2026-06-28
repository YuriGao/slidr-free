import AppKit
import Combine
import SlidrFreeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let permissionManager = PermissionManager()
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private let debugState = DebugState()
    private var debugWindowController: DebugWindowController?
    private var cancellables = Set<AnyCancellable>()

    private let systemControl = SystemControl()
    private var inputEventTap: InputEventTap?
    private var physicalTrackpadMonitor: PhysicalTrackpadMonitor?
    private var gestureRecognizer = GestureRecognizer(settings: .default.validated())

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settingsWindowController = SettingsWindowController(store: settingsStore, permissionManager: permissionManager)
        debugWindowController = DebugWindowController(state: debugState)
        menuBarController = MenuBarController(
            settingsStore: settingsStore,
            showSettings: { [weak self] in self?.settingsWindowController?.show() },
            showDebug: { [weak self] in self?.debugWindowController?.show() }
        )

        // Rebuild recognizer and manage event tap lifecycle on settings changes
        settingsStore.$settings.sink { [weak self] settings in
            guard let self = self else { return }
            self.gestureRecognizer = GestureRecognizer(settings: settings)
            self.menuBarController?.refresh()
            self.updateEventTap()
        }.store(in: &cancellables)

        // React to permission changes at runtime
        permissionManager.$snapshot.sink { [weak self] snapshot in
            self?.updateDebugPermissions(snapshot)
            self?.updateEventTap()
        }.store(in: &cancellables)

        // Refresh permission status when returning from System Settings.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            self?.permissionManager.currentSnapshot()
        }.store(in: &cancellables)

        // Initial setup
        gestureRecognizer = GestureRecognizer(settings: settingsStore.settings)
        updateDebugPermissions(permissionManager.snapshot)
        updateEventTap()
    }

    func applicationWillTerminate(_ notification: Notification) {
            physicalTrackpadMonitor?.stop()
            inputEventTap?.stop()
        }

    // MARK: - Event Pipeline

    private func updateEventTap() {
        let settings = settingsStore.settings
        let permissions = permissionManager.snapshot

        if settings.isAppEnabled && permissions.canListen {
            debugState.monitorStatus = "Running"
            if physicalTrackpadMonitor == nil {
                physicalTrackpadMonitor = PhysicalTrackpadMonitor(debugState: debugState) { [weak self] event in
                    self?.handleInputEvent(event)
                }
            }
            physicalTrackpadMonitor?.start()

            if inputEventTap == nil {
                inputEventTap = InputEventTap { [weak self] event in
                    self?.handleAuxiliaryInputEvent(event)
                }
            }
            inputEventTap?.start()
        } else {
            debugState.monitorStatus = settings.isAppEnabled ? "Stopped (permissions)" : "Stopped (disabled)"
            physicalTrackpadMonitor?.stop()
            inputEventTap?.stop()
        }
    }

    private func handleAuxiliaryInputEvent(_ event: NormalizedInputEvent) {
        switch event {
        case .keyDown, .middleClick:
            handleInputEvent(event)
        case .scroll, .physicalTouchFrame:
            updateDebugInput(event)
        }
    }

    private func handleInputEvent(_ event: NormalizedInputEvent) {
        updateDebugInput(event)
        guard let recognized = gestureRecognizer.process(event) else { return }
        debugState.lastGesture = String(describing: recognized)
        debugState.log("Gesture: \(recognized)")
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
        case .middleClick(let x, let y):
            result = systemControl.middleClick(x: x, y: y)
        }
        debugState.lastAction = String(describing: action)
        debugState.lastActionResult = String(describing: result)
        debugState.log("Action: \(action) -> \(result)")
    }

    private func updateDebugPermissions(_ snapshot: PermissionSnapshot) {
        debugState.accessibility = NSLocalizedString(snapshot.accessibility.rawValue, comment: "")
        debugState.inputMonitoring = NSLocalizedString(snapshot.inputMonitoring.rawValue, comment: "")
    }

    private func updateDebugInput(_ event: NormalizedInputEvent) {
        switch event {
        case .physicalTouchFrame(let touches, _):
            debugState.multitouchStatus = "Receiving frames"
            debugState.deviceStatus = "Physical trackpad"
            debugState.lastTouchCount = touches.count
            if let touch = touches.first {
                debugState.lastTouchDescription = String(format: "id=%d x=%.3f y=%.3f pressure=%@ state=%@", touch.id, touch.x, touch.y, optionalDescription(touch.pressure), optionalDescription(touch.state))
                if touch.x <= settingsStore.settings.gesture.edgeWidthPercent {
                    debugState.lastEdgeHit = "left"
                } else if touch.x >= 1 - settingsStore.settings.gesture.edgeWidthPercent {
                    debugState.lastEdgeHit = "right"
                } else {
                    debugState.lastEdgeHit = "None"
                }
            } else {
                debugState.lastTouchDescription = "None"
                debugState.lastEdgeHit = "None"
            }
        case .scroll:
            debugState.lastTouchDescription = "Scroll event"
        case .keyDown:
            debugState.lastTouchDescription = "Key down"
        case .middleClick(let x, let y, _):
            debugState.lastTouchDescription = String(format: "Middle click x=%.1f y=%.1f", x, y)
        }
    }

    private func optionalDescription<T>(_ value: T?) -> String {
        value.map { String(describing: $0) } ?? "nil"
    }
}
