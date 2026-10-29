import Foundation
import Testing
@testable import MeetingAssistantCore

private let instant = Date(timeIntervalSince1970: 1_800_000_000)

private func meeting(_ id: String = "one", end: TimeInterval = 600, kind: QualifyingMeeting.ActionKind = .join) -> QualifyingMeeting {
    QualifyingMeeting(eventID: id, occurrenceKey: "\(id)|start", title: id,
                      start: instant.addingTimeInterval(-600), end: instant.addingTimeInterval(end),
                      actionURL: URL(string: "https://meet.google.com/abc")!, actionKind: kind)
}

@Test func endCountdownOnlyTracksEligibleJoins() {
    var countdown = MeetingEndCountdown()
    countdown.join(meeting(), enabled: false, now: instant)
    #expect(countdown.meeting == nil)
    countdown.join(meeting(kind: .openEvent), enabled: true, now: instant)
    #expect(countdown.meeting == nil)
    countdown.join(meeting(end: 0), enabled: true, now: instant)
    #expect(countdown.meeting == nil)
    countdown.join(meeting("selected"), enabled: true, now: instant)
    #expect(countdown.meeting?.id == "selected|start")
    countdown.join(meeting("replacement"), enabled: true, now: instant)
    #expect(countdown.meeting?.id == "replacement|start")
}

@Test func endCountdownThresholdProgressAndOvertime() throws {
    var countdown = MeetingEndCountdown()
    countdown.join(meeting(), enabled: true, now: instant)
    #expect(countdown.presentation(now: instant, leadTime: 300, regularReminderVisible: false) == nil)
    let first = try #require(countdown.presentation(now: instant.addingTimeInterval(300), leadTime: 300, regularReminderVisible: false))
    #expect(first.text == "05:00")
    #expect(first.progress == 1)
    #expect(first.phase == .upcoming)
    let half = try #require(countdown.presentation(now: instant.addingTimeInterval(450), leadTime: 300, regularReminderVisible: false))
    #expect(half.progress == 0.5)
    #expect(countdown.presentation(now: instant.addingTimeInterval(540), leadTime: 300, regularReminderVisible: false)?.phase == .urgent)
    let zero = try #require(countdown.presentation(now: instant.addingTimeInterval(600), leadTime: 300, regularReminderVisible: false))
    #expect(zero.text == "00:00")
    #expect(zero.progress == 0)
    let over = try #require(countdown.presentation(now: instant.addingTimeInterval(665), leadTime: 300, regularReminderVisible: false))
    #expect(over.text == "Over by 01:05")
    #expect(over.phase == .late)
    #expect(over.progress == 0)
}

@Test func lateJoinStartsWithFullProgress() {
    var countdown = MeetingEndCountdown()
    countdown.join(meeting(end: 120), enabled: true, now: instant)
    #expect(countdown.presentation(now: instant, leadTime: 300, regularReminderVisible: false)?.progress == 1)
    #expect(countdown.presentation(now: instant.addingTimeInterval(60), leadTime: 300, regularReminderVisible: false)?.progress == 0.5)
}

@Test func dismissalAndRegularRemindersPermanentlyClearTracking() {
    var countdown = MeetingEndCountdown()
    countdown.join(meeting(), enabled: true, now: instant)
    #expect(countdown.presentation(now: instant, leadTime: 300, regularReminderVisible: true) == nil)
    #expect(countdown.meeting == nil)
    #expect(countdown.presentation(now: instant.addingTimeInterval(400), leadTime: 300, regularReminderVisible: false) == nil)
    countdown.join(meeting(), enabled: true, now: instant)
    countdown.clear()
    #expect(countdown.presentation(now: instant.addingTimeInterval(700), leadTime: 300, regularReminderVisible: false) == nil)
}

@Test func calendarChangesUpdateEndAndRemovalClearsTracking() {
    var countdown = MeetingEndCountdown()
    countdown.join(meeting(end: 120), enabled: true, now: instant)
    _ = countdown.presentation(now: instant, leadTime: 300, regularReminderVisible: false)
    countdown.synchronize([meeting(end: 900)])
    #expect(countdown.presentation(now: instant, leadTime: 300, regularReminderVisible: false) == nil)
    #expect(countdown.presentation(now: instant.addingTimeInterval(600), leadTime: 300, regularReminderVisible: false)?.progress == 1)
    countdown.synchronize([])
    #expect(countdown.meeting == nil)
}

@Test func nextReminderReplacesVisibleOvertime() {
    var countdown = MeetingEndCountdown()
    countdown.join(meeting(end: 60), enabled: true, now: instant)
    _ = countdown.presentation(now: instant, leadTime: 300, regularReminderVisible: false)
    #expect(countdown.presentation(now: instant.addingTimeInterval(120), leadTime: 300, regularReminderVisible: false)?.text == "Over by 01:00")
    #expect(countdown.presentation(now: instant.addingTimeInterval(120), leadTime: 300, regularReminderVisible: true) == nil)
    #expect(countdown.meeting == nil)
}

@Test func wakingAfterEndShowsEmptyOvertimeBar() {
    var countdown = MeetingEndCountdown()
    countdown.join(meeting(), enabled: true, now: instant)
    let presentation = countdown.presentation(now: instant.addingTimeInterval(720), leadTime: 300, regularReminderVisible: false)
    #expect(presentation?.text == "Over by 02:00")
    #expect(presentation?.progress == 0)
}
