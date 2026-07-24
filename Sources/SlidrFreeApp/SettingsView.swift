import AppKit
import SwiftUI
import SlidrFreeCore
import UniformTypeIdentifiers

private enum SettingsSection: String, CaseIterable, Identifiable {
    case overview
    case edges
    case corners
    case middleClick
    case diagnostics

    var id: String { rawValue }
    var title: String { NSLocalizedString("nav_\(rawValue)", comment: "") }
    var icon: String {
        switch self {
        case .overview: return "heart.text.square"
        case .edges: return "rectangle.and.hand.point.up.left"
        case .corners: return "square.grid.2x2"
        case .middleClick: return "computermouse"
        case .diagnostics: return "stethoscope"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var pipelineStatus: InputPipelineStatus
    @ObservedObject var gestureTestController: GestureTestController
    @State private var selection: SettingsSection? = .overview
    @State private var launchAtLoginError: String?
    @State private var appSelectionError: String?
    @State private var showResetConfirmation = false
    @State private var diagnosticPreview: DiagnosticPreview?
    @State private var showCompatibility = false
    @State private var showPermissionRecovery = false

    private let healthResolver = AppHealthResolver()

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView(
                    store: store,
                    permissionManager: permissionManager,
                    pipelineStatus: pipelineStatus,
                    gestureTestController: gestureTestController
                )
            } else {
                NavigationSplitView {
                    List(SettingsSection.allCases, selection: $selection) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                    .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
                } detail: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            banners
                            detailView
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .onChange(of: selection) { _ in gestureTestController.stop() }
        .onDisappear { gestureTestController.stop() }
        .sheet(item: $diagnosticPreview) { preview in
            DiagnosticPreviewSheet(text: preview.text) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(preview.text, forType: .string)
                diagnosticPreview = nil
            } cancel: {
                diagnosticPreview = nil
            }
        }
        .confirmationDialog(
            NSLocalizedString("reset_settings_title", comment: ""),
            isPresented: $showResetConfirmation
        ) {
            Button(NSLocalizedString("reset_settings_confirm", comment: ""), role: .destructive) {
                gestureTestController.stop()
                store.restoreDefaults()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("reset_settings_message", comment: ""))
        }
    }

    private var needsOnboarding: Bool {
        store.settings.experience.onboardingVersion < ExperienceSettings.currentOnboardingVersion
    }

    @ViewBuilder private var banners: some View {
        if !store.settings.experience.hasSeenV04Welcome {
            BannerView(
                text: NSLocalizedString("v04_welcome_banner", comment: ""),
                actionTitle: NSLocalizedString("got_it", comment: "")
            ) {
                var updated = store.settings
                updated.experience.hasSeenV04Welcome = true
                store.save(updated)
            }
        }
        if let diagnostic = store.lastLoadDiagnostic {
            BannerView(
                text: NSLocalizedString("settings_restored_banner", comment: ""),
                actionTitle: NSLocalizedString("view_diagnostics", comment: "")
            ) {
                selection = .diagnostics
                store.dismissLoadDiagnostic()
            }
            .accessibilityHint(diagnostic)
        }
        if store.lastSaveDiagnostic != nil {
            BannerView(text: NSLocalizedString("settings_save_error", comment: ""))
        }
        if let launchAtLoginError {
            BannerView(text: launchAtLoginError)
        }
        if let appSelectionError {
            BannerView(text: appSelectionError)
        }
    }

    @ViewBuilder private var detailView: some View {
        switch selection ?? .overview {
        case .overview: overview
        case .edges: edgeSettings
        case .corners: cornerSettings
        case .middleClick: middleClickSettings
        case .diagnostics: diagnostics
        }
    }

    private var currentHealth: AppHealthState {
        healthResolver.resolve(settings: store.settings, permission: permissionManager.snapshot, pipeline: pipelineStatus)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("nav_overview", subtitleKey: "overview_subtitle")
            HealthCard(health: currentHealth, action: performHealthAction)

            GroupBox(NSLocalizedString("overview_general", comment: "")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(NSLocalizedString("enable_app_toggle", comment: ""), isOn: binding(\.isAppEnabled))
                    Toggle(NSLocalizedString("launch_at_login", comment: ""), isOn: launchAtLoginBinding)
                    Divider()
                    HStack {
                        Text(NSLocalizedString("recent_touch", comment: ""))
                        Spacer()
                        RecentTouchText(pipelineStatus: pipelineStatus)
                    }
                }.padding(8)
            }

