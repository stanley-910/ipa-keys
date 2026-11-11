/// When a batch of keystrokes (deleting a typed name, cycling a symbol)
/// was decided: the context generation and the app in front then.
public struct OutputStamp: Equatable, Sendable {
    /// Goes up whenever focus or state changes outside the keys ipa-keys
    /// holds back: app switch, secure input, the tap stopping, a toggle.
    public var generation: Int
    /// Process id of the app the keystrokes are meant for.
    public var app: Int32

    public init(generation: Int, app: Int32) {
        self.generation = generation
        self.app = app
    }
}

public enum OutputVerdict: Equatable, Sendable {
    /// Send the next keystroke.
    case go
    /// Nothing sent yet: drop the batch (and give back the key it kept).
    case abandon(String)
    /// Part sent: stop, rather than delete at a cursor that moved.
    case stop(String)
}

/// Checked before every keystroke of a batch, at the moment it would be
/// posted, not when the batch was decided.
public func checkOutput(_ stamp: OutputStamp, generation: Int, frontApp: Int32, secureInput: Bool,
                        started: Bool) -> OutputVerdict {
    let reason: String
    if secureInput {
        reason = "secure input is on"
    } else if generation != stamp.generation {
        reason = "focus or state changed"
    } else if frontApp != stamp.app {
        reason = "another app is in front"
    } else {
        return .go
    }
    return started ? .stop(reason) : .abandon(reason)
}

/// Keeps the user's keys and clicks behind ipa-keys's own keystrokes: while
/// any batch is pending, input is held and replayed after it, in order.
public struct OutputSequencer: Sendable {
    public private(set) var pending = 0
    public init() {}
    /// Hold this input event rather than let it pass the pending keystrokes.
    public var mustHold: Bool { pending > 0 }
    public mutating func enqueue() { pending += 1 }
    public mutating func finish() { pending = max(0, pending - 1) }
}
