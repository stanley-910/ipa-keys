import Testing
@testable import IPAKeysCore

struct PaletteTests {
    static let palette = Palette(ConfigTests.defaults)

    func symbol(_ id: String) -> PaletteSymbol {
        (Self.palette.tiles.flatMap(\.symbols) + Self.palette.unchorded).first { $0.id == id }!
    }

    @Test func tilesFollowTheConfig() {
        let p = Self.palette
        #expect(p.tiles.map(\.key) == ConfigTests.defaults.groupOrder)
        #expect(p.tiles[4].label == "E")
        #expect(p.tiles[4].symbols.map(\.symbol) == ["ə", "ɚ", "ɵ"])
        #expect(p.tiles.first { $0.key == "," }?.label == ",")
        #expect(p.tiles.first { $0.key == "k" }?.note == "clicks (k for click)")
        #expect(p.tiles.first { $0.key == "e" }?.note == nil)
    }

    @Test func symbolKnowsItsNames() {
        let schwa = symbol("e1")
        #expect(schwa.names == ["schwa", "e1"])
        #expect(schwa.presses == 1)
    }

    @Test func tooltipReadsLikeTheWebsite() {
        let p = Self.palette
        #expect(p.tooltip(symbol("e2")) == "latin small letter schwa with hook\nCtrl+Shift+E ×2\n;rschwa  ;e2")
        #expect(p.tooltip(symbol("e1")) == "latin small letter schwa\nCtrl+Shift+E\n;schwa  ;e1")
        #expect(p.chordText(symbol("55")) == "Ctrl+Shift+5 ×5")
    }

    @Test func marksShowOnADottedCircle() {
        #expect(symbol(".3").glyph == "◌\u{306}")
        #expect(symbol("e1").glyph == "ə")
        #expect(symbol("a4").glyph == "ɑ\u{303}")
    }

    /// Names with no chord get their own list, once each.
    @Test func unchordedSymbols() {
        let u = Self.palette.unchorded.map(\.symbol)
        #expect(u.contains("ʧ"))
        #expect(u.contains("ɡ"))
        #expect(!u.contains("ə"))
        #expect(Set(u).count == u.count)
        #expect(Self.palette.unchorded.first { $0.symbol == "ʧ" }?.names == ["tshlig"])
        #expect(Self.palette.tooltip(Self.palette.unchorded.first { $0.symbol == "ʧ" }!)
            == "latin small letter tesh digraph\n;tshlig")
    }

    @Test func emptySearchShowsAll() {
        #expect(Self.palette.search("") == nil)
        #expect(Self.palette.search("  ") == nil)
    }

    @Test func searchByName() {
        let r = Self.palette.search("schwa")!
        #expect(r.contains("e1"))     // schwa
        #expect(r.contains("e2"))     // rschwa (anywhere, 3+ letters)
        #expect(r.contains("68"))     // supschwa
        #expect(!r.contains("31"))
    }

    @Test func searchIgnoresThePrefix() {
        #expect(Self.palette.search(";schwa") == Self.palette.search("schwa"))
        #expect(Self.palette.search(";e2") == ["e2"])
    }

    @Test func searchBySymbol() {
        #expect(Self.palette.search("ə") == ["e1"])
        #expect(Self.palette.search("ɑ\u{303}")?.contains("a4") == true)
        #expect(Self.palette.search("◌\u{306}") == [".3"])
    }

    /// One letter is the key: E shows the E tile, not every name with an e.
    @Test func singleLetterIsTheKey() {
        #expect(Self.palette.search("e") == ["e1", "e2", "e3"])
        #expect(Self.palette.search("comma")?.isSuperset(of: [",1", ",2", ",3", ",4", ",5"]) == true)
        #expect(Self.palette.search(",") == [",1", ",2", ",3", ",4", ",5"])
    }

    @Test func searchByUnicodeName() {
        let r = Self.palette.search("breve")!
        #expect(r.contains(".3"))
        #expect(Self.palette.search("click")?.isSuperset(of: ["k1", "k2", "k3", "k4", "k5"]) == true)
    }

    @Test func noMatch() {
        #expect(Self.palette.search("zzzz") == [])
    }

    @Test func reflectsEdits() {
        let c = Config.parse("[settings]\nchord = option\nprefix = \\\\\n[groups]\n# mine\nx = ʘ ǀ\n[names]\nbull = ʘ\nfoo = ŋ\n")
        let p = Palette(c)
        #expect(p.tiles.map(\.key) == ["x"])
        #expect(p.tiles[0].note == "mine")
        #expect(p.unchorded.map(\.symbol) == ["ŋ"])
        #expect(p.tooltip(p.tiles[0].symbols[1]) == "latin letter dental click\nOption+X ×2\n\\\\x2")
        #expect(p.search("\\\\bull") == ["x1"])
    }
}
