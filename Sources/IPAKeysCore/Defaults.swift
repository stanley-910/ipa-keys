/// What the built-in default config has that a user's config lacks, as
/// config text that can be pasted into the file: a section header on its
/// own line, valid `key = value` lines, notes as `#` comments. Empty when
/// nothing is missing. Derived names (e1) follow the groups, so they are
/// not listed; a symbol the user moved to another key or renamed counts.
public func missingDefaults(in user: Config, defaults: Config = Config.parse(defaultConfigText)) -> [String] {
    var groups: [String] = []
    let userSymbols = Set(user.groups.values.joined())
    for key in defaults.groupOrder {
        let want = defaults.groups[key] ?? []
        let name = Config.keyConfigName(key)
        guard let have = user.groups[key] else {
            if want.contains(where: { !userSymbols.contains($0) }) { groups.append("\(name) = \(visible(want))") }
            continue
        }
        let lacking = want.filter { !have.contains($0) && !userSymbols.contains($0) }
        if !lacking.isEmpty {
            groups.append("# replace your line \(name) = \(visible(have)) with:")
            groups.append("\(name) = \(visible(have + lacking))")
        }
    }
    var names: [String] = []
    let derived = Set(defaults.groupOrder.flatMap { k in defaults.groups[k, default: []].indices.map { k + String($0 + 1) } })
    for name in defaults.nameOrder where !derived.contains(name) {
        guard let text = defaults.names[name] else { continue }
        if user.names[name] == nil && !user.names.values.contains(text) {
            names.append("\(name) = \(visible([text]))")
        }
    }
    var out: [String] = []
    if !groups.isEmpty { out += ["[groups]"] + groups }
    if !names.isEmpty { out += ["[names]"] + names }
    return out
}

/// Symbols separated by spaces, each combining mark on a dotted circle.
public func visible(_ symbols: [String]) -> String {
    symbols.map(dotted).joined(separator: " ")
}

/// A lone mark drawn on ◌ so it can be seen.
public func dotted(_ s: String) -> String {
    if let u = s.unicodeScalars.first, attaches(u) { return "\u{25CC}" + s }
    return s
}
