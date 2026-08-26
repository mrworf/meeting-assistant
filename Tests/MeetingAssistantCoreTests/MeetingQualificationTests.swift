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

@Test func movedRecurringOccurrenceGetsANewAlertIdentity() throws {
    var original = event(id: "recurring-event")
    original.originalStartTime = .init(dateTime: start)
    let originalMeeting = try #require(MeetingQualifier().qualify(original))
    #expect(originalMeeting.id == "recurring-event|\(start)")

    var moved = original
    moved.start = .init(dateTime: "2026-08-25T18:15:00Z")
    moved.end = .init(dateTime: "2026-08-25T18:45:00Z")
    let movedMeeting = try #require(MeetingQualifier().qualify(moved))

    #expect(movedMeeting.id != originalMeeting.id)
    #expect(movedMeeting.id == "recurring-event|\(start)|rescheduled:2026-08-25T18:15:00Z")
    let oneMinuteBeforeMovedStart = try #require(CalendarDateParser.date(from: moved.start.dateTime)).addingTimeInterval(-60)
    let visible = AlertPolicy(leadTime: 15 * 60).meetingsToDisplay(
        [movedMeeting],
        acknowledged: [originalMeeting.id],
        now: oneMinuteBeforeMovedStart
    )
    #expect(visible.map(\.id) == [movedMeeting.id])
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

@Test func participantNamesExcludeSelfDeclinedResourcesAndDuplicates() throws {
    var value = event(organizer: false)
    value.organizer = .init(email: "organizer@example.com", displayName: "Organizer")
    value.attendees = [
        .init(email: "me@example.com", displayName: "Me", selfUser: true, responseStatus: "accepted"),
        .init(email: "me@example.com", displayName: "Duplicate Me", responseStatus: "accepted"),
        .init(email: "alex@example.com", displayName: "Alex", responseStatus: "accepted"),
        .init(email: "alex@example.com", displayName: "Alex Duplicate", responseStatus: "accepted"),
        .init(email: "declined@example.com", displayName: "Declined", responseStatus: "declined"),
        .init(email: "room@example.com", displayName: "Room", resource: true, responseStatus: "accepted"),
    ]
    let meeting = try #require(MeetingQualifier().qualify(value))
    #expect(meeting.participants == ["Alex", "Organizer"])
    #expect(!meeting.participants.contains("Me"))
    #expect(!meeting.participants.contains("Duplicate Me"))
}

@Test func participantListShowsFourNamesAndAdditionalCountWhenOverFive() {
    let participants = ["One", "Two", "Three", "Four", "Five", "Six", "Seven"]
    #expect(ParticipantListPolicy().displayEntries(participants) == ["One", "Two", "Three", "Four", "and 3 additional"])
    #expect(ParticipantListPolicy().displayEntries(Array(participants.prefix(5))) == ["One", "Two", "Three", "Four", "Five"])
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

@Test func policyShowsLeadWindowAndOnlyRecentlyStartedMeetings() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    func meeting(_ id: String, start: TimeInterval, end: TimeInterval) -> QualifyingMeeting {
        .init(eventID: id, occurrenceKey: id, title: id, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), actionURL: URL(string: "https://meet.google.com/abc")!, actionKind: .join)
    }
    let meetings = [
        meeting("soon", start: 300, end: 600),
        meeting("later", start: 301, end: 700),
        meeting("active", start: -60, end: 60),
        meeting("ten-minutes-late", start: -600, end: 60),
        meeting("too-late", start: -601, end: 60),
        meeting("ended", start: -120, end: -1),
    ]
    let visible = AlertPolicy().meetingsToDisplay(meetings, acknowledged: ["active"], now: now)
    #expect(visible.map(\.id) == ["ten-minutes-late", "soon"])
}

@Test func upcomingPolicyIncludesActiveMeetingsAndLimitsTheMenuToFive() {
    let now = Date(timeIntervalSince1970: 10_000)
    let url = URL(string: "https://meet.google.com/abc")!
    func meeting(_ id: String, start: TimeInterval, end: TimeInterval) -> QualifyingMeeting {
        .init(eventID: id, occurrenceKey: id, title: "Meeting \(id)", start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), actionURL: url, actionKind: .join)
    }
    let futureMeetings: [QualifyingMeeting] = (1...7).reversed().map { index in
        let start = TimeInterval(index * 60)
        return meeting("\(index)", start: start, end: start + 60)
    }
    let input: [QualifyingMeeting] = [
        meeting("ended", start: -1_200, end: -60),
        meeting("active", start: -900, end: 900),
    ] + futureMeetings
    let result = UpcomingMeetingPolicy().meetings(input, after: now)
    #expect(result.map(\.eventID) == ["active", "1", "2", "3", "4"])
}

@Test func upcomingPolicyIdentifiesOnlyMeetingsHappeningNow() {
    let now = Date(timeIntervalSince1970: 10_000)
    let url = URL(string: "https://meet.google.com/abc")!
    func meeting(_ id: String, start: TimeInterval, end: TimeInterval) -> QualifyingMeeting {
        .init(eventID: id, occurrenceKey: id, title: id, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), actionURL: url, actionKind: .join)
    }
    let policy = UpcomingMeetingPolicy()

    #expect(policy.isActive(meeting("started", start: 0, end: 60), at: now))
    #expect(policy.isActive(meeting("ongoing", start: -900, end: 60), at: now))
    #expect(!policy.isActive(meeting("future", start: 1, end: 60), at: now))
    #expect(!policy.isActive(meeting("ended", start: -60, end: 0), at: now))
}

@Test func upcomingDaySectionsSeparateDaysAndLabelOnlyDateGaps() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 9)))
    let url = URL(string: "https://meet.google.com/abc")!
    func meeting(_ id: String, dayOffset: Int, hour: Int) -> QualifyingMeeting {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return .init(eventID: id, occurrenceKey: id, title: id, start: start, end: start.addingTimeInterval(60), actionURL: url, actionKind: .join)
    }

    let sections = UpcomingMeetingDayPolicy().sections([
        meeting("today", dayOffset: 0, hour: 10),
        meeting("tomorrow-1", dayOffset: 1, hour: 9),
        meeting("tomorrow-2", dayOffset: 1, hour: 11),
        meeting("later", dayOffset: 3, hour: 9),
    ], relativeTo: today, calendar: calendar)

    #expect(sections.map(\.meetings.count) == [1, 2, 1])
    #expect(sections.map(\.showsDateHeading) == [false, false, true])
}

@Test func firstMeetingBeyondTomorrowGetsADateHeading() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 9)))
    let start = try #require(calendar.date(byAdding: .day, value: 2, to: today))
    let meeting = QualifyingMeeting(eventID: "later", occurrenceKey: "later", title: "Later", start: start, end: start.addingTimeInterval(60), actionURL: URL(string: "https://meet.google.com/abc")!, actionKind: .join)
    #expect(UpcomingMeetingDayPolicy().sections([meeting], relativeTo: today, calendar: calendar).first?.showsDateHeading == true)
}
