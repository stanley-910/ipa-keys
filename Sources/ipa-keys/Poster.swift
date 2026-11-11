import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IPAKeysCore

/// Posts ipa-keys's own keystrokes, one batch at a time, off the tap's
/// thread. While anything is pending, the tap holds the user's keys and
/// clicks and hands them to `replay`, so they land after it, in order.
enum Poster {
    /// Stamped on our events (`eventSourceUserData`) so the tap lets them by.
    static let marker: Int64 = 0x6970_616B  // "ipak"
    private static let queue = DispatchQueue(label: "ipa-keys.post", qos: .userInteractive)
    /// A private source: the Control and Shift the user is still holding
    /// must not leak into what we type.
    private static let source = CGEventSource(stateID: .privateState)
    /// Between events, so apps that read keys slowly keep them in order.
    private static let gap: useconds_t = 1500
    private static let lock = NSLock()
    private static var sequencer = OutputSequencer()
    /// The current context generation and front app's pid, asked before
    /// every keystroke. Set at launch.
    static var context: () -> (generation: Int, app: Int32) = { (0, 0) }

    /// Input arriving now must wait behind pending output.
    static var mustHold: Bool { lock.withLock { sequencer.mustHold } }

    struct Batch {
        var actions: [Action]
        var stamp: OutputStamp
        var note: String
        /// The user's own events this batch kept from the app (the last key
        /// of a name): posted instead if the batch is abandoned.
        var giveBack: [CGEvent] = []
    }

    /// Sends a batch, checking before every keystroke that focus, the
    /// front app and secure input are as they were when it was decided.
    static func send(_ b: Batch, done: ((OutputVerdict) -> Void)? = nil) {
        lock.withLock { sequencer.enqueue() }
        queue.async {
            var started = false
            var verdict = OutputVerdict.go
            var failed = 0
            func check() -> Bool {
                let now = context()
                verdict = checkOutput(b.stamp, generation: now.generation, frontApp: now.app,
                                      secureInput: IsSecureEventInputEnabled(), started: started)
                return verdict == .go
            }
            run: for action in b.actions {
                switch action {
                case .backspace(let n):
                    for _ in 0..<max(0, n) {
                        guard check() else { break run }
                        if !key(kVK_Delete, flags: []) { failed += 1 }
                        started = true
                    }
                case .selectBack(let n):
                    for _ in 0..<max(0, n) {
                        guard check() else { break run }
                        if !key(kVK_LeftArrow, flags: [.maskShift, .maskNumericPad, .maskSecondaryFn]) { failed += 1 }
                        started = true
                    }
                case .insert(let text):
                    for chunk in keyEventChunks(text) {
                        guard check() else { break run }
                        if !type(chunk) { failed += 1 }
                        started = true
                    }
                }
            }
            switch verdict {
            case .go: break
            case .abandon(let why):
                Log.write("\(b.note): not sent, \(why)\(b.giveBack.isEmpty ? "" : "; the key it kept was given back")")
                post(b.giveBack)
            case .stop(let why):
                Log.write("\(b.note): stopped partway, \(why)")
            }
            if failed > 0 { Log.write("\(b.note): \(failed) keystrokes could not be made") }
            lock.withLock { sequencer.finish() }
            if let done { DispatchQueue.main.async { done(verdict) } }
        }
    }

    /// The user's own events, held while output was pending: posted after
    /// it, in the order they arrived, marked so the tap lets them by.
    static func replay(_ events: [CGEvent]) {
        lock.withLock { sequencer.enqueue() }
        queue.async {
            post(events)
            lock.withLock { sequencer.finish() }
        }
    }

    private static func post(_ events: [CGEvent]) {
        for e in events {
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cgSessionEventTap)
            usleep(gap)
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
