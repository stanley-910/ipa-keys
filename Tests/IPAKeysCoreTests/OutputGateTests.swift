import Testing
@testable import IPAKeysCore

struct OutputGateTests {
    let stamp = OutputStamp(generation: 7, app: 501)

    @Test func sameContextGoes() {
        #expect(checkOutput(stamp, generation: 7, frontApp: 501, secureInput: false, started: false) == .go)
        #expect(checkOutput(stamp, generation: 7, frontApp: 501, secureInput: false, started: true) == .go)
    }

    /// Focus moved before anything was sent: drop it all.
    @Test func changedBeforeStartingIsAbandoned() {
        #expect(checkOutput(stamp, generation: 8, frontApp: 501, secureInput: false, started: false)
            == .abandon("focus or state changed"))
        #expect(checkOutput(stamp, generation: 7, frontApp: 600, secureInput: false, started: false)
            == .abandon("another app is in front"))
    }

    /// ...after some Backspaces: stop instead of deleting somewhere else.
    @Test func changedMidwayStops() {
        #expect(checkOutput(stamp, generation: 8, frontApp: 501, secureInput: false, started: true)
            == .stop("focus or state changed"))
    }

    /// A password field took the keyboard: checked when posting, not only
    /// when the batch was decided.
    @Test func secureInputAtPostTime() {
        #expect(checkOutput(stamp, generation: 7, frontApp: 501, secureInput: true, started: false)
            == .abandon("secure input is on"))
        #expect(checkOutput(stamp, generation: 7, frontApp: 501, secureInput: true, started: true)
            == .stop("secure input is on"))
    }

    @Test func inputIsHeldOnlyWhileSomethingIsPending() {
        var s = OutputSequencer()
        #expect(!s.mustHold)
        s.enqueue()          // ;schwa's Backspaces and ə
        #expect(s.mustHold)  // a key typed now waits
        s.enqueue()          // ...as a replay, behind them
        s.finish()
        #expect(s.mustHold)  // still behind the replay
        s.finish()
        #expect(!s.mustHold)
        s.finish()
        #expect(s.pending == 0)
    }
}
