import Testing
@testable import IPAKeysCore

struct ConfigTests {
    static let defaults = Config.parse(defaultConfigText)

    @Test func defaultConfigHasNoWarnings() {
        #expect(Self.defaults.warnings == [])
    }

    @Test func defaultSettings() {
        let c = Self.defaults
        #expect(c.chord == [.control, .shift])
        #expect(c.prefix == ";")
        #expect(c.toggle == nil)
        #expect(c.backspaceApps.contains("com.apple.Terminal"))
    }

    /// The website's keys, in its order, then the ones added for marks.
    @Test func defaultGroupsFollowTheWebsite() {
        let website = "a b c d e 3 g h i j l m n o 0 p r s t u v w x y z 2 q f".split(separator: " ").map(String.init)
        #expect(Array(Self.defaults.groupOrder.prefix(website.count)) == website)
        #expect(Self.defaults.groups["e"] == ["ə", "ɚ", "ɵ"])
        #expect(Self.defaults.groups["d"] == ["ð", "d\u{361}ʒ", "ɖ", "ɗ"])
        #expect(Self.defaults.groups["a"]?.last == "ɑ\u{303}")
    }

    @Test func addedGroups() {
        let g = Self.defaults.groups
        #expect(g["k"] == ["ʘ", "ǀ", "ǃ", "ǂ", "ǁ"])
        #expect(g["."] == ["ː", "ˑ", "\u{306}"])
        #expect(g[","]?.first == "\u{325}")
        #expect(g["1"] == ["˥", "˦", "˧", "˨", "˩"])
        for key in ["k", "'", ".", "`", ",", "[", "]", "-", "=", "\\", "6", "1", "4", "5", "7"] {
            #expect(g[key] != nil, "missing group \(key)")
        }
    }

    /// No group so long that e1 would be the start of e10.
    @Test func groupsFitInNineSoDerivedNamesStayPrefixFree() {
        for (key, symbols) in Self.defaults.groups { #expect(symbols.count <= 9, "group \(key)") }
    }

    @Test func dottedCircleIsStripped() {
        #expect(Self.defaults.names["extrashort"] == "\u{306}")
        #expect(Self.defaults.groups["f"] == ["\u{361}", "‿"])
        #expect(Config.stripDottedCircles("◌̃") == "\u{303}")
        // Not before a mark: kept.
        #expect(Config.stripDottedCircles("◌") == "◌")
        #expect(Config.stripDottedCircles("a◌b") == "a◌b")
    }

    @Test func namesFromTheTableAndDerived() {
        let n = Self.defaults.names
        #expect(n["schwa"] == "ə")
        #expect(n["e1"] == "ə")
        #expect(n["e2"] == "ɚ")
        #expect(n["d2"] == "d\u{361}ʒ")
        #expect(n["k1"] == "ʘ")
        #expect(n[",1"] == "\u{325}")
        #expect(n["tone5"] == "˥")
        // 157 from the table plus one per group symbol.
        let derived = Self.defaults.groups.values.map(\.count).reduce(0, +)
        #expect(n.count == 157 + derived)
    }

    @Test func parsesHandWrittenFile() {
        let c = Config.parse("""
        # comment
        [settings]
        chord = option+command
        prefix = ::
        toggle = control+shift+escape
        backspace_apps = a.b  c.d

        [groups]
        E = x y
        comma = ◌̥
        [names]
        foo = bar baz
        """)
        #expect(c.warnings == [])
        #expect(c.chord == [.option, .command])
        #expect(c.prefix == "::")
        #expect(c.toggle == Shortcut(modifiers: [.control, .shift], key: "escape"))
        #expect(c.backspaceApps == ["a.b", "c.d"])
        #expect(c.groups["e"] == ["x", "y"])
        #expect(c.groups[","] == ["\u{325}"])
        #expect(c.names["foo"] == "bar baz")
        #expect(c.names["e2"] == "y")
        #expect(c.names[",1"] == "\u{325}")
    }

    @Test func warnsAboutPrefixNames() {
        let c = Config.parse("[names]\nlo = a\nlong = b\nlower = c\n")
        #expect(c.warnings.count == 2)
        #expect(c.warnings.allSatisfy { $0.hasPrefix("name lo is the start of") })
    }

    @Test func warnsAboutBadLines() {
        let c = Config.parse("""
        stray = 1
        [settings]
        chord = hyper
        colour = red
        [groups]
        tab = x
        [names]
        two words = x
        nothing
        [other]
        """)
        #expect(c.chord == [.control, .shift])
        #expect(c.warnings.count == 7)
    }

    @Test func handWrittenNameBeatsDerived() {
        let c = Config.parse("[groups]\ne = ə ɚ\n[names]\ne1 = x\n")
        #expect(c.names["e1"] == "x")
        #expect(c.warnings.count == 1)
    }
}
