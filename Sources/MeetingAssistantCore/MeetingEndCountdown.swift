import Foundation

public struct MeetingEndPresentation: Equatable, Sendable {
    public let text: String
    public let phase: CountdownPhase
    public let progress: Double

    public init(end: Date, now: Date, baseline: TimeInterval) {
        let remaining = end.timeIntervalSince(now)
        let seconds = remaining >= 0 ? Int(remaining.rounded(.up)) : Int((-remaining).rounded(.down))
        let duration = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        text = remaining < 0 ? "Over by \(duration)" : duration
        phase = remaining < 0 ? .late : remaining <= 60 ? .urgent : .upcoming
        progress = baseline > 0 ? min(1, max(0, remaining / baseline)) : 0
    }
}

public struct MeetingEndCountdown: Sendable {
    public private(set) var meeting: QualifyingMeeting?
    private var baseline: TimeInterval?

    public init() {}

    public mutating func join(_ meeting: QualifyingMeeting, enabled: Bool, now: Date) {
        guard enabled, meeting.actionKind == .join, meeting.end > now else { return }
        self.meeting = meeting
        baseline = nil
    }

    public mutating func clear() {
        meeting = nil
        baseline = nil
    }

    public mutating func synchronize(_ meetings: [QualifyingMeeting]) {
        guard let tracked = meeting else { return }
        guard let updated = meetings.first(where: { $0.id == tracked.id }) else { clear(); return }
        if updated.end != tracked.end { baseline = nil }
        meeting = updated
    }

    public mutating func presentation(now: Date, leadTime: TimeInterval, regularReminderVisible: Bool) -> MeetingEndPresentation? {
        if regularReminderVisible { clear(); return nil }
        guard let meeting else { return nil }
        let remaining = meeting.end.timeIntervalSince(now)
        guard remaining <= leadTime else { baseline = nil; return nil }
        if baseline == nil { baseline = max(0, remaining) }
        return MeetingEndPresentation(end: meeting.end, now: now, baseline: baseline ?? 0)
    }
}
