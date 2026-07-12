import Combine
import Foundation
import SlidrFreeCore

enum TouchMonitorRuntimeState: String, Equatable, Sendable {
    case stopped
    case starting
    case running
    case unavailable
}

final class InputPipelineStatus: ObservableObject {
    @Published private(set) var frameworkAvailable: Bool?
    @Published private(set) var deviceAvailable: Bool?
    @Published private(set) var touchMonitor: TouchMonitorRuntimeState = .stopped
    @Published private(set) var eventTap: MouseButtonEventTapStatus = .stopped
    @Published private(set) var generation: UInt64 = 0
    @Published private(set) var lastFailureReason: String?
    @Published private(set) var lastFrameReceivedAt: Double?

    var lastFrameAge: Double? {
        guard let lastFrameReceivedAt else { return nil }
        return max(0, ProcessInfo.processInfo.systemUptime - lastFrameReceivedAt)
    }

    func update(
        frameworkAvailable: Bool? = nil,
        deviceAvailable: Bool? = nil,
        touchMonitor: TouchMonitorRuntimeState? = nil,
        eventTap: MouseButtonEventTapStatus? = nil,
        generation: UInt64? = nil,
        failure: String? = nil,
        frameReceivedAt: Double? = nil
    ) {
        let apply = { [weak self] in
            guard let self else { return }
            if let frameworkAvailable { self.frameworkAvailable = frameworkAvailable }
            if let deviceAvailable { self.deviceAvailable = deviceAvailable }
            if let touchMonitor { self.touchMonitor = touchMonitor }
            if let eventTap { self.eventTap = eventTap }
            if let generation { self.generation = generation }
            if let failure { self.lastFailureReason = String(failure.prefix(160)) }
            if let frameReceivedAt { self.lastFrameReceivedAt = frameReceivedAt }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }
}

protocol InputPipelineInstance: AnyObject {
    var generation: UInt64 { get }
    func startTouchMonitor() -> Bool
    func startEventTap(completion: @escaping (Bool) -> Void)
    func updateEdgeSettings(_ settings: AppSettings)
    func quiesce(completion: @escaping () -> Void)
}

protocol InputPipelineFactory {
    func make(
        generation: UInt64,
        settings: AppSettings,
        status: InputPipelineStatus,
        eventTapStatus: @escaping (MouseButtonEventTapStatus) -> Void
    ) -> any InputPipelineInstance
}

final class InputPipelineCoordinator {
    private let lock = NSRecursiveLock()
    private let factory: any InputPipelineFactory
    private let status: InputPipelineStatus
    private let refreshPermission: () -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var nextGeneration: UInt64 = 0
    private var pipeline: (any InputPipelineInstance)?
    private var settings: AppSettings?
    private var permission: PermissionState = .unknown
    private var sleeping = false
    private var terminated = false
    private var isRefreshingForStart = false
    private var isQuiescing = false
    private var restartRequested = false
    private var stopCompletions: [() -> Void] = []

    var activeGeneration: UInt64? { withLock { pipeline?.generation } }

    init(
        factory: any InputPipelineFactory,
        status: InputPipelineStatus,
        refreshPermission: @escaping () -> Void,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void
    ) {
        self.factory = factory
        self.status = status
        self.refreshPermission = refreshPermission
        self.schedule = schedule
    }

    func update(settings newSettings: AppSettings, permission newPermission: PermissionState) {
        withLock { updateLocked(settings: newSettings, permission: newPermission) }
    }

    private func updateLocked(settings newSettings: AppSettings, permission newPermission: PermissionState) {
        let previous = settings
        settings = newSettings.validated()
        permission = newPermission

        if isRefreshingForStart { return }

        guard !terminated, !sleeping else { return }
        let semanticChange = previous.map {
            $0.isAppEnabled != newSettings.isAppEnabled || $0.middleClick != newSettings.middleClick
        } ?? true
        let eligible = newSettings.isAppEnabled && newPermission == .granted && hasPhysicalGesture(newSettings)

        guard eligible else {
            stopActive(completion: {})
            return
        }
        if pipeline == nil || semanticChange {
            restart()
        } else {
            pipeline?.updateEdgeSettings(newSettings)
        }
    }

