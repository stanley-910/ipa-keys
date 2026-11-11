/// What the built-in default config has that a user's config lacks: whole
/// groups, symbols missing from a group, and hand-written names. Lines are
/// ready to paste under the section they name. Derived names (e1) follow
/// the groups, so they are not listed.
public func missingDefaults(in user: Config, defaults: Config = Config.parse(defaultConfigText)) -> [String] {
    var out: [String] = []
    let userSymbols = Set(user.groups.values.joined())
    for key in defaults.groupOrder {
        let want = defaults.groups[key] ?? []
        let name = Config.keyNames.first(where: { $0.value == key })?.key ?? key
        guard let have = user.groups[key] else {
            // A group may have moved to another key; only report symbols with no chord at all.
            let lacking = want.filter { !userSymbols.contains($0) }
            if !lacking.isEmpty { out.append("[groups] \(name) = \(visible(want))") }
            continue
        }
        let lacking = want.filter { !have.contains($0) && !userSymbols.contains($0) }
        if !lacking.isEmpty {
            out.append("[groups] \(name) = \(visible(have + lacking))   (yours: \(visible(have)))")
        }
    }
    let derived = Set(defaults.groupOrder.flatMap { k in defaults.groups[k, default: []].indices.map { k + String($0 + 1) } })
    for (name, text) in defaults.names.sorted(by: { $0.key < $1.key }) where !derived.contains(name) {
        if user.names[name] == nil && !user.names.values.contains(text) {
            out.append("[names] \(name) = \(visible([text]))")
        }
    }
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
