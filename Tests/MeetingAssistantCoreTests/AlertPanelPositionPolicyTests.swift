import Foundation
import Testing
@testable import MeetingAssistantCore

@Test func defaultAlertPositionUsesLargerCornerInset() {
    let policy = AlertPanelPositionPolicy()
    let origin = policy.defaultOrigin(panelSize: CGSize(width: 420, height: 168), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    #expect(origin == CGPoint(x: 972, y: 684))
}

@Test func legacyDefaultPositionMigratesButCustomPositionIsPreserved() {
    let policy = AlertPanelPositionPolicy()
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 420, height: 168)
    #expect(policy.restoredOrigin(saved: CGPoint(x: 1000, y: 712), panelSize: size, visibleFrame: visible) == CGPoint(x: 972, y: 684))
    #expect(policy.restoredOrigin(saved: CGPoint(x: 700, y: 400), panelSize: size, visibleFrame: visible) == CGPoint(x: 700, y: 400))
}