    func willSleep() {
        withLock {
            sleeping = true
            stopActive(completion: {})
        }
    }

    func didWake() {
        withLock {
            guard !terminated else { return }
            schedule(2.0) { [weak self] in
                self?.withLock {
                    guard let self, !self.terminated else { return }
                    self.sleeping = false
                    self.restartIfEligible()
                }
            }
        }
    }

    func terminate(completion: @escaping () -> Void) {
        withLock {
            terminated = true
            stopActive(completion: completion)
        }
    }

    private func restartIfEligible() {
        guard let settings,
              settings.isAppEnabled,
              permission == .granted,
              hasPhysicalGesture(settings) else { return }
        restart()
    }

    private func restart() {
        restartRequested = true
        beginQuiesceIfNeeded()
    }

    private func startFresh() {
        guard !terminated, !sleeping, let settings,
              settings.isAppEnabled, permission == .granted,
              hasPhysicalGesture(settings) else { return }
        isRefreshingForStart = true
        refreshPermission()
        isRefreshingForStart = false
        guard permission == .granted else { return }
        nextGeneration &+= 1
        let generation = nextGeneration
        status.update(generation: generation)
        let instance = factory.make(
            generation: generation,
            settings: settings,
            status: status,
            eventTapStatus: { [weak self] eventStatus in
                self?.withLock { self?.handleEventTapStatus(eventStatus, generation: generation) }
            }
        )
        pipeline = instance
        if instance.startTouchMonitor() {
            status.update(touchMonitor: .running)
        } else {
            status.update(touchMonitor: .unavailable, failure: "Physical touch monitor could not start.")
        }
        if settings.middleClick.isEnabled {
            instance.startEventTap { [weak self, weak instance] success in
                self?.withLock {
                    guard let self, let instance, self.pipeline === instance else { return }
                    if !success {
                        self.status.update(eventTap: .degraded, failure: "Middle-click Event Tap could not start.")
                        self.refreshPermission()
                    }
                }
            }
        }
    }

    private func handleEventTapStatus(_ eventStatus: MouseButtonEventTapStatus, generation: UInt64) {
        guard pipeline?.generation == generation else { return }
        status.update(eventTap: eventStatus)
        switch eventStatus {
        case .recoveryRequiresPipelineRestart:
            refreshPermission()
            restart()
        case .degraded:
            refreshPermission()
            status.update(failure: "Middle-click Event Tap entered degraded mode.")
        case .stopped, .starting, .running:
            break
        }
    }

    private func stopActive(completion: @escaping () -> Void) {
        restartRequested = false
        stopCompletions.append(completion)
        beginQuiesceIfNeeded()
    }

    private func beginQuiesceIfNeeded() {
        guard !isQuiescing else { return }
        guard let active = pipeline else {
            let completions = stopCompletions
            stopCompletions.removeAll()
            completions.forEach { $0() }
            if restartRequested {
                restartRequested = false
                startFresh()
            }
            return
        }
        isQuiescing = true
        pipeline = nil
        active.quiesce { [self, active, status] in
            withLock {
                _ = active
                status.update(touchMonitor: .stopped, eventTap: .stopped)
                isQuiescing = false
                let completions = stopCompletions
                stopCompletions.removeAll()
                completions.forEach { $0() }
                if restartRequested {
                    restartRequested = false
                    startFresh()
                }
            }
        }
    }

