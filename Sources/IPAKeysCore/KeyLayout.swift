/// Which physical key (key code) stands for each character a config can
/// name, on the current keyboard layout.
public enum KeyLayout {
    /// US ANSI key codes.
    public static let ansi: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50,
    ]

    /// `layout` is what each key types with no modifiers. Rules, in order:
    /// 1. Digits are the number-row keys, where they are printed even when
    ///    the layout needs Shift for them (AZERTY).
    /// 2. Letters and punctuation are the key that types them, lowest key
    ///    code first, unless a digit took that key.
    /// 3. Anything left uses its US position, if that key types no other
    ///    config character and is not taken.
    /// A character with no key left is missing from the result.
    public static func resolve(layout: [UInt16: String]) -> [String: UInt16] {
        var codes: [String: UInt16] = [:]
        var taken = Set<UInt16>()
        for d in "0123456789".map(String.init) {
            let code = ansi[d]!
            codes[d] = code
            taken.insert(code)
        }
        for code in layout.keys.sorted() where !taken.contains(code) {
            let ch = layout[code]!.lowercased()
            guard ch.count == 1, Config.keyChars.contains(Character(ch)), codes[ch] == nil else { continue }
            codes[ch] = code
            taken.insert(code)
        }
        for ch in ansi.keys.sorted() where codes[ch] == nil {
            let code = ansi[ch]!
            if !taken.contains(code) {
                codes[ch] = code
                taken.insert(code)
            }
        }
        return codes
    }
}
