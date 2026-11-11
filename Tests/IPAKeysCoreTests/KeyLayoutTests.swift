import Testing
@testable import IPAKeysCore

struct KeyLayoutTests {
    static let us: [UInt16: String] = Dictionary(uniqueKeysWithValues: KeyLayout.ansi.map { ($0.value, $0.key) })

    /// French AZERTY, unshifted, on the US key codes.
    static let azerty: [UInt16: String] = {
        var t = us
        let changes: [UInt16: String] = [
            0: "q", 12: "a", 13: "z", 6: "w", 46: ",", 41: "m", 43: ";", 47: ":", 44: "=", 39: "ù",
            18: "&", 19: "é", 20: "\"", 21: "'", 23: "(", 22: "§", 26: "è", 28: "!", 25: "ç", 29: "à",
            27: ")", 24: "-", 30: "$", 42: "`", 50: "<",
        ]
        for (k, v) in changes { t[k] = v }
        t[33] = nil  // ^ is a dead key: no character
        return t
    }()

    @Test func usIsTheAnsiTable() {
        #expect(KeyLayout.resolve(layout: Self.us) == KeyLayout.ansi)
    }

    /// Digits stay on the number row although AZERTY needs Shift for them.
    @Test func azertyDigitsAreReachable() {
        let c = KeyLayout.resolve(layout: Self.azerty)
        for d in "0123456789".map(String.init) { #expect(c[d] == KeyLayout.ansi[d], "\(d)") }
    }

    @Test func azertyLettersAndPunctuationFollowTheLayout() {
        let c = KeyLayout.resolve(layout: Self.azerty)
        #expect(c["a"] == 12)
        #expect(c["q"] == 0)
        #expect(c["m"] == 41)
        #expect(c[","] == 46)
        #expect(c["-"] == 24)
        #expect(c["="] == 44)
        #expect(c["`"] == 42)
    }

    /// ' is typed by the 4 key on AZERTY, which the digit keeps; ' falls
    /// back to its US key, which types ù there.
    @Test func collisionsResolveTheSameWayEveryTime() {
        let c = KeyLayout.resolve(layout: Self.azerty)
        #expect(c["4"] == 21)
        #expect(c["'"] == 39)
        #expect(c == KeyLayout.resolve(layout: Self.azerty))
    }

    /// Every key gets a different code. On AZERTY two are lost: / and \\,
    /// whose US keys type = and ` there. (So the default Symbols shortcut,
    /// Control+Shift+/, needs changing on AZERTY; --check shows this.)
    @Test func noTwoCharactersShareAKey() {
        for layout in [Self.us, Self.azerty] {
            let c = KeyLayout.resolve(layout: layout)
            #expect(Set(c.values).count == c.count)
        }
        let c = KeyLayout.resolve(layout: Self.azerty)
        #expect(Set(KeyLayout.ansi.keys).subtracting(c.keys) == ["/", "\\"])
        #expect(c["["] == 33)
        #expect(c["."] == 47)
    }
}
