import Darwin
import Foundation
import SlidrFreeCore

/// Experimental bridge to the private MultitouchSupport framework.
///
/// Keep all private API surface in this file. The monitor fails closed when the
/// framework or any required symbol is unavailable.
final class PhysicalTrackpadMonitor {
    private typealias MTDeviceRef = UnsafeMutableRawPointer

    private struct MTPoint {
        var x: Float
        var y: Float
    }

    private struct MTVector {
        var position: MTPoint
        var velocity: MTPoint
    }

    private struct MTTouch {
        var frame: Int32
        var timestamp: Double
        var identifier: Int32
        var state: Int32
        var finger: Int32
        var hand: Int32
        var normalized: MTVector
        var size: Float
        var zero1: Int32
        var angle: Float
        var majorAxis: Float
        var minorAxis: Float
        var zero2: MTVector
        var zero3: Int32
        var zero4: Int32
        var pressure: Float

        var normalizedPosition: MTPoint { normalized.position }
    }

    private typealias ContactFrameCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Void
    private typealias MTDeviceCreateDefaultFunction = @convention(c) () -> MTDeviceRef?
    private typealias MTRegisterContactFrameCallbackFunction = @convention(c) (MTDeviceRef?, ContactFrameCallback?) -> Void
    private typealias MTDeviceStartFunction = @convention(c) (MTDeviceRef?, Int32) -> Int32
    private typealias MTDeviceStopFunction = @convention(c) (MTDeviceRef?) -> Int32

    private final class WeakMonitor {
        weak var monitor: PhysicalTrackpadMonitor?

        init(_ monitor: PhysicalTrackpadMonitor) {
            self.monitor = monitor
        }
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private static let maxTouchCount = 16
    private static let registryLock = NSLock()
    private static var monitorsByDevice: [UInt: WeakMonitor] = [:]

    private let handler: (NormalizedInputEvent) -> Void
    private weak var debugState: DebugState?
    private let lock = NSLock()

    private var libraryHandle: UnsafeMutableRawPointer?
    private var device: MTDeviceRef?
    private var deviceStop: MTDeviceStopFunction?
    private var running = false
    private var generation: UInt64 = 0

    var isRunning: Bool {
        lock.withLock { running }
    }

    init(debugState: DebugState, handler: @escaping (NormalizedInputEvent) -> Void) {
        self.debugState = debugState
        self.handler = handler
    }

    deinit {
        stop()
        if let libraryHandle {
            dlclose(libraryHandle)
        }
    }

    func start() {
        lock.withLock {
            guard !running else { return }
            generation &+= 1

            guard loadAndStartLocked() else { return }
            running = true
            updateDebug(multitouch: "Running", device: "Physical trackpad monitor")
        }
    }

    func stop() {
        lock.withLock {
            guard running || device != nil else { return }

            running = false
            generation &+= 1

            if let device, let deviceStop {
                _ = deviceStop(device)
                Self.registryLock.withLock {
                    _ = Self.monitorsByDevice.removeValue(forKey: UInt(bitPattern: device))
                }
            }

            device = nil
            updateDebug(multitouch: "Stopped", device: "Physical trackpad unavailable")
        }
    }

    private func loadAndStartLocked() -> Bool {
        if libraryHandle == nil {
            guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else {
                failLocked("MultitouchSupport unavailable: \(dlerrorString())")
                return false
            }
            libraryHandle = handle
        }

        guard let handle = libraryHandle else {
            failLocked("MultitouchSupport unavailable")
            return false
        }

        guard
            let create: MTDeviceCreateDefaultFunction = loadSymbol("MTDeviceCreateDefault", from: handle),
            let registerCallback: MTRegisterContactFrameCallbackFunction = loadSymbol("MTRegisterContactFrameCallback", from: handle),
            let startDevice: MTDeviceStartFunction = loadSymbol("MTDeviceStart", from: handle),
            let stopDevice: MTDeviceStopFunction = loadSymbol("MTDeviceStop", from: handle)
        else {
            failLocked("MultitouchSupport missing required symbols")
            return false
        }

        guard let newDevice = create() else {
            failLocked("MTDeviceCreateDefault returned nil")
            return false
        }

        device = newDevice
        deviceStop = stopDevice
        Self.registryLock.withLock {
            Self.monitorsByDevice[UInt(bitPattern: newDevice)] = WeakMonitor(self)
        }
        registerCallback(newDevice, Self.contactFrameCallback)

        guard startDevice(newDevice, 0) == 0 else {
            _ = stopDevice(newDevice)
            Self.registryLock.withLock {
                _ = Self.monitorsByDevice.removeValue(forKey: UInt(bitPattern: newDevice))
            }
            device = nil
            failLocked("MTDeviceStart failed")
            return false
        }

        return true
    }

    private func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static let contactFrameCallback: ContactFrameCallback = { device, touchBytes, count, timestamp, _ in
        guard let device else { return }
        let monitor = registryLock.withLock { monitorsByDevice[UInt(bitPattern: device)]?.monitor }
        guard let monitor else { return }

        guard count >= 0, count <= maxTouchCount else {
            monitor.dropFrame(reason: "invalid touch count \(count)")
            return
        }

        guard let touchBytes else {
            monitor.dropFrame(reason: "missing touch buffer")
            return
        }

        monitor.handleFrame(touches: touchBytes.assumingMemoryBound(to: MTTouch.self), count: Int(count), timestamp: timestamp)
    }

    private func handleFrame(touches: UnsafeMutablePointer<MTTouch>, count: Int, timestamp: Double) {
        var frameGeneration: UInt64 = 0
        let shouldRead = lock.withLock { () -> Bool in
            guard running else { return false }
            frameGeneration = generation
            return true
        }
        guard shouldRead else { return }

        let physicalTouches = (0..<count).map { index -> PhysicalTouch in
            let touch = touches[index]
            return PhysicalTouch(
                id: Int(touch.identifier),
                x: Double(touch.normalizedPosition.x),
                y: Double(touch.normalizedPosition.y),
                pressure: Double(touch.pressure),
                state: Int(touch.state)
            )
        }

        DispatchQueue.main.async { [weak self, handler, weak debugState] in
            guard self?.isCurrentFrameGeneration(frameGeneration) == true else { return }
            debugState?.multitouchStatus = "Receiving frames"
            debugState?.deviceStatus = "Physical trackpad"
            handler(.physicalTouchFrame(touches: physicalTouches, timestamp: timestamp))
        }
    }

    private func isCurrentFrameGeneration(_ frameGeneration: UInt64) -> Bool {
        lock.withLock { running && generation == frameGeneration }
    }

    private func dropFrame(reason: String) {
        DispatchQueue.main.async { [weak self, weak debugState] in
            guard self?.isRunning == true else { return }
            debugState?.log("Multitouch: dropped frame (\(reason))")
        }
    }

    private func failLocked(_ reason: String) {
        running = false
        generation &+= 1
        device = nil
        updateDebug(multitouch: "Failed: \(reason)", device: "Physical trackpad unavailable")
    }

    private func updateDebug(multitouch: String, device: String) {
        DispatchQueue.main.async { [weak debugState] in
            debugState?.setMultitouchStatus(multitouch, deviceStatus: device)
            debugState?.log("Multitouch: \(multitouch)")
        }
    }

    private func dlerrorString() -> String {
        guard let error = dlerror() else { return "unknown error" }
        return String(cString: error)
    }
}
