import Foundation

public enum CountdownPhase: Equatable, Sendable {
    case upcoming
    case urgent
    case late
}

public struct CountdownPresentation: Equatable, Sendable {
    public let phase: CountdownPhase
    public let text: String

    public init(meetingStart: Date, now: Date) {
        let seconds = Int(meetingStart.timeIntervalSince(now).rounded(.up))
        if seconds <= 0 {
            phase = .late
            text = "Late by \(Self.duration(abs(seconds)))"
        } else {
            phase = seconds <= 60 ? .urgent : .upcoming
            text = Self.duration(seconds)
        }
    }

    private static func duration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

public struct AlertPolicy: Sendable {
    public var leadTime: TimeInterval

    public init(leadTime: TimeInterval = AppIdentity.alertLeadTime) {
        self.leadTime = leadTime
    }

    public func meetingsToDisplay(_ meetings: [QualifyingMeeting], acknowledged: Set<String>, now: Date) -> [QualifyingMeeting] {
        meetings
            .filter { !acknowledged.contains($0.id) }
            .filter { meeting in
                if meeting.start <= now { return meeting.end > now }
                return meeting.start.timeIntervalSince(now) <= leadTime
            }
            .sorted { $0.start < $1.start }
    }
}

public struct UpcomingMeetingPolicy: Sendable {
    public init() {}

    public func meetings(_ meetings: [QualifyingMeeting], after now: Date, limit: Int = 5) -> [QualifyingMeeting] {
        guard limit > 0 else { return [] }
        return Array(meetings
            .filter { $0.start > now }
            .sorted {
                if $0.start == $1.start { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return $0.start < $1.start
            }
            .prefix(limit))
    }
}

public struct UpcomingMeetingDaySection: Equatable, Sendable {
    public let day: Date
    public let meetings: [QualifyingMeeting]
    public let showsDateHeading: Bool

    public init(day: Date, meetings: [QualifyingMeeting], showsDateHeading: Bool) {
        self.day = day
        self.meetings = meetings
        self.showsDateHeading = showsDateHeading
    }
}

public struct UpcomingMeetingDayPolicy: Sendable {
    public init() {}

    public func sections(_ meetings: [QualifyingMeeting], relativeTo now: Date, calendar: Calendar = .current) -> [UpcomingMeetingDaySection] {
        var result: [UpcomingMeetingDaySection] = []
        var previousDay = calendar.startOfDay(for: now)

        for meeting in meetings.sorted(by: { $0.start < $1.start }) {
            let day = calendar.startOfDay(for: meeting.start)
            if let last = result.last, calendar.isDate(last.day, inSameDayAs: day) {
                result[result.count - 1] = UpcomingMeetingDaySection(day: last.day, meetings: last.meetings + [meeting], showsDateHeading: last.showsDateHeading)
                continue
            }

            let distance = calendar.dateComponents([.day], from: previousDay, to: day).day ?? 0
            result.append(UpcomingMeetingDaySection(day: day, meetings: [meeting], showsDateHeading: distance > 1))
            previousDay = day
        }
        return result
    }
}

public protocol AcknowledgementStoring: Sendable {
    func load() -> Set<String>
    func save(_ identifiers: Set<String>)
}

public final class UserDefaultsAcknowledgementStore: AcknowledgementStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "acknowledgedMeetingOccurrences") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public func save(_ identifiers: Set<String>) {
        defaults.set(Array(identifiers).sorted(), forKey: key)
    }
}

public final class AcknowledgementController: @unchecked Sendable {
    private let store: AcknowledgementStoring
    private let lock = NSLock()
    private var identifiers: Set<String>

    public init(store: AcknowledgementStoring) {
        self.store = store
        self.identifiers = store.load()
    }

    public var acknowledged: Set<String> {
        lock.withLock { identifiers }
    }

    public func acknowledge(_ meetings: [QualifyingMeeting]) {
        let updated = lock.withLock { () -> Set<String> in
            identifiers.formUnion(meetings.map(\.id))
            return identifiers
        }
        store.save(updated)
    }
}
