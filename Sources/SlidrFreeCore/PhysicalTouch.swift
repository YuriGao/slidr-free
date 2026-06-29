import Foundation

public struct PhysicalTouch: Equatable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double
    public let pressure: Double?
    public let state: Int?

    public init(id: Int, x: Double, y: Double, pressure: Double? = nil, state: Int? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.pressure = pressure
        self.state = state
    }
}

public enum PhysicalEdgeHit: Equatable, Sendable {
    case left
    case right
    case top
}
