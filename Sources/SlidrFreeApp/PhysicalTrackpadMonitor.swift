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
    private let lock = NSLock()

    private var libraryHandle: UnsafeMutableRawPointer?
    private var device: MTDeviceRef?
    private var deviceStop: MTDeviceStopFunction?
    private var running = false
    private var generation: UInt64 = 0

    private struct PreparedDeviceStart {
        let device: MTDeviceRef
        let startDevice: MTDeviceStartFunction
        let stopDevice: MTDeviceStopFunction
        let generation: UInt64
    }

    var isRunning: Bool {
        lock.withLock { running }
    }

    init(handler: @escaping (NormalizedInputEvent) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
        if let libraryHandle {
            dlclose(libraryHandle)
        }
    }

    func start() {
        let preparedStart = lock.withLock { () -> PreparedDeviceStart? in
            guard !running else { return nil }
            generation &+= 1

            return prepareStartLocked(generation: generation)
        }

        guard let preparedStart else { return }

        guard preparedStart.startDevice(preparedStart.device, 0) == 0 else {
            _ = preparedStart.stopDevice(preparedStart.device)
            Self.registryLock.withLock {
                _ = Self.monitorsByDevice.removeValue(forKey: UInt(bitPattern: preparedStart.device))
            }
            lock.withLock {
                if device == preparedStart.device {
                    device = nil
                    deviceStop = nil
                }
                failLocked("MTDeviceStart failed")
            }
            return
        }

        lock.withLock {
            guard device == preparedStart.device, generation == preparedStart.generation else { return }
            running = true
        }
    }

    func stop() {
        let deviceToStop = lock.withLock { () -> (device: MTDeviceRef, stop: MTDeviceStopFunction)? in
            guard running || device != nil else { return nil }

            running = false
            generation &+= 1

            let deviceToStop = device.flatMap { device in deviceStop.map { (device, $0) } }

            device = nil
            deviceStop = nil

            return deviceToStop
        }

        if let deviceToStop {
            _ = deviceToStop.stop(deviceToStop.device)
            Self.registryLock.withLock {
                _ = Self.monitorsByDevice.removeValue(forKey: UInt(bitPattern: deviceToStop.device))
            }
        }
    }

    private func prepareStartLocked(generation: UInt64) -> PreparedDeviceStart? {
        if libraryHandle == nil {
            guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else {
                failLocked("MultitouchSupport unavailable: \(dlerrorString())")
                return nil
            }
            libraryHandle = handle
        }

        guard let handle = libraryHandle else {
            failLocked("MultitouchSupport unavailable")
            return nil
        }

        guard
            let create: MTDeviceCreateDefaultFunction = loadSymbol("MTDeviceCreateDefault", from: handle),
            let registerCallback: MTRegisterContactFrameCallbackFunction = loadSymbol("MTRegisterContactFrameCallback", from: handle),
            let startDevice: MTDeviceStartFunction = loadSymbol("MTDeviceStart", from: handle),
            let stopDevice: MTDeviceStopFunction = loadSymbol("MTDeviceStop", from: handle)
        else {
            failLocked("MultitouchSupport missing required symbols")
            return nil
        }

        guard let newDevice = create() else {
            failLocked("MTDeviceCreateDefault returned nil")
            return nil
        }

        device = newDevice
        deviceStop = stopDevice
        Self.registryLock.withLock {
            Self.monitorsByDevice[UInt(bitPattern: newDevice)] = WeakMonitor(self)
        }
        registerCallback(newDevice, Self.contactFrameCallback)

        return PreparedDeviceStart(device: newDevice, startDevice: startDevice, stopDevice: stopDevice, generation: generation)
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

        DispatchQueue.main.async { [weak self, handler] in
            guard self?.isCurrentFrameGeneration(frameGeneration) == true else { return }
            handler(.physicalTouchFrame(touches: physicalTouches, timestamp: timestamp))
        }
    }

    private func isCurrentFrameGeneration(_ frameGeneration: UInt64) -> Bool {
        lock.withLock { running && generation == frameGeneration }
    }

    private func dropFrame(reason: String) {
    }

    private func failLocked(_ reason: String) {
        running = false
        generation &+= 1
        device = nil
    }

    private func dlerrorString() -> String {
        guard let error = dlerror() else { return "unknown error" }
        return String(cString: error)
    }
}
