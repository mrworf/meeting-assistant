import Testing
@testable import MeetingAssistantCore

@Test func appIdentityUsesPlannedDefaults() {
    #expect(AppIdentity.name == "Meeting Assistant")
    #expect(AppIdentity.bundleIdentifier == "nu.sensenet.meetingassistant")
    #expect(AppIdentity.legacyBundleIdentifier == "com.henricandersson.MeetingAssistant")
    #expect(AppIdentity.alertLeadTime == 300)
    #expect(AppIdentity.refreshInterval == 300)
    #expect(AppIdentity.alertLeadMinuteOptions == [5, 10, 15])
}
