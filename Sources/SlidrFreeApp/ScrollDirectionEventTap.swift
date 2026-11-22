import CoreGraphics
import Foundation
import SlidrFreeCore

enum ScrollDirectionTapStatus: String, Equatable, Sendable {
    case stopped
    case starting
    case running
    case degraded
}

protocol ScrollDirectionTapLifecycle: AnyObject {
    func start() -> Bool
    func stop()
    func update(_ settings: ScrollDirectionSettings)
}

/// A session Event Tap that inverts scroll deltas for one hardware class.
///
/// macOS applies one "Natural scrolling" preference to every pointing device.
/// This tap rewrites the deltas of the class the user asked to reverse, which
/// yields the split trackpad/mouse behavior the system setting cannot express.
/// It never synthesizes events and never guesses direction: an event it cannot
/// classify, or one with no movement, passes through untouched.
final class ScrollDirectionEventTap: ScrollDirectionTapLifecycle {
    static let eventType = CGEventType.scrollWheel
    static let eventMask = CGEventMask(1) << CGEventType.scrollWheel.rawValue

    private let executor: EventTapRunLoopExecutor
    private let context: ScrollDirectionTapContext

    init(
        settings: ScrollDirectionSettings,
        statusHandler: @escaping (ScrollDirectionTapStatus) -> Void = { _ in }
    ) {
        executor = EventTapRunLoopExecutor(threadName: "com.slidr.free.scroll-direction-event-tap")
        context = ScrollDirectionTapContext(settings: settings, statusHandler: statusHandler)
    }

    func update(_ settings: ScrollDirectionSettings) {
        context.update(settings)
    }

    func start() -> Bool {
        var started = false
        let performed = executor.performAndWait { [context] in
            started = context.install()
        }
        return performed && started
    }

    func stop() {
        guard executor.performAndWait({ [context, executor] in
            context.uninstall()
            executor.stopRunLoop()
        }) else { return }
    }

    deinit {
        if executor.isCurrentThread {
            context.uninstall()
            executor.stopRunLoop()
            return
        }
        guard executor.performAndWait(timeout: 1, { [context, executor] in
            context.uninstall()
            executor.stopRunLoop()
        }) else { return }
    }
}

final class ScrollDirectionTapContext {
    private static let maximumConsecutiveReenables = 3

    private let lock = NSLock()
    private let statusHandler: (ScrollDirectionTapStatus) -> Void
    private var settings: ScrollDirectionSettings
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var consecutiveReenables = 0
    private var isUninstalled = false

    init(settings: ScrollDirectionSettings, statusHandler: @escaping (ScrollDirectionTapStatus) -> Void) {
        self.settings = settings
        self.statusHandler = statusHandler
    }

    func update(_ settings: ScrollDirectionSettings) {
        withLock { self.settings = settings }
    }

    func install() -> Bool {
        guard withLock({ eventTap == nil }) else { return true }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: ScrollDirectionEventTap.eventMask,
            callback: scrollDirectionTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            statusHandler(.degraded)
            return false
        }

