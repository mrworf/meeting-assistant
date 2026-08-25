import Testing
@testable import MeetingAssistantCore

@Test func appIdentityUsesPlannedDefaults() {
    #expect(AppIdentity.name == "Meeting Assistant")
    #expect(AppIdentity.alertLeadTime == 300)
    #expect(AppIdentity.refreshInterval == 300)
}