            DisclosureGroup(NSLocalizedString("compatibility_notes", comment: ""), isExpanded: $showCompatibility) {
                Text(NSLocalizedString("physical_trackpad_experimental_warning", comment: ""))
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }

    private var edgeSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("nav_edges", subtitleKey: "edges_subtitle")
            HStack(alignment: .top, spacing: 24) {
                TrackpadDiagram(settings: store.settings)
                    .frame(width: 250, height: 190)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(NSLocalizedString("trackpad_mapping_diagram", comment: ""))
                VStack(alignment: .leading, spacing: 14) {
                    sideEdgePicker("left_edge", keyPath: \.edgeAssignments.left)
                    sideEdgePicker("right_edge", keyPath: \.edgeAssignments.right)
                    topEdgePicker
                }
                .frame(maxWidth: .infinity)
            }
            if duplicateSideAssignment {
                Label(NSLocalizedString("duplicate_edge_hint", comment: ""), systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            labeledSlider(
                NSLocalizedString("edge_width", comment: ""),
                keyPath: \.gesture.edgeWidthPercent,
                range: GestureSettings.edgeWidthPercentRange,
                isPercent: true
            )
            GroupBox(NSLocalizedString("edge_step_distances", comment: "")) {
                VStack(alignment: .leading, spacing: 12) {
                    labeledSlider(
                        NSLocalizedString("left_edge_step_distance", comment: ""),
                        keyPath: \.gesture.leftPhysicalStepDistance,
                        range: GestureSettings.physicalStepDistanceRange,
                        isPercent: true
                    )
                    labeledSlider(
                        NSLocalizedString("right_edge_step_distance", comment: ""),
                        keyPath: \.gesture.rightPhysicalStepDistance,
                        range: GestureSettings.physicalStepDistanceRange,
                        isPercent: true
                    )
                    labeledSlider(
                        NSLocalizedString("top_edge_step_distance", comment: ""),
                        keyPath: \.gesture.topPhysicalStepDistance,
                        range: GestureSettings.physicalStepDistanceRange,
                        isPercent: true
                    )
                    Text(NSLocalizedString("edge_step_distance_help", comment: ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            GestureTestPanel(controller: gestureTestController, kind: .edge)
        }
    }

    private var cornerSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("nav_corners", subtitleKey: "corners_subtitle")
            HStack(alignment: .top, spacing: 24) {
                CornerTrackpadDiagram(bindings: store.settings.cornerAppBindings)
                    .frame(width: 250, height: 190)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(NSLocalizedString("corner_mapping_diagram", comment: ""))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(TrackpadCorner.allCases, id: \.self) { corner in
                        cornerBindingRow(corner)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            labeledSlider(
                NSLocalizedString("corner_trigger_percent", comment: ""),
                keyPath: \.gesture.cornerTriggerPercent,
                range: GestureSettings.cornerTriggerPercentRange,
                isPercent: true
            )
            Text(NSLocalizedString("corner_trigger_percent_help", comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
            labeledSlider(
                NSLocalizedString("corner_movement_tolerance", comment: ""),
                keyPath: \.gesture.cornerMovementTolerancePercent,
                range: GestureSettings.cornerMovementTolerancePercentRange,
                isPercent: true,
                step: 0.01
            )
            Text(NSLocalizedString("corner_movement_tolerance_help", comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
            labeledSlider(
                NSLocalizedString("corner_double_tap_interval", comment: ""),
                keyPath: \.gesture.cornerDoubleTapIntervalSeconds,
                range: GestureSettings.cornerDoubleTapIntervalRange,
                isPercent: false,
                step: 0.05
            )
            Text(NSLocalizedString("corner_double_tap_interval_help", comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("corner_double_tap_help", comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
            GestureTestPanel(controller: gestureTestController, kind: .corner)
        }
    }

    private var middleClickSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("nav_middleClick", subtitleKey: "middle_click_subtitle")
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(NSLocalizedString("middle_click_enable", comment: ""), isOn: binding(\.middleClick.isEnabled))
                    Toggle(NSLocalizedString("middle_click_tap_enable", comment: ""), isOn: binding(\.middleClick.tapEnabled))
                        .disabled(!store.settings.middleClick.isEnabled)
                    Picker(NSLocalizedString("middle_click_finger_count", comment: ""), selection: binding(\.middleClick.fingerCount)) {
                        ForEach(MiddleClickSettings.supportedFingerCounts, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!store.settings.middleClick.isEnabled)
                    Text(NSLocalizedString("middle_click_exact_count_help", comment: ""))
                        .font(.callout).foregroundStyle(.secondary)
                    middleClickWarning
                }.padding(8)
            }
            GestureTestPanel(controller: gestureTestController, kind: .middleClick)
                .disabled(!store.settings.middleClick.isEnabled || !store.settings.middleClick.tapEnabled)
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("nav_diagnostics", subtitleKey: "diagnostics_subtitle")
            GroupBox(NSLocalizedString("diagnostic_status", comment: "")) {
                VStack(spacing: 10) {
                    diagnosticRow("diagnostic_overall", NSLocalizedString(currentHealth.localizationKey, comment: ""))
                    diagnosticRow("accessibility", localizedPermission(permissionManager.snapshot.accessibility))
                    diagnosticRow("diagnostic_framework", localizedOptional(pipelineStatus.frameworkAvailable))
                    diagnosticRow("diagnostic_device", localizedOptional(pipelineStatus.deviceAvailable))
                    diagnosticRow("touch_monitor_status", localizedTouch(pipelineStatus.touchMonitor))
                    diagnosticRow("event_tap_status", eventTapDisplay)
                    HStack(alignment: .firstTextBaseline) {
                        Text(NSLocalizedString("recent_touch", comment: ""))
                        Spacer()
                        RecentTouchText(pipelineStatus: pipelineStatus)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    diagnosticRow("diagnostic_last_failure", pipelineStatus.lastFailureReason ?? NSLocalizedString("none", comment: ""))
                    diagnosticRow("diagnostic_version", versionText)
                    diagnosticRow("diagnostic_system", systemText)
                }.padding(8)
            }
            HStack {
                Button(NSLocalizedString("recheck", comment: "")) { permissionManager.currentSnapshot() }
                Button(NSLocalizedString("copy_diagnostics", comment: "")) { diagnosticPreview = DiagnosticPreview(text: diagnosticSummary) }
                Spacer()
                Button(NSLocalizedString("rerun_onboarding", comment: "")) {
                    var updated = store.settings
                    updated.isAppEnabled = false
                    updated.experience.onboardingVersion = 0
                    store.save(updated)
                }
            }
            DisclosureGroup(NSLocalizedString("permission_recovery_title", comment: ""), isExpanded: $showPermissionRecovery) {
                Text(NSLocalizedString("permission_recovery_guidance", comment: ""))
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }
            Divider()
            Button(NSLocalizedString("restore_defaults", comment: ""), role: .destructive) { showResetConfirmation = true }
        }
    }

    @ViewBuilder private var middleClickWarning: some View {
        if store.settings.middleClick.fingerCount == 2 {
            Label(NSLocalizedString("middle_click_two_finger_warning", comment: ""), systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
        } else if store.settings.middleClick.fingerCount == 3 {
            Text(NSLocalizedString("middle_click_three_finger_drag_guidance", comment: ""))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func performHealthAction() {
        switch currentHealth {
        case .disabledByUser:
            var updated = store.settings; updated.isAppEnabled = true; store.save(updated)
        case .noGesturesConfigured:
            selection = .edges
        case .permissionRequired:
            permissionManager.promptForAccessibility()
        case .setupRequired:
            break
        case .hardwareUnavailable, .degraded, .starting, .recovering:
            permissionManager.currentSnapshot(); selection = .diagnostics
        case .ready:
            break
        }
    }

    private func pageTitle(_ titleKey: String, subtitleKey: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString(titleKey, comment: "")).font(.largeTitle.bold())
            Text(NSLocalizedString(subtitleKey, comment: "")).foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in
            var updated = store.settings
            updated[keyPath: keyPath] = value
            store.save(updated)
        })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { store.settings.launchAtLogin }, set: { value in
            do {
                try permissionManager.setLaunchAtLogin(value)
                var updated = store.settings; updated.launchAtLogin = value; store.save(updated)
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = String(format: NSLocalizedString("launch_at_login_error", comment: ""), error.localizedDescription)
            }
        })
    }

    private func sideEdgePicker(_ labelKey: String, keyPath: WritableKeyPath<AppSettings, SideEdgeAction>) -> some View {
        Picker(NSLocalizedString(labelKey, comment: ""), selection: binding(keyPath)) {
            ForEach(SideEdgeAction.allCases, id: \.self) { action in
                Text(NSLocalizedString("side_action_\(action.rawValue)", comment: "")).tag(action)
            }
        }
    }

    private func cornerBindingRow(_ corner: TrackpadCorner) -> some View {
        let binding = store.settings.cornerAppBindings[corner]
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(corner.localizationKey, comment: ""))
                    .font(.headline)
                Text(binding?.displayName ?? NSLocalizedString("corner_not_configured", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(NSLocalizedString(binding == nil ? "corner_choose_app" : "corner_change_app", comment: "")) {
                chooseApplication(for: corner)
            }
            if binding != nil {
                Button(NSLocalizedString("corner_clear", comment: ""), role: .destructive) {
                    clearApplication(for: corner)
                }
            }
        }
    }

    private func chooseApplication(for corner: TrackpadCorner) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = NSLocalizedString("corner_app_picker_prompt", comment: "")
        panel.message = NSLocalizedString("corner_app_picker_message", comment: "")
        if let path = store.settings.cornerAppBindings[corner]?.applicationPath {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            appSelectionError = NSLocalizedString("corner_app_picker_error", comment: "")
            return
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        var updated = store.settings
        updated.cornerAppBindings[corner] = ApplicationBinding(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            applicationPath: url.path
        )
        store.save(updated)
        appSelectionError = nil
    }

    private func clearApplication(for corner: TrackpadCorner) {
        var updated = store.settings
        updated.cornerAppBindings[corner] = nil
        store.save(updated)
        appSelectionError = nil
    }

    private var topEdgePicker: some View {
        Picker(NSLocalizedString("top_edge", comment: ""), selection: binding(\.edgeAssignments.top)) {
            ForEach(TopEdgeAction.allCases, id: \.self) { action in
                Text(NSLocalizedString("top_action_\(action.rawValue)", comment: "")).tag(action)
            }
        }
    }

    private var duplicateSideAssignment: Bool {
        store.settings.edgeAssignments.left != .none && store.settings.edgeAssignments.left == store.settings.edgeAssignments.right
    }

    private func labeledSlider(
        _ title: String,
        keyPath: WritableKeyPath<AppSettings, Double>,
        range: ClosedRange<Double>,
        isPercent: Bool,
        step: Double = 0.01
    ) -> some View {
        DeferredSettingsSlider(
            title: title,
            value: store.settings[keyPath: keyPath],
            range: range,
            step: step,
            valueText: { sliderValue($0, isPercent: isPercent) }
        ) { value in
            var updated = store.settings
            updated[keyPath: keyPath] = value
            store.save(updated)
        }
    }

    private func sliderValue(_ value: Double, isPercent: Bool) -> String {
        if isPercent {
            return value.formatted(.percent.precision(.fractionLength(0)))
        }
        return String(format: NSLocalizedString("seconds_value", comment: ""), value)
    }

    private func diagnosticRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(NSLocalizedString(key, comment: ""))
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private func localizedPermission(_ state: PermissionState) -> String { NSLocalizedString(state.rawValue, comment: "") }
    private func localizedOptional(_ value: Bool?) -> String {
        guard let value else { return NSLocalizedString("unknown", comment: "") }
        return NSLocalizedString(value ? "available" : "unavailable", comment: "")
    }
    private func localizedTouch(_ state: TouchMonitorRuntimeState) -> String { NSLocalizedString("pipeline_\(state.rawValue)", comment: "") }
    private var eventTapDisplay: String {
        guard store.settings.middleClick.isEnabled else { return NSLocalizedString("not_enabled", comment: "") }
        switch pipelineStatus.eventTap {
        case .stopped: return NSLocalizedString("pipeline_stopped", comment: "")
        case .starting: return NSLocalizedString("pipeline_starting", comment: "")
        case .running: return NSLocalizedString("pipeline_running", comment: "")
        case .recoveryRequiresPipelineRestart: return NSLocalizedString("pipeline_restarting", comment: "")
        case .degraded: return NSLocalizedString("pipeline_degraded", comment: "")
        }
    }
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
        return "\(version) (\(build))"
    }
    private var systemText: String { "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(architecture)" }
    private var architecture: String {
#if arch(arm64)
        return "arm64"
#else
        return "x86_64"
#endif
    }
    private var diagnosticSummary: String {
        [
            "Slidr Free diagnostics",
            "health=\(currentHealth.rawValue)",
            "accessibility=\(permissionManager.snapshot.accessibility.rawValue)",
            "framework=\(pipelineStatus.frameworkAvailable.map(String.init) ?? "unknown")",
            "device=\(pipelineStatus.deviceAvailable.map(String.init) ?? "unknown")",
            "touchMonitor=\(pipelineStatus.touchMonitor.rawValue)",
            "physicalClickListener=\(store.settings.middleClick.isEnabled ? String(describing: pipelineStatus.eventTap) : "notEnabled")",
            "lastFrameAgeSeconds=\(pipelineStatus.lastFrameAge.map { String(Int($0)) } ?? "none")",
            "lastFailure=\(pipelineStatus.lastFailureReason ?? "none")",
            "version=\(versionText)",
            "system=\(systemText)"
        ].joined(separator: "\n")
    }
}

struct DeferredSliderValue {
    private(set) var draft: Double
    private var persisted: Double
    private var isEditing = false

    init(persisted: Double) {
        self.draft = persisted
        self.persisted = persisted
    }

    mutating func beginEditing() {
        isEditing = true
    }

    mutating func updateDraft(_ value: Double) {
        draft = value
    }

    mutating func finishEditing() -> Double? {
        guard isEditing else { return nil }
        isEditing = false
        guard draft != persisted else { return nil }
        persisted = draft
        return draft
    }

    mutating func synchronizePersistedValue(_ value: Double) {
        persisted = value
        guard !isEditing else { return }
        draft = value
    }
}

private struct DeferredSettingsSlider: View {
    let title: String
    let persistedValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: (Double) -> String
    let onCommit: (Double) -> Void
    @State private var value: DeferredSliderValue

    init(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        valueText: @escaping (Double) -> String,
        onCommit: @escaping (Double) -> Void
    ) {
        self.title = title
        self.persistedValue = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.onCommit = onCommit
        _value = State(initialValue: DeferredSliderValue(persisted: value))
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText(value.draft))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { value.draft },
                    set: { value.updateDraft($0) }
                ),
                in: range,
                step: step,
                onEditingChanged: { editing in
                    if editing {
                        value.beginEditing()
                    } else if let committed = value.finishEditing() {
                        onCommit(committed)
                    }
                }
            )
        }
        .onChange(of: persistedValue) { newValue in
            value.synchronizePersistedValue(newValue)
        }
    }
}

enum RecentTouchDescription {
    static func age(lastFrameReceivedAt: Double?, now: Double) -> Int? {
        guard let lastFrameReceivedAt else { return nil }
        return Int(max(0, now - lastFrameReceivedAt))
    }
}

private struct RecentTouchText: View {
    let pipelineStatus: InputPipelineStatus

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private var text: String {
        guard let age = RecentTouchDescription.age(
            lastFrameReceivedAt: pipelineStatus.lastFrameReceivedAt,
            now: ProcessInfo.processInfo.systemUptime
        ) else {
            return NSLocalizedString("no_recent_touch", comment: "")
        }
        return String(format: NSLocalizedString("seconds_ago", comment: ""), age)
    }
}

private struct HealthCard: View {
    let health: AppHealthState
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString(health.localizationKey, comment: "")).font(.headline)
                Text(NSLocalizedString("health_impact_\(health.rawValue)", comment: "")).foregroundStyle(.secondary)
            }
            Spacer()
            if let key = health.actionLocalizationKey { Button(NSLocalizedString(key, comment: ""), action: action) }
        }
        .padding(16)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch health {
        case .ready: return "checkmark.circle.fill"
        case .disabledByUser: return "pause.circle.fill"
        case .noGesturesConfigured: return "slider.horizontal.3"
        case .starting, .recovering: return "arrow.triangle.2.circlepath"
        default: return "exclamationmark.triangle.fill"
        }
    }
    private var tint: Color { health == .ready ? .green : (health == .disabledByUser ? .secondary : .orange) }
}

