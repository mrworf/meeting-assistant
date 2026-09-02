import Foundation
import Testing
@testable import MeetingAssistantCore

private final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    var credential: StoredGoogleCredential?
    func load() throws -> StoredGoogleCredential? { credential }
    func save(_ credential: StoredGoogleCredential) throws { self.credential = credential }
    func clear() throws { credential = nil }
}

private final class MemorySnapshotStore: CalendarSnapshotStoring, @unchecked Sendable {
    var snapshot = CalendarSnapshot()
    func load() -> CalendarSnapshot { snapshot }
    func save(_ snapshot: CalendarSnapshot) { self.snapshot = snapshot }
    func clear() { snapshot = CalendarSnapshot() }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = Self.lock.withLock { Self.handler }
            let (response, data) = try handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.withLock { value += 1; return value } }
    func read() -> Int { lock.withLock { value } }
}

private struct EncodableEventsPage: Encodable {
    let items: [GoogleCalendarEvent]
    let nextSyncToken: String
}

private func eventsPageData(_ events: [GoogleCalendarEvent], syncToken: String) throws -> Data {
    try JSONEncoder().encode(EncodableEventsPage(items: events, nextSyncToken: syncToken))
}

private func cachedTestEvent(
    status: String = "confirmed",
    start: String = "2026-08-25T18:00:00Z",
    end: String = "2026-08-25T18:30:00Z",
    originalStart: String? = nil,
    selfStatus: String = "accepted",
    hasActionURL: Bool = true
) -> GoogleCalendarEvent {
    GoogleCalendarEvent(
        id: "cached-event",
        status: status,
        summary: "Required meeting title",
        description: "PRIVATE-DESCRIPTION-SENTINEL",
        location: "PRIVATE-LOCATION-SENTINEL",
        htmlLink: hasActionURL ? "https://calendar.google.com/calendar/event?eid=cached" : nil,
        hangoutLink: hasActionURL ? "https://meet.google.com/cache-test" : nil,
        start: .init(dateTime: start),
        end: .init(dateTime: end),
        originalStartTime: originalStart.map { .init(dateTime: $0) },
        organizer: .init(email: "PRIVATE-ORGANIZER-SENTINEL@example.test", displayName: "Organizer"),
        attendees: [
            .init(email: "me@example.test", selfUser: true, responseStatus: selfStatus),
            .init(email: "PRIVATE-ATTENDEE-SENTINEL@example.test", displayName: "Displayed Participant", responseStatus: "accepted"),
        ],
        conferenceData: .init(entryPoints: [.init(entryPointType: "phone", uri: "PRIVATE-CONFERENCE-SENTINEL")])
    )
}

private func mockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

@Suite(.serialized)
struct GoogleServicesTests {
@Test func authorizationRequestUsesPKCEAndReadOnlyScope() throws {
    let request = try GoogleOAuthService().makeAuthorizationRequest(clientID: "client.apps.googleusercontent.com", loopbackPort: 8123)
    let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
    let values = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
    #expect(values["code_challenge_method"] == "S256")
    #expect(values["scope"] == GoogleOAuthService.calendarReadOnlyScope)
    #expect(values["redirect_uri"] == "http://127.0.0.1:8123/oauth2callback")
    #expect(request.verifier.count >= 43)
}

@Test func importsDownloadedGoogleDesktopClientJSON() throws {
    let data = Data(#"{"installed":{"client_id":"desktop.apps.googleusercontent.com","project_id":"project","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","client_secret":"secret-value","redirect_uris":["http://localhost"]}}"#.utf8)
    let configuration = try GoogleOAuthClientConfiguration.decodeGoogleClientJSON(data)
    #expect(configuration.clientID == "desktop.apps.googleusercontent.com")
    #expect(configuration.clientSecret == "secret-value")
}

@Test func rejectsOAuthJSONWithoutClientCredentials() {
    #expect(throws: GoogleAuthError.invalidClientFile) {
        try GoogleOAuthClientConfiguration.decodeGoogleClientJSON(Data(#"{"installed":{"client_id":"id"}}"#.utf8))
    }
}

@Test func tokenFormIncludesAndEncodesClientSecret() throws {
    let data = GoogleOAuthService.tokenFormBody(["client_id": "client"], clientSecret: "secret + value")
    let body = try #require(String(data: data!, encoding: .utf8))
    #expect(body.contains("client_id=client"))
    #expect(body.contains("client_secret=secret%20%2B%20value"))
}

@Test func refreshesExpiredCredentialAndKeepsRefreshToken() async throws {
    let store = MemoryCredentialStore()
    store.credential = .init(accessToken: "old", refreshToken: "refresh", expiresAt: .distantPast)
    MockURLProtocol.lock.withLock {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"access_token":"new","expires_in":3600}"#.utf8))
        }
    }
    let token = try await GoogleOAuthService(session: mockSession(), credentialStore: store).validAccessToken(clientID: "client")
    #expect(token == "new")
    #expect(store.credential?.refreshToken == "refresh")
}

@Test func calendarAPIUsesPrimaryAndSyncToken() async throws {
    MockURLProtocol.lock.withLock {
        MockURLProtocol.handler = { request in
            #expect(request.url!.path.contains("/calendars/primary/events"))
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "syncToken", value: "sync-1")) == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"items":[],"nextSyncToken":"sync-2"}"#.utf8))
        }
    }
    let page = try await GoogleCalendarAPI(session: mockSession()).eventsPage(accessToken: "access", syncToken: "sync-1")
    #expect(page.nextSyncToken == "sync-2")
}

