import Foundation
import Testing
@testable import MeetingAssistantCore

private final class MemoryAcknowledgementStore: AcknowledgementStoring, @unchecked Sendable {
    var identifiers: Set<String> = []
    func load() -> Set<String> { identifiers }
    func save(_ identifiers: Set<String>) { self.identifiers = identifiers }
}

@Test func acknowledgesTheEntireDisplayedGroup() {
    let store = MemoryAcknowledgementStore()
    let controller = AcknowledgementController(store: store)
    let now = Date()
    let url = URL(string: "https://meet.google.com/abc")!
    let meetings = [
        QualifyingMeeting(eventID: "1", occurrenceKey: "1|start", title: "One", start: now, end: now.addingTimeInterval(60), actionURL: url, actionKind: .join),
        QualifyingMeeting(eventID: "2", occurrenceKey: "2|start", title: "Two", start: now, end: now.addingTimeInterval(60), actionURL: url, actionKind: .join),
    ]
    controller.acknowledge(meetings)
    #expect(controller.acknowledged == ["1|start", "2|start"])
    #expect(store.identifiers == controller.acknowledged)
}

@Test func rescheduledOccurrenceHasANewAcknowledgementIdentity() {
    let store = MemoryAcknowledgementStore()
    store.identifiers = ["event|2026-08-25T10:00:00Z"]
    let controller = AcknowledgementController(store: store)
    #expect(!controller.acknowledged.contains("event|2026-08-25T10:30:00Z"))
}
