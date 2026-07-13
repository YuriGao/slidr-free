import CoreGraphics
import Foundation

enum MouseButtonEventTapStatus: Equatable, Sendable {
    case stopped
    case starting
    case running
    case recoveryRequiresPipelineRestart
    case degraded
}

final class MouseButtonEventTapRecoveryCoordinator {
    private static let maximumAttempts = 3
    private static let retryDelay: TimeInterval = 0.1

    private let enable: () -> Void
    private let isEnabled: () -> Bool
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let status: (MouseButtonEventTapStatus) -> Void
    private var isRecovering = false

    init(
        enable: @escaping () -> Void,
        isEnabled: @escaping () -> Bool,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        status: @escaping (MouseButtonEventTapStatus) -> Void
    ) {
        self.enable = enable
        self.isEnabled = isEnabled
        self.schedule = schedule
        self.status = status
    }

    func recover() {
        guard !isRecovering else { return }
        isRecovering = true
        scheduleAttempt(1)
    }

    private func scheduleAttempt(_ attempt: Int) {
        schedule(Self.retryDelay) { [weak self] in
            self?.attemptEnable(attempt)
        }
    }

    private func attemptEnable(_ attempt: Int) {
        enable()
        if isEnabled() {
            isRecovering = false
            status(.recoveryRequiresPipelineRestart)
        } else if attempt < Self.maximumAttempts {
            scheduleAttempt(attempt + 1)
        } else {
            isRecovering = false
            status(.degraded)
        }
    }
}

final class MouseButtonEventTap {
    static let handledEventTypes: Set<CGEventType> = [
        CGEventType.leftMouseDown,
        .leftMouseUp,
        .leftMouseDragged,
        .rightMouseDown,
        .rightMouseUp,
        .rightMouseDragged,
        .tapDisabledByTimeout,
        .tapDisabledByUserInput
    ]

    // Quartz delivers tap-disabled notifications to the callback regardless of
    // the subscription mask. Their raw values are sentinels outside mask width.
    static let eventMask: CGEventMask = handledEventTypes
        .filter { $0 != .tapDisabledByTimeout && $0 != .tapDisabledByUserInput }
        .reduce(0) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }

    private let executor: MouseButtonEventTapExecutor
    private let context: MouseButtonEventTapContext

    init(
        reducer: MouseButtonEventReducer,
        releaseEmitter: any MiddleClickReleaseEmitting = MiddleClickEmitter(),
        statusHandler: @escaping (MouseButtonEventTapStatus) -> Void = { _ in },
        hapticFeedback: (any MiddleClickHapticFeedbackPerforming)? = nil
    ) {
        executor = MouseButtonEventTapExecutor()
        context = MouseButtonEventTapContext(
            reducer: reducer,
            releaseHandler: { pending in
                _ = releaseEmitter.emitRelease(eventNumber: pending.eventNumber)
            },
            statusHandler: statusHandler,
            hapticFeedback: hapticFeedback
        )
    }

    func start(completion: @escaping (Bool) -> Void) {
        guard executor.perform({ [context] in
            context.start(completion: completion)
        }) else {
            completion(false)
            return
        }
    }

    func quiesce(completion: @escaping () -> Void) {
        guard executor.perform({ [context] in
            context.quiesce(completion: completion)
        }) else {
            completion()
            return
        }
    }

    func stop(completion: @escaping () -> Void) {
        guard executor.perform({ [context, executor] in
            context.quiesce {
                executor.stopRunLoop()
                completion()
            }
        }) else {
            completion()
            return
        }
    }

    deinit {
        let context = self.context
        if executor.isCurrentThread {
            context.quiesce(completion: {})
            executor.stopRunLoop()
            return
        }

        let stopped = DispatchSemaphore(value: 0)
        guard executor.perform({ [executor] in
            context.quiesce {
                executor.stopRunLoop()
                stopped.signal()
            }
        }) else {
            return
        }
        stopped.wait()
    }
}

final class MouseButtonEventTapContext {
    private let reducer: MouseButtonEventReducer
    private let releaseHandler: (MiddleClickPendingRelease) -> Void
    private let statusHandler: (MouseButtonEventTapStatus) -> Void
    private let hapticFeedback: (any MiddleClickHapticFeedbackPerforming)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recovery: MouseButtonEventTapRecoveryCoordinator?
    private var isQuiesced = false

    init(
        reducer: MouseButtonEventReducer,
        releaseHandler: @escaping (MiddleClickPendingRelease) -> Void,
        statusHandler: @escaping (MouseButtonEventTapStatus) -> Void,
        recovery: MouseButtonEventTapRecoveryCoordinator? = nil,
        hapticFeedback: (any MiddleClickHapticFeedbackPerforming)? = nil
    ) {
        self.reducer = reducer
        self.releaseHandler = releaseHandler
        self.statusHandler = statusHandler
        self.recovery = recovery
        self.hapticFeedback = hapticFeedback
    }

