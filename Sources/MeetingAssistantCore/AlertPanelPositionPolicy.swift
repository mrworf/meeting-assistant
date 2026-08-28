import CoreGraphics
import Foundation

public struct AlertPanelPositionPolicy: Sendable {
    public static let defaultInset: CGFloat = 48
    public static let defaultVerticalInset: CGFloat = defaultInset * 3
    public static let legacyInset: CGFloat = 20

    public init() {}

    public func defaultOrigin(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.maxX - panelSize.width - Self.defaultInset,
            y: visibleFrame.maxY - panelSize.height - Self.defaultVerticalInset
        )
    }

    public func restoredOrigin(saved: CGPoint?, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        guard let saved else { return defaultOrigin(panelSize: panelSize, visibleFrame: visibleFrame) }
        let priorAutomaticOrigins = [Self.legacyInset, Self.defaultInset].map { inset in
            CGPoint(
                x: visibleFrame.maxX - panelSize.width - inset,
                y: visibleFrame.maxY - panelSize.height - inset
            )
        }
        let stillAtPriorAutomaticOrigin = priorAutomaticOrigins.contains { origin in
            abs(saved.x - origin.x) < 3 && abs(saved.y - origin.y) < 3
        }
        return stillAtPriorAutomaticOrigin ? defaultOrigin(panelSize: panelSize, visibleFrame: visibleFrame) : saved
    }
}
