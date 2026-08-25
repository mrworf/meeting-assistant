import Foundation

public struct GoogleEventsPage: Decodable, Sendable {
    public let items: [GoogleCalendarEvent]
    public let nextPageToken: String?
    public let nextSyncToken: String?

    public init(items: [GoogleCalendarEvent], nextPageToken: String?, nextSyncToken: String?) {
        self.items = items
        self.nextPageToken = nextPageToken
        self.nextSyncToken = nextSyncToken
    }

    enum CodingKeys: String, CodingKey { case items, nextPageToken, nextSyncToken }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([GoogleCalendarEvent].self, forKey: .items) ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
        nextSyncToken = try container.decodeIfPresent(String.self, forKey: .nextSyncToken)
    }
}

public enum GoogleCalendarAPIError: LocalizedError, Equatable {
    case fullSyncRequired
    case requestFailed(Int, String)

    public var errorDescription: String? {
        switch self {
        case .fullSyncRequired: "Google Calendar requires a fresh synchronization."
        case .requestFailed(let status, let message): "Google Calendar request failed (\(status)): \(message)"
        }
    }
}

public struct GoogleCalendarAPI: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func eventsPage(
        accessToken: String,
        syncToken: String? = nil,
        pageToken: String? = nil,
        timeMin: Date? = nil,
        timeMax: Date? = nil
    ) async throws -> GoogleEventsPage {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        var query: [URLQueryItem] = [
            .init(name: "singleEvents", value: "true"),
            .init(name: "showDeleted", value: "true"),
            .init(name: "maxResults", value: "2500"),
        ]
        if let syncToken {
            query.append(.init(name: "syncToken", value: syncToken))
        } else {
            if let timeMin { query.append(.init(name: "timeMin", value: ISO8601DateFormatter().string(from: timeMin))) }
            if let timeMax { query.append(.init(name: "timeMax", value: ISO8601DateFormatter().string(from: timeMax))) }
        }
        if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleCalendarAPIError.requestFailed(0, "Invalid response") }
        if http.statusCode == 410 { throw GoogleCalendarAPIError.fullSyncRequired }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleCalendarAPIError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try JSONDecoder().decode(GoogleEventsPage.self, from: data)
    }
}
