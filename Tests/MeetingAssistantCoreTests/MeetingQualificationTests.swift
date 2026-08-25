import Foundation
import Testing
@testable import MeetingAssistantCore

private let start = "2026-08-25T18:00:00Z"
private let end = "2026-08-25T18:30:00Z"

private func event(
    id: String = "event-1",
    organizer: Bool = false,
    selfStatus: String = "accepted",
    otherStatus: String = "accepted",
    allDay: Bool = false,
    eventType: String = "default",
    hangoutLink: String? = "https://meet.google.com/abc-defg-hij",
    location: String? = nil,
    description: String? = nil,
    htmlLink: String? = "https://calendar.google.com/calendar/event?eid=abc"
) -> GoogleCalendarEvent {
    GoogleCalendarEvent(
        id: id,
        description: description,
        location: location,
        htmlLink: htmlLink,
        hangoutLink: hangoutLink,
        eventType: eventType,
        start: allDay ? .init(date: "2026-08-25") : .init(dateTime: start),
        end: allDay ? .init(date: "2026-08-26") : .init(dateTime: end),
        organizer: .init(selfUser: organizer),
        attendees: [
            .init(email: "me@example.com", selfUser: true, responseStatus: selfStatus),
            .init(email: "you@example.com", responseStatus: otherStatus),
        ]
    )
}

@Test func acceptsInvitedAndHostedMeetings() {
    #expect(MeetingQualifier().qualify(event()) != nil)
    #expect(MeetingQualifier().qualify(event(organizer: true, selfStatus: "needsAction")) != nil)
}

@Test func rejectsNonMeetingsAndUnacceptedInvitations() {
    #expect(MeetingQualifier().qualify(event(selfStatus: "tentative")) == nil)
    #expect(MeetingQualifier().qualify(event(otherStatus: "declined")) == nil)
    #expect(MeetingQualifier().qualify(event(allDay: true)) == nil)
    #expect(MeetingQualifier().qualify(event(eventType: "focusTime")) == nil)
}

@Test func ignoresRoomsWhenCountingParticipants() {
    var value = event()
    value.attendees = [
        .init(selfUser: true, responseStatus: "accepted"),
        .init(email: "room@example.com", resource: true, responseStatus: "accepted"),
    ]
    #expect(MeetingQualifier().qualify(value) == nil)
}

@Test func resolvesConferenceThenTextThenCalendarFallback() {
    var value = event(hangoutLink: nil, location: "Zoom: https://acme.zoom.us/j/123")
    value.conferenceData = .init(entryPoints: [.init(entryPointType: "video", uri: "https://teams.microsoft.com/l/meetup-join/first")])
    #expect(MeetingQualifier().qualify(value)?.actionURL.host == "teams.microsoft.com")

    value.conferenceData = nil
    #expect(MeetingQualifier().qualify(value)?.actionURL.host == "acme.zoom.us")

    value.location = "https://example.com/not-a-meeting"
    #expect(MeetingQualifier().qualify(value)?.actionKind == .openEvent)
}

@Test func countdownTransitionsAtExactBoundaries() {
    let base = Date(timeIntervalSince1970: 1_000)
    #expect(CountdownPresentation(meetingStart: base.addingTimeInterval(61), now: base).phase == .upcoming)
    #expect(CountdownPresentation(meetingStart: base.addingTimeInterval(60), now: base).phase == .urgent)
    #expect(CountdownPresentation(meetingStart: base, now: base).phase == .late)
    #expect(CountdownPresentation(meetingStart: base.addingTimeInterval(-65), now: base).text == "Late by 01:05")
}

@Test func policyShowsLeadWindowAndOnlyActiveOverdueMeetings() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    func meeting(_ id: String, start: TimeInterval, end: TimeInterval) -> QualifyingMeeting {
        .init(eventID: id, occurrenceKey: id, title: id, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), actionURL: URL(string: "https://meet.google.com/abc")!, actionKind: .join)
    }
    let meetings = [meeting("soon", start: 300, end: 600), meeting("later", start: 301, end: 700), meeting("active", start: -60, end: 60), meeting("ended", start: -120, end: -1)]
    let visible = AlertPolicy().meetingsToDisplay(meetings, acknowledged: ["active"], now: now)
    #expect(visible.map(\.id) == ["soon"])
}

