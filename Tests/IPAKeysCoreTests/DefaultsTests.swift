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
            "[groups]",
            "# replace your line w = ɯ ʍ with:",
            "w = ɯ ʍ ɰ",
            "comma = ◌̥",
            "[names]",
            "null = ∅",
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

struct PasteableDefaultsTests {
    /// Pasted into the file as printed (indented, as the script shows it),
    /// with the user's old w line replaced as the comment says, the result
    /// parses cleanly and has everything.
    @Test func outputParsesAndFillsTheGaps() {
        let mine = "[settings]\nprefix = ;\n[groups]\nw = ɯ ʍ\n2 = ʔ ʕ\n[names]\nschwa = ə\n"
        let block = missingDefaults(in: Config.parse(mine))
        let snippet = Config.parse(block.map { "  " + $0 }.joined(separator: "\n"))
        #expect(snippet.warnings == [])
        #expect(snippet.groups["w"] == ["ɯ", "ʍ", "ɰ"])
        #expect(snippet.groups["2"] == ["ʔ", "ʕ", "ʡ", "ʢ"])
        #expect(snippet.groups[","] != nil)
        #expect(snippet.names["null"] == "∅")
        // Every line is a header, a comment, or a key = value line.
        for line in block {
            #expect(line.hasPrefix("[") || line.hasPrefix("#") || line.contains(" = "), "\(line)")
            #expect(!line.contains("yours:") || line.hasPrefix("#"))
        }
    }

    @Test func nothingMissingPrintsNothing() {
        #expect(missingDefaults(in: ConfigTests.defaults).isEmpty)
    }
}
