import Testing
@testable import IPAKeysCore

struct PressTrackerTests {
    /// Chord held, modifiers let go, key still down: the repeats are still
    /// kept from the app, and the key-up too.
    @Test func repeatsOfAKeptPressStayKept() {
        var t = PressTracker()
        t.claim(14)
        let r1 = t.down(14, isRepeat: true), r2 = t.down(14, isRepeat: true), up = t.up(14)
        #expect(r1 && r2 && up)
        // Afterwards the key is ordinary again.
        let fresh = t.down(14, isRepeat: false), up2 = t.up(14)
        #expect(!fresh && !up2)
    }

    @Test func otherKeysAreNotTouched() {
        var t = PressTracker()
        t.claim(14)
        let a = t.down(15, isRepeat: false), b = t.down(15, isRepeat: true), c = t.up(15)
        #expect(!a && !b && !c)
    }

    /// A key-up lost while the tap was off: the next fresh press of that
    /// key is not mistaken for the old one, so its key-up reaches the app.
    @Test func missedKeyUpDoesNotEatTheNextPress() {
        var t = PressTracker()
        t.claim(14)
        let fresh = t.down(14, isRepeat: false), up = t.up(14)
        #expect(!fresh && !up)
    }

    @Test func clearForgetsEverything() {
        var t = PressTracker()
        t.claim(14)
        t.claim(15)
        t.clear()
        let up = t.up(14), rep = t.down(15, isRepeat: true)
        #expect(!up && !rep)
    }
}
