import AppKit
import MeetingAssistantCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var configurationController: ConfigurationWindowController?
    private var alertPanels: AlertPanelController?
    private var quitApproved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: AppIdentity.name)
        let menu = NSMenu()
        let configureItem = NSMenuItem(title: "Configure", action: #selector(configure), keyEquivalent: ",")
        configureItem.target = self
        let quitItem = NSMenuItem(title: "Quit", action: #selector(requestQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(configureItem)
        menu.addItem(quitItem)
        menu.addItem(.separator())
        menu.delegate = self
        item.menu = menu
        statusItem = item

        alertPanels = AlertPanelController(model: model)
        registerLaunchAtLoginOnFirstRun()
        model.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitApproved ? .terminateNow : .terminateCancel
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        while menu.items.count > 3 { menu.removeItem(at: 3) }
        for meeting in model.upcomingMeetings {
            let start = meeting.start.formatted(date: .omitted, time: .shortened)
            let item = NSMenuItem(title: "\(start) — \(meeting.title)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    @objc private func configure() {
        if configurationController == nil { configurationController = ConfigurationWindowController(model: model) }
        configurationController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        configurationController?.window?.makeKeyAndOrderFront(nil)
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

    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(editRoot)
        mainMenu.setSubmenu(editMenu, for: editRoot)
        NSApp.mainMenu = mainMenu
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
