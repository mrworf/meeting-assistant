import Foundation

public struct CalendarSnapshot: Codable, Equatable, Sendable {
    public var meetings: [String: QualifyingMeeting]
    public var syncToken: String?
    public var lastFullSync: Date?
    public var lastSuccessfulSync: Date?

    public init(meetings: [String: QualifyingMeeting] = [:], syncToken: String? = nil, lastFullSync: Date? = nil, lastSuccessfulSync: Date? = nil) {
        self.meetings = meetings
        self.syncToken = syncToken
        self.lastFullSync = lastFullSync
        self.lastSuccessfulSync = lastSuccessfulSync
    }
}

public protocol CalendarSnapshotStoring: Sendable {
    func load() -> CalendarSnapshot
    func save(_ snapshot: CalendarSnapshot)
    func clear()
}

public final class UserDefaultsCalendarSnapshotStore: CalendarSnapshotStoring, @unchecked Sendable {
    private static let currentSchemaVersion = 3
    private let defaults: UserDefaults
    private let key: String
    private var schemaVersionKey: String { "\(key).schemaVersion" }

    public init(defaults: UserDefaults = .standard, key: String = "googleCalendarSnapshot") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> CalendarSnapshot {
        guard defaults.integer(forKey: schemaVersionKey) == Self.currentSchemaVersion else {
            clear()
            return CalendarSnapshot()
        }
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(CalendarSnapshot.self, from: data) else {
            clear()
            return CalendarSnapshot()
        }
        return value
    }

    public func save(_ snapshot: CalendarSnapshot) {
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: key)
        defaults.set(Self.currentSchemaVersion, forKey: schemaVersionKey)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: schemaVersionKey)
    }
}

public actor CalendarSyncEngine {
    private let api: GoogleCalendarAPI
    private let store: CalendarSnapshotStoring
    private let qualifier: MeetingQualifier
    private var snapshot: CalendarSnapshot

    public init(api: GoogleCalendarAPI = GoogleCalendarAPI(), store: CalendarSnapshotStoring = UserDefaultsCalendarSnapshotStore(), qualifier: MeetingQualifier = MeetingQualifier()) {
        self.api = api
        self.store = store
        self.qualifier = qualifier
        self.snapshot = store.load()
    }

    public func refresh(accessToken: String, now: Date = Date()) async throws -> [QualifyingMeeting] {
        let fullSyncIsStale = snapshot.lastFullSync.map { now.timeIntervalSince($0) >= 24 * 60 * 60 } ?? true
        do {
            try await synchronize(accessToken: accessToken, now: now, forceFull: fullSyncIsStale)
        } catch GoogleCalendarAPIError.fullSyncRequired {
            try await synchronize(accessToken: accessToken, now: now, forceFull: true)
        }
        return snapshot.meetings.values.sorted { $0.start < $1.start }
    }

    public func cachedMeetings() -> [QualifyingMeeting] {
        snapshot.meetings.values.sorted { $0.start < $1.start }
    }

    public func lastSuccessfulSync() -> Date? { snapshot.lastSuccessfulSync }

    public func clear() {
        snapshot = CalendarSnapshot()
        store.clear()
    }

    private func synchronize(accessToken: String, now: Date, forceFull: Bool) async throws {
        let syncToken = forceFull ? nil : snapshot.syncToken
        var updated = forceFull ? CalendarSnapshot() : snapshot
        var pageToken: String?
        var finalSyncToken: String?
        repeat {
            let page = try await api.eventsPage(
                accessToken: accessToken,
                syncToken: syncToken,
                pageToken: pageToken,
                timeMin: syncToken == nil ? now.addingTimeInterval(-24 * 60 * 60) : nil,
                timeMax: syncToken == nil ? now.addingTimeInterval(30 * 24 * 60 * 60) : nil
            )
            for event in page.items {
                let key = Self.storageKey(event)
                updated.meetings.removeValue(forKey: key)
                if event.status != "cancelled", let meeting = qualifier.qualify(event) {
                    updated.meetings[key] = meeting
                }
            }
            pageToken = page.nextPageToken
            finalSyncToken = page.nextSyncToken ?? finalSyncToken
        } while pageToken != nil

        updated.syncToken = finalSyncToken ?? updated.syncToken
        if forceFull { updated.lastFullSync = now }
        updated.lastSuccessfulSync = now
        snapshot = updated
        store.save(snapshot)
    }

    private static func storageKey(_ event: GoogleCalendarEvent) -> String {
        "\(event.id)|\(event.originalStartTime?.dateTime ?? event.start.dateTime ?? event.start.date ?? "unknown")"
    }
}
