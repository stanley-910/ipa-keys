import AppKit
import IPAKeysCore
import SwiftUI

final class PaletteModel: ObservableObject {
    @Published var palette = Palette(Config())
    @Published var query = ""
    @Published var status: String?
    @Published var hovered: PaletteSymbol?
    /// Bumped to put the cursor in the search field.
    @Published var focusRequest = 0
    var insert: (PaletteSymbol) -> Void = { _ in }

    var matches: Set<String>? { palette.search(query) }

    /// Return in the search field: the first match.
    func insertFirst() {
        guard let m = matches else { return }
        let all = palette.tiles.flatMap(\.symbols) + palette.unchorded
        if let first = all.first(where: { m.contains($0.id) }) { insert(first) }
    }
}

/// Lays children left to right, wrapping to a new row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @FocusState private var searchFocused: Bool

    // The bodies below are kept small, with the types written out: one long
    // expression here stopped an older compiler ("unable to type-check this
    // expression in reasonable time").
    private var tiles: [PaletteTile] {
        guard let matches: Set<String> = model.matches else { return model.palette.tiles }
        var out: [PaletteTile] = []
        for tile in model.palette.tiles {
            let hit: Bool = tile.symbols.contains { (s: PaletteSymbol) -> Bool in matches.contains(s.id) }
            if hit { out.append(tile) }
        }
        return out
    }

    private var unchorded: [PaletteSymbol] {
        guard let matches: Set<String> = model.matches else { return model.palette.unchorded }
        return model.palette.unchorded.filter { (s: PaletteSymbol) -> Bool in matches.contains(s.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            ScrollView { grid }
            Divider()
            InfoBar(symbol: model.hovered, palette: model.palette)
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.focusRequest) { _, _ in searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search by name, key or symbol", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit { model.insertFirst() }
            if let status = model.status {
                Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 16) {
            FlowLayout(spacing: 6) {
                ForEach(tiles) { tile in
                    TileView(tile: tile, matches: model.matches, model: model)
                }
            }
            if !unchorded.isEmpty {
                unchordedSection
            }
            if tiles.isEmpty && unchorded.isEmpty {
                Text("No match").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .padding(10)
    }

    private var unchordedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No chord, type the name").font(.headline)
            FlowLayout(spacing: 2) {
                ForEach(unchorded) { s in
                    SymbolCell(symbol: s, highlighted: false, dimmed: false, model: model)
                }
            }
            .padding(4)
            .background(TileBackground())
        }
    }
}

struct TileBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor)))
    }
}

struct TileView: View {
    let tile: PaletteTile
    let matches: Set<String>?
    @ObservedObject var model: PaletteModel

    private var badgeHelp: String {
        var text: String = model.palette.chord.words
        text += "+"
        text += tile.label
        if let note: String = tile.note {
            text += ": "
            text += note
        }
        return text
    }

    private func matched(_ s: PaletteSymbol) -> Bool {
        guard let matches else { return false }
        return matches.contains(s.id)
    }

    private func dimmed(_ s: PaletteSymbol) -> Bool {
        guard let matches else { return false }
        return !matches.contains(s.id)
    }

    var body: some View {
        HStack(spacing: 2) {
            KeyBadge(label: tile.label, help: badgeHelp)
            ForEach(tile.symbols) { s in
                SymbolCell(symbol: s, highlighted: matched(s), dimmed: dimmed(s), model: model)
            }
        }
        .padding(4)
        .background(TileBackground())
    }
}

/// The key to hold the chord with.
struct KeyBadge: View {
    let label: String
    let help: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        let tint: Color = Color.accentColor
        return Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 2)
            .background(shape.fill(tint.opacity(0.18)))
            .overlay(shape.stroke(tint.opacity(0.5)))
            .padding(.trailing, 4)
            .help(help)
    }
}

struct SymbolCell: View {
    let symbol: PaletteSymbol
    let highlighted: Bool
    let dimmed: Bool
    @ObservedObject var model: PaletteModel
    // Hover lives in the model: @State needs a SwiftUI macro plugin that
    // the Command Line Tools toolchain lacks.
    private var hovering: Bool { model.hovered == symbol }

    var body: some View {
        Button { model.insert(symbol) } label: {
            Text(symbol.glyph)
                .font(.system(size: 21))
                .frame(minWidth: 30, minHeight: 34)
                .padding(.horizontal, 1)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 6).fill(fill))
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .help(tooltip)
        .onHover { (inside: Bool) in hover(inside) }
    }

    private var opacity: Double { dimmed ? 0.3 : 1.0 }
    private var tooltip: String { model.palette.tooltip(symbol) }

    private func hover(_ inside: Bool) {
        if inside {
            model.hovered = symbol
        } else if model.hovered == symbol {
            model.hovered = nil
        }
    }

    private var fill: Color {
        if hovering { return Color.accentColor.opacity(0.28) }
        if highlighted { return Color.accentColor.opacity(0.14) }
        return .clear
    }
}

/// The hovered symbol, large, with its name, chord and typed names.
struct InfoBar: View {
    let symbol: PaletteSymbol?
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            if let s = symbol {
                Text(s.glyph).font(.system(size: 30)).frame(minWidth: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.unicodeName).font(.callout)
                    HStack(spacing: 12) {
                        if let c = palette.chordText(s) { Text(c).fontWeight(.medium) }
                        Text(typedNames(s))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
    }

    private func typedNames(_ s: PaletteSymbol) -> String {
        var parts: [String] = []
        for name in s.names { parts.append(palette.prefix + name) }
        return parts.joined(separator: "  ")
    }

    private var hint: String {
        let chord: String = palette.chord.words
        return "Click a symbol to type it. Hold " + chord + " and press the key; press again for the next one."
    }
}

/// Takes the first click even when the panel is not key, so one click types.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A floating panel that does not make ipa-keys the active app, so the app
/// being typed into keeps the keyboard.
final class PalettePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    init(model: PaletteModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                   styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered, defer: true)
        title = "Symbols"
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        allowsToolTipsWhenApplicationIsInactive = true
        isReleasedWhenClosed = false
        contentView = FirstClickHostingView(rootView: PaletteView(model: model))
        center()
        setFrameAutosaveName("Symbols")
    }
}