    func start(completion: @escaping (Bool) -> Void) {
        guard !isQuiesced else {
            statusHandler(.degraded)
            completion(false)
            return
        }
        if let eventTap, CGEvent.tapIsEnabled(tap: eventTap) {
            completion(true)
            return
        }

        statusHandler(.starting)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: MouseButtonEventTap.eventMask,
            callback: mouseButtonEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            statusHandler(.degraded)
            completion(false)
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            destroyTap()
            statusHandler(.degraded)
            completion(false)
            return
        }

        recovery = makeRecoveryCoordinator(for: tap)
        statusHandler(.running)
        completion(true)
    }

    func quiesce(completion: @escaping () -> Void) {
        if !isQuiesced {
            isQuiesced = true
            if let pending = reducer.quiesce() {
                releaseHandler(pending)
            }
        }
        destroyTap()
        recovery = nil
        statusHandler(.stopped)
        completion()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isQuiesced {
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                return nil
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        let metadata = MouseButtonEventMetadata(
            kind: metadataKind(for: type),
            sourceButton: event.getIntegerValueField(.mouseEventButtonNumber),
            eventNumber: event.getIntegerValueField(.mouseEventNumber),
            marker: event.getIntegerValueField(.eventSourceUserData)
        )
        let decision = reducer.reduce(metadata)

        switch decision {
        case .requestSyntheticUp(let pending, then: .reenableEventTap):
            isQuiesced = true
            releaseHandler(pending)
            recovery?.recover()
            return nil
        case .reenableEventTap:
            isQuiesced = true
            recovery?.recover()
            return nil
        case .enterDegradedState:
            statusHandler(.degraded)
            return nil
        case .passUnchanged:
            return Unmanaged.passUnretained(event)
        case .transform(let transform):
            guard let output = MouseButtonEventFactory.event(for: decision, original: event) else {
                return Unmanaged.passUnretained(event)
            }
            if transform.kind == .up {
                hapticFeedback?.performSuccess()
            }
            return Unmanaged.passUnretained(output)
        }
    }

    private func makeRecoveryCoordinator(for tap: CFMachPort) -> MouseButtonEventTapRecoveryCoordinator {
        MouseButtonEventTapRecoveryCoordinator(
            enable: {
                CGEvent.tapEnable(tap: tap, enable: true)
            },
            isEnabled: {
                CGEvent.tapIsEnabled(tap: tap)
            },
            schedule: { delay, work in
                let fireDate = CFAbsoluteTimeGetCurrent() + delay
                let timer = CFRunLoopTimerCreateWithHandler(
                    kCFAllocatorDefault,
                    fireDate,
                    0,
                    0,
                    0
                ) { timer in
                    CFRunLoopTimerInvalidate(timer)
                    work()
                }
                CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
            },
            status: { [statusHandler] status in
                statusHandler(status)
            }
        )
    }

    private func destroyTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func metadataKind(for type: CGEventType) -> MouseButtonEventMetadata.Kind {
        switch type {
        case .leftMouseDown, .rightMouseDown:
            return .down
        case .leftMouseDragged, .rightMouseDragged:
            return .dragged
        case .leftMouseUp, .rightMouseUp:
            return .up
        case .tapDisabledByTimeout:
            return .tapDisabledByTimeout
        case .tapDisabledByUserInput:
            return .tapDisabledByUserInput
        default:
            return .other
        }
    }
}

private func mouseButtonEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let context = Unmanaged<MouseButtonEventTapContext>.fromOpaque(userInfo).takeUnretainedValue()
    return context.handle(type: type, event: event)
}

private final class MouseButtonEventTapExecutor {
    private final class State {
        let condition = NSCondition()
        var runLoop: CFRunLoop?
        var isStopping = false
        var didStop = false

        func run() {
            let keepAlivePort = Port()
            RunLoop.current.add(keepAlivePort, forMode: .default)

            condition.lock()
            runLoop = CFRunLoopGetCurrent()
            condition.broadcast()
            condition.unlock()

            CFRunLoopRun()

            condition.lock()
            runLoop = nil
            didStop = true
            condition.broadcast()
            condition.unlock()
        }

        func waitForRunLoop() -> CFRunLoop? {
            condition.lock()
            defer { condition.unlock() }
            while runLoop == nil && !isStopping && !didStop {
                condition.wait()
            }
            return isStopping ? nil : runLoop
        }

        func markStopping() {
            condition.lock()
            isStopping = true
            condition.broadcast()
            condition.unlock()
        }
    }

    private let state = State()
    private let thread: Thread

    init() {
        let state = self.state
        thread = Thread {
            state.run()
        }
        thread.name = "com.slidr.free.middle-click-event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        precondition(state.waitForRunLoop() != nil, "Event Tap run loop failed to start")
    }

    var isCurrentThread: Bool {
        Thread.current === thread
    }

    @discardableResult
    func perform(_ work: @escaping () -> Void) -> Bool {
        guard let runLoop = state.waitForRunLoop() else { return false }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(runLoop)
        return true
    }

    func stopRunLoop() {
        precondition(isCurrentThread, "Event Tap run loop must stop on its owning thread")
        state.markStopping()
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}
