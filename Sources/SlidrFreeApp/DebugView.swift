import SwiftUI

struct DebugView: View {
    @ObservedObject var state: DebugState

    var body: some View {
        Form {
            Section("Permissions") {
                statusRow("Accessibility", state.accessibility)
                statusRow("Input Monitoring", state.inputMonitoring)
            }
            Section("Physical Trackpad") {
                statusRow("Multitouch Status", state.multitouchStatus)
                statusRow("Device Status", state.deviceStatus)
                statusRow("Monitor Status", state.monitorStatus)
                statusRow("Last Touch Count", String(state.lastTouchCount))
                statusRow("Last Touch", state.lastTouchDescription)
                statusRow("Last Edge Hit", state.lastEdgeHit)
            }
            Section("Recognition") {
                statusRow("Last Gesture", state.lastGesture)
                statusRow("Last Action", state.lastAction)
                statusRow("Last Action Result", state.lastActionResult)
            }
            Section {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(state.logs.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(6)
                }.frame(minHeight: 160)
                Button("Clear Logs") { state.logs.removeAll() }
            } header: { Text("Logs") }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560, height: 640)
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}
