import Testing
@testable import IPAKeysCore

struct EngineTests {
    func engine() -> Engine { Engine(config: ConfigTests.defaults) }

    func type(_ e: Engine, _ s: String) -> [Decision] {
        s.map { e.typed(String($0)) }
    }

    @Test func firstPressInserts() {
        let e = engine()
        let d = e.chord(key: "e", mode: .select)
        #expect(d?.swallow == true)
        #expect(d?.actions == [.insert("ə")])
    }

    @Test func keyWithoutGroupPassesAndResets() {
        let e = engine()
        _ = type(e, "ab")
        #expect(e.chord(key: "8", mode: .select) == nil)
        #expect(e.context == "")
    }

    @Test func cyclesAndWraps() {
        let e = engine()
        _ = e.chord(key: "e", mode: .select)
        #expect(e.chord(key: "e", mode: .select)?.actions == [.selectBack(1), .insert("ɚ")])
        #expect(e.chord(key: "e", mode: .select)?.actions == [.selectBack(1), .insert("ɵ")])
        #expect(e.chord(key: "e", mode: .select)?.actions == [.selectBack(1), .insert("ə")])
        #expect(e.context == "ə")
    }

    @Test func typingBetweenStartsOver() {
        let e = engine()
        _ = e.chord(key: "e", mode: .select)
        _ = e.typed("x")
        #expect(e.chord(key: "e", mode: .select)?.actions == [.insert("ə")])
        #expect(e.context == "əxə")
    }

    @Test func otherKeyStartsItsOwnCycle() {
        let e = engine()
        _ = e.chord(key: "e", mode: .select)
        #expect(e.chord(key: "s", mode: .select)?.actions == [.insert("ʃ")])
        #expect(e.chord(key: "s", mode: .select)?.actions == [.selectBack(1), .insert("ʂ")])
        #expect(e.context == "əʂ")
    }

    @Test func resetStartsOver() {
        let e = engine()
        _ = e.chord(key: "e", mode: .select)
        e.reset()
        #expect(e.chord(key: "e", mode: .select)?.actions == [.insert("ə")])
    }

    @Test func singleSymbolGroupDoesNothingOnRepeat() {
        let e = engine()
        _ = e.chord(key: "m", mode: .select)
        let d = e.chord(key: "m", mode: .select)
        #expect(d?.swallow == true)
        #expect(d?.actions == [])
    }

    /// A mark after a typed letter: the cycle selects the letter with its
    /// mark and types both back, so the letter survives whatever the app's
    /// Backspace would do.
    @Test func markCyclesKeepTheLetter() {
        let e = engine()
        _ = e.typed("u")
        #expect(e.chord(key: ".", mode: .select)?.actions == [.insert("ː")])
        #expect(e.chord(key: ".", mode: .select)?.actions == [.selectBack(1), .insert("ˑ")])
        // ˑ is its own character; the breve typed over it joins the u.
        #expect(e.chord(key: ".", mode: .select)?.actions == [.selectBack(1), .insert("\u{306}")])
        #expect(e.context == "u\u{306}")
        #expect(e.chord(key: ".", mode: .select)?.actions == [.selectBack(1), .insert("uː")])
    }

    @Test func markToMark() {
        let e = engine()
        _ = type(e, "xt")
        #expect(e.chord(key: "[", mode: .select)?.actions == [.insert("\u{32A}")])
        #expect(e.chord(key: "[", mode: .select)?.actions == [.selectBack(1), .insert("t\u{33A}")])
        #expect(e.context == "xt\u{33A}")
    }

    /// Marks stack: the second group's cycle keeps the first mark.
    @Test func stackedMarks() {
        let e = engine()
        _ = e.typed("a")
        _ = e.chord(key: "`", mode: .select)            // a + tilde
        _ = e.chord(key: "4", mode: .select)            // + double acute
        #expect(e.chord(key: "4", mode: .select)?.actions == [.selectBack(1), .insert("a\u{303}\u{301}")])
    }

    /// The letter was there before a click: unknown, so remove just the
    /// mark with Control-Backspace.
    @Test func markWithUnknownLetter() {
        let e = engine()
        _ = e.chord(key: ",", mode: .select)
        #expect(e.chord(key: ",", mode: .select)?.actions == [.decomposingBackspace(1), .insert("\u{30A}")])
    }