@Test func calendarAPIAllowsAnOmittedEmptyItemsArray() async throws {
    MockURLProtocol.lock.withLock {
        MockURLProtocol.handler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"nextSyncToken":"sync"}"#.utf8))
        }
    }
    let page = try await GoogleCalendarAPI(session: mockSession()).eventsPage(accessToken: "access")
    #expect(page.items.isEmpty)
}

@Test func snapshotStoreDeletesLegacyCacheAndRoundTripsCurrentSchema() throws {
    let suiteName = "MeetingAssistantTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let key = "calendarSnapshot"
    let schemaKey = "\(key).schemaVersion"
    defaults.set(Data("PRIVATE-LEGACY-CALENDAR-SENTINEL".utf8), forKey: key)
    defaults.set(2, forKey: schemaKey)
    let store = UserDefaultsCalendarSnapshotStore(defaults: defaults, key: key)

    #expect(store.load() == CalendarSnapshot())
    #expect(defaults.object(forKey: key) == nil)
    #expect(defaults.object(forKey: schemaKey) == nil)

    let currentSnapshot = CalendarSnapshot(syncToken: "current-token", lastFullSync: Date())
    store.save(currentSnapshot)
    #expect(defaults.integer(forKey: schemaKey) == 3)
    #expect(store.load() == currentSnapshot)
}

@Test func snapshotStoreDeletesUndecodableCurrentCache() throws {
    let suiteName = "MeetingAssistantTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let key = "calendarSnapshot"
    let schemaKey = "\(key).schemaVersion"
    defaults.set(Data("not-json".utf8), forKey: key)
    defaults.set(3, forKey: schemaKey)
    let store = UserDefaultsCalendarSnapshotStore(defaults: defaults, key: key)

    #expect(store.load() == CalendarSnapshot())
    #expect(defaults.object(forKey: key) == nil)
    #expect(defaults.object(forKey: schemaKey) == nil)
}

@Test func legacyCacheRemovalForcesAFullSynchronization() async throws {
    let suiteName = "MeetingAssistantTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let key = "calendarSnapshot"
    defaults.set(Data("PRIVATE-LEGACY-CALENDAR-SENTINEL".utf8), forKey: key)
    defaults.set(2, forKey: "\(key).schemaVersion")
    let store = UserDefaultsCalendarSnapshotStore(defaults: defaults, key: key)
    MockURLProtocol.lock.withLock {
        MockURLProtocol.handler = { request in
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(!queryItems.contains { $0.name == "syncToken" })
            #expect(queryItems.contains { $0.name == "timeMin" })
            #expect(queryItems.contains { $0.name == "timeMax" })
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try eventsPageData([], syncToken: "fresh-after-migration"))
        }
    }
    let engine = CalendarSyncEngine(api: GoogleCalendarAPI(session: mockSession()), store: store)

    let meetings = try await engine.refresh(accessToken: "access", now: Date(timeIntervalSince1970: 1_777_000_000))

    #expect(meetings.isEmpty)
    #expect(defaults.integer(forKey: "\(key).schemaVersion") == 3)
}

