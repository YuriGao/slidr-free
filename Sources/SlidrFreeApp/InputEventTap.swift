import AppKit
import CoreGraphics
import SlidrFreeCore

/// Listen-only CGEventTap bridge that maps system events into `NormalizedInputEvent`
/// and dispatches them to the main queue for recognizer/action handling.
final class InputEventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (NormalizedInputEvent) -> Void

    /// Whether the event tap is currently active and valid.
    var isRunning: Bool {
        guard let tap = tap else { return false }
        return CFMachPortIsValid(tap)
    }

    init(handler: @escaping (NormalizedInputEvent) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Start listening for scroll, key-down, and middle-click events.
    /// Requires accessibility permissions; silently no-ops if already running.
    func start() {
        guard tap == nil else { return }

        let eventMask = CGEventMask(
            (1 << CGEventType.scrollWheel.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.otherMouseDown.rawValue)
        )

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let tapInstance = Unmanaged<InputEventTap>.fromOpaque(refcon).takeUnretainedValue()
                tapInstance.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[SlidrFree] InputEventTap: Failed to create event tap (permissions may be missing)")
            return
        }

        tap = newTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }

    /// Stop listening and clean up the event tap.
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let existingTap = tap {
            CGEvent.tapEnable(tap: existingTap, enable: false)
            CFMachPortInvalidate(existingTap)
            tap = nil
        }
    }

    // MARK: - Event Handling

    private func handleEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .scrollWheel:
            let location = event.location
            let deltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let timestamp = Double(event.timestamp)
            let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
            let normalized = NormalizedInputEvent.scroll(
                x: location.x,
                y: location.y,
                deltaY: deltaY,
                timestamp: timestamp,
                screenSize: screenSize
            )
            DispatchQueue.main.async { [handler] in
                handler(normalized)
            }

        case .keyDown:
            let normalized = NormalizedInputEvent.keyDown(timestamp: Double(event.timestamp))
            DispatchQueue.main.async { [handler] in
                handler(normalized)
            }

        case .otherMouseDown:
            let location = event.location
            let normalized = NormalizedInputEvent.middleClick(
                x: location.x,
                y: location.y,
                timestamp: Double(event.timestamp)
            )
            DispatchQueue.main.async { [handler] in
                handler(normalized)
            }

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let existingTap = tap {
                CGEvent.tapEnable(tap: existingTap, enable: true)
            }

        default:
            break
        }
    }
}