    /// d͡ʒ is two characters to the cursor (d͡ and ʒ).
    @Test func multiCharacterSymbol() {
        let e = engine()
        _ = e.chord(key: "d", mode: .select)
        #expect(e.chord(key: "d", mode: .select)?.actions == [.selectBack(1), .insert("d\u{361}ʒ")])
        #expect(e.chord(key: "d", mode: .select)?.actions == [.selectBack(2), .insert("ɖ")])
    }

    /// A tie bar after a letter, cycling to a spacing symbol.
    @Test func markToSpacingSymbol() {
        let e = engine()
        _ = e.typed("t")
        _ = e.chord(key: "f", mode: .select)
        #expect(e.chord(key: "f", mode: .select)?.actions == [.selectBack(1), .insert("t‿")])
    }

    @Test func terminalsBackspacePerCodePoint() {
        let e = engine()
        _ = e.typed("u")
        _ = e.chord(key: "a", mode: .backspace)
        _ = e.chord(key: "a", mode: .backspace)
        _ = e.chord(key: "a", mode: .backspace)
        #expect(e.chord(key: "a", mode: .backspace)?.actions == [.backspace(1), .insert("ɑ\u{303}")])
        #expect(e.chord(key: "a", mode: .backspace)?.actions == [.backspace(2), .insert("ɑ")])
    }

    @Test func nameExpandsOnLastKey() {
        let e = engine()
        let ds = type(e, ";schwa")
        #expect(ds.dropLast().allSatisfy { $0 == .pass })
        #expect(ds.last?.swallow == true)
        #expect(ds.last?.actions == [.backspace(5), .insert("ə")])
        #expect(e.context == "ə")
    }

    @Test func derivedNameExpands() {
        let e = engine()
        #expect(type(e, ";e2").last?.actions == [.backspace(2), .insert("ɚ")])
    }

    @Test func markNameAfterLetter() {
        let e = engine()
        #expect(type(e, "u;extrashort").last?.actions == [.backspace(10), .insert("\u{306}")])
        #expect(e.context == "u\u{306}")
    }

    /// A mark typed by name, then cycled by chord, keeps its letter.
    @Test func nameThenChordKnowsTheLetter() {
        let e = engine()
        _ = type(e, "u;extrashort")
        _ = e.chord(key: "[", mode: .select)
        #expect(e.chord(key: "[", mode: .select)?.actions == [.selectBack(1), .insert("u\u{306}\u{33A}")])
    }

    @Test func noMatchWithoutPrefix() {
        let e = engine()
        #expect(type(e, "schwa").allSatisfy { $0 == .pass })
    }

    @Test func backspaceFixesATypo() {
        let e = engine()
        _ = type(e, ";scx")
        e.backspace()
        #expect(type(e, "hwa").last?.actions == [.backspace(5), .insert("ə")])
    }

    @Test func backspaceOverMarkForgets() {
        let e = engine()
        _ = type(e, "u;extrashort")
        e.backspace()
        #expect(e.context == "")
    }

    @Test func resetForgetsThePrefix() {
        let e = engine()
        _ = type(e, ";sch")
        e.reset()
        #expect(type(e, "wa").allSatisfy { $0 == .pass })
    }

    @Test func latestPrefixCounts() {
        let e = engine()
        #expect(type(e, ";x;;e1").last?.actions == [.backspace(2), .insert("ə")])
    }

    @Test func multiCharacterPrefix() {
        let e = Engine(config: Config.parse("[settings]\nprefix = \\\\\n[names]\nsh = ʃ\n"))
        #expect(type(e, "\\\\sh").last?.actions == [.backspace(3), .insert("ʃ")])
    }

    @Test func contextStaysBounded() {
        let e = engine()
        _ = type(e, String(repeating: "x", count: 500))
        #expect(e.context.count <= 64)
        #expect(type(e, ";schwa").last?.actions == [.backspace(5), .insert("ə")])
    }
}

struct ChunkTests {
    @Test func shortTextIsOneChunk() {
        #expect(keyEventChunks("d\u{361}ʒ") == ["d\u{361}ʒ"])
    }

    @Test func longTextSplitsBetweenLetters() {
        let text = String(repeating: "u\u{306}", count: 15)  // 30 units
        let chunks = keyEventChunks(text)
        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { $0.utf16.count <= 20 && $0.unicodeScalars.first == "u" })
        #expect(chunks.joined() == text)
    }
}
