/// One symbol in the palette.
public struct PaletteSymbol: Identifiable, Hashable, Sendable {
    /// "e2" for the second symbol on E; "name:schwa" for one with no chord.
    public let id: String
    public let symbol: String
    /// The group key, nil for a symbol with only names.
    public let key: String?
    /// Presses of the chord to reach it (1 for the first).
    public let presses: Int
    /// Typed names, hand-written ones first, without the prefix.
    public let names: [String]

    /// What it looks like on its own: a mark on a dotted circle.
    public var glyph: String { dotted(symbol) }

    /// The Unicode names: "latin small letter schwa", "combining breve".
    public var unicodeName: String {
        symbol.unicodeScalars.map { $0.properties.name?.lowercased() ?? String(format: "u+%04x", $0.value) }
            .joined(separator: " + ")
    }
}

/// One chord key and its symbols, in cycling order.
public struct PaletteTile: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    /// The keycap: "E", ",".
    public let label: String
    /// The comment above the group in the config, if any.
    public let note: String?
    public let symbols: [PaletteSymbol]
}

/// Everything the symbol palette shows, built from the live config.
public struct Palette: Sendable {
    public let tiles: [PaletteTile]
    /// Symbols that have names but no chord.
    public let unchorded: [PaletteSymbol]
    public let chord: Modifiers
    public let prefix: String

    public init(_ c: Config) {
        chord = c.chord
        prefix = c.prefix
        var bySymbol: [String: [String]] = [:]
        let derived = Set(c.groupOrder.flatMap { k in c.groups[k, default: []].indices.map { k + String($0 + 1) } })
        for name in c.nameOrder { if let t = c.names[name] { bySymbol[t, default: []].append(name) } }
        for name in c.names.keys.sorted() where derived.contains(name) && !c.nameOrder.contains(name) {
            bySymbol[c.names[name]!, default: []].append(name)
        }
        tiles = c.groupOrder.map { key in
            let symbols = c.groups[key, default: []].enumerated().map { i, s in
                PaletteSymbol(id: key + String(i + 1), symbol: s, key: key, presses: i + 1, names: bySymbol[s] ?? [])
            }
            return PaletteTile(key: key, label: Config.keyLabel(key), note: c.groupNotes[key], symbols: symbols)
        }
        let chorded = Set(c.groups.values.joined())
        var seen = Set<String>()
        unchorded = c.nameOrder.compactMap { name in
            guard let s = c.names[name], !chorded.contains(s), seen.insert(s).inserted else { return nil }
            return PaletteSymbol(id: "name:" + name, symbol: s, key: nil, presses: 0, names: bySymbol[s] ?? [])
        }
    }

    /// "Ctrl+Shift+E ×2", or nil for a symbol with no chord.
    public func chordText(_ s: PaletteSymbol) -> String? {
        guard let key = s.key else { return nil }
        let base = chord.words + "+" + Config.keyLabel(key)
        return s.presses > 1 ? "\(base) ×\(s.presses)" : base
    }

    /// The hover text: what it is, how to chord it, how to type it.
    public func tooltip(_ s: PaletteSymbol) -> String {
        var lines = [s.unicodeName]
        if let c = chordText(s) { lines.append(c) }
        if !s.names.isEmpty { lines.append(s.names.map { prefix + $0 }.joined(separator: "  ")) }
        return lines.joined(separator: "\n")
    }

    /// The ids of symbols matching a search, or nil when the query is
    /// empty (show everything). Matches the symbol itself, its key, its
    /// names (from the start; anywhere from 3 letters) and, from 3 letters,
    /// words of its Unicode name. A leading prefix (;schwa) is ignored.
    public func search(_ query: String) -> Set<String>? {
        var q = query.trimmingCharacters(in: .whitespaces)
        if q.hasPrefix(prefix) { q = String(q.dropFirst(prefix.count)) }
        q = Config.stripDottedCircles(q).replacingOccurrences(of: "\u{25CC}", with: "")
        guard !q.isEmpty else { return query.trimmingCharacters(in: .whitespaces).isEmpty ? nil : [] }
        let lower = q.lowercased()
        let keyQuery = Config.keyChar(lower)
        var out = Set<String>()
        func matches(_ s: PaletteSymbol) -> Bool {
            if s.symbol == q || (q.count > 1 || !q.allSatisfy(\.isASCII)) && s.symbol.contains(q) { return true }
            if lower.count == 1 { return s.names.contains(lower) }
            if s.names.contains(where: { $0.lowercased().hasPrefix(lower) }) { return true }
            guard lower.count >= 3 else { return false }
            if s.names.contains(where: { $0.lowercased().contains(lower) }) { return true }
            return s.unicodeName.split(whereSeparator: { $0 == " " || $0 == "-" }).contains { $0.hasPrefix(lower) }
        }
        for tile in tiles {
            let keyHit = tile.key == keyQuery
            for s in tile.symbols where keyHit || matches(s) { out.insert(s.id) }
        }
        for s in unchorded where matches(s) { out.insert(s.id) }
        return out
    }
}