    private func hasPhysicalGesture(_ settings: AppSettings) -> Bool {
        settings.middleClick.isEnabled || settings.features.volumeEdgeGesture || settings.features.brightnessEdgeGesture || settings.features.browserTabEdgeGesture
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class ProductionInputPipelineFactory: InputPipelineFactory {
    private let actionHandler: (RecognizedGesture) -> Void

    init(actionHandler: @escaping (RecognizedGesture) -> Void) {
        self.actionHandler = actionHandler
    }

    func make(generation: UInt64, settings: AppSettings, status: InputPipelineStatus, eventTapStatus: @escaping (MouseButtonEventTapStatus) -> Void) -> any InputPipelineInstance {
        ProductionInputPipeline(generation: generation, settings: settings, status: status, actionHandler: actionHandler, eventTapStatus: eventTapStatus)
    }
}

private final class ProductionInputPipeline: InputPipelineInstance {
    let generation: UInt64
    private let status: InputPipelineStatus
    private let bridge: MiddleClickSessionBridge
    private let emitter = MiddleClickEmitter()
    private let actionHandler: (RecognizedGesture) -> Void
    private let eventTapStatus: (MouseButtonEventTapStatus) -> Void
    private var middleRecognizer: MiddleClickRecognizer
    private var edgeRecognizer: GestureRecognizer
    private var didQuiesce = false
    private var eventTapInstance: MouseButtonEventTap?

    private lazy var monitor = PhysicalTrackpadMonitor(
        generation: generation,
        statusHandler: { [weak self] runtime in self?.handleMonitorStatus(runtime) },
        middleClickUpdateHandler: { [weak self] update in self?.processMiddleClick(update) },
        handler: { [weak self] event in self?.processEdge(event) }
    )
    init(generation: UInt64, settings: AppSettings, status: InputPipelineStatus, actionHandler: @escaping (RecognizedGesture) -> Void, eventTapStatus: @escaping (MouseButtonEventTapStatus) -> Void) {
        self.generation = generation
        self.status = status
        self.actionHandler = actionHandler
        self.eventTapStatus = eventTapStatus
        bridge = MiddleClickSessionBridge(generation: generation, now: { ProcessInfo.processInfo.systemUptime })
        middleRecognizer = MiddleClickRecognizer(tapEnabled: settings.middleClick.tapEnabled)
        edgeRecognizer = GestureRecognizer(settings: settings)
    }

    func startTouchMonitor() -> Bool { monitor.start() }
    func startEventTap(completion: @escaping (Bool) -> Void) {
        let tap = MouseButtonEventTap(
            reducer: MouseButtonEventReducer(bridge: bridge, generation: generation, ownMarker: MiddleClickEventIdentity.marker),
            releaseEmitter: emitter,
            statusHandler: { [weak self] value in self?.eventTapStatus(value) }
        )
        eventTapInstance = tap
        tap.start(completion: completion)
    }
    func updateEdgeSettings(_ settings: AppSettings) { edgeRecognizer.settings = settings.validated() }

    func quiesce(completion: @escaping () -> Void) {
        guard !didQuiesce else { completion(); return }
        didQuiesce = true
        if let pending = bridge.quiesce() { _ = emitter.emitRelease(eventNumber: pending.eventNumber) }
        let finish = { [weak self] in self?.monitor.stop(); completion() }
        if let eventTapInstance {
            eventTapInstance.stop(completion: finish)
        } else {
            finish()
        }
    }

    private func processMiddleClick(_ update: MiddleClickInputUpdate) {
        guard !didQuiesce else { return }
        let output = middleRecognizer.process(update)
        bridge.applyTouchUpdate(output)
        status.update(frameReceivedAt: output.receivedAt)
        guard output.tapCandidate, let sessionID = output.sessionID,
              bridge.claimTap(sessionID: sessionID, generation: generation) else { return }
        DispatchQueue.main.async { [weak self] in self?.actionHandler(.middleClickTap) }
    }

    private func processEdge(_ event: NormalizedInputEvent) {
        guard !didQuiesce, let recognized = edgeRecognizer.process(event) else { return }
        actionHandler(recognized)
    }

    private func handleMonitorStatus(_ runtime: PhysicalTrackpadMonitorStatus) {
        status.update(frameworkAvailable: runtime.frameworkAvailable, deviceAvailable: runtime.deviceAvailable, touchMonitor: runtime.state, failure: runtime.failure)
    }
}