private struct BannerView: View {
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill").accessibilityHidden(true)
            Text(text)
            Spacer()
            if let actionTitle, let action { Button(actionTitle, action: action) }
        }
        .padding(10).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GestureTestPanel: View {
    @ObservedObject var controller: GestureTestController
    let kind: GestureTestKind
    var body: some View {
        GroupBox(NSLocalizedString("gesture_test_title", comment: "")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString(helpLocalizationKey, comment: ""))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    if controller.kind == kind {
                        Button(NSLocalizedString("stop_test", comment: "")) { controller.stop() }
                        Text(String(format: NSLocalizedString("test_seconds_remaining", comment: ""), controller.secondsRemaining))
                            .foregroundStyle(.secondary)
                    } else {
                        Button(NSLocalizedString("start_safe_test", comment: "")) { controller.start(kind) }
                    }
                    Spacer()
                    if let feedback = controller.feedback { Label(feedback, systemImage: controller.didRecognizeGesture ? "checkmark.circle.fill" : "waveform").foregroundStyle(controller.didRecognizeGesture ? .green : .secondary) }
                }
            }.padding(8)
        }
    }

    private var helpLocalizationKey: String {
        switch kind {
        case .edge: return "gesture_test_edge_help"
        case .corner: return "gesture_test_corner_help"
        case .middleClick: return "gesture_test_middle_help"
        }
    }
}

