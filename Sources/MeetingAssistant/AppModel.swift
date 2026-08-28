import AppKit
import Combine
import MeetingAssistantCore
import Network

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var visibleMeetings: [QualifyingMeeting] = []
    @Published private(set) var upcomingMeetings: [QualifyingMeeting] = []
    @Published private(set) var now = Date()
    @Published private(set) var isConnected = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var alertLeadMinutes: Int
    @Published var statusMessage = "Not connected"
    @Published var launchAtLoginError: String?
    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: "googleOAuthClientID") }
    }
    @Published var clientSecret: String {
        didSet {
            do { try clientSecretStore.save(clientSecret) }
            catch { statusMessage = error.localizedDescription }
        }
    }

    private let clientSecretStore: KeychainStringStore
    private let oauth = GoogleOAuthService()
    private let syncEngine = CalendarSyncEngine()
    private let acknowledgements = AcknowledgementController(store: UserDefaultsAcknowledgementStore())
    private let upcomingPolicy = UpcomingMeetingPolicy()
    private let oauthCoordinator = LoopbackOAuthCoordinator()
    private let pathMonitor = NWPathMonitor()
    private var allMeetings: [QualifyingMeeting] = []
    private var latchedMeetings: [String: QualifyingMeeting] = [:]
    private var refreshLoop: Task<Void, Never>?
    private var secondTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var networkWasAvailable = false

    init() {
        let secretStore = KeychainStringStore(account: "google-oauth-client-secret")
        clientSecretStore = secretStore
        clientID = UserDefaults.standard.string(forKey: "googleOAuthClientID") ?? ""
        clientSecret = (try? secretStore.load()) ?? ""
        let savedLeadMinutes = UserDefaults.standard.integer(forKey: "alertLeadMinutes")
        alertLeadMinutes = AppIdentity.alertLeadMinuteOptions.contains(savedLeadMinutes) ? savedLeadMinutes : 5
    }

    var hasOAuthClientConfiguration: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !clientSecret.isEmpty
    }

    func setAlertLeadMinutes(_ minutes: Int) {
        guard AppIdentity.alertLeadMinuteOptions.contains(minutes) else { return }
        alertLeadMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "alertLeadMinutes")
        recalculateVisibleMeetings()
    }

    func importOAuthClientJSON(_ data: Data) {
        do {
            let configuration = try GoogleOAuthClientConfiguration.decodeGoogleClientJSON(data)
            clientID = configuration.clientID
            clientSecret = configuration.clientSecret
            statusMessage = "OAuth credentials imported. Connect your Google account."
        } catch { statusMessage = error.localizedDescription }
    }

    func start() {
        Task {
            allMeetings = await syncEngine.cachedMeetings()
            lastSuccessfulSync = await syncEngine.lastSuccessfulSync()
            recalculateVisibleMeetings()
            await refresh()
        }
        secondTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.recalculateVisibleMeetings()
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let available = path.status == .satisfied
                if available && !self.networkWasAvailable { await self.refresh() }
                self.networkWasAvailable = available
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "MeetingAssistant.NetworkMonitor"))
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppIdentity.refreshInterval))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isConnected = false
            statusMessage = GoogleAuthError.missingClientID.localizedDescription
            return
        }
        guard !clientSecret.isEmpty else {
            isConnected = false
            statusMessage = GoogleAuthError.missingClientSecret.localizedDescription
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await oauth.validAccessToken(clientID: clientID, clientSecret: clientSecret)
            allMeetings = try await syncEngine.refresh(accessToken: token)
            lastSuccessfulSync = await syncEngine.lastSuccessfulSync()
            isConnected = true
            statusMessage = "Calendar synchronized"
            recalculateVisibleMeetings()
        } catch GoogleAuthError.authorizationRequired {
            isConnected = false
            statusMessage = GoogleAuthError.authorizationRequired.localizedDescription
        } catch { statusMessage = error.localizedDescription }
    }

    func connect() async {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = GoogleAuthError.missingClientID.localizedDescription
            return
        }
        guard !clientSecret.isEmpty else {
            statusMessage = GoogleAuthError.missingClientSecret.localizedDescription
            return
        }
        do {
            statusMessage = "Waiting for Google authorization…"
            let result = try await oauthCoordinator.authorize(clientID: clientID, oauth: oauth)
            _ = try await oauth.exchangeAuthorizationCode(result.code, request: result.request, clientID: clientID, clientSecret: clientSecret)
            isConnected = true
            await refresh()
        } catch { statusMessage = error.localizedDescription }
    }

    func disconnect() {
        do { try oauth.disconnect() }
        catch { statusMessage = error.localizedDescription; return }
        Task { await syncEngine.clear() }
        allMeetings = []
        latchedMeetings = [:]
        visibleMeetings = []
        upcomingMeetings = []
        isConnected = false
        lastSuccessfulSync = nil
        statusMessage = "Disconnected"
    }

    func open(_ meeting: QualifyingMeeting) {
        guard openURL(for: meeting) else { return }
        acknowledgeCurrentGroup()
    }

    func openFromMenu(_ meeting: QualifyingMeeting) {
        guard openURL(for: meeting) else { return }
        guard visibleMeetings.contains(where: { $0.id == meeting.id }) else { return }
        acknowledgeCurrentGroup()
    }

    private func openURL(for meeting: QualifyingMeeting) -> Bool {
        guard NSWorkspace.shared.open(meeting.actionURL) else {
            statusMessage = "Could not open \(meeting.actionURL.absoluteString)"
            return false
        }
        return true
    }

    private func acknowledgeCurrentGroup() {
        let currentGroup = visibleMeetings
        acknowledgements.acknowledge(currentGroup)
        currentGroup.forEach { latchedMeetings.removeValue(forKey: $0.id) }
        visibleMeetings = []
    }

    private func recalculateVisibleMeetings() {
        let currentIDs = Set(allMeetings.map(\.id))
        let alertPolicy = AlertPolicy(leadTime: TimeInterval(alertLeadMinutes * 60))
        latchedMeetings = latchedMeetings.filter {
            currentIDs.contains($0.key) && alertPolicy.shouldRemainVisible($0.value, now: now)
        }
        alertPolicy.meetingsToDisplay(allMeetings, acknowledged: acknowledgements.acknowledged, now: now).forEach { latchedMeetings[$0.id] = $0 }
        visibleMeetings = latchedMeetings.values.sorted { $0.start < $1.start }
        let nextMeetings = upcomingPolicy.meetings(allMeetings, after: now)
        if upcomingMeetings != nextMeetings { upcomingMeetings = nextMeetings }
    }
}
