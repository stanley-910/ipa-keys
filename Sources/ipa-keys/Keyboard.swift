import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IPAKeysCore

/// Which physical key types which character, from the current keyboard
/// layout, so a chord can match on key codes: with Control and Shift held
/// the key no longer types its letter.
struct KeyMap {
    /// Key code to the character it types with no modifiers.
    var chars: [CGKeyCode: String] = [:]
    var codes: [String: CGKeyCode] = [:]
    var layoutName = "US (built in)"

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
        var typed: [UInt16: String] = [:]
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
                        typed[UInt16(code)] = String(utf16CodeUnits: out, count: len)
                    }
                }
            }
        }
        for (s, code) in KeyLayout.resolve(layout: typed) {
            map.codes[s] = CGKeyCode(code)
            map.chars[CGKeyCode(code)] = s
        }
        return map
    }

    func code(for key: String) -> CGKeyCode? { KeyMap.special[key] ?? codes[key] }
}
