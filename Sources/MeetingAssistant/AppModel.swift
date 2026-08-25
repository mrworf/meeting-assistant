import AppKit
import Combine
import MeetingAssistantCore
import Network

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var visibleMeetings: [QualifyingMeeting] = []
    @Published private(set) var now = Date()
    @Published private(set) var isConnected = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSuccessfulSync: Date?
    @Published var statusMessage = "Not connected"
    @Published var launchAtLoginError: String?
    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: "googleOAuthClientID") }
    }

    private let oauth = GoogleOAuthService()
    private let syncEngine = CalendarSyncEngine()
    private let acknowledgements = AcknowledgementController(store: UserDefaultsAcknowledgementStore())
    private let policy = AlertPolicy()
    private let oauthCoordinator = LoopbackOAuthCoordinator()
    private let pathMonitor = NWPathMonitor()
    private var allMeetings: [QualifyingMeeting] = []
    private var latchedMeetings: [String: QualifyingMeeting] = [:]
    private var refreshLoop: Task<Void, Never>?
    private var secondTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var networkWasAvailable = false

    init() {
        clientID = UserDefaults.standard.string(forKey: "googleOAuthClientID") ?? ""
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
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await oauth.validAccessToken(clientID: clientID)
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
        do {
            statusMessage = "Waiting for Google authorization…"
            let result = try await oauthCoordinator.authorize(clientID: clientID, oauth: oauth)
            _ = try await oauth.exchangeAuthorizationCode(result.code, request: result.request, clientID: clientID)
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
        isConnected = false
        lastSuccessfulSync = nil
        statusMessage = "Disconnected"
    }

    func open(_ meeting: QualifyingMeeting) {
        let currentGroup = visibleMeetings
        guard NSWorkspace.shared.open(meeting.actionURL) else {
            statusMessage = "Could not open \(meeting.actionURL.absoluteString)"
            return
        }
        acknowledgements.acknowledge(currentGroup)
        currentGroup.forEach { latchedMeetings.removeValue(forKey: $0.id) }
        visibleMeetings = []
    }

    private func recalculateVisibleMeetings() {
        let currentIDs = Set(allMeetings.map(\.id))
        latchedMeetings = latchedMeetings.filter { currentIDs.contains($0.key) }
        policy.meetingsToDisplay(allMeetings, acknowledged: acknowledgements.acknowledged, now: now).forEach { latchedMeetings[$0.id] = $0 }
        visibleMeetings = latchedMeetings.values.sorted { $0.start < $1.start }
    }
}

