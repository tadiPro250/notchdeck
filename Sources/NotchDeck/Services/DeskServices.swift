import AppKit
import Combine

enum AppSupport {
    static let folder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}

/// A scratchpad that saves itself.
final class NotesStore: ObservableObject {
    @Published var text: String {
        didSet { scheduleSave() }
    }

    private let file = AppSupport.folder.appendingPathComponent("notes.txt")
    private var saveWork: DispatchWorkItem?
    private let persists: Bool

    init(live: Bool = true) {
        persists = live
        text = live ? (try? String(contentsOf: file, encoding: .utf8)) ?? "" : ""
    }

    func clear() { text = "" }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    private func scheduleSave() {
        guard persists else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [file, text] in try? text.write(to: file, atomically: true, encoding: .utf8) }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

/// The user's Shortcuts (from the `shortcuts` command-line tool), run with one click.
final class ShortcutsService: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var running: String?
    @Published private(set) var lastResult: (name: String, ok: Bool)?

    private let queue = DispatchQueue(label: "notchdeck.shortcuts")

    func reload() {
        queue.async { [weak self] in
            let output = Self.run(["list"])?.output ?? ""
            let names = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            DispatchQueue.main.async { self?.names = names }
        }
    }

    func showPreview(_ names: [String]) {
        self.names = names
    }

    func run(_ name: String) {
        running = name
        queue.async { [weak self] in
            let ok = Self.run(["run", name])?.status == 0
            DispatchQueue.main.async {
                self?.running = nil
                self?.lastResult = (name, ok)
            }
        }
    }

    func openShortcutsApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Shortcuts.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    private static func run(_ arguments: [String]) -> (output: String, status: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }
}

/// Runs the shell command from Settings → Desk and shows its output (git status, a ping, CI…).
final class ScriptRunner: ObservableObject {
    @Published private(set) var output = ""
    @Published private(set) var lastRun: Date?
    @Published private(set) var isRunning = false
    @Published private(set) var failed = false

    private let settings: AppSettings
    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchdeck.script")

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Runs now and then every interval, while the Script view is on screen.
    func startRefreshing() {
        run()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(Double(settings.scriptInterval), 2), repeats: true) { [weak self] _ in
            self?.run()
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func showPreview(_ text: String) {
        output = text
        lastRun = Date()
    }

    func run() {
        let command = settings.scriptCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isRunning else { return }
        isRunning = true
        queue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var text = ""
            var status: Int32 = -1
            if (try? process.run()) != nil {
                // Never let a hung command block the widget.
                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: killer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()
                text = String(decoding: data.prefix(8000), as: UTF8.self)
                status = process.terminationStatus
            } else {
                text = "Couldn't start /bin/zsh"
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.output = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.failed = status != 0
                self.lastRun = Date()
                self.isRunning = false
            }
        }
    }
}
