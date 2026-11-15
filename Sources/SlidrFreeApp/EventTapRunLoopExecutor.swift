import Foundation

/// Owns the dedicated thread and run loop that an Event Tap is installed on.
///
/// Quartz taps must live on a thread whose run loop stays scheduled, and mouse
/// or scroll delivery should never depend on the main thread being free, so
/// every tap in Slidr Free gets its own executor.
final class EventTapRunLoopExecutor {
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

    init(threadName: String, qualityOfService: QualityOfService = .userInteractive) {
        let state = self.state
        thread = Thread {
            state.run()
        }
        thread.name = threadName
        thread.qualityOfService = qualityOfService
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

    /// Runs `work` on the owning thread and waits for it to finish. Tap
    /// installation is part of a settings round trip, so callers need the
    /// outcome rather than a fire-and-forget block.
    @discardableResult
    func performAndWait(timeout: TimeInterval = 2, _ work: @escaping () -> Void) -> Bool {
        if isCurrentThread {
            work()
            return true
        }
        guard let runLoop = state.waitForRunLoop() else { return false }
        let finished = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            work()
            finished.signal()
        }
        CFRunLoopWakeUp(runLoop)
        return finished.wait(timeout: .now() + timeout) == .success
    }

    func stopRunLoop() {
        precondition(isCurrentThread, "Event Tap run loop must stop on its owning thread")
        state.markStopping()
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}
