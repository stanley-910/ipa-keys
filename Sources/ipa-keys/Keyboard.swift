import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Which physical key types which character, from the current keyboard
/// layout, so a chord can match on key codes: with Control and Shift held
/// the key no longer types its letter.
struct KeyMap {
    /// Key code to the character it types with no modifiers.
    var chars: [CGKeyCode: String] = [:]
    var codes: [String: CGKeyCode] = [:]
    var layoutName = "US (built in)"

    /// US ANSI positions, used for anything the layout does not give.
    static let ansi: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50,
    ]

    /// Keys that are not characters, for the toggle chord.
    static let special: [String: CGKeyCode] = [
        "escape": CGKeyCode(kVK_Escape), "space": CGKeyCode(kVK_Space), "tab": CGKeyCode(kVK_Tab),
        "return": CGKeyCode(kVK_Return),
        "f1": CGKeyCode(kVK_F1), "f2": CGKeyCode(kVK_F2), "f3": CGKeyCode(kVK_F3), "f4": CGKeyCode(kVK_F4),
        "f5": CGKeyCode(kVK_F5), "f6": CGKeyCode(kVK_F6), "f7": CGKeyCode(kVK_F7), "f8": CGKeyCode(kVK_F8),
        "f9": CGKeyCode(kVK_F9), "f10": CGKeyCode(kVK_F10), "f11": CGKeyCode(kVK_F11), "f12": CGKeyCode(kVK_F12),
    ]

    /// Reads the current layout. Call on the main thread.
    static func current() -> KeyMap {
        var map = KeyMap()
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() {
            if let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                map.layoutName = Unmanaged<CFString>.fromOpaque(name).takeUnretainedValue() as String
            }
            if let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
                data.withUnsafeBytes { buf in
                    guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
                    // Main block only: skip the keypad (65-92) so "1" is the top row.
                    for code in Array(0...64) + [93, 94, 95] {
                        var dead: UInt32 = 0
                        var len = 0
                        var out = [UniChar](repeating: 0, count: 4)
                        let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                                    &dead, out.count, &len, &out)
                        guard status == noErr, len > 0 else { continue }
                        let s = String(utf16CodeUnits: out, count: len).lowercased()
                        guard s.count == 1, map.codes[s] == nil else { continue }
                        map.codes[s] = CGKeyCode(code)
                    }
                }
            }
        }
        for (s, code) in ansi where map.codes[s] == nil && !map.codes.values.contains(code) {
            map.codes[s] = code
        }
        for (s, code) in map.codes { map.chars[code] = s }
        return map
    }

    func code(for key: String) -> CGKeyCode? { KeyMap.special[key] ?? codes[key] }
}
