/// The physical key presses ipa-keys keeps from the app, from key-down
/// through every repeat to key-up, whatever the modifiers do meanwhile.
public struct PressTracker: Sendable {
    private var held: Set<UInt16> = []

    public init() {}

    /// Keep this press (its repeats and key-up) from the app.
    public mutating func claim(_ code: UInt16) { held.insert(code) }

    /// A key-down. True when it repeats a press we keep. A fresh press of
    /// a key we thought held means its key-up was missed: forget it.
    public mutating func down(_ code: UInt16, isRepeat: Bool) -> Bool {
        guard held.contains(code) else { return false }
        if isRepeat { return true }
        held.remove(code)
        return false
    }

    /// A key-up. True when it ends a press we keep.
    public mutating func up(_ code: UInt16) -> Bool { held.remove(code) != nil }

    /// Event delivery was interrupted (the tap was off): key-ups may be lost.
    public mutating func clear() { held.removeAll() }
}
