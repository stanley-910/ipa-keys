import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IPAKeysCore

/// Posts the keystrokes for an Action list, off the tap's thread.
enum Poster {
    /// Stamped on our events (`eventSourceUserData`) so the tap lets them by.
    static let marker: Int64 = 0x6970_616B  // "ipak"
    private static let queue = DispatchQueue(label: "ipa-keys.post", qos: .userInteractive)
    /// A private source: the Control and Shift the user is still holding
    /// must not leak into what we type.
    private static let source = CGEventSource(stateID: .privateState)
    /// Between events, so apps that read keys slowly keep them in order.
    private static let gap: useconds_t = 1500

    static func post(_ actions: [Action], note: String) {
        queue.async {
            var sent = 0
            var failed = 0
            for action in actions {
                switch action {
                case .backspace(let n):
                    for _ in 0..<max(0, n) { key(kVK_Delete, flags: []) ? (sent += 1) : (failed += 1) }
                case .decomposingBackspace(let n):
                    for _ in 0..<max(0, n) { key(kVK_Delete, flags: .maskControl) ? (sent += 1) : (failed += 1) }
                case .selectBack(let n):
                    for _ in 0..<max(0, n) {
                        key(kVK_LeftArrow, flags: [.maskShift, .maskNumericPad, .maskSecondaryFn]) ? (sent += 1) : (failed += 1)
                    }
                case .insert(let text):
                    for chunk in keyEventChunks(text) { type(chunk) ? (sent += 1) : (failed += 1) }
                }
            }
            if failed > 0 { Log.write("\(note): \(failed) of \(sent + failed) keystrokes could not be made") }
        }
    }

    private static func key(_ code: Int, flags: CGEventFlags) -> Bool {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: false)
        else { return false }
        send(down, up, flags: flags)
        return true
    }

    private static func type(_ text: String) -> Bool {
        let units = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return false }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        send(down, up, flags: [])
        return true
    }

    private static func send(_ down: CGEvent, _ up: CGEvent, flags: CGEventFlags) {
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
        }
        down.post(tap: .cgSessionEventTap)
        usleep(gap)
        up.post(tap: .cgSessionEventTap)
        usleep(gap)
    }
}
