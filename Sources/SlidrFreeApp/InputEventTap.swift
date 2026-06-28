import AppKit
import CoreGraphics
import SlidrFreeCore

/// Listen-only CGEventTap bridge that maps system events into `NormalizedInputEvent`
/// and dispatches them to the main queue for recognizer/action handling.
final class InputEventTap {
    private var _tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (NormalizedInputEvent) -> Void
    private let lock = NSLock()

    /// Whether the event tap is currently active and valid.
    var isRunning: Bool {
        lock.withLock {
            guard let tap = _tap else { return false }
            return CFMachPortIsValid(tap)
        }
    }

    init(handler: @escaping (NormalizedInputEvent) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Start listening for middle-click events.
    /// Requires accessibility permissions; silently no-ops if already running.
    func start() {
        lock.withLock {
            guard _tap == nil else { return }

            let eventMask = CGEventMask(
                (1 << CGEventType.otherMouseDown.rawValue)
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

            _tap = newTap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
    }

    /// Stop listening and clean up the event tap.
    func stop() {
        lock.withLock {
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                runLoopSource = nil
            }
            if let existingTap = _tap {
                CGEvent.tapEnable(tap: existingTap, enable: false)
                CFMachPortInvalidate(existingTap)
                _tap = nil
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(type: CGEventType, event: CGEvent) {
        switch type {
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
            lock.withLock {
                if let existingTap = _tap {
                    CGEvent.tapEnable(tap: existingTap, enable: true)
                }
            }

        default:
            break
        }
    }
}
