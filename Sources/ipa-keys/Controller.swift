import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IPAKeysCore

/// Turns the tap's events into Engine calls and posts what it decides.
/// Called on the tap's thread; the setters come from main, hence the lock.
final class Controller {
    private let lock = NSLock()
    private var config: Config
    private var engine: Engine
    private var keymap: KeyMap
    private var enabled: Bool
    private var frontApp = ""
    private var frontPID: Int32 = 0
    /// Goes up when focus or state changes other than through keys and
    /// clicks the tap holds back; output decided before is then dropped.
    private var generation = 0
    /// Presses we keep from the app, through repeats to key-up.
    private var presses = PressTracker()
    /// After an Option key, which may be a dead key (Option-E then e makes
    /// é in the app), the next character is not what the app shows.
    private var afterOption = false
    /// Run on main when the toggle chord flips Enabled.
    var onToggle: ((Bool) -> Void)?
    /// Run on main when the symbols chord is pressed.
    var onSymbols: (() -> Void)?

    init(config: Config, keymap: KeyMap, enabled: Bool) {
        self.config = config
        engine = Engine(config: config)
        self.keymap = keymap
        self.enabled = enabled
    }

    private var paused = false
    /// While a shortcut is being recorded, keys go straight to the app.
    var isPaused: Bool {
        get { lock.withLock { paused } }
        set { lock.withLock { paused = newValue; engine.reset(); generation += 1 } }
    }

    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue; engine.reset(); generation += 1 } }
    }

    func setConfig(_ c: Config) { lock.withLock { config = c; engine = Engine(config: c) } }
    func setKeyMap(_ k: KeyMap) { lock.withLock { keymap = k } }

    /// Something moved the cursor or changed focus.
    func reset() { lock.withLock { engine.reset(); afterOption = false } }

    /// Focus or state changed (secure input): drop output not yet sent.
    func contextChanged() {
        lock.withLock {
            engine.reset()
            afterOption = false
            generation += 1
        }
    }

    /// The tap was off for a while: key-ups may have been missed.
    func interrupted() {
        lock.withLock {
            engine.reset()
            afterOption = false
            presses.clear()
            generation += 1
        }
    }

    func appChanged(_ bundleID: String, pid: Int32) {
        lock.withLock {
            frontApp = bundleID
            frontPID = pid
            engine.reset()
            afterOption = false
            generation += 1
        }
    }

    /// What Poster checks before each keystroke.
    var outputContext: (generation: Int, app: Int32) { lock.withLock { (generation, frontPID) } }

    /// A stamp for output decided now, for `app` (default: the front app).
    func stamp(for app: Int32? = nil) -> OutputStamp {
        lock.withLock { OutputStamp(generation: generation, app: app ?? frontPID) }
    }

    /// Keys that move the cursor, leave the field, or do something we can't follow.
    private static let resetKeys: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_ForwardDelete, kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Help,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static func modifiers(_ f: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if f.contains(.maskControl) { m.insert(.control) }
        if f.contains(.maskShift) { m.insert(.shift) }
        if f.contains(.maskAlternate) { m.insert(.option) }
        if f.contains(.maskCommand) { m.insert(.command) }
        return m
    }

    private static let holdable: Set<CGEventType> = [
        .keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]

    /// True to keep the event from the app (now; it may be replayed later).
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if decide(type: type, event: event) { return true }
        // Our keystrokes are still being sent: a key or click that passed
        // them now could land between a Backspace and its text, or move the
        // cursor under them. Hold it and send it after, in order.
        if Controller.holdable.contains(type), Poster.mustHold, let copy = event.copy() {
            Poster.replay([copy])
            return true
        }
        return false
    }

    private func decide(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            engine.reset()
            return false
        case .keyUp:
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            return presses.up(code)
        case .keyDown:
            return keyDown(event)
        default:
            return false
        }
    }

    private func keyDown(_ event: CGEvent) -> Bool {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = Controller.modifiers(event.flags)
        let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        // A repeat of a press we kept stays kept, even if the modifiers
        // were let go meanwhile.
        if presses.down(code, isRepeat: repeating) { return true }
        if paused { return false }

        if let t = config.toggle, keymap.code(for: t.key) == code, mods == t.modifiers {
            presses.claim(code)
            if !repeating {
                enabled.toggle()
                engine.reset()
                let on = enabled
                Log.write("toggle chord: \(on ? "enabled" : "disabled")")
                DispatchQueue.main.async { self.onToggle?(on) }
            }
            return true
        }
        if let t = config.symbols, keymap.code(for: t.key) == code, mods == t.modifiers {
            presses.claim(code)
            if !repeating {
                engine.reset()
                DispatchQueue.main.async { self.onSymbols?() }
            }
            return true
        }
        guard enabled else { return false }

        if mods == config.chord, let key = keymap.chars[code], config.groups[key] != nil {
            if IsSecureEventInputEnabled() {
                engine.reset()
                Log.write("chord \(key) ignored: secure input is on")
                return false
            }
            presses.claim(code)
            if repeating { return true }
            let mode: DeleteMode = config.codePointApps.contains(frontApp) ? .codePoints
                : config.terminalApps.contains(frontApp) ? .terminal : .select
            if let d = engine.chord(key: key, mode: mode) { act(d, mode: mode, giveBack: []) }
            return true
        }
        if !mods.isDisjoint(with: [.command, .control]) || Controller.resetKeys.contains(Int(code)) {
            engine.reset()
            afterOption = false
            return false
        }
        if Int(code) == kVK_Delete {
            if mods.contains(.option) { engine.reset() } else { engine.backspace() }
            afterOption = false
            return false
        }
        let text = Controller.characters(event)
        if mods.contains(.option) || afterOption || text.isEmpty
            || text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            engine.reset()
            afterOption = mods.contains(.option)
            return false
        }
        let d = engine.typed(text)
        guard d.swallow else { return false }
        if IsSecureEventInputEnabled() {
            engine.reset()
            Log.write("\(d.note) ignored: secure input is on")
            return false
        }
        presses.claim(code)
        // If the expansion is dropped before it starts, the key goes through.
        var giveBack: [CGEvent] = []
        if let down = event.copy(), let up = event.copy() {
            up.type = .keyUp
            giveBack = [down, up]
        }
        act(d, mode: .codePoints, giveBack: giveBack)
        return true
    }

    private func act(_ d: Decision, mode: DeleteMode, giveBack: [CGEvent]) {
        let app = frontApp.isEmpty ? "unknown app" : frontApp
        let how = mode == .codePoints ? "code point mode" : mode == .terminal ? "terminal mode" : "select mode"
        let detail = Log.debug ? d.detail.map { " " + $0 } ?? "" : ""
        Log.write("\(d.note)\(detail) in \(app) (\(how)): \(describeActions(d.actions, content: Log.debug))")
        guard !d.actions.isEmpty else { return }
        let stamp = OutputStamp(generation: generation, app: frontPID)
        Poster.send(Poster.Batch(actions: d.actions, stamp: stamp, note: d.note, giveBack: giveBack))
    }

    static func characters(_ event: CGEvent) -> String {
        var len = 0
        var buf = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buf.count, actualStringLength: &len, unicodeString: &buf)
        return String(utf16CodeUnits: buf, count: len)
    }
}
