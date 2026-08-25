import CoreGraphics
import Foundation

public struct AlertPanelPositionPolicy: Sendable {
    public static let defaultInset: CGFloat = 48
    public static let legacyInset: CGFloat = 20

    public init() {}

    public func defaultOrigin(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.maxX - panelSize.width - Self.defaultInset,
            y: visibleFrame.maxY - panelSize.height - Self.defaultInset
        )
    }

    public func restoredOrigin(saved: CGPoint?, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        guard let saved else { return defaultOrigin(panelSize: panelSize, visibleFrame: visibleFrame) }
        let legacy = CGPoint(
            x: visibleFrame.maxX - panelSize.width - Self.legacyInset,
            y: visibleFrame.maxY - panelSize.height - Self.legacyInset
        )
        let stillAtLegacyDefault = abs(saved.x - legacy.x) < 3 && abs(saved.y - legacy.y) < 3
        return stillAtLegacyDefault ? defaultOrigin(panelSize: panelSize, visibleFrame: visibleFrame) : saved
    }
}
