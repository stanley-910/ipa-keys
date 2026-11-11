import CoreGraphics
import Foundation

/// A CGEventTap on its own thread, so keys keep flowing while main is busy.
/// Needs Accessibility: an active tap can keep a key from the app.
final class Tap {
    private let controller: Controller
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?

    init(controller: Controller) { self.controller = controller }

    var isEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// False when macOS refused the tap (no Accessibility yet).
    func start() -> Bool {
        var mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        // Clicks reset what ipa-keys knows of the text; ups and drags are
        // watched too so all of a click can be held behind our keystrokes.
        for t in [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp,
                  .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged] {
            mask |= 1 << t.rawValue
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<Tap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: refcon)
        else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        let ready = DispatchSemaphore(value: 0)
        var runLoop: CFRunLoop?
        let thread = Thread {
            runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "ipa-keys.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        loop = runLoop
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.write("event tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabling")
            controller.interrupted()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Poster.marker {
            return Unmanaged.passUnretained(event)
        }
        return controller.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }
}
