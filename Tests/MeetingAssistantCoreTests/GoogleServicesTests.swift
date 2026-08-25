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
