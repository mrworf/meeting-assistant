import Foundation

public struct GoogleCalendarEvent: Codable, Equatable, Sendable {
    public struct EventDate: Codable, Equatable, Sendable {
        public var dateTime: String?
        public var date: String?

        public init(dateTime: String? = nil, date: String? = nil) {
            self.dateTime = dateTime
            self.date = date
        }
    }

    public struct Person: Codable, Equatable, Sendable {
        public var email: String?
        public var displayName: String?
        public var selfUser: Bool?
        public var resource: Bool?
        public var responseStatus: String?

        enum CodingKeys: String, CodingKey {
            case email, displayName, resource, responseStatus
            case selfUser = "self"
        }

        public init(email: String? = nil, displayName: String? = nil, selfUser: Bool? = nil, resource: Bool? = nil, responseStatus: String? = nil) {
            self.email = email
            self.displayName = displayName
            self.selfUser = selfUser
            self.resource = resource
            self.responseStatus = responseStatus
        }
    }

    public struct ConferenceData: Codable, Equatable, Sendable {
        public struct EntryPoint: Codable, Equatable, Sendable {
            public var entryPointType: String?
            public var uri: String?

            public init(entryPointType: String? = nil, uri: String? = nil) {
                self.entryPointType = entryPointType
                self.uri = uri
            }
        }

        public var entryPoints: [EntryPoint]?

        public init(entryPoints: [EntryPoint]? = nil) {
            self.entryPoints = entryPoints
        }
    }

    public var id: String
    public var status: String?
    public var summary: String?
    public var description: String?
    public var location: String?
    public var htmlLink: String?
    public var hangoutLink: String?
    public var eventType: String?
    public var start: EventDate
    public var end: EventDate
    public var originalStartTime: EventDate?
    public var organizer: Person?
    public var attendees: [Person]?
    public var conferenceData: ConferenceData?

    public init(
        id: String,
        status: String? = "confirmed",
        summary: String? = nil,
        description: String? = nil,
        location: String? = nil,
        htmlLink: String? = nil,
        hangoutLink: String? = nil,
        eventType: String? = "default",
        start: EventDate,
        end: EventDate,
        originalStartTime: EventDate? = nil,
        organizer: Person? = nil,
        attendees: [Person]? = nil,
        conferenceData: ConferenceData? = nil
    ) {
        self.id = id
        self.status = status
        self.summary = summary
        self.description = description
        self.location = location
        self.htmlLink = htmlLink
        self.hangoutLink = hangoutLink
        self.eventType = eventType
        self.start = start
        self.end = end
        self.originalStartTime = originalStartTime
        self.organizer = organizer
        self.attendees = attendees
        self.conferenceData = conferenceData
    }
}

public struct QualifyingMeeting: Codable, Equatable, Identifiable, Sendable {
    public enum ActionKind: String, Codable, Sendable {
        case join
        case openEvent
    }

    public let id: String
    public let eventID: String
    public let title: String
    public let start: Date
    public let end: Date
    public let actionURL: URL
    public let actionKind: ActionKind
    public let participants: [String]

    public init(eventID: String, occurrenceKey: String, title: String, start: Date, end: Date, actionURL: URL, actionKind: ActionKind, participants: [String] = []) {
        self.eventID = eventID
        self.id = occurrenceKey
        self.title = title
        self.start = start
        self.end = end
        self.actionURL = actionURL
        self.actionKind = actionKind
        self.participants = participants
    }
}

public enum CalendarDateParser {
    public static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}
