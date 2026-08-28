import Foundation
import Testing
@testable import MeetingAssistantCore

@Test func defaultAlertPositionUsesTripleVerticalInset() {
    let policy = AlertPanelPositionPolicy()
    let origin = policy.defaultOrigin(panelSize: CGSize(width: 420, height: 168), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    #expect(origin == CGPoint(x: 972, y: 588))
}

@Test func priorDefaultPositionsMigrateButCustomPositionIsPreserved() {
    let policy = AlertPanelPositionPolicy()
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 420, height: 168)
    let newDefault = CGPoint(x: 972, y: 588)
    #expect(policy.restoredOrigin(saved: CGPoint(x: 1000, y: 712), panelSize: size, visibleFrame: visible) == newDefault)
    #expect(policy.restoredOrigin(saved: CGPoint(x: 972, y: 684), panelSize: size, visibleFrame: visible) == newDefault)
    #expect(policy.restoredOrigin(saved: CGPoint(x: 700, y: 400), panelSize: size, visibleFrame: visible) == CGPoint(x: 700, y: 400))
}
