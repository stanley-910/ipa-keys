/// Pieces of at most 20 UTF-16 units (what one key event carries), never
/// splitting a letter from its marks.
public func keyEventChunks(_ text: String, limit: Int = 20) -> [String] {
    var out: [String] = []
    var cur = ""
    for ch in text {
        if !cur.isEmpty, cur.utf16.count + String(ch).utf16.count > limit {
            out.append(cur)
            cur = ""
        }
        cur.append(ch)
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}