private struct TrackpadDiagram: View {
    let settings: AppSettings
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.08))
                RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.4), lineWidth: 2)
                Rectangle().fill(Color.accentColor.opacity(0.16)).frame(width: w * settings.gesture.edgeWidthPercent).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.accentColor.opacity(0.16)).frame(width: w * settings.gesture.edgeWidthPercent).frame(maxWidth: .infinity, alignment: .trailing)
                Rectangle().fill(Color.accentColor.opacity(0.16)).frame(height: h * settings.gesture.edgeWidthPercent).frame(maxHeight: .infinity, alignment: .top)
                HStack {
                    edgeLabel(sideText(settings.edgeAssignments.left), arrow: "arrow.up.and.down")
                    Spacer()
                    edgeLabel(sideText(settings.edgeAssignments.right), arrow: "arrow.up.and.down")
                }.padding(12)
                VStack { edgeLabel(topText(settings.edgeAssignments.top), arrow: "arrow.left.and.right"); Spacer() }.padding(12)
            }.clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
    private func edgeLabel(_ text: String, arrow: String) -> some View { VStack { Image(systemName: arrow); Text(text).font(.caption.bold()) } }
    private func sideText(_ action: SideEdgeAction) -> String { NSLocalizedString("side_action_\(action.rawValue)", comment: "") }
    private func topText(_ action: TopEdgeAction) -> String { NSLocalizedString("top_action_\(action.rawValue)", comment: "") }
}

