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
    private let deliverOnMain: (@escaping () -> Void) -> Void
    @Published private(set) var frameworkAvailable: Bool?
    @Published private(set) var deviceAvailable: Bool?
    @Published private(set) var touchMonitor: TouchMonitorRuntimeState = .stopped
    @Published private(set) var eventTap: MouseButtonEventTapStatus = .stopped
    @Published private(set) var generation: UInt64 = 0
    @Published private(set) var lastFailureReason: String?
    @Published private(set) var lastFrameReceivedAt: Double?

    init(deliverOnMain: @escaping (@escaping () -> Void) -> Void = { work in
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }) {
        self.deliverOnMain = deliverOnMain
    }

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
        frameReceivedAt: Double? = nil,
        frameGeneration: UInt64? = nil,
        sourceGeneration: UInt64? = nil
    ) {
        let apply = { [weak self] in
            guard let self else { return }
            if let generation {
                if generation != self.generation {
                    self.frameworkAvailable = nil
                    self.deviceAvailable = nil
                    self.touchMonitor = .stopped
                    self.lastFailureReason = nil
                    self.lastFrameReceivedAt = nil
                }
                self.generation = generation
            }
            let acceptsSource = sourceGeneration.map { $0 == self.generation } ?? true
            if acceptsSource {
                if let frameworkAvailable { self.frameworkAvailable = frameworkAvailable }
                if let deviceAvailable { self.deviceAvailable = deviceAvailable }
                if let touchMonitor { self.touchMonitor = touchMonitor }
                if let failure { self.lastFailureReason = String(failure.prefix(160)) }
            }
            if let eventTap { self.eventTap = eventTap }
            if let frameReceivedAt,
               let frameGeneration,
               frameGeneration == self.generation {
                self.lastFrameReceivedAt = frameReceivedAt
            }
        }
        deliverOnMain(apply)
    }
}

struct PipelineTerminationWaiter {
    let timeout: TimeInterval
    private let wait: (DispatchSemaphore, TimeInterval) -> Bool

    init(
        timeout: TimeInterval = 2,
        wait: @escaping (DispatchSemaphore, TimeInterval) -> Bool = { semaphore, seconds in
            semaphore.wait(timeout: .now() + seconds) == .success
        }
    ) {
        self.timeout = timeout
        self.wait = wait
    }

    func waitForStop(_ beginStop: (@escaping () -> Void) -> Void) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        beginStop { semaphore.signal() }
        return wait(semaphore, timeout)
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
    private let refreshPermission: () -> PermissionState
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var nextGeneration: UInt64 = 0
    private var pipeline: (any InputPipelineInstance)?
    private var settings: AppSettings?
    private var permission: PermissionState = .unknown
    private var sleeping = false
    private var terminated = false
    private var isStarting = false
    private var isQuiescing = false
    private var restartRequested = false
    private var stopCompletions: [() -> Void] = []
    private var lifecycleEpoch: UInt64 = 0
    private var nextWakeToken: UInt64 = 0
    private var pendingWakeToken: UInt64?

    var activeGeneration: UInt64? { withLock { pipeline?.generation } }

