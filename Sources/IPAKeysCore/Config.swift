import Foundation

/// Modifier keys, independent of CoreGraphics so the parser stays testable.
public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = Modifiers(rawValue: 1)
    public static let shift = Modifiers(rawValue: 2)
    public static let option = Modifiers(rawValue: 4)
    public static let command = Modifiers(rawValue: 8)

    static let names: [String: Modifiers] = [
        "control": .control, "ctrl": .control, "shift": .shift,
        "option": .option, "alt": .option, "command": .command, "cmd": .command,
    ]
}

/// Modifiers plus one key, e.g. control+shift+escape.
public struct Shortcut: Equatable, Sendable {
    public var modifiers: Modifiers
    /// A character key ("e", ",") or a named key ("escape", "f5").
    public var key: String
}

public struct Config: Sendable {
    public var chord: Modifiers = [.control, .shift]
    public var prefix = ";"
    public var toggle: Shortcut?
    /// Opens the symbol palette. Control+Shift+/ unless the file says otherwise.
    public var symbols: Shortcut? = Shortcut(modifiers: [.control, .shift], key: "/")
    /// Bundle ids of terminals: Shift-Left doesn't select there.
    public var terminalApps: Set<String> = []
    /// Bundle ids where Backspace is known to remove one code point, so
    /// cycling may delete marks with it. Opt-in.
    public var codePointApps: Set<String> = []
    /// Group key (one character, e.g. "e" or ",") to its symbols, in order.
    public var groups: [String: [String]] = [:]
    /// Group keys in file order.
    public var groupOrder: [String] = []
    /// The comment line just above a group, if any ("clicks (k for click)").
    public var groupNotes: [String: String] = [:]
    /// Name (without prefix) to text, including the derived ones like "e1".
    public var names: [String: String] = [:]
    /// Names written in [names], in file order.
    public var nameOrder: [String] = []
    /// Write typed names and inserted text to the log (off: lengths only).
    public var debugLog = false
    /// Problems found while reading, one line each, for the log.
    public var warnings: [String] = []

    public init() {}

    /// Keys that are written by name in the file because the character
    /// itself would be awkward there.
    public static let keyNames: [String: String] = [
        "grave": "`", "comma": ",", "period": ".", "slash": "/", "semicolon": ";",
        "quote": "'", "minus": "-", "equals": "=", "lbracket": "[", "rbracket": "]",
        "backslash": "\\",
    ]

    /// Named keys that are not characters, accepted only in `toggle`.
    public static let specialKeys: Set<String> = [
        "escape", "space", "tab", "return",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    ]

    /// Every character a group key may be: what the main keys of a US
    /// keyboard type without modifiers.
    static let keyChars = Set("abcdefghijklmnopqrstuvwxyz0123456789`,./;'-=[]\\")

