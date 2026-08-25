import AppKit
import MeetingAssistantCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var configurationController: ConfigurationWindowController?
    private var alertPanels: AlertPanelController?
    private var quitApproved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: AppIdentity.name)
        let menu = NSMenu()
        let configureItem = NSMenuItem(title: "Configure", action: #selector(configure), keyEquivalent: ",")
        configureItem.target = self
        let quitItem = NSMenuItem(title: "Quit", action: #selector(requestQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(configureItem)
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item

        alertPanels = AlertPanelController(model: model)
        registerLaunchAtLoginOnFirstRun()
        model.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitApproved ? .terminateNow : .terminateCancel
    }

    @objc private func configure() {
        if configurationController == nil { configurationController = ConfigurationWindowController(model: model) }
        configurationController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func requestQuit() {
        let alert = NSAlert()
        alert.messageText = "Are you sure?"
        alert.informativeText = "Meeting Assistant prevents accidental quitting. You can confirm in 5 seconds."
        alert.window.level = .modalPanel
        let yes = alert.addButton(withTitle: "Yes (5)")
        alert.addButton(withTitle: "No")
        yes.isEnabled = false
        let countdown = QuitCountdown(button: yes)
        countdown.start()
        let response = alert.runModal()
        countdown.stop()
        guard response == .alertFirstButtonReturn, countdown.remaining == 0 else { return }
        quitApproved = true
        NSApp.terminate(nil)
    }

    private func registerLaunchAtLoginOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didConfigureLaunchAtLogin") else { return }
        defaults.set(true, forKey: "didConfigureLaunchAtLogin")
        do { try SMAppService.mainApp.register() }
        catch { model.launchAtLoginError = error.localizedDescription }
    }
}

@MainActor
private final class QuitCountdown: NSObject {
    private let button: NSButton
    private var timer: Timer?
    private(set) var remaining = 5

    init(button: NSButton) { self.button = button }

    func start() {
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate() }

    @objc private func tick() {
        remaining -= 1
        if remaining == 0 {
            button.title = "Yes"
            button.isEnabled = true
            stop()
        } else { button.title = "Yes (\(remaining))" }
    }
}
