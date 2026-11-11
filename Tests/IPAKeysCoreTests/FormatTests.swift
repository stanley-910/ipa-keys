import Testing
@testable import IPAKeysCore

struct FormatTests {
    @Test func modifierSpellings() {
        let m: Modifiers = [.shift, .control]
        #expect(m.configString == "control+shift")
        #expect(m.glyphs == "⌃⇧")
        #expect(m.words == "Ctrl+Shift")
        #expect(Modifiers([.command, .option, .control, .shift]).configString == "control+option+shift+command")
    }

    @Test func shortcutSpellings() {
        #expect(Shortcut([.control, .shift], "escape").configString == "control+shift+escape")
        #expect(Shortcut([.control, .shift], "escape").display == "⌃⇧Esc")
        #expect(Shortcut([.control, .shift], "/").configString == "control+shift+slash")
        #expect(Shortcut([.control, .shift], "/").display == "⌃⇧/")
        #expect(Shortcut([.option], "e").display == "⌥E")
    }

    /// What the file writes reads back as the same shortcut.
    @Test func shortcutRoundTrips() {
        for s in [Shortcut([.control, .shift], "escape"), Shortcut([.command, .option], ","), Shortcut([.control], "f5")] {
            #expect(Config.parseShortcut(s.configString) == s)
        }
    }

    @Test func chordNeedsARealModifier() {
        #expect(Config.chordProblem([.shift]) != nil)
        #expect(Config.chordProblem([]) != nil)
        #expect(Config.chordProblem([.control, .shift]) == nil)
        #expect(Config.chordProblem([.option]) == nil)
    }

    @Test func prefixRules() {
        #expect(Config.prefixProblem(";") == nil)
        #expect(Config.prefixProblem("\\\\") == nil)
        #expect(Config.prefixProblem("") != nil)
        #expect(Config.prefixProblem("; ") != nil)
        #expect(Config.prefixProblem("=") != nil)
        #expect(Config.prefixProblem("#") != nil)
    }

    @Test func toggleMustNotTakeAGroupKey() {
        let c = ConfigTests.defaults
        #expect(c.shortcutProblem(Shortcut([.control, .shift], "e"), for: "toggle") != nil)
        #expect(c.shortcutProblem(Shortcut([.control, .shift], "escape"), for: "toggle") == nil)
        #expect(c.shortcutProblem(Shortcut([.shift], "escape"), for: "toggle") != nil)
    }
}

struct ConfigEditorTests {
    static let file = """
    # my notes
    [settings]
    # the chord
    chord = control+shift
      prefix = ;

    [groups]
    # mine
    e = ə ɚ
    """

    @Test func replacesTheValueAndKeepsEverythingElse() {
        let out = ConfigEditor.set("chord", to: "option+command", in: Self.file)
        #expect(out == Self.file.replacingOccurrences(of: "chord = control+shift", with: "chord = option+command"))
    }

    @Test func keepsIndent() {
        let out = ConfigEditor.set("prefix", to: "::", in: Self.file)
        #expect(out.contains("\n  prefix = ::\n"))
        #expect(Config.parse(out).prefix == "::")
    }

    @Test func addsAMissingSettingAfterTheLastOne() {
        let out = ConfigEditor.set("toggle", to: "control+shift+escape", in: Self.file)
        #expect(out.contains("  prefix = ;\ntoggle = control+shift+escape\n\n[groups]"))
        #expect(Config.parse(out).toggle == Shortcut([.control, .shift], "escape"))
        #expect(out.contains("# mine\ne = ə ɚ"))
    }

    @Test func clearingWritesAnEmptyValue() {
        let withToggle = ConfigEditor.set("toggle", to: "control+shift+escape", in: Self.file)
        let out = ConfigEditor.set("toggle", to: "", in: withToggle)
        #expect(out.contains("\ntoggle =\n"))
        #expect(Config.parse(out).toggle == nil)
    }

    @Test func addsTheSectionWhenMissing() {
        let out = ConfigEditor.set("prefix", to: "::", in: "# hi\n[groups]\ne = ə\n")
        #expect(out == "# hi\n[settings]\nprefix = ::\n\n[groups]\ne = ə\n")
        #expect(ConfigEditor.set("prefix", to: "::", in: "") == "\n[settings]\nprefix = ::\n")
    }

    /// A key in another section with the same spelling is not touched.
    @Test func onlyTouchesSettings() {
        let text = "[names]\nchord = x\n[settings]\nchord = control+shift\n"
        #expect(ConfigEditor.set("chord", to: "option", in: text) == "[names]\nchord = x\n[settings]\nchord = option\n")
    }

    @Test func keepsWindowsLineEndings() {
        let out = ConfigEditor.set("chord", to: "option", in: "[settings]\r\nchord = control\r\n")
        #expect(out == "[settings]\r\nchord = option\r\n")
    }

    /// The real default file: changing each setting changes only that line.
    @Test func defaultFileChangesOneLine() {
        let before = defaultConfigText.components(separatedBy: "\n")
        let after = ConfigEditor.set("chord", to: "control+option", in: defaultConfigText).components(separatedBy: "\n")
        #expect(before.count == after.count)
        #expect(zip(before, after).filter { $0 != $1 }.count == 1)
        #expect(Config.parse(after.joined(separator: "\n")).chord == [.control, .option])
    }
}

struct SymbolsSettingTests {
    @Test func defaultsToControlShiftSlash() {
        #expect(ConfigTests.defaults.symbols == Shortcut([.control, .shift], "/"))
        // A file from before the setting existed still gets it.
        #expect(Config.parse("[groups]\ne = ə\n").symbols == Shortcut([.control, .shift], "/"))
    }

    @Test func emptyTurnsItOff() {
        #expect(Config.parse("[settings]\nsymbols =\n").symbols == nil)
    }

    @Test func clashWithAGroupIsReported() {
        let c = Config.parse("[groups]\nslash = x\n")
        #expect(c.warnings == ["symbols uses the chord with /, so that group cannot be typed"])
    }

    @Test func settingsRejectASecondUse() {
        var c = ConfigTests.defaults
        c.toggle = Shortcut([.control, .shift], "escape")
        #expect(c.shortcutProblem(Shortcut([.control, .shift], "escape"), for: "symbols") == "Already used for toggle")
        #expect(c.shortcutProblem(Shortcut([.control, .shift], "escape"), for: "toggle") == nil)
    }
}

struct LogTextTests {
    /// By default the log says how much, never what.
    @Test func noTextByDefault() {
        let a: [Action] = [.backspace(5), .selectBack(1), .insert("u\u{306}")]
        #expect(describeActions(a, content: false) == "Backspace x5, Shift-Left x1, type 2 code points")
        #expect(describeText("ə", content: false) == "1 code point")
    }

    @Test func debugShowsTextAndCodePoints() {
        #expect(describeText("u\u{306}", content: true) == "\"u\u{306}\" (U+0075 U+0306)")
        #expect(describeActions([.insert("ə")], content: true) == "type \"ə\" (U+0259)")
    }

    /// The typed name is kept out of the note, which is always logged.
    @Test func nameIsADetailNotTheNote() {
        let e = Engine(config: ConfigTests.defaults)
        let d = ";schwa".map { e.typed(String($0)) }.last!
        #expect(d.note == "name")
        #expect(d.detail == ";schwa")
    }

    @Test func debugLogSetting() {
        #expect(ConfigTests.defaults.debugLog == false)
        #expect(Config.parse("[settings]\ndebug_log = on\n").debugLog)
        #expect(Config.parse("[settings]\ndebug_log = maybe\n").warnings.count == 1)
    }
}
