import AppKit
import ServiceManagement

@main
enum Main {
    static let delegate = AppDelegate()

    static func main() {
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
    private var controller: NotchController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()

        // `--open <tab>` opens the notch on launch (handy for screenshots and for testing).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), args.count > i + 1, let tab = NotchTab(rawValue: args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.controller?.expand(tab: tab, sticky: true)
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "NotchDeck")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for tab in NotchTab.allCases {
            let entry = NSMenuItem(title: "Open \(tab.title)", action: #selector(openTab(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = tab.rawValue
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = NotchTab(rawValue: raw) else { return }
        controller?.expand(tab: tab, sticky: true)
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
