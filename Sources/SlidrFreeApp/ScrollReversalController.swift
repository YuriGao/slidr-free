import Foundation
import SlidrFreeCore

/// Keeps the scroll Event Tap in step with settings, permission, and sleep.
///
/// The tap is armed only while the app is enabled, at least one device class is
/// reversed, and Accessibility is granted. It is independent of the gesture
/// pipeline: reversing scroll needs no physical trackpad frames, so a user who
/// only wants the split scrolling behavior never starts the private touch
/// monitor.
final class ScrollReversalController {
    private static let maximumRetries = 3
    private static let retryDelay: TimeInterval = 2

    private let lock = NSRecursiveLock()
    private let makeTap: (ScrollDirectionSettings, @escaping (ScrollDirectionTapStatus) -> Void) -> any ScrollDirectionTapLifecycle
    private let refreshPermission: () -> PermissionState
    private let statusHandler: (ScrollDirectionTapStatus) -> Void
    private let deliverOnMain: (@escaping () -> Void) -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var tap: (any ScrollDirectionTapLifecycle)?
    private var settings: AppSettings = .default
    private var permission: PermissionState = .unknown
    private var asleep = false
    private var terminated = false
    private var remainingRetries = ScrollReversalController.maximumRetries

    init(
        makeTap: @escaping (ScrollDirectionSettings, @escaping (ScrollDirectionTapStatus) -> Void) -> any ScrollDirectionTapLifecycle,
        refreshPermission: @escaping () -> PermissionState,
        statusHandler: @escaping (ScrollDirectionTapStatus) -> Void,
        deliverOnMain: @escaping (@escaping () -> Void) -> Void = { work in
            if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
        },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.makeTap = makeTap
        self.refreshPermission = refreshPermission
        self.statusHandler = statusHandler
        self.deliverOnMain = deliverOnMain
        self.schedule = schedule
    }

    func update(settings newSettings: AppSettings, permission newPermission: PermissionState, refreshPermission: Bool = false) {
        withLock {
            let validated = newSettings.validated()
            if validated.scrollDirection != settings.scrollDirection { remainingRetries = Self.maximumRetries }
            settings = validated
            permission = refreshPermission ? self.refreshPermission() : newPermission
            if permission == .granted { remainingRetries = Self.maximumRetries }
            sync()
        }
    }

    func willSleep() {
        withLock {
            asleep = true
            stopTap()
        }
    }

    func didWake() {
        withLock {
            guard !terminated else { return }
            asleep = false
            permission = refreshPermission()
            remainingRetries = Self.maximumRetries
            sync()
        }
    }

    func terminate() {
        withLock {
            terminated = true
            stopTap()
        }
    }

    private func sync() {
        guard !terminated, !asleep, isEligible else {
            stopTap()
            return
        }
        if let tap {
            tap.update(settings.scrollDirection)
            return
        }
        startTap()
    }

    private var isEligible: Bool {
        settings.isAppEnabled && settings.scrollDirection.isActive && permission == .granted
    }

    private func startTap() {
        let created = makeTap(settings.scrollDirection) { [weak self] status in
            self?.deliverOnMain { [weak self] in self?.handleTapStatus(status) }
        }
        guard created.start() else {
            stopTap(status: .degraded)
            retryLater()
            return
        }
        tap = created
        statusHandler(.running)
    }

    private func stopTap(status: ScrollDirectionTapStatus = .stopped) {
        guard let tap else {
            if status != .stopped { statusHandler(status) }
            return
        }
        self.tap = nil
        tap.stop()
        statusHandler(status)
    }

    /// The tap reports failure from its own thread; dropping and retrying is
    /// decided on the thread that owns the settings snapshot.
    private func handleTapStatus(_ status: ScrollDirectionTapStatus) {
        withLock {
            guard status == .degraded, !terminated else { return }
            stopTap(status: .degraded)
            retryLater()
        }
    }

    private func retryLater() {
        guard remainingRetries > 0 else { return }
        remainingRetries -= 1
        schedule(Self.retryDelay) { [weak self] in
            self?.withLock { self?.sync() }
        }
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