@Test func syncPersistsOnlyReminderReadyMeetingFields() async throws {
    let store = MemorySnapshotStore()
    MockURLProtocol.lock.withLock {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try eventsPageData([cachedTestEvent()], syncToken: "sync-minimal"))
        }
    }
    let engine = CalendarSyncEngine(api: GoogleCalendarAPI(session: mockSession()), store: store)

    let refreshed = try await engine.refresh(accessToken: "access", now: Date(timeIntervalSince1970: 1_777_000_000))
    let meeting = try #require(refreshed.first)
    #expect(refreshed.count == 1)
    #expect(meeting.title == "Required meeting title")
    #expect(meeting.actionURL.absoluteString == "https://meet.google.com/cache-test")
    #expect(meeting.participants == ["Displayed Participant", "Organizer"])
    let cached = await engine.cachedMeetings()
    #expect(cached == refreshed)

    let encoded = try JSONEncoder().encode(store.snapshot)
    let persisted = try #require(String(data: encoded, encoding: .utf8))
    #expect(!persisted.contains("PRIVATE-DESCRIPTION-SENTINEL"))
    #expect(!persisted.contains("PRIVATE-LOCATION-SENTINEL"))
    #expect(!persisted.contains("PRIVATE-ORGANIZER-SENTINEL"))
    #expect(!persisted.contains("PRIVATE-ATTENDEE-SENTINEL"))
    #expect(!persisted.contains("PRIVATE-CONFERENCE-SENTINEL"))
}

@Test func incrementalUpdatesRemoveMeetingsThatNoLongerQualifyOrAreCancelled() async throws {
    let store = MemorySnapshotStore()
    let callCount = LockedCounter()
    MockURLProtocol.lock.withLock {
        MockURLProtocol.handler = { request in
            let call = callCount.increment()
            let event: GoogleCalendarEvent
            switch call {
            case 1, 3, 5: event = cachedTestEvent()
            case 2: event = cachedTestEvent(selfStatus: "declined")
            case 4: event = cachedTestEvent(hasActionURL: false)
            default: event = cachedTestEvent(status: "cancelled")
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try eventsPageData([event], syncToken: "sync-\(call)"))
        }
    }
    let engine = CalendarSyncEngine(api: GoogleCalendarAPI(session: mockSession()), store: store)
    let now = Date(timeIntervalSince1970: 1_777_000_000)

    let initiallyQualified = try await engine.refresh(accessToken: "access", now: now)
    let declined = try await engine.refresh(accessToken: "access", now: now)
    let qualifiedAgain = try await engine.refresh(accessToken: "access", now: now)
    let missingAction = try await engine.refresh(accessToken: "access", now: now)
    let qualifiedBeforeCancellation = try await engine.refresh(accessToken: "access", now: now)
    let cancelled = try await engine.refresh(accessToken: "access", now: now)

    #expect(initiallyQualified.count == 1)
    #expect(declined.isEmpty)
    #expect(qualifiedAgain.count == 1)
    #expect(missingAction.isEmpty)
    #expect(qualifiedBeforeCancellation.count == 1)
    #expect(cancelled.isEmpty)
    #expect(store.snapshot.meetings.isEmpty)
}

@Test func rescheduledOccurrenceReplacesStableCachedEntry() async throws {
    let store = MemorySnapshotStore()
    let callCount = LockedCounter()
    let originalStart = "2026-08-25T18:00:00Z"
    MockURLProtocol.lock.withLock {
        MockURLProtocol.handler = { request in
            let call = callCount.increment()
            let event = call == 1
                ? cachedTestEvent(start: originalStart)
                : cachedTestEvent(
                    start: "2026-08-25T18:15:00Z",
                    end: "2026-08-25T18:45:00Z",
                    originalStart: originalStart
                )
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try eventsPageData([event], syncToken: "sync-\(call)"))
        }
    }
    let engine = CalendarSyncEngine(api: GoogleCalendarAPI(session: mockSession()), store: store)
    let now = Date(timeIntervalSince1970: 1_777_000_000)

    let original = try await engine.refresh(accessToken: "access", now: now)
    let rescheduled = try await engine.refresh(accessToken: "access", now: now)

    #expect(original.count == 1)
    #expect(rescheduled.count == 1)
    #expect(store.snapshot.meetings.count == 1)
    #expect(original[0].id != rescheduled[0].id)
    #expect(rescheduled[0].id.contains("rescheduled:2026-08-25T18:15:00Z"))
}

@Test func syncEngineRecoversFromExpiredSyncToken() async throws {
    let store = MemorySnapshotStore()
    store.snapshot = CalendarSnapshot(syncToken: "expired", lastFullSync: Date())
    let callCount = LockedCounter()
    MockURLProtocol.lock.withLock {
        MockURLProtocol.handler = { request in
            let call = callCount.increment()
            if call == 1 {
                return (HTTPURLResponse(url: request.url!, statusCode: 410, httpVersion: nil, headerFields: nil)!, Data())
            }
            let json = #"{"items":[],"nextSyncToken":"fresh"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
    }
    let engine = CalendarSyncEngine(api: GoogleCalendarAPI(session: mockSession()), store: store)
    _ = try await engine.refresh(accessToken: "access", now: Date())
    #expect(store.snapshot.syncToken == "fresh")
    #expect(callCount.read() == 2)
}
}
