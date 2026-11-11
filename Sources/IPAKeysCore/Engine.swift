import Foundation

/// A keystroke to post, in order.
public enum Action: Equatable, Sendable {
    /// Plain Backspace, n times.
    case backspace(Int)
    /// Control-Backspace, n times: in Cocoa text it removes only the last
    /// mark of a letter (deleteBackwardByDecomposingPreviousCharacter:);
    /// in Chromium it is a plain Backspace, which already does that.
    case decomposingBackspace(Int)
    /// Shift-Left, n times: selects n characters as the app counts them, a
    /// letter with its marks being one.
    case selectBack(Int)
    /// Types this text (replacing any selection).
    case insert(String)
}

/// How to remove a symbol when cycling.
public enum DeleteMode: Sendable {
    /// Select it with Shift-Left and type over it (text views and browsers).
    case select
    /// Backspace once per code point (terminals).
    case backspace
}

public struct Decision: Equatable, Sendable {
    /// Keep the keystroke from the app.
    public var swallow: Bool
    public var actions: [Action]
    /// What happened, for the log.
    public var note: String

    public static let pass = Decision(swallow: false, actions: [], note: "")
}

/// The pure part of ipa-keys: what to send for a chord or a typed key.
/// Not thread-safe; the caller serializes access.
public final class Engine {
    public private(set) var config: Config
    /// What is known to be just before the cursor: keys typed and text
    /// inserted since the last click, arrow key, shortcut or app switch.
    public private(set) var context = ""
    /// The chord pressed last, while nothing else has happened since.
    struct Cycle { var key: String; var index: Int; var inserted: String; var before: String }
    private var cycle: Cycle?
    private let contextLimit: Int

    public init(config: Config) {
        self.config = config
        let longest = config.names.keys.map(\.count).max() ?? 0
        contextLimit = max(64, longest + config.prefix.count + 8)
    }

    /// Forget everything about the text around the cursor.
    public func reset() {
        context = ""
        cycle = nil
    }

    /// The chord plus `key`. Nil when the key has no group: the caller lets
    /// the keystroke through (and it counts as a shortcut, so state resets).
    public func chord(key: String, mode: DeleteMode) -> Decision? {
        guard let group = config.groups[key], !group.isEmpty else {
            reset()
            return nil
        }
        if let c = cycle, c.key == key {
            let next = (c.index + 1) % group.count
            let new = group[next]
            cycle = Cycle(key: key, index: next, inserted: new, before: c.before)
            if next == c.index {
                return Decision(swallow: true, actions: [], note: "\(key) has one symbol")
            }
            setContext(c.before + new)
            let actions = Engine.replace(before: c.before, old: c.inserted, new: new, mode: mode)
            return Decision(swallow: true, actions: actions, note: "cycle \(key)\(next + 1)")
        }
        let before = context
        let new = group[0]
        cycle = Cycle(key: key, index: 0, inserted: new, before: before)
        setContext(before + new)
        return Decision(swallow: true, actions: [.insert(new)], note: "chord \(key)1")
    }

    /// Characters the user typed (no Command or Control held). Expands a
    /// name the moment it is complete, swallowing its last key.
    public func typed(_ s: String) -> Decision {
        cycle = nil
        let candidate = context + s
        if let r = candidate.range(of: config.prefix, options: [.backwards, .literal]) {
            let name = String(candidate[r.upperBound...])
            if let text = config.names[name] {
                let alreadyTyped = config.prefix.count + name.count - s.count
                setContext(String(candidate[..<r.lowerBound]) + text)
                return Decision(swallow: true, actions: [.backspace(alreadyTyped), .insert(text)],
                                note: "name \(config.prefix)\(name)")
            }
        }
        setContext(candidate)
        return .pass
    }

    /// The user pressed Backspace (no modifiers).
    public func backspace() {
        cycle = nil
        // A lone code point goes the same way in every app; a letter with
        // marks may lose one mark or all of it, so stop guessing.
        if let last = context.last, last.unicodeScalars.count == 1 {
            context.removeLast()
        } else {
            context = ""
        }
    }

    private func setContext(_ s: String) {
        context = s.count > contextLimit ? String(s.suffix(contextLimit)) : s
    }

    /// Keystrokes that turn `before + old` into `before + new`, where the
    /// cursor is after `old` and only `before` is known of the text.
    ///
    /// Apps disagree on what Backspace removes after a combining mark: Cocoa
    /// text and WebKit delete the letter with its marks, Chromium deletes
    /// the mark alone. They agree on Shift-Left, which selects the whole
    /// letter, so select it and type the letter back with the new symbol.
    /// That needs the letter; when it is unknown (typed before a click),
    /// fall back to Control-Backspace per code point.
    public static func replace(before: String, old: String, new: String, mode: DeleteMode) -> [Action] {
        let oldScalars = old.unicodeScalars.count
        if mode == .backspace { return [.backspace(oldScalars), .insert(new)] }
        let chars = Array(before + old)
        var i = chars.count, covered = 0
        while covered < oldScalars, i > 0 {
            i -= 1
            covered += chars[i].unicodeScalars.count
        }
        let first = chars[i]
        if i == 0, let u = first.unicodeScalars.first, attaches(u) {
            // The character starts before anything we saw.
            return [.decomposingBackspace(oldScalars), .insert(new)]
        }
        let extra = covered - oldScalars
        let keep = String(String.UnicodeScalarView(first.unicodeScalars.prefix(extra)))
        return [.selectBack(chars.count - i), .insert(keep + new)]
    }
}