private struct CornerTrackpadDiagram: View {
    let bindings: CornerAppBindings

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 2)
            ForEach(TrackpadCorner.allCases, id: \.self) { corner in
                marker(for: corner)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                    .padding(14)
            }
        }
    }

    private func marker(for corner: TrackpadCorner) -> some View {
        let binding = bindings[corner]
        return VStack(spacing: 3) {
            Image(systemName: binding == nil ? "plus.circle" : "app.fill")
                .foregroundStyle(binding == nil ? Color.secondary : Color.accentColor)
            Text(binding?.displayName ?? NSLocalizedString(corner.localizationKey, comment: ""))
                .font(.caption2.bold())
                .lineLimit(1)
                .frame(maxWidth: 92)
        }
    }
}

private extension TrackpadCorner {
    var localizationKey: String {
        switch self {
        case .topLeft: return "corner_top_left"
        case .topRight: return "corner_top_right"
        case .bottomLeft: return "corner_bottom_left"
        case .bottomRight: return "corner_bottom_right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

private struct DiagnosticPreviewSheet: View {
    let text: String
    let copy: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("diagnostic_preview_title", comment: "")).font(.title2.bold())
            Text(NSLocalizedString("diagnostic_privacy_note", comment: "")).foregroundStyle(.secondary)
            ScrollView { Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .padding(10).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); Button(NSLocalizedString("cancel", comment: ""), action: cancel); Button(NSLocalizedString("copy", comment: ""), action: copy).keyboardShortcut(.defaultAction) }
        }.padding(22).frame(width: 560, height: 420)
    }
}

private struct DiagnosticPreview: Identifiable {
    let id = UUID()
    let text: String
}
