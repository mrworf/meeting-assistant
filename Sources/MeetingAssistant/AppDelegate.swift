import AppKit
import MeetingAssistantCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var model = AppModel()
    private var statusItem: NSStatusItem?
    private var configurationController: ConfigurationWindowController?
    private var alertPanels: AlertPanelController?
    private var quitApproved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyNamespaceIfNeeded()
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
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item

        alertPanels = AlertPanelController(model: model)
        registerLaunchAtLoginOnFirstRun()
        model.start()
    }

    private func migrateLegacyNamespaceIfNeeded() {
        guard Bundle.main.bundleIdentifier == AppIdentity.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateFrom.\(AppIdentity.legacyBundleIdentifier)"
        guard !defaults.bool(forKey: migrationKey) else { return }

        if let legacyValues = defaults.persistentDomain(forName: AppIdentity.legacyBundleIdentifier) {
            for (key, value) in legacyValues where key != "didConfigureLaunchAtLogin" && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        do {
            let currentSecret = KeychainStringStore(account: "google-oauth-client-secret")
            let legacySecret = KeychainStringStore(service: AppIdentity.legacyBundleIdentifier, account: "google-oauth-client-secret")
            if try currentSecret.load() == nil, let value = try legacySecret.load() {
                try currentSecret.save(value)
            }

            let currentCredential = KeychainCredentialStore()
            let legacyCredential = KeychainCredentialStore(service: AppIdentity.legacyBundleIdentifier)
            if try currentCredential.load() == nil, let value = try legacyCredential.load() {
                try currentCredential.save(value)
            }
            defaults.set(true, forKey: migrationKey)
        } catch {
            // Retry on the next launch if Keychain access is temporarily unavailable.
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitApproved ? .terminateNow : .terminateCancel
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        while menu.items.count > 3 { menu.removeItem(at: 3) }
        let now = Date()
        let upcomingPolicy = UpcomingMeetingPolicy()
        let sections = UpcomingMeetingDayPolicy().sections(model.upcomingMeetings, relativeTo: now)
        for (sectionIndex, section) in sections.enumerated() {
            if sectionIndex > 0 { menu.addItem(.separator()) }
            if section.showsDateHeading {
                let title = section.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
                let heading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                heading.isEnabled = false
                menu.addItem(heading)
            }
            for meeting in section.meetings {
                let start = meeting.start.formatted(date: .omitted, time: .shortened)
                let currentPrefix = upcomingPolicy.isActive(meeting, at: now) ? "» " : ""
                let item = NSMenuItem(title: "\(currentPrefix)\(start) — \(meeting.title)", action: nil, keyEquivalent: "")
                let attendeeMenu = NSMenu(title: "Participants")
                attendeeMenu.autoenablesItems = false
                let attendees = ParticipantListPolicy().displayEntries(meeting.participants)
                for attendee in attendees.isEmpty ? ["Participant details unavailable"] : attendees {
                    let attendeeItem = NSMenuItem(title: attendee, action: nil, keyEquivalent: "")
                    attendeeItem.isEnabled = false
                    attendeeMenu.addItem(attendeeItem)
                }
                attendeeMenu.addItem(.separator())
                let joinItem = NSMenuItem(title: "Join meeting", action: #selector(joinMeetingFromMenu(_:)), keyEquivalent: "")
                joinItem.target = self
                joinItem.representedObject = MenuMeetingBox(meeting)
                joinItem.isEnabled = true
                attendeeMenu.addItem(joinItem)
                item.submenu = attendeeMenu
                item.isEnabled = true
                menu.addItem(item)
            }
        }
    }

    @objc private func joinMeetingFromMenu(_ sender: NSMenuItem) {
        guard let meeting = (sender.representedObject as? MenuMeetingBox)?.meeting else { return }
        model.openFromMenu(meeting)
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

private final class MenuMeetingBox: NSObject {
    let meeting: QualifyingMeeting
    init(_ meeting: QualifyingMeeting) { self.meeting = meeting }
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