    public static func parse(_ text: String) -> Config {
        var c = Config()
        var section = ""
        var explicitNames: [(String, String, Int)] = []
        var comment: String?
        for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
            let lineNo = n + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { comment = nil; continue }
            if line.hasPrefix("#") {
                comment = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                continue
            }
            defer { comment = nil }
            if line.hasPrefix("[") && line.hasSuffix("]") && line.count > 2 {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
                if !["settings", "groups", "names"].contains(section) {
                    c.warnings.append("line \(lineNo): unknown section [\(section)]")
                }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else {
                c.warnings.append("line \(lineNo): no '=' in \"\(line)\"")
                continue
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch section {
            case "settings": c.setting(key.lowercased(), value, line: lineNo)
            case "groups":
                c.group(key, value, line: lineNo)
                if let k = Config.keyChar(key), let comment, !comment.isEmpty { c.groupNotes[k] = comment }
            case "names":
                if key.isEmpty || key.contains(where: \.isWhitespace) {
                    c.warnings.append("line \(lineNo): a name must be one word: \"\(key)\"")
                } else if value.isEmpty {
                    c.warnings.append("line \(lineNo): \(key) has no text")
                } else {
                    explicitNames.append((key, stripDottedCircles(value), lineNo))
                }
            default:
                c.warnings.append("line \(lineNo): outside [settings], [groups] or [names]")
            }
        }
        // Derived names first, so a hand-written one of the same name wins.
        for key in c.groupOrder {
            for (i, symbol) in c.groups[key, default: []].enumerated() {
                c.names[key + String(i + 1)] = symbol
            }
        }
        for (name, text, lineNo) in explicitNames {
            if let old = c.names[name], old != text {
                c.warnings.append("line \(lineNo): \(name) is already a name (from [groups] or earlier); this one wins")
            }
            c.names[name] = text
            if !c.nameOrder.contains(name) { c.nameOrder.append(name) }
        }
        c.checkNames()
        for (setting, s) in [("toggle", c.toggle), ("symbols", c.symbols)] {
            if let s, s.modifiers == c.chord, c.groups[s.key] != nil {
                c.warnings.append("\(setting) uses the chord with \(s.key), so that group cannot be typed")
            }
        }
        return c
    }

    private mutating func setting(_ key: String, _ value: String, line: Int) {
        switch key {
        case "chord":
            if let m = Config.parseModifiers(value), !m.isEmpty {
                if let p = Config.chordProblem(m) {
                    // Shift alone would turn capital letters into symbols.
                    warnings.append("line \(line): chord \"\(value)\": \(p); using control+shift")
                } else {
                    chord = m
                }
            } else {
                warnings.append("line \(line): chord \"\(value)\" is not modifiers like control+shift; using control+shift")
            }
        case "prefix":
            if value.isEmpty || value.contains(where: \.isWhitespace) {
                warnings.append("line \(line): prefix must be non-empty with no spaces; using ;")
            } else {
                prefix = value
            }
        case "toggle":
            if value.isEmpty { toggle = nil; return }
            if let s = Config.parseShortcut(value) {
                if let p = Config.chordProblem(s.modifiers) {
                    warnings.append("line \(line): toggle \"\(value)\": \(p); no toggle chord")
                } else {
                    toggle = s
                }
            } else {
                warnings.append("line \(line): toggle \"\(value)\" is not like control+shift+escape; no toggle chord")
            }
        case "symbols":
            if value.isEmpty { symbols = nil; return }
            if let s = Config.parseShortcut(value) {
                if let p = Config.chordProblem(s.modifiers) {
                    warnings.append("line \(line): symbols \"\(value)\": \(p); using control+shift+slash")
                } else {
                    symbols = s
                }
            } else {
                warnings.append("line \(line): symbols \"\(value)\" is not like control+shift+slash; using control+shift+slash")
            }
        case "terminal_apps", "backspace_apps":  // backspace_apps: the old name
            terminalApps = Set(value.split(whereSeparator: \.isWhitespace).map(String.init))
        case "debug_log":
            switch value.lowercased() {
            case "on", "yes", "true": debugLog = true
            case "off", "no", "false", "": debugLog = false
            default: warnings.append("line \(line): debug_log is on or off, not \"\(value)\"")
            }
        case "code_point_apps":
            codePointApps = Set(value.split(whereSeparator: \.isWhitespace).map(String.init))
        default:
            warnings.append("line \(line): unknown setting \(key)")
        }
    }

    private mutating func group(_ rawKey: String, _ value: String, line: Int) {
        guard let key = Config.keyChar(rawKey) else {
            warnings.append("line \(line): \"\(rawKey)\" is not a key; use a letter, a digit or one of "
                + Config.keyNames.keys.sorted().joined(separator: " "))
            return
        }
        let symbols = value.split(whereSeparator: \.isWhitespace).map { Config.stripDottedCircles(String($0)) }
        if symbols.isEmpty {
            warnings.append("line \(line): group \(rawKey) has no symbols")
            return
        }
        if groups[key] != nil {
            warnings.append("line \(line): group \(rawKey) appears twice; this one wins")
        } else {
            groupOrder.append(key)
        }
        groups[key] = symbols
    }

    /// A name that is the start of another fires first, so the longer one
    /// can never be typed. Also flags names that contain the prefix.
    private mutating func checkNames() {
        let sorted = names.keys.sorted()
        for (i, a) in sorted.enumerated() {
            var j = i + 1
            while j < sorted.count, sorted[j].hasPrefix(a) {
                warnings.append("name \(a) is the start of \(sorted[j]), so \(prefix)\(sorted[j]) can never be typed")
                j += 1
            }
            if a.contains(prefix) {
                warnings.append("name \(a) contains the prefix \(prefix) and may not expand")
            }
        }
    }

    /// The character a group key stands for: "e" → "e", "comma" → ",".
    public static func keyChar(_ raw: String) -> String? {
        let k = raw.lowercased()
        if let named = keyNames[k] { return named }
        if k.count == 1, let ch = k.first, keyChars.contains(ch) { return k }
        return nil
    }

    static func parseModifiers(_ spec: String) -> Modifiers? {
        var m: Modifiers = []
        for part in spec.lowercased().split(separator: "+") {
            guard let one = Modifiers.names[part.trimmingCharacters(in: .whitespaces)] else { return nil }
            m.insert(one)
        }
        return m
    }

    static func parseShortcut(_ spec: String) -> Shortcut? {
        let parts = spec.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, parts.count >= 2,
              let mods = parseModifiers(parts.dropLast().joined(separator: "+")), !mods.isEmpty
        else { return nil }
        if specialKeys.contains(last) { return Shortcut(modifiers: mods, key: last) }
        guard let key = keyChar(last) else { return nil }
        return Shortcut(modifiers: mods, key: key)
    }

    /// Drops each ◌ (U+25CC) that sits in front of a mark, which is only
    /// there to make the mark visible in the file.
    public static func stripDottedCircles(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        let scalars = Array(s.unicodeScalars)
        for (i, u) in scalars.enumerated() {
            if u == "\u{25CC}", i + 1 < scalars.count, attaches(scalars[i + 1]) { continue }
            out.append(u)
        }
        return String(out)
    }
}

/// True when the scalar joins the character before it (a combining mark,
/// a joiner), by the same grapheme rules text views use for the cursor.
public func attaches(_ u: Unicode.Scalar) -> Bool {
    var s = "a"
    s.unicodeScalars.append(u)
    return s.count == 1
}
