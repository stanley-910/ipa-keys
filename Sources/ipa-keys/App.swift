import AppKit
import ApplicationServices
import Carbon.HIToolbox
import IPAKeysCore

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ipa-keys/config.txt")

    private var controller: Controller!
    private var tap: Tap?
    private var statusItem: NSStatusItem?
    private var problemItem = NSMenuItem()
    private var enabledItem = NSMenuItem()
    private var configStamp: [FileAttributeKey: AnyHashable] = [:]
    private var configWarnings = 0
    private var secureInput = false
    private var trusted = false
    private var timer: Timer?

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.open()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let commit = Bundle.main.object(forInfoDictionaryKey: "IPAKeysCommit") as? String ?? "unknown commit"
        Log.write("ipa-keys \(version) (\(commit)) starting (pid \(getpid()), \(Bundle.main.bundlePath))")
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
            Log.write("another ipa-keys is already running; quitting so symbols are not typed twice")
            exit(0)
        }
        let keymap = KeyMap.current()
        Log.write("keyboard layout: \(keymap.layoutName)")
        controller = Controller(config: loadConfig(), keymap: keymap, enabled: enabled)
        controller.onToggle = { [weak self] on in
            self?.enabled = on
            self?.refresh()
        }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { controller.appChanged(front) }
        setUpMenu()
        observe()

        trusted = AXIsProcessTrusted()
        if !trusted {
            // Shows the system prompt once; the grant is in System Settings.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            Log.write("waiting for Accessibility permission: System Settings > Privacy & Security > Accessibility, turn on ipa-keys")
        }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Once a second: start the tap when permission arrives, follow secure
    /// input, and reload the config when the file changes.
    private func tick() {
        let nowTrusted = AXIsProcessTrusted()
        if nowTrusted != trusted {
            trusted = nowTrusted
            Log.write(nowTrusted ? "Accessibility granted" : "Accessibility was turned off; keys will not work until it is back on")
            refresh()
        }
        if tap == nil, nowTrusted {
            let t = Tap(controller: controller)
            if t.start() {
                tap = t
                Log.write("ready: chord \(chordName()), prefix \(currentPrefix)")
                refresh()
            } else {
                Log.write("could not create the event tap although Accessibility is granted; try turning ipa-keys off and on in Accessibility")
            }
        }
        let secure = IsSecureEventInputEnabled()
        if secure != secureInput {
            secureInput = secure
            controller.reset()
            if secure {
                let pid = (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"] as? NSNumber
                let name = pid.flatMap { NSRunningApplication(processIdentifier: pid_t($0.int32Value))?.localizedName }
                Log.write("secure input on\(name.map { " (\($0))" } ?? ""): ipa-keys does nothing until it is off")
            } else {
                Log.write("secure input off")
            }
            refresh()
        }
        if stamp() != configStamp { reload(reason: "file changed") }
    }

    // MARK: config

    private var currentPrefix = ";"
    private var currentChord: Modifiers = [.control, .shift]

    private func stamp() -> [FileAttributeKey: AnyHashable] {
        guard let a = try? FileManager.default.attributesOfItem(atPath: App.configURL.path) else { return [:] }
        var s: [FileAttributeKey: AnyHashable] = [:]
        for k in [FileAttributeKey.modificationDate, .size, .systemFileNumber] {
            if let v = a[k] as? AnyHashable { s[k] = v }
        }
        return s
    }

    private func loadConfig() -> Config {
        let fm = FileManager.default
        let url = App.configURL
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try defaultConfigText.write(to: url, atomically: true, encoding: .utf8)
                Log.write("wrote the default config to \(url.path)")
            } catch {
                Log.write("could not write the default config to \(url.path): \(error.localizedDescription); using built-in defaults")
            }
        }
        configStamp = stamp()
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Log.write("could not read \(url.path) as UTF-8 (\(error.localizedDescription)); using built-in defaults")
            text = defaultConfigText
        }
        let c = Config.parse(text)
        for w in c.warnings { Log.write("config: \(w)") }
        configWarnings = c.warnings.count
        currentPrefix = c.prefix
        currentChord = c.chord
        Log.write("config: \(c.groups.count) groups, \(c.names.count) names, \(c.warnings.count) problems")
        return c
    }

    private func reload(reason: String) {
        Log.write("reloading config (\(reason))")
        controller.setConfig(loadConfig())
        refresh()
    }

    private func chordName() -> String {
        var parts: [String] = []
        if currentChord.contains(.control) { parts.append("control") }
        if currentChord.contains(.option) { parts.append("option") }
        if currentChord.contains(.shift) { parts.append("shift") }
        if currentChord.contains(.command) { parts.append("command") }
        return parts.joined(separator: "+")
    }

    // MARK: system events

    private func observe() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.controller.appChanged(app?.bundleIdentifier ?? "")
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            let map = KeyMap.current()
            self?.controller.setKeyMap(map)
            Log.write("keyboard layout: \(map.layoutName)")
        }
    }

    // MARK: menu

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "ə"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        problemItem.target = self
        menu.addItem(problemItem)
        enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(.separator())
        for (title, action) in [("Edit Config", #selector(editConfig)), ("Reload", #selector(reloadConfig))] {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        if App.updateScript != nil {
            let i = NSMenuItem(title: "Update…", action: #selector(update), keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    private func refresh() {
        enabledItem.state = enabled ? .on : .off
        var problem: (String, Selector?)?
        if !trusted {
            problem = ("Grant Accessibility…", #selector(openAccessibility))
        } else if tap == nil {
            problem = ("Not running; see log", #selector(openLog))
        } else if secureInput {
            problem = ("Secure input on", nil)
        } else if configWarnings > 0 {
            problem = ("Config problems: \(configWarnings)", #selector(openLog))
        }
        problemItem.isHidden = problem == nil
        problemItem.title = problem?.0 ?? ""
        problemItem.action = problem?.1
        problemItem.isEnabled = problem?.1 != nil
        let working = enabled && trusted && tap != nil && !secureInput
        statusItem?.button?.appearsDisabled = !working
        statusItem?.button?.toolTip = working ? "ipa-keys" : (problem?.0 ?? "ipa-keys off")
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        controller.isEnabled = enabled
        Log.write(enabled ? "enabled" : "disabled")
        refresh()
    }

    @objc private func editConfig() {
        if !FileManager.default.fileExists(atPath: App.configURL.path) { reload(reason: "file missing") }
        NSWorkspace.shared.open(App.configURL)
    }

    @objc private func reloadConfig() { reload(reason: "menu") }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The source checkout's update script, recorded at build time.
    static var updateScript: URL? {
        guard let root = Bundle.main.object(forInfoDictionaryKey: "IPAKeysSource") as? String else { return nil }
        let url = URL(fileURLWithPath: root).appendingPathComponent("scripts/update.sh")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Runs update.sh in a Terminal window: it shows the result, can ask for
    /// a password, and is not stopped when the install restarts ipa-keys.
    @objc private func update() {
        guard let script = App.updateScript else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        Log.write("update: opening \(script.path) in Terminal")
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Log.write("update: could not open Terminal: \(error.localizedDescription)") }
        }
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }
}
