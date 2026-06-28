import Foundation

final class DebugState: ObservableObject {
    @Published var accessibility = ""
    @Published var inputMonitoring = ""
    @Published var multitouchStatus = "Not connected"
    @Published var deviceStatus = "Unknown"
    @Published var monitorStatus = "Stopped"
    @Published var lastTouchCount = 0
    @Published var lastTouchDescription = "None"
    @Published var lastEdgeHit = "None"
    @Published var lastGesture = "None"
    @Published var lastAction = "None"
    @Published var lastActionResult = "None"
    @Published var logs: [String] = []

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        logs.append("[\(formatter.string(from: Date()))] \(message)")
        if logs.count > 50 {
            logs.removeFirst(logs.count - 50)
        }
    }
}
