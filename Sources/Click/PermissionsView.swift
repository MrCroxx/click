import AppKit
import SwiftUI
import ServiceManagement
import ClickCore

struct PermissionsView: View {
    @ObservedObject var model: AppModel
    private func tr(_ key: String) -> String { L10n.text(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Text(tr("Permissions")).font(.system(size: 24, weight: .semibold))
                Spacer()
                Button(tr("Check Again")) { model.refresh() }.disabled(model.demo)
            }
            VStack(spacing: 0) {
                row("Accessibility", detail: "Allows macro actions to control apps and insert text.",
                    status: model.accessibility ? "Granted" : "Not granted", ready: model.accessibility) {
                    if !model.accessibility { model.requestAccessibility() }
                    model.openSettings("Privacy_Accessibility")
                }
                Divider()
                row("Input Monitoring", detail: "Checks Click’s access. Keyboard Service access is verified when capture starts.",
                    status: model.inputMonitoring ? "Granted" : "Not granted", ready: model.inputMonitoring) {
                    if !model.inputMonitoring { model.requestInputMonitoring() }
                    model.openSettings("Privacy_ListenEvent")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Background Items")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    row("Keyboard Service", detail: "Allows Click’s keyboard service to run in the background.",
                        status: status(model.serviceStatus), ready: model.serviceStatus == .enabled) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    Divider()
                    row("Launch at login", detail: "Optional. Opens Click when you sign in.",
                        status: status(model.loginStatus), ready: model.loginStatus == .enabled) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .onAppear { if !model.demo { model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !model.demo { model.refresh() }
        }
    }

    private func status(_ value: SMAppService.Status) -> String {
        switch value {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Approval required"
        case .notRegistered: return "Not enabled"
        case .notFound: return "Unavailable"
        @unknown default: return "Unknown"
        }
    }

    private func row(_ title: String, detail: String, status: String, ready: Bool,
                     action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text(tr(title)).fontWeight(.medium)
                Spacer()
                Label(tr(status), systemImage: ready ? "checkmark.circle" : "circle")
                    .foregroundStyle(ready ? Color.secondary : Color.orange)
                Button(tr("Open Settings"), action: action).disabled(model.demo)
                    .accessibilityLabel(tr("Open Settings") + ": " + tr(title))
            }
            Text(tr(detail)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 18)
    }
}
