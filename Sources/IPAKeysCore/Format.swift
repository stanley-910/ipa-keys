/// Spelling modifiers and shortcuts for the config file and for people.
extension Modifiers {
    /// Apple's order: Control, Option, Shift, Command.
    static let ordered: [(Modifiers, String, String, String)] = [
        (.control, "control", "⌃", "Ctrl"), (.option, "option", "⌥", "Option"),
        (.shift, "shift", "⇧", "Shift"), (.command, "command", "⌘", "Cmd"),
    ]

    /// "control+shift", as the config file writes it.
    public var configString: String {
        Modifiers.ordered.filter { contains($0.0) }.map(\.1).joined(separator: "+")
    }

    /// "⌃⇧", as menus show it.
    public var glyphs: String {
        Modifiers.ordered.filter { contains($0.0) }.map(\.2).joined()
    }

    /// "Ctrl+Shift", as the website writes it.
    public var words: String {
        Modifiers.ordered.filter { contains($0.0) }.map(\.3).joined(separator: "+")
    }
}

extension Config {
    /// How a key is written in the file: "e", "comma", "escape".
    public static func keyConfigName(_ key: String) -> String {
        keyNames.first(where: { $0.value == key })?.key ?? key
    }

    /// How a key is shown on a keycap: "E", ",", "Esc".
    public static func keyLabel(_ key: String) -> String {
        switch key {
        case "escape": return "Esc"
        case "space": return "Space"
        case "tab": return "Tab"
        case "return": return "Return"
        default: return key.uppercased()
        }
    }

    /// A chord must hold Control, Option or Command, or it would take over
    /// ordinary typing (Shift+E is a capital E).
    public static func chordProblem(_ m: Modifiers) -> String? {
        m.isDisjoint(with: [.control, .option, .command]) ? "Needs Control, Option or Command" : nil
    }

    public static func prefixProblem(_ p: String) -> String? {
        if p.isEmpty { return "Can't be empty" }
        if p.contains(where: \.isWhitespace) { return "No spaces" }
        if p.contains("=") || p.hasPrefix("#") { return "Can't use = or start with #" }
        return nil
    }

    /// The shortcut settings, by their name in the file.
    public var shortcuts: [(String, Shortcut?)] { [("toggle", toggle)] }

    /// Problems with a shortcut for `setting`: it needs a real modifier,
    /// and must not take a group's chord or another shortcut.
    public func shortcutProblem(_ s: Shortcut, for setting: String) -> String? {
        if let p = Config.chordProblem(s.modifiers) { return p }
        if s.modifiers == chord, groups[s.key] != nil {
            return "\(s.display) is the chord for group \(Config.keyLabel(s.key))"
        }
        for (name, other) in shortcuts where name != setting && other == s {
            return "Already used for \(name)"
        }
        return nil
    }
}

extension Shortcut {
    public init(_ modifiers: Modifiers, _ key: String) {
        self.init(modifiers: modifiers, key: key)
    }

    /// "control+shift+escape", as the config file writes it.
    public var configString: String { modifiers.configString + "+" + Config.keyConfigName(key) }

    /// "⌃⇧Esc".
    public var display: String { modifiers.glyphs + Config.keyLabel(key) }
}

/// Changes settings in the text of a config file, keeping everything else
/// (comments, blank lines, order) exactly as it was.
public enum ConfigEditor {
    /// Sets `key = value` in [settings]: replaces the existing line, or adds
    /// one after the section's last setting, or adds the section at the top.
    public static func set(_ key: String, to value: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let newLine = value.isEmpty ? "\(key) =" : "\(key) = \(value)"
        var inSettings = false
        var header: Int?
        var lastSetting: Int?
        var replaced = false
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inSettings = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased() == "settings"
                if inSettings, header == nil { header = i }
                continue
            }
            guard inSettings, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            lastSetting = i
            if line[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == key {
                let indent = raw.prefix(while: { $0 == " " || $0 == "\t" })
                let cr = raw.hasSuffix("\r") ? "\r" : ""
                lines[i] = indent + newLine + cr
                replaced = true
            }
        }
        if replaced { return lines.joined(separator: "\n") }
        if let at = lastSetting ?? header {
            lines.insert(newLine, at: at + 1)
        } else if let first = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) {
            lines.insert(contentsOf: ["[settings]", newLine, ""], at: first)
        } else {
            if lines.last == "" { lines.removeLast() }
            lines.append(contentsOf: ["", "[settings]", newLine, ""])
        }
        return lines.joined(separator: "\n")
    }
}
