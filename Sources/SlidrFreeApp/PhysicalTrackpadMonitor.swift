import Darwin
import Foundation
import SlidrFreeCore

struct PhysicalTrackpadMonitorStatus: Sendable {
    let frameworkAvailable: Bool
    let deviceAvailable: Bool
    let state: TouchMonitorRuntimeState
    let failure: String?
}

struct PhysicalTouchAdapter {
    let maximumTouchCount: Int

    init(maximumTouchCount: Int = 16) {
        self.maximumTouchCount = maximumTouchCount
    }

    func adapt(
        count: Int,
        touches: [PhysicalTouch]?,
        generation: UInt64,
        sequence: UInt64,
        timestamp: Double,
        receivedAt: Double
    ) -> MiddleClickInputUpdate {
        guard count >= 0, count <= maximumTouchCount else {
            return .cancel(
                generation: generation,
                sequence: sequence,
                receivedAt: receivedAt,
                reason: .invalidTouchCount
            )
        }

        if count == 0 {
            return .empty(
                generation: generation,
                sequence: sequence,
                timestamp: timestamp,
                receivedAt: receivedAt
            )
        }

        guard let touches else {
            return .cancel(
                generation: generation,
                sequence: sequence,
                receivedAt: receivedAt,
                reason: .missingBuffer
            )
        }

        guard touches.count == count else {
            return .cancel(
                generation: generation,
                sequence: sequence,
                receivedAt: receivedAt,
                reason: .invalidTouchCount
            )
        }

        return .frame(
            generation: generation,
            sequence: sequence,
            timestamp: timestamp,
            receivedAt: receivedAt,
            touches: touches
        )
    }
}

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
    private let middleClickUpdateHandler: (MiddleClickInputUpdate) -> Void
    private let statusHandler: (PhysicalTrackpadMonitorStatus) -> Void
    private let adapter = PhysicalTouchAdapter(maximumTouchCount: maxTouchCount)
    private let lock = NSLock()

    private var libraryHandle: UnsafeMutableRawPointer?
    private var device: MTDeviceRef?
    private var deviceStop: MTDeviceStopFunction?
    private var running = false
    private let generation: UInt64
    private var frameSequence: UInt64 = 0

    private struct PreparedDeviceStart {
        let device: MTDeviceRef
        let startDevice: MTDeviceStartFunction
        let stopDevice: MTDeviceStopFunction
        let generation: UInt64
    }

    var isRunning: Bool {
        lock.withLock { running }
    }

    init(
        generation: UInt64 = 1,
        statusHandler: @escaping (PhysicalTrackpadMonitorStatus) -> Void = { _ in },
        middleClickUpdateHandler: @escaping (MiddleClickInputUpdate) -> Void = { _ in },
        handler: @escaping (NormalizedInputEvent) -> Void
    ) {
        self.generation = generation
        self.statusHandler = statusHandler
        self.middleClickUpdateHandler = middleClickUpdateHandler
        self.handler = handler
    }

    deinit {
        stop()
        if let libraryHandle {
            dlclose(libraryHandle)
        }
    }

    @discardableResult
    func start() -> Bool {
        let preparedStart = lock.withLock { () -> PreparedDeviceStart? in
            guard !running else { return nil }
            return prepareStartLocked(generation: generation)
        }
        guard let preparedStart else { return isRunning }

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
            report(framework: true, device: true, state: .unavailable, failure: "MTDeviceStart failed")
            return false
        }

        let committed = lock.withLock { () -> Bool in
            guard device == preparedStart.device, generation == preparedStart.generation else { return false }
            running = true
            return true
        }
        guard committed else { return false }
        report(framework: true, device: true, state: .running, failure: nil)
        return true
    }

    func stop() {
        let stopped = lock.withLock { () -> (
            deviceToStop: (device: MTDeviceRef, stop: MTDeviceStopFunction)?,
            cancellation: MiddleClickInputUpdate,
            hadDevice: Bool
        )? in
            guard running || device != nil else { return nil }

            running = false
            frameSequence &+= 1

            let deviceToStop = device.flatMap { device in deviceStop.map { (device, $0) } }
            let hadDevice = device != nil
            let cancellation = MiddleClickInputUpdate.cancel(
                generation: generation,
                sequence: frameSequence,
                receivedAt: ProcessInfo.processInfo.systemUptime,
                reason: .monitorStopped
            )

            device = nil
            deviceStop = nil

            return (deviceToStop, cancellation, hadDevice)
        }

        guard let stopped else { return }
        middleClickUpdateHandler(stopped.cancellation)
        DispatchQueue.main.async { [handler] in
            handler(.physicalTouchCancelled)
        }

        if let deviceToStop = stopped.deviceToStop {
            _ = deviceToStop.stop(deviceToStop.device)
            Self.registryLock.withLock {
                _ = Self.monitorsByDevice.removeValue(forKey: UInt(bitPattern: deviceToStop.device))
            }
        }
        report(framework: libraryHandle != nil, device: stopped.hadDevice, state: .stopped, failure: nil)
    }

    private func prepareStartLocked(generation: UInt64) -> PreparedDeviceStart? {
        report(framework: true, device: false, state: .starting, failure: nil)
        if libraryHandle == nil {
            guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else {
                failLocked("MultitouchSupport unavailable: \(dlerrorString())")
                report(framework: false, device: false, state: .unavailable, failure: "MultitouchSupport unavailable")
                return nil
            }
            libraryHandle = handle
        }

        guard let handle = libraryHandle else {
            failLocked("MultitouchSupport unavailable")
            report(framework: false, device: false, state: .unavailable, failure: "MultitouchSupport unavailable")
            return nil
        }

        guard
            let create: MTDeviceCreateDefaultFunction = loadSymbol("MTDeviceCreateDefault", from: handle),
            let registerCallback: MTRegisterContactFrameCallbackFunction = loadSymbol("MTRegisterContactFrameCallback", from: handle),
            let startDevice: MTDeviceStartFunction = loadSymbol("MTDeviceStart", from: handle),
            let stopDevice: MTDeviceStopFunction = loadSymbol("MTDeviceStop", from: handle)
        else {
            failLocked("MultitouchSupport missing required symbols")
            report(framework: false, device: false, state: .unavailable, failure: "MultitouchSupport missing required symbols")
            return nil
        }

        guard let newDevice = create() else {
            failLocked("MTDeviceCreateDefault returned nil")
            report(framework: true, device: false, state: .unavailable, failure: "No default multitouch device")
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

        monitor.handleFrame(touchBytes: touchBytes, count: Int(count), timestamp: timestamp)
    }

    private func handleFrame(touchBytes: UnsafeMutableRawPointer?, count: Int, timestamp: Double) {
        let receivedAt = ProcessInfo.processInfo.systemUptime
        var frameGeneration: UInt64 = 0
        var sequence: UInt64 = 0
        let shouldRead = lock.withLock { () -> Bool in
            guard running else { return false }
            frameGeneration = generation
            frameSequence &+= 1
            sequence = frameSequence
            return true
        }
        guard shouldRead else { return }

        let physicalTouches: [PhysicalTouch]?
        if count > 0, count <= Self.maxTouchCount, let touchBytes {
            let touches = touchBytes.assumingMemoryBound(to: MTTouch.self)
            physicalTouches = (0..<count).map { index -> PhysicalTouch in
                let touch = touches[index]
                return PhysicalTouch(
                    id: Int(touch.identifier),
                    x: Double(touch.normalizedPosition.x),
                    y: Double(touch.normalizedPosition.y),
                    pressure: Double(touch.pressure),
                    state: Int(touch.state)
                )
            }
        } else {
            physicalTouches = nil
        }

        let update = adapter.adapt(
            count: count,
            touches: physicalTouches,
            generation: frameGeneration,
            sequence: sequence,
            timestamp: timestamp,
            receivedAt: receivedAt
        )

        middleClickUpdateHandler(update)

        DispatchQueue.main.async { [weak self, handler] in
            guard self?.isCurrentFrameGeneration(frameGeneration) == true else { return }
            switch update {
            case .frame(_, _, let timestamp, _, let touches):
                handler(.physicalTouchFrame(touches: touches, timestamp: timestamp))
            case .empty(_, _, let timestamp, _):
                handler(.physicalTouchFrame(touches: [], timestamp: timestamp))
            case .cancel:
                handler(.physicalTouchCancelled)
            }
        }
    }

    private func isCurrentFrameGeneration(_ frameGeneration: UInt64) -> Bool {
        lock.withLock { running && generation == frameGeneration }
    }

    private func failLocked(_ reason: String) {
        running = false
        device = nil
    }

    private func report(framework: Bool, device: Bool, state: TouchMonitorRuntimeState, failure: String?) {
        statusHandler(PhysicalTrackpadMonitorStatus(frameworkAvailable: framework, deviceAvailable: device, state: state, failure: failure.map { String($0.prefix(160)) }))
    }

    private func dlerrorString() -> String {
        guard let error = dlerror() else { return "unknown error" }
        return String(cString: error)
    }
}
