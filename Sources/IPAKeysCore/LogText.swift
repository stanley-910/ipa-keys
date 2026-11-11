/// How text appears in the log. Without `content` (the default, see the
/// debug_log setting) no text is written, only how long it is, so the log
/// never holds what someone typed or a private expansion.
public func describeText(_ s: String, content: Bool) -> String {
    let n = s.unicodeScalars.count
    guard content else { return "\(n) code point\(n == 1 ? "" : "s")" }
    let codes = s.unicodeScalars.map { "U+" + String($0.value, radix: 16, uppercase: true).leftPadded(4) }
    return "\"\(s)\" (\(codes.joined(separator: " ")))"
}

/// The keystrokes of an action list, for the log.
public func describeActions(_ actions: [Action], content: Bool) -> String {
    if actions.isEmpty { return "nothing to send" }
    return actions.map { a -> String in
        switch a {
        case .backspace(let n): return "Backspace x\(n)"
        case .selectBack(let n): return "Shift-Left x\(n)"
        case .insert(let s): return "type " + describeText(s, content: content)
        }
    }.joined(separator: ", ")
}

extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
