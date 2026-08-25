import Foundation

public struct JoinURLResolver: Sendable {
    public init() {}

    public func resolve(_ event: GoogleCalendarEvent) -> (URL, QualifyingMeeting.ActionKind)? {
        if let uri = event.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri,
           let url = safeWebURL(uri) {
            return (url, .join)
        }
        if let url = safeWebURL(event.hangoutLink) {
            return (url, .join)
        }
        for text in [event.location, event.description].compactMap({ $0 }) {
            if let url = recognizedMeetingURL(in: text) {
                return (url, .join)
            }
        }
        if let url = safeWebURL(event.htmlLink) {
            return (url, .openEvent)
        }
        return nil
    }

    private func safeWebURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        return url
    }

    private func recognizedMeetingURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { continue }
            let allowed = host == "meet.google.com"
                || host == "zoom.us" || host.hasSuffix(".zoom.us")
                || host == "zoomgov.com" || host.hasSuffix(".zoomgov.com")
                || host == "teams.microsoft.com" || host.hasSuffix(".teams.microsoft.com")
                || host == "teams.live.com"
            if allowed { return url }
        }
        return nil
    }
}

public struct MeetingQualifier: Sendable {
    private let resolver: JoinURLResolver

    public init(resolver: JoinURLResolver = JoinURLResolver()) {
        self.resolver = resolver
    }

    public func qualify(_ event: GoogleCalendarEvent) -> QualifyingMeeting? {
        guard event.status != "cancelled",
              event.eventType == nil || event.eventType == "default",
              event.start.date == nil,
              let start = CalendarDateParser.date(from: event.start.dateTime),
              let end = CalendarDateParser.date(from: event.end.dateTime),
              end > start,
              isAccepted(event),
              hasAnotherParticipant(event),
              let (actionURL, actionKind) = resolver.resolve(event)
        else { return nil }

        let occurrenceStart = event.originalStartTime?.dateTime ?? event.start.dateTime ?? "unknown"
        return QualifyingMeeting(
            eventID: event.id,
            occurrenceKey: "\(event.id)|\(occurrenceStart)",
            title: event.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled meeting",
            start: start,
            end: end,
            actionURL: actionURL,
            actionKind: actionKind,
            participants: participantNames(event)
        )
    }

    private func isAccepted(_ event: GoogleCalendarEvent) -> Bool {
        if event.organizer?.selfUser == true { return true }
        return event.attendees?.first(where: { $0.selfUser == true })?.responseStatus == "accepted"
    }

    private func hasAnotherParticipant(_ event: GoogleCalendarEvent) -> Bool {
        event.attendees?.contains {
            $0.selfUser != true && $0.resource != true && $0.responseStatus != "declined"
        } == true
    }

    private func participantNames(_ event: GoogleCalendarEvent) -> [String] {
        let selfEmails = Set((event.attendees ?? [])
            .filter { $0.selfUser == true }
            .compactMap { $0.email?.lowercased() })
        var people = (event.attendees ?? []).filter {
            $0.selfUser != true && $0.resource != true && $0.responseStatus != "declined"
        }
        if let organizer = event.organizer, organizer.selfUser != true, organizer.resource != true {
            people.append(organizer)
        }

        var seen: Set<String> = []
        var names: [String] = []
        for person in people {
            let email = person.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let email, selfEmails.contains(email.lowercased()) { continue }
            let displayName = person.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name = displayName?.nonEmpty ?? email?.nonEmpty else { continue }
            let identity = (email?.nonEmpty ?? name).lowercased()
            guard seen.insert(identity).inserted else { continue }
            names.append(name)
        }
        return names
    }
}

public struct ParticipantListPolicy: Sendable {
    public init() {}

    public func displayEntries(_ participants: [String], limit: Int = 5) -> [String] {
        guard limit > 0 else { return [] }
        guard participants.count > limit else { return participants }
        let visibleCount = max(limit - 1, 0)
        return Array(participants.prefix(visibleCount)) + ["and \(participants.count - visibleCount) additional"]
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
