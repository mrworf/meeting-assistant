import AppKit
import MeetingAssistantCore
import ServiceManagement
import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var model: AppModel
    @State private var loginEnabled = false
    @State private var loginStatus = ""

    var body: some View {
        Form {
            Section("Google Calendar") {
                Text("Create a Google Cloud Desktop OAuth client, enable the Google Calendar API, and paste its client ID below.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("OAuth client ID", text: $model.clientID)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(model.isConnected ? "Reconnect Google Account" : "Connect Google Account") {
                        Task { await model.connect() }
                    }
                    .disabled(model.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSyncing)
                    Button("Refresh Now") { Task { await model.refresh() } }
                        .disabled(!model.isConnected || model.isSyncing)
                    if model.isConnected { Button("Disconnect", role: .destructive) { model.disconnect() } }
                    if model.isSyncing { ProgressView().controlSize(.small) }
                }
                LabeledContent("Status", value: model.statusMessage)
                LabeledContent("Last sync", value: model.lastSuccessfulSync?.formatted(date: .abbreviated, time: .standard) ?? "Never")
            }

            Section("Startup") {
                Toggle("Launch Meeting Assistant at login", isOn: Binding(
                    get: { loginEnabled },
                    set: { setLaunchAtLogin($0) }
                ))
                if !loginStatus.isEmpty { Text(loginStatus).font(.caption).foregroundStyle(.secondary) }
            }

            Section("Reminder behavior") {
                LabeledContent("Countdown appears", value: "5 minutes before")
                Text("The reminder cannot be dismissed. Joining any displayed meeting acknowledges the current group.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 610, minHeight: 430)
        .onAppear { refreshLoginStatus() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { model.launchAtLoginError = error.localizedDescription }
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            loginEnabled = true
            loginStatus = "Enabled"
        case .requiresApproval:
            loginEnabled = false
            loginStatus = "Approval is required in System Settings → General → Login Items."
        case .notRegistered:
            loginEnabled = false
            loginStatus = model.launchAtLoginError ?? "Disabled"
        case .notFound:
            loginEnabled = false
            loginStatus = "Install the packaged app in Applications to enable launch at login."
        @unknown default:
            loginEnabled = false
            loginStatus = "Unknown status"
        }
    }
}

@MainActor
final class ConfigurationWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 470), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = AppIdentity.name
        window.contentView = NSHostingView(rootView: ConfigurationView(model: model))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
