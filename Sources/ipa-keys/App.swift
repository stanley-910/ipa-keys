import AppKit
import ApplicationServices
import Carbon.HIToolbox
import IPAKeysCore

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// The running app, for views that need it.
    private(set) static var shared: App?
    /// Held open (and locked) for the life of the process.
    private static var lockFD: Int32 = -1
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
    /// The current keyboard layout, for the shortcut recorder.
    private(set) var keymap = KeyMap()
    private let settingsModel = SettingsModel()
    private lazy var settingsWindow = SettingsWindow(model: settingsModel)
    private let paletteModel = PaletteModel()
    private lazy var palettePanel: PalettePanel = {
        let p = PalettePanel(model: paletteModel)
        p.onEscape = { [weak self] in self?.closePalette() }
        return p
    }()
    private var symbolsItem = NSMenuItem()
    private var updateItem = NSMenuItem()
    private var updateState: UpdateState?
    private var updateChecking = false
    private var lastUpdateCheck = Date.distantPast
    private let updateQueue = DispatchQueue(label: "ipa-keys.update-check", qos: .utility)

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        App.shared = self
        Log.open()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let commit = Bundle.main.object(forInfoDictionaryKey: "IPAKeysCommit") as? String ?? "unknown commit"
        Log.write("ipa-keys \(version) (\(commit)) starting (pid \(getpid()), \(Bundle.main.bundlePath))")
        // One copy at a time, bundled or not (a build run from .build has no
        // bundle id): two taps would type every symbol twice.
        let lockPath = Log.url.deletingLastPathComponent().appendingPathComponent("running.lock").path
        App.lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o600)
        if App.lockFD < 0 || flock(App.lockFD, LOCK_EX | LOCK_NB) != 0 {
            Log.write("another ipa-keys is already running; quitting so symbols are not typed twice")
            exit(0)
        }
        keymap = KeyMap.current()
        Log.write("keyboard layout: \(keymap.layoutName)")
        let config = loadConfig()
        controller = Controller(config: config, keymap: keymap, enabled: enabled)
        settingsModel.load(config)
        settingsModel.save = { [weak self] key, value in self?.writeSetting(key, value) }
        paletteModel.palette = Palette(config)
        paletteModel.insert = { [weak self] s in self?.insertFromPalette(s) }
        controller.onSymbols = { [weak self] in self?.symbolsChord() }
        controller.onToggle = { [weak self] on in
            self?.enabled = on
            self?.refresh()
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            controller.appChanged(front.bundleIdentifier ?? "", pid: front.processIdentifier)
        }
        Poster.context = { [controller] in controller!.outputContext }
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
        checkForUpdates()
        Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdates() }
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
            controller.contextChanged()
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
        if c.debugLog != Log.debug { Log.write("debug_log \(c.debugLog ? "on: typed names and text are logged" : "off")") }
        Log.debug = c.debugLog
        currentChord = c.chord
        Log.write("config: \(c.groups.count) groups, \(c.names.count) names, \(c.warnings.count) problems")
        let lacking = missingDefaults(in: c)
        if !lacking.isEmpty {
            Log.write("config lacks \(lacking.count) default groups or names; list them with: \(Bundle.main.executablePath ?? "ipa-keys") --missing-defaults")
        }
        return c
    }

    private func reload(reason: String) {
        Log.write("reloading config (\(reason))")
        let c = loadConfig()
        controller.setConfig(c)
        settingsModel.load(c)
        paletteModel.palette = Palette(c)
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
            self?.controller.appChanged(app?.bundleIdentifier ?? "", pid: app?.processIdentifier ?? 0)
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            let map = KeyMap.current()
            self?.keymap = map
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
        symbolsItem = NSMenuItem(title: "Symbols", action: #selector(openSymbols), keyEquivalent: "")
        symbolsItem.target = self
        menu.addItem(symbolsItem)
        for (title, action) in [("Settings…", #selector(openSettings)), ("Edit Config", #selector(editConfig)),
                                ("Reload", #selector(reloadConfig))] {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        if App.sourceFolder != nil {
            updateItem = NSMenuItem(title: "Checking for Updates…", action: #selector(updateChosen), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Opening the menu re-checks, at most once a minute.
        if Date().timeIntervalSince(lastUpdateCheck) > 60 { checkForUpdates() }
        refresh()
    }

    private func refresh() {
        enabledItem.state = enabled ? .on : .off
        // The last result stays up while a new check runs.
        updateItem.title = updateState?.label ?? "Checking for Updates…"
        updateItem.isEnabled = updateState.map { $0.canUpdate || $0.isProblem } ?? false
        // Show the symbols chord beside the item (it works from any app).
        let sc = settingsModel.config.symbols
        symbolsItem.keyEquivalent = sc.map { Config.keyNames.values.contains($0.key) || $0.key.count == 1 ? $0.key : "" } ?? ""
        var mask: NSEvent.ModifierFlags = []
        if let m = sc?.modifiers {
            if m.contains(.control) { mask.insert(.control) }
            if m.contains(.option) { mask.insert(.option) }
            if m.contains(.shift) { mask.insert(.shift) }
            if m.contains(.command) { mask.insert(.command) }
        }
        symbolsItem.keyEquivalentModifierMask = mask
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

    @objc private func openSettings() { settingsWindow.show() }

    // MARK: symbols

    @objc private func openSymbols() { showPalette(focus: false) }

    private func showPalette(focus: Bool) {
        paletteModel.status = nil
        if focus {
            palettePanel.makeKeyAndOrderFront(nil)
            paletteModel.focusRequest += 1
        } else {
            palettePanel.orderFrontRegardless()
        }
    }

    /// The symbols chord: open with the cursor in search, or close.
    private func symbolsChord() {
        if palettePanel.isVisible { closePalette() } else { showPalette(focus: true) }
    }

    private func closePalette() {
        let wasKey = palettePanel.isKeyWindow
        palettePanel.orderOut(nil)
        if wasKey { NSWorkspace.shared.frontmostApplication?.activate() }
    }

    /// Types a symbol from the palette into the app in front, as a chord
    /// would (a mark joins the letter before it). Falls back to copying.
    private func insertFromPalette(_ s: PaletteSymbol) {
        let target = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == getpid() ? nil : $0 }
        guard let target else { return copy(s, because: "no other app is in front") }
        guard trusted, tap != nil else { return copy(s, because: "Accessibility is not granted") }
        guard !IsSecureEventInputEnabled() else { return copy(s, because: "secure input is on") }
        let name = target.localizedName ?? target.bundleIdentifier ?? "the app"
        let send = { [weak self] in
            guard let self else { return }
            self.controller.reset()
            Log.write("palette \(s.id) in \(target.bundleIdentifier ?? name): type \(describeText(s.symbol, content: Log.debug))")
            // Checked again when it is posted: if the app in front, focus or
            // secure input changed by then, it is copied instead.
            let batch = Poster.Batch(actions: [.insert(s.symbol)], stamp: self.controller.stamp(for: target.processIdentifier),
                                     note: "palette \(s.id)")
            Poster.send(batch) { [weak self] verdict in
                switch verdict {
                case .go: self?.paletteModel.status = "Typed \(s.glyph) in \(name)"
                case .abandon(let why), .stop(let why): self?.copy(s, because: why)
                }
            }
        }
        guard palettePanel.isKeyWindow else { return send() }
        // The search field has the keyboard: hand it back to the app first.
        target.activate()
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let back = !self.palettePanel.isKeyWindow && NSWorkspace.shared.frontmostApplication == target
            if back {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: send)
            } else if Date().timeIntervalSince(start) > 0.6 {
                timer.invalidate()
                self.copy(s, because: "\(name) did not take the keyboard back")
            }
        }
    }

    private func copy(_ s: PaletteSymbol, because reason: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s.symbol, forType: .string)
        Log.write("palette \(s.id): copied \(describeText(s.symbol, content: Log.debug)) instead of typing: \(reason)")
        paletteModel.status = "Copied \(s.glyph): \(reason)"
    }

    /// Stops reading keys while a shortcut field is recording.
    func pauseKeys(_ paused: Bool) { controller.isPaused = paused }

    /// Sets one line of [settings] in config.txt, leaving the rest of the
    /// file as it is, and reloads. Returns a problem to show, or nil.
    func writeSetting(_ key: String, _ value: String) -> String? {
        let url = App.configURL
        if !FileManager.default.fileExists(atPath: url.path) { _ = loadConfig() }
        let backup = url.appendingPathExtension("bak")
        do {
            // If an editor saves while this runs, the edit is redone on its
            // version; the version replaced is kept in config.txt.bak.
            try ConfigEditor.update(key, to: value, read: { try String(contentsOf: url, encoding: .utf8) }) { new, old in
                try old.write(to: backup, atomically: true, encoding: .utf8)
                try new.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch is ConfigEditor.KeptChanging {
            Log.write("settings: config.txt kept changing; \(key) not saved")
            return "Not saved: config.txt is being edited. Try again."
        } catch {
            Log.write("settings: could not write \(key) to \(url.path): \(error.localizedDescription)")
            return "Could not save: \(error.localizedDescription)"
        }
        Log.write("settings: \(key) = \(value)")
        reload(reason: "Settings")
        return nil
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The source checkout this app was built from, recorded at build time.
    static var sourceFolder: String? { Bundle.main.object(forInfoDictionaryKey: "IPAKeysSource") as? String }
    static var installedCommit: String? { Bundle.main.object(forInfoDictionaryKey: "IPAKeysCommit") as? String }

    /// Fetches and compares in the background; the menu item follows.
    private func checkForUpdates() {
        guard let root = App.sourceFolder, !updateChecking else { return }
        updateChecking = true
        lastUpdateCheck = Date()
        refresh()
        let installed = App.installedCommit
        updateQueue.async { [weak self] in
            let facts = UpdateCheck.facts(source: root, installed: installed)
            let state = UpdateState(facts)
            DispatchQueue.main.async {
                guard let self else { return }
                if state != self.updateState {
                    Log.write("update check: \(state.label) (ahead \(facts.ahead), behind \(facts.behind)\(facts.fetchError.map { ", fetch: \($0)" } ?? ""))")
                }
                self.updateState = state
                self.updateChecking = false
                self.refresh()
            }
        }
    }

    @objc private func updateChosen() {
        guard let state = updateState, let root = App.sourceFolder else { return }
        if state.canUpdate { return update() }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = state.label
        alert.informativeText = state.explanation(source: root)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Check Again")
        if alert.runModal() == .alertSecondButtonReturn { checkForUpdates() }
    }

    /// Runs update.sh in a Terminal window: it shows the result, can ask for
    /// a password, and is not stopped when the install restarts ipa-keys.
    private func update() {
        guard let root = App.sourceFolder else { return }
        let script = URL(fileURLWithPath: root).appendingPathComponent("scripts/update.sh")
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        Log.write("update: opening \(script.path) in Terminal")
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Log.write("update: could not open Terminal: \(error.localizedDescription)") }
        }
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }
}
