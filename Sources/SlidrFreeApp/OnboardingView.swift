import AppKit
import SwiftUI
import SlidrFreeCore

struct OnboardingView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var pipelineStatus: InputPipelineStatus
    @ObservedObject var gestureTestController: GestureTestController
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule().fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.2)).frame(height: 5)
                }
            }.padding(.horizontal, 34).padding(.top, 24)

            Group {
                switch step {
                case 0: compatibilityStep
                case 1: permissionStep
                case 2: mappingStep
                default: verificationStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)

            Divider()
            HStack {
                Button(NSLocalizedString("setup_later", comment: "")) {
                    gestureTestController.stop()
                    NSApp.keyWindow?.close()
                }
                Spacer()
                if step > 0 { Button(NSLocalizedString("back", comment: "")) { step -= 1 } }
                if step < 3 {
                    Button(NSLocalizedString("continue", comment: "")) { advance() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 1 && permissionManager.snapshot.accessibility != .granted)
                } else {
                    Button(NSLocalizedString("finish_setup", comment: ""), action: complete)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!gestureTestController.didRecognizeGesture)
                }
            }.padding(20)
        }
        .onChange(of: step) { value in
            gestureTestController.stop()
            if value == 0 { gestureTestController.start(.edge) }
        }
        .onAppear { gestureTestController.start(.edge) }
        .onDisappear { gestureTestController.stop() }
    }

    private var compatibilityStep: some View {
        VStack(spacing: 20) {
            stepHeader(icon: "checkmark.shield", title: "onboarding_compatibility_title", subtitle: "onboarding_compatibility_subtitle")
            VStack(spacing: 12) {
                checkRow("diagnostic_framework", state: pipelineStatus.frameworkAvailable)
                checkRow("diagnostic_device", state: pipelineStatus.deviceAvailable)
                HStack {
                    Image(systemName: "desktopcomputer")
                    Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    Spacer()
                    Text(NSLocalizedString("supported", comment: "")).foregroundStyle(.secondary)
                }
            }
            .padding(16).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Text(NSLocalizedString("onboarding_compatibility_note", comment: ""))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var permissionStep: some View {
        VStack(spacing: 22) {
            stepHeader(icon: "hand.raised", title: "onboarding_permission_title", subtitle: "onboarding_permission_subtitle")
            Label(
                localizedPermission,
                systemImage: permissionManager.snapshot.accessibility == .granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(permissionManager.snapshot.accessibility == .granted ? .green : .orange)
            if permissionManager.snapshot.accessibility != .granted {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("permission_steps", comment: ""))
                    Text(NSLocalizedString("permission_step_1", comment: ""))
                    Text(NSLocalizedString("permission_step_2", comment: ""))
                    Text(NSLocalizedString("permission_step_3", comment: ""))
                }.frame(maxWidth: 440, alignment: .leading).foregroundStyle(.secondary)
                HStack {
                    Button(NSLocalizedString("grant_accessibility", comment: "")) { permissionManager.promptForAccessibility() }
                        .keyboardShortcut(.defaultAction)
                    Button(NSLocalizedString("open_accessibility_settings", comment: "")) { permissionManager.openAccessibilitySettings() }
                }
            }
        }
    }

    private var mappingStep: some View {
        VStack(spacing: 20) {
            stepHeader(icon: "rectangle.and.hand.point.up.left", title: "onboarding_mapping_title", subtitle: "onboarding_mapping_subtitle")
            HStack(spacing: 28) {
                TrackpadOnboardingDiagram(settings: store.settings).frame(width: 260, height: 190)
                VStack(spacing: 16) {
                    Picker(NSLocalizedString("left_edge", comment: ""), selection: binding(\.edgeAssignments.left)) {
                        sideActions
                    }
                    Picker(NSLocalizedString("right_edge", comment: ""), selection: binding(\.edgeAssignments.right)) {
                        sideActions
                    }
                    Picker(NSLocalizedString("top_edge", comment: ""), selection: binding(\.edgeAssignments.top)) {
                        ForEach(TopEdgeAction.allCases, id: \.self) { action in
                            Text(NSLocalizedString("top_action_\(action.rawValue)", comment: "")).tag(action)
                        }
                    }
                }.frame(width: 270)
            }
            Text(NSLocalizedString("mapping_direction_help", comment: "")).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var verificationStep: some View {
        VStack(spacing: 22) {
            stepHeader(icon: "waveform.path", title: "onboarding_test_title", subtitle: "onboarding_test_subtitle")
            Image(systemName: gestureTestController.didRecognizeGesture ? "checkmark.circle.fill" : "hand.draw")
                .font(.system(size: 64)).foregroundStyle(gestureTestController.didRecognizeGesture ? .green : .accentColor)
                .accessibilityHidden(true)
            if gestureTestController.kind == .edge {
                Text(String(format: NSLocalizedString("test_seconds_remaining", comment: ""), gestureTestController.secondsRemaining)).foregroundStyle(.secondary)
            } else {
                Button(NSLocalizedString("start_safe_test", comment: "")) { gestureTestController.start(.edge) }
            }
            Text(gestureTestController.feedback ?? NSLocalizedString("gesture_test_waiting", comment: ""))
                .font(.headline).multilineTextAlignment(.center)
            Text(NSLocalizedString("test_no_side_effects", comment: "")).font(.callout).foregroundStyle(.secondary)
        }
        .onAppear { gestureTestController.start(.edge) }
    }

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(Color.accentColor)
            Text(NSLocalizedString(title, comment: "")).font(.largeTitle.bold())
            Text(NSLocalizedString(subtitle, comment: "")).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func checkRow(_ key: String, state: Bool?) -> some View {
        HStack {
            Image(systemName: state == false ? "xmark.circle.fill" : (state == true ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"))
                .foregroundStyle(state == false ? .red : (state == true ? .green : .secondary))
            Text(NSLocalizedString(key, comment: ""))
            Spacer()
            Text(NSLocalizedString(state == nil ? "checking" : (state! ? "available" : "unavailable"), comment: "")).foregroundStyle(.secondary)
        }
    }

    private var localizedPermission: String {
        NSLocalizedString(permissionManager.snapshot.accessibility == .granted ? "permission_granted_message" : "permission_required_message", comment: "")
    }

    private var sideActions: some View {
        ForEach(SideEdgeAction.allCases, id: \.self) { action in
            Text(NSLocalizedString("side_action_\(action.rawValue)", comment: "")).tag(action)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in
            var updated = store.settings; updated[keyPath: keyPath] = value; store.save(updated)
        })
    }

    private func advance() {
        if step == 0 && pipelineStatus.frameworkAvailable == false { return }
        step += 1
    }

    private func complete() {
        gestureTestController.stop()
        var updated = store.settings
        updated.experience.onboardingVersion = ExperienceSettings.currentOnboardingVersion
        updated.experience.hasSeenV04Welcome = true
        updated.isAppEnabled = permissionManager.snapshot.accessibility == .granted && pipelineStatus.deviceAvailable != false
        store.save(updated)
    }
}

private struct TrackpadOnboardingDiagram: View {
    let settings: AppSettings
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.4), lineWidth: 2)
            HStack {
                mappingLabel(side(settings.edgeAssignments.left), "arrow.up.and.down")
                Spacer()
                mappingLabel(side(settings.edgeAssignments.right), "arrow.up.and.down")
            }.padding(14)
            VStack { mappingLabel(top(settings.edgeAssignments.top), "arrow.left.and.right"); Spacer() }.padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NSLocalizedString("trackpad_mapping_diagram", comment: ""))
    }
    private func mappingLabel(_ title: String, _ icon: String) -> some View { VStack { Image(systemName: icon); Text(title).font(.caption.bold()) } }
    private func side(_ action: SideEdgeAction) -> String { NSLocalizedString("side_action_\(action.rawValue)", comment: "") }
    private func top(_ action: TopEdgeAction) -> String { NSLocalizedString("top_action_\(action.rawValue)", comment: "") }
}
