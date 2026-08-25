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