    init(
        factory: any InputPipelineFactory,
        status: InputPipelineStatus,
        refreshPermission: @escaping () -> PermissionState,
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

        if isStarting { return }

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
            lifecycleEpoch &+= 1
            pendingWakeToken = nil
            sleeping = true
            stopActive(completion: {})
        }
    }

    func didWake() {
        withLock {
            guard !terminated, sleeping, pendingWakeToken == nil else { return }
            let wakeEpoch = lifecycleEpoch
            nextWakeToken &+= 1
            let wakeToken = nextWakeToken
            pendingWakeToken = wakeToken
            schedule(2.0) { [weak self] in
                self?.withLock {
                    guard let self,
                          !self.terminated,
                          self.lifecycleEpoch == wakeEpoch,
                          self.pendingWakeToken == wakeToken else { return }
                    self.pendingWakeToken = nil
                    self.sleeping = false
                    self.restartIfEligible()
                }
            }
        }
    }

    func terminate(completion: @escaping () -> Void) {
        withLock {
            lifecycleEpoch &+= 1
            pendingWakeToken = nil
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
        guard !terminated, !sleeping, let initialSettings = settings,
              initialSettings.isAppEnabled, permission == .granted,
              hasPhysicalGesture(initialSettings) else { return }
        isStarting = true
        permission = refreshPermission()
        isStarting = false
        guard permission == .granted,
              let settings,
              settings.isAppEnabled,
              hasPhysicalGesture(settings) else { return }
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
                        self.permission = self.refreshPermission()
                        if self.permission != .granted { self.stopActive(completion: {}) }
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
            permission = refreshPermission()
            if permission == .granted { restart() } else { stopActive(completion: {}) }
        case .degraded:
            permission = refreshPermission()
            status.update(failure: "Middle-click Event Tap entered degraded mode.")
            if permission != .granted { stopActive(completion: {}) }
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

protocol InputTouchMonitoring: AnyObject {
    func start() -> Bool
    func stop()
}

protocol InputEventTapLifecycle: AnyObject {
    func start(completion: @escaping (Bool) -> Void)
    func stop(completion: @escaping () -> Void)
}

extension PhysicalTrackpadMonitor: InputTouchMonitoring {}
extension MouseButtonEventTap: InputEventTapLifecycle {}

typealias InputTouchMonitorFactory = (
    @escaping (PhysicalTrackpadMonitorStatus) -> Void,
    @escaping (MiddleClickInputUpdate) -> Void,
    @escaping (NormalizedInputEvent) -> Void
) -> any InputTouchMonitoring

typealias InputEventTapFactory = (
    MouseButtonEventReducer,
    any MiddleClickReleaseEmitting,
    @escaping (MouseButtonEventTapStatus) -> Void
) -> any InputEventTapLifecycle

final class ProductionInputPipeline: InputPipelineInstance {
    let generation: UInt64
    // The touch callback, settings updates, and quiesce linearize here. Event
    // creation, emission, monitor/tap teardown, and action delivery stay outside.
    private let lock = NSRecursiveLock()
    private let status: InputPipelineStatus
    private let bridge: MiddleClickSessionBridge
    private let releaseEmitter: any MiddleClickReleaseEmitting
    private let actionHandler: (RecognizedGesture) -> Void
    private let eventTapStatus: (MouseButtonEventTapStatus) -> Void
    private let monitorFactory: InputTouchMonitorFactory
    private let eventTapFactory: InputEventTapFactory
    private let deliverAction: (@escaping () -> Void) -> Void
    private var middleRecognizer: MiddleClickRecognizer
    private var edgeRecognizer: GestureRecognizer
    private var isActive = true
    private var activeToken: UInt64 = 1
    private var lastAcceptedMiddleClickSequence: UInt64 = 0
    private var eventTapInstance: (any InputEventTapLifecycle)?

    private lazy var monitor = monitorFactory(
        { [weak self] runtime in self?.handleMonitorStatus(runtime) },
        { [weak self] update in self?.receiveMiddleClick(update) },
        { [weak self] event in self?.receiveEdge(event) }
    )

    init(
        generation: UInt64,
        settings: AppSettings,
        status: InputPipelineStatus,
        bridge: MiddleClickSessionBridge? = nil,
        releaseEmitter: any MiddleClickReleaseEmitting = MiddleClickEmitter(),
        actionHandler: @escaping (RecognizedGesture) -> Void,
        eventTapStatus: @escaping (MouseButtonEventTapStatus) -> Void,
        monitorFactory: InputTouchMonitorFactory? = nil,
        eventTapFactory: InputEventTapFactory? = nil,
        deliverAction: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) }
    ) {
        self.generation = generation
        self.status = status
        self.releaseEmitter = releaseEmitter
        self.actionHandler = actionHandler
        self.eventTapStatus = eventTapStatus
        self.bridge = bridge ?? MiddleClickSessionBridge(generation: generation, now: { ProcessInfo.processInfo.systemUptime })
        self.monitorFactory = monitorFactory ?? { statusHandler, middleHandler, edgeHandler in
            PhysicalTrackpadMonitor(
                generation: generation,
                statusHandler: statusHandler,
                middleClickUpdateHandler: middleHandler,
                handler: edgeHandler
            )
        }
        self.eventTapFactory = eventTapFactory ?? { reducer, emitter, statusHandler in
            MouseButtonEventTap(reducer: reducer, releaseEmitter: emitter, statusHandler: statusHandler)
        }
        self.deliverAction = deliverAction
        middleRecognizer = MiddleClickRecognizer(tapEnabled: settings.middleClick.tapEnabled)
        edgeRecognizer = GestureRecognizer(settings: settings)
    }

    func startTouchMonitor() -> Bool {
        guard let token = withLock({ isActive ? activeToken : nil }) else { return false }
        let started = monitor.start()
        let remainsActive = withLock { isActive && activeToken == token }
        if !remainsActive { monitor.stop() }
        return started && remainsActive
    }
    func startEventTap(completion: @escaping (Bool) -> Void) {
        let tap = eventTapFactory(
            MouseButtonEventReducer(bridge: bridge, generation: generation, ownMarker: MiddleClickEventIdentity.marker),
            releaseEmitter,
            { [weak self] value in self?.eventTapStatus(value) }
        )
        let accepted = withLock { () -> Bool in
            guard isActive else { return false }
            eventTapInstance = tap
            return true
        }
        guard accepted else {
            tap.stop { completion(false) }
            return
        }
        tap.start(completion: completion)
    }
    func updateEdgeSettings(_ settings: AppSettings) {
        withLock {
            guard isActive else { return }
            edgeRecognizer.settings = settings.validated()
        }
    }

    func quiesce(completion: @escaping () -> Void) {
        let transition = withLock { () -> (MiddleClickPendingRelease?, (any InputEventTapLifecycle)?)? in
            guard isActive else { return nil }
            isActive = false
            activeToken &+= 1
            return (bridge.quiesce(), eventTapInstance)
        }
        guard let (pending, eventTapInstance) = transition else { completion(); return }
        if let pending { _ = releaseEmitter.emitRelease(eventNumber: pending.eventNumber) }
        let finish = { [self] in monitor.stop(); completion() }
        if let eventTapInstance {
            eventTapInstance.stop(completion: finish)
        } else {
            finish()
        }
    }

    func receiveMiddleClick(_ update: MiddleClickInputUpdate) {
        let result = withLock { () -> (receivedAt: Double, deliveryToken: UInt64?)? in
            guard isActive else { return nil }
            let updateMetadata: (generation: UInt64, sequence: UInt64)
            switch update {
            case .frame(let generation, let sequence, _, _, _),
                 .empty(let generation, let sequence, _, _),
                 .cancel(let generation, let sequence, _, _):
                updateMetadata = (generation, sequence)
            }
            guard updateMetadata.generation == generation,
                  updateMetadata.sequence > lastAcceptedMiddleClickSequence else { return nil }
            lastAcceptedMiddleClickSequence = updateMetadata.sequence
            let output = middleRecognizer.process(update)
            bridge.applyTouchUpdate(output)
            let token: UInt64?
            if output.tapCandidate,
               let sessionID = output.sessionID,
               bridge.claimTap(sessionID: sessionID, generation: generation) {
                token = activeToken
            } else {
                token = nil
            }
            return (output.receivedAt, token)
        }
        guard let result else { return }
        status.update(frameReceivedAt: result.receivedAt, frameGeneration: generation)
        guard let token = result.deliveryToken else { return }
        deliverAction { [weak self] in
            guard let self else { return }
            // This token check is the action-delivery linearization point.
            let shouldDeliver = self.withLock { self.isActive && self.activeToken == token }
            if shouldDeliver { self.actionHandler(.middleClickTap) }
        }
    }

    func receiveEdge(_ event: NormalizedInputEvent) {
        let result = withLock { () -> (RecognizedGesture, UInt64)? in
            guard isActive, let recognized = edgeRecognizer.process(event) else { return nil }
            return (recognized, activeToken)
        }
        guard let (recognized, token) = result else { return }
        let shouldDeliver = withLock { isActive && activeToken == token }
        if shouldDeliver { actionHandler(recognized) }
    }

    private func handleMonitorStatus(_ runtime: PhysicalTrackpadMonitorStatus) {
        status.update(
            frameworkAvailable: runtime.frameworkAvailable,
            deviceAvailable: runtime.deviceAvailable,
            touchMonitor: runtime.state,
            failure: runtime.failure,
            sourceGeneration: generation
        )
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
