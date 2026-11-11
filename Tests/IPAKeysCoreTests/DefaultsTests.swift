import Testing
@testable import IPAKeysCore

struct DefaultsTests {
    @Test func defaultLacksNothing() {
        #expect(missingDefaults(in: ConfigTests.defaults) == [])
    }

    @Test func newSymbolsAreInTheDefault() {
        let c = ConfigTests.defaults
        #expect(c.groups["w"] == ["ɯ", "ʍ", "ɰ"])
        #expect(c.groups["2"] == ["ʔ", "ʕ", "ʡ", "ʢ"])
        #expect(c.groups["8"] == ["ʳ", "ᵗ", "ᵝ"])
        #expect(c.groups["9"] == ["→", "∅"])
        #expect(c.names["null"] == "∅")
        #expect(c.names["becomes"] == "→")
        #expect(c.names["supbeta"] == "ᵝ")
        #expect(c.names["mleg"] == "ɰ")
        #expect(c.names["epiglottalstop"] == "ʡ")
    }

    @Test func reportsWhatAnOlderFileLacks() {
        let old = Config.parse("""
        [groups]
        w = ɯ ʍ
        e = ə ɚ ɵ
        [names]
        schwa = ə
        """)
        let defaults = Config.parse("""
        [groups]
        w = ɯ ʍ ɰ
        e = ə ɚ ɵ
        comma = ◌̥
        [names]
        schwa = ə
        null = ∅
        """)
        #expect(missingDefaults(in: old, defaults: defaults) == [
            "[groups] w = ɯ ʍ ɰ   (yours: ɯ ʍ)",
            "[groups] comma = ◌̥",
            "[names] null = ∅",
        ])
    }

    /// Her edits count: a symbol moved to another key, or a name renamed,
    /// is not reported as missing.
    @Test func movedOrRenamedIsNotMissing() {
        let mine = Config.parse("[groups]\nw = ɯ\nk = ʍ\n[names]\nempty = ∅\n")
        let defaults = Config.parse("[groups]\nw = ɯ ʍ\n[names]\nnull = ∅\n")
        #expect(missingDefaults(in: mine, defaults: defaults) == [])
    }
}
