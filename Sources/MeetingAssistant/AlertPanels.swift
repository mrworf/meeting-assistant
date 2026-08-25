import AppKit
import Combine
import MeetingAssistantCore
import SwiftUI

struct AlertContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let earliest = model.visibleMeetings.first
        let presentation = earliest.map { CountdownPresentation(meetingStart: $0.start, now: model.now) }
        VStack(spacing: 14) {
            Text(presentation?.text ?? "")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(presentation?.text ?? "")

            ForEach(model.visibleMeetings) { meeting in
                Button { model.open(meeting) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.title).font(.headline).lineLimit(1)
                            Text(rowStatus(meeting)).font(.caption).monospacedDigit().opacity(0.85)
                        }
                        Spacer()
                        Text(meeting.actionKind == .join ? "Join" : "Open Event")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(18)
        .foregroundStyle(.white)
        .background(PhaseBackground(phase: presentation?.phase ?? .upcoming))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private func rowStatus(_ meeting: QualifyingMeeting) -> String {
        let presentation = CountdownPresentation(meetingStart: meeting.start, now: model.now)
        return presentation.phase == .late ? presentation.text : "Starts in \(presentation.text)"
    }
}

private struct PhaseBackground: View {
    let phase: CountdownPhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: phase == .upcoming ? 60 : 0.45)) { context in
            let alternating = Int(context.date.timeIntervalSinceReferenceDate / 0.45).isMultiple(of: 2)
            Group {
                switch phase {
                case .upcoming:
                    Color(red: 0.12, green: 0.15, blue: 0.22)
                case .urgent:
                    Color.orange.opacity(alternating ? 1 : 0.65)
                case .late:
                    Color.red.opacity(alternating ? 1 : 0.42)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: alternating)
        }
    }
}

@MainActor
final class AlertPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panels: [String: NSPanel] = [:]
    private var cancellable: AnyCancellable?
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        cancellable = model.$visibleMeetings.sink { [weak self] meetings in
            Task { @MainActor in self?.update(meetingCount: meetings.count) }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuildPanels() }
        }
        rebuildPanels()
    }

    private func rebuildPanels() {
        let validIDs = Set(NSScreen.screens.map(screenID))
        let removedIDs = panels.keys.filter { !validIDs.contains($0) }
        for id in removedIDs {
            panels.removeValue(forKey: id)?.orderOut(nil)
        }
        for screen in NSScreen.screens where panels[screenID(screen)] == nil {
            panels[screenID(screen)] = makePanel(for: screen)
        }
        update(meetingCount: model.visibleMeetings.count)
    }

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let count = max(model.visibleMeetings.count, 1)
        let size = NSSize(width: 420, height: CGFloat(112 + count * 56))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: AlertContentView(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self
        restorePosition(of: panel, on: screen)
        return panel
    }

    private func update(meetingCount: Int) {
        if Set(panels.keys) != Set(NSScreen.screens.map(screenID)) { rebuildPanels(); return }
        for screen in NSScreen.screens {
            guard let panel = panels[screenID(screen)] else { continue }
            let desiredHeight = CGFloat(112 + max(meetingCount, 1) * 56)
            var frame = panel.frame
            frame.origin.y += frame.height - desiredHeight
            frame.size.height = desiredHeight
            panel.setFrame(clamped(frame, to: screen.visibleFrame), display: true)
            if meetingCount > 0 { panel.orderFrontRegardless() }
            else { panel.orderOut(nil) }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, let screen = panel.screen else { return }
        let adjusted = clamped(panel.frame, to: screen.visibleFrame)
        if adjusted != panel.frame { panel.setFrame(adjusted, display: true) }
        UserDefaults.standard.set([adjusted.origin.x, adjusted.origin.y], forKey: positionKey(screen))
    }

    private func restorePosition(of panel: NSPanel, on screen: NSScreen) {
        var frame = panel.frame
        if let saved = UserDefaults.standard.array(forKey: positionKey(screen)) as? [Double], saved.count == 2 {
            frame.origin = NSPoint(x: saved[0], y: saved[1])
        } else {
            frame.origin = NSPoint(x: screen.visibleFrame.maxX - frame.width - 20, y: screen.visibleFrame.maxY - frame.height - 20)
        }
        panel.setFrame(clamped(frame, to: screen.visibleFrame), display: false)
    }

    private func clamped(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    private func screenID(_ screen: NSScreen) -> String {
        String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)
    }

    private func positionKey(_ screen: NSScreen) -> String { "alertPanelPosition.\(screenID(screen))" }
}
