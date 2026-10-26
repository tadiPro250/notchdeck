import AppKit
import ServiceManagement

@main
enum Main {
    static let delegate = AppDelegate()

    static func main() {
        if CommandLine.arguments.contains("--test-media") {
            NowPlaying.selfTest()
            return
        }
        if CommandLine.arguments.contains("--test-dog") {
            CatBrain.selfTest()
            return
        }
        if CommandLine.arguments.contains("--test-hover") {
            HoverIntent.selfTest()
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-previews") {
            let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "previews"
            Previews.render(to: URL(fileURLWithPath: dir))
            return
        }
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var hub: NotchHub?
    private var statusItem: NSStatusItem?
    private let settingsWindow = SettingsWindowController()
    private let onboarding = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hub = NotchHub()
        self.hub = hub
        settingsWindow.services = hub.services
        hub.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        if CommandLine.arguments.contains("--settings") { settingsWindow.show() }
        // `--test-ring` rings a sample alarm for five seconds (for checking the ringing card).
        if CommandLine.arguments.contains("--test-ring") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                hub.services.clock.ring(.alarm(Alarm(hour: 7, minute: 30, label: "Test alarm")))
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { hub.services.clock.stopRinging() }
            }
        }
        // `--preview-lockscreen` shows the lock-screen turntable over the desktop for a while.
        if CommandLine.arguments.contains("--preview-lockscreen") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { hub.previewLockScreen(seconds: 20) }
        }
        if !AppSettings.shared.onboarded || CommandLine.arguments.contains("--onboarding") {
            onboarding.show(settings: .shared) { [weak self] in self?.settingsWindow.show() }
        }

        // `--open <tab>` opens the notch on launch (handy for screenshots and for testing).
        let args = CommandLine.arguments
        // `--open desk:colors` also picks a Desk section.
        if let i = args.firstIndex(of: "--open"), args.count > i + 1 {
            let parts = args[i + 1].split(separator: ":").map(String.init)
            if let tab = NotchTab(rawValue: parts[0]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    if parts.count > 1, let section = DeskSection(rawValue: parts[1]) {
                        self?.hub?.controllers.forEach { $0.model.deskSection = section }
                    }
                    // `--open tasks:deadline` shows the deadline card for a new task.
                    if parts.count > 1, parts[1] == "deadline" {
                        self?.hub?.controllers.forEach { $0.model.deadlineSheet.target = .newTask }
                    }
                    self?.hub?.expand(tab: tab, sticky: true)
                }
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "NotchDeck")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func previewLockScreen() { hub?.previewLockScreen(seconds: 12) }
    @objc private func feedCat() { hub?.services.cat.feed() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let welcome = NSMenuItem(title: "Welcome & Permissions…", action: #selector(openOnboarding), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
        menu.addItem(.separator())
        for tab in AppSettings.shared.visibleTabs {
            let entry = NSMenuItem(title: "Open \(tab.title)", action: #selector(openTab(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = tab.rawValue
            menu.addItem(entry)
        }
        let lock = NSMenuItem(title: "Preview Lock Screen", action: #selector(previewLockScreen), keyEquivalent: "")
        lock.target = self
        menu.addItem(lock)
        let feed = NSMenuItem(title: "Feed \(AppSettings.shared.catName)", action: #selector(feedCat), keyEquivalent: "")
        feed.target = self
        if AppSettings.shared.catEnabled { menu.addItem(feed) }
        menu.addItem(.separator())

        let hud = NSMenuItem(title: "Replace macOS Volume & Brightness HUD", action: #selector(toggleSystemHUD), keyEquivalent: "")
        hud.target = self
        hud.state = AppSettings.shared.replaceSystemHUD ? .on : .off
        menu.addItem(hud)
        if AppSettings.shared.replaceSystemHUD, !MediaKeyInterceptor.isTrusted {
            let hint = NSMenuItem(title: "Allow NotchDeck in Accessibility…", action: #selector(openAccessibility), keyEquivalent: "")
            hint.target = self
            menu.addItem(hint)
        }

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = NotchTab(rawValue: raw) else { return }
        hub?.expand(tab: tab, sticky: true)
    }

    @objc private func openOnboarding() {
        onboarding.show(settings: .shared) { [weak self] in self?.settingsWindow.show() }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func toggleSystemHUD() {
        AppSettings.shared.replaceSystemHUD.toggle()
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove NotchDeck.app to /Applications and try again."
            alert.runModal()
        }
    }
}
