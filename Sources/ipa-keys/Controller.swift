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
    /// Key codes whose key-down we kept from the app: keep the key-up too.
    private var swallowedUps: Set<CGKeyCode> = []
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
        set { lock.withLock { paused = newValue; engine.reset() } }
    }

    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue; engine.reset() } }
    }

    func setConfig(_ c: Config) { lock.withLock { config = c; engine = Engine(config: c) } }
    func setKeyMap(_ k: KeyMap) { lock.withLock { keymap = k } }

    /// Something moved the cursor or changed focus.
    func reset() { lock.withLock { engine.reset(); afterOption = false } }

    func appChanged(_ bundleID: String) {
        lock.withLock {
            frontApp = bundleID
            engine.reset()
            afterOption = false
        }
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

    /// True to keep the event from the app.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            engine.reset()
            return false
        case .keyUp:
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            return swallowedUps.remove(code) != nil
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
        if paused { return false }

        if let t = config.toggle, keymap.code(for: t.key) == code, mods == t.modifiers {
            swallowedUps.insert(code)
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
            swallowedUps.insert(code)
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
            swallowedUps.insert(code)
            if repeating { return true }
            let mode: DeleteMode = config.backspaceApps.contains(frontApp) ? .backspace : .select
            if let d = engine.chord(key: key, mode: mode) { act(d, mode: mode) }
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
        swallowedUps.insert(code)
        act(d, mode: .backspace)
        return true
    }

    private func act(_ d: Decision, mode: DeleteMode) {
        let app = frontApp.isEmpty ? "unknown app" : frontApp
        let how = mode == .backspace ? "backspace mode" : "select mode"
        Log.write("\(d.note) in \(app) (\(how)): \(Controller.describe(d.actions))")
        if !d.actions.isEmpty { Poster.post(d.actions, note: d.note) }
    }

    static func describe(_ actions: [Action]) -> String {
        if actions.isEmpty { return "nothing to send" }
        return actions.map { a -> String in
            switch a {
            case .backspace(let n): return "Backspace x\(n)"
            case .decomposingBackspace(let n): return "Control-Backspace x\(n)"
            case .selectBack(let n): return "Shift-Left x\(n)"
            case .insert(let s): return "type \(Log.show(s))"
            }
        }.joined(separator: ", ")
    }

    static func characters(_ event: CGEvent) -> String {
        var len = 0
        var buf = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buf.count, actualStringLength: &len, unicodeString: &buf)
        return String(utf16CodeUnits: buf, count: len)
    }
}