        withLock {
            eventTap = tap
            runLoopSource = source
            consecutiveReenables = 0
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            uninstall()
            statusHandler(.degraded)
            return false
        }
        return true
    }

    func uninstall() {
        let pending = withLock { () -> (CFMachPort?, CFRunLoopSource?)? in
            guard !isUninstalled, eventTap != nil || runLoopSource != nil else { return nil }
            isUninstalled = true
            let value = (eventTap, runLoopSource)
            eventTap = nil
            runLoopSource = nil
            return value
        }
        guard let (tap, source) = pending else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap { CFMachPortInvalidate(tap) }
        withLock {
            consecutiveReenables = 0
            isUninstalled = false
        }
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenableOrDegrade()
            return nil
        case .scrollWheel:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        let decision = withLock { settings }.decision(for: classify(event))
        guard !decision.isIdentity else {
            withLock { consecutiveReenables = 0 }
            return Unmanaged.passUnretained(event)
        }
        withLock { consecutiveReenables = 0 }
        if let uniformLines = decision.uniformLines {
            ScrollDirectionTapContext.applyUniformVertical(
                lines: uniformLines,
                inverts: decision.invertsVertical,
                in: event
            )
            if decision.invertsHorizontal {
                ScrollDirectionTapContext.invertAxis(
                    in: event,
                    line: .scrollWheelEventDeltaAxis2,
                    point: .scrollWheelEventPointDeltaAxis2,
                    fixedPoint: .scrollWheelEventFixedPtDeltaAxis2
                )
            }
        } else {
            ScrollDirectionTapContext.invert(decision, in: event)
        }
        return Unmanaged.passUnretained(event)
    }

    /// Line deltas are zero on some high-resolution wheels that only fill point
    /// deltas, so the classification uses whichever axis value carries movement.
    private func classify(_ event: CGEvent) -> ScrollEventClassification {
        let lineVertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let lineHorizontal = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let pointVertical = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let pointHorizontal = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        return ScrollEventClassification(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
            momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
            verticalDelta: lineVertical != 0 ? lineVertical : pointVertical,
            horizontalDelta: lineHorizontal != 0 ? lineHorizontal : pointHorizontal
        )
    }

    private func reenableOrDegrade() {
        let tapAndCount = withLock { () -> (CFMachPort?, Int) in
            consecutiveReenables += 1
            return (eventTap, consecutiveReenables)
        }
        guard let tap = tapAndCount.0,
              tapAndCount.1 <= Self.maximumConsecutiveReenables else {
            statusHandler(.degraded)
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        if !CGEvent.tapIsEnabled(tap: tap) { statusHandler(.degraded) }
    }

    /// Quartz keeps three views of one scroll delta and they are not
    /// independent: writing the line delta recomputes the point and fixed-point
    /// deltas from it. Every original value is therefore read first, and the
    /// writes are ordered so the recomputation cannot overwrite a restored axis.
    static func invert(_ decision: ScrollDirectionDecision, in event: CGEvent) {
        if decision.invertsVertical {
            invertAxis(in: event, line: .scrollWheelEventDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1, fixedPoint: .scrollWheelEventFixedPtDeltaAxis1)
        }
        if decision.invertsHorizontal {
            invertAxis(in: event, line: .scrollWheelEventDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2, fixedPoint: .scrollWheelEventFixedPtDeltaAxis2)
        }
    }

    /// Replaces the vertical delta with a fixed number of lines per notch.
    ///
    /// macOS scales wheel deltas with rotation speed, so a slow notch and a fast
    /// notch move different distances. Writing only the line delta is what makes
    /// this uniform: Quartz derives the point (line × 8) and fixed-point views
    /// from the line value, which discards the accelerated magnitudes the driver
    /// and WindowServer supplied. `NSEvent.deltaY` and
    /// `NSEvent.scrollingDeltaY` both follow those derived fields.
    static func applyUniformVertical(lines: Int, inverts: Bool, in event: CGEvent) {
        let lineDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let pointDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedPointDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        guard lineDelta != 0 || pointDelta != 0 || fixedPointDelta != 0 else { return }

        let scrollsPositive: Bool
        if lineDelta != 0 {
            scrollsPositive = lineDelta > 0
        } else if pointDelta != 0 {
            scrollsPositive = pointDelta > 0
        } else {
            scrollsPositive = fixedPointDelta > 0
        }
        let magnitude = Int64(max(1, lines))
        let signed = (scrollsPositive ? magnitude : -magnitude) * (inverts ? -1 : 1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: signed)
    }

    static func invertAxis(
        in event: CGEvent,
        line: CGEventField,
        point: CGEventField,
        fixedPoint: CGEventField
    ) {
        let lineDelta = event.getIntegerValueField(line)
        let pointDelta = event.getIntegerValueField(point)
        let fixedPointDelta = event.getDoubleValueField(fixedPoint)

        event.setIntegerValueField(line, value: -lineDelta)
        event.setDoubleValueField(fixedPoint, value: -fixedPointDelta)
        event.setIntegerValueField(point, value: -pointDelta)
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func scrollDirectionTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let context = Unmanaged<ScrollDirectionTapContext>.fromOpaque(userInfo).takeUnretainedValue()
    return context.handle(type: type, event: event)
}
