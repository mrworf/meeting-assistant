import AppKit
import MeetingAssistantCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationView: View {
    @ObservedObject var model: AppModel
    @State private var loginEnabled = false
    @State private var loginMessage: String?
    @State private var showReconnectConfirmation = false
    @State private var showDisconnectConfirmation = false
    @State private var showAbout = false

    var body: some View {
        Form {
            Section("Google Calendar") {
                Text("Import the OAuth JSON downloaded for a Google Cloud Desktop client. The client secret is stored in macOS Keychain.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Import Google OAuth JSON…") { importOAuthJSON() }
                TextField("OAuth client ID", text: $model.clientID)
                    .textFieldStyle(.roundedBorder)
                SecureField("OAuth client secret", text: $model.clientSecret)
                    .textFieldStyle(.roundedBorder)
                Text("You can also paste the client ID and secret manually.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.isConnected ? "Reconnect Google Account" : "Connect Google Account") {
                        if model.isConnected { showReconnectConfirmation = true }
                        else { Task { await model.connect() } }
                    }
                    .disabled(!model.hasOAuthClientConfiguration || model.isSyncing)
                    Button("Refresh Now") { Task { await model.refresh() } }
                        .disabled(!model.isConnected || model.isSyncing)
                    if model.isConnected { Button("Disconnect", role: .destructive) { showDisconnectConfirmation = true } }
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
                if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
            }

            Section("Reminder behavior") {
                Picker("Countdown appears", selection: Binding(
                    get: { model.alertLeadMinutes },
                    set: { model.setAlertLeadMinutes($0) }
                )) {
                    ForEach(AppIdentity.alertLeadMinuteOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                Text("The reminder cannot be dismissed. Joining any displayed meeting acknowledges the current group.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("About Meeting Assistant") { showAbout = true }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 610, minHeight: 510)
        .onAppear { refreshLoginStatus() }
        .alert("Are you sure?", isPresented: $showReconnectConfirmation) {
            Button("Reconnect", role: .destructive) { Task { await model.connect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reconnect will replace the current Google account authorization.")
        }
        .alert("Are you sure?", isPresented: $showDisconnectConfirmation) {
            Button("Disconnect", role: .destructive) { model.disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Disconnect will remove the stored Google authorization and clear cached meetings.")
        }
        .sheet(isPresented: $showAbout) { AboutMeetingAssistantView() }
    }

    private func importOAuthJSON() {
        let panel = NSOpenPanel()
        panel.title = "Choose Google OAuth Client JSON"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { model.importOAuthClientJSON(try Data(contentsOf: url)) }
        catch { model.statusMessage = error.localizedDescription }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        model.launchAtLoginError = nil
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
            loginMessage = nil
        case .requiresApproval:
            loginEnabled = false
            loginMessage = "Approval is required in System Settings → General → Login Items."
        case .notRegistered:
            loginEnabled = false
            loginMessage = model.launchAtLoginError
        case .notFound:
            loginEnabled = false
            loginMessage = "Install the packaged app in Applications to enable launch at login."
        @unknown default:
            loginEnabled = false
            loginMessage = "Unable to determine launch-at-login status."
        }
    }
}

private struct AboutMeetingAssistantView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Why did I create this app?")
                .font(.title2.bold())
            Text("I kept arriving late to meetings. Google gave me a five-minute warning and Slack gave me a one-minute warning, but neither was persistent. I keep popup notifications turned off, so those reminders were easy to miss.")
            Text("Meeting Assistant provides a reminder that stays visible until I act. It only cares about meetings with more than one participant—I do not need a reminder to join a meeting when I am the only person there. Meetings I declined or did not accept are ignored as well.")
            Spacer()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 310)
    }
}

@MainActor
final class ConfigurationWindowController: NSWindowController {
    init(model: AppModel) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 550), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = AppIdentity.name
        window.contentView = NSHostingView(rootView: ConfigurationView(model: model))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
