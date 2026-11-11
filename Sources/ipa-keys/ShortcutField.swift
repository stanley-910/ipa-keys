import AppKit
import IPAKeysCore
import SwiftUI

/// A click-to-record shortcut box. In `modifiersOnly` mode it keeps only
/// the modifiers of the keystroke (for the chord); otherwise it needs a key.
struct ShortcutField: NSViewRepresentable {
    var text: String
    var modifiersOnly = false
    var onRecord: (Modifiers, String?) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.modifiersOnly = modifiersOnly
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.text = text
        v.onRecord = onRecord
    }
}

final class RecorderView: NSView {
    var modifiersOnly = false
    var onRecord: ((Modifiers, String?) -> Void)?
    var text = "" { didSet { update() } }
    private let label = NSTextField(labelWithString: "")
    private var recording = false {
        didSet {
            update()
            // The tap would otherwise take the very chord being recorded.
            App.shared?.pauseKeys(recording)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func viewDidChangeEffectiveAppearance() { update() }

    private func update() {
        label.stringValue = recording ? (modifiersOnly ? "Hold modifiers, press a key" : "Press shortcut") : text
        label.textColor = recording ? .secondaryLabelColor : .labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = (recording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        var mods: Modifiers = []
        let f = event.modifierFlags
        if f.contains(.control) { mods.insert(.control) }
        if f.contains(.option) { mods.insert(.option) }
        if f.contains(.shift) { mods.insert(.shift) }
        if f.contains(.command) { mods.insert(.command) }
        let code = CGKeyCode(event.keyCode)
        if mods.isEmpty, code == 53 {  // Escape: stop without changing
            window?.makeFirstResponder(nil)
            return
        }
        if modifiersOnly {
            onRecord?(mods, nil)
        } else {
            let key = KeyMap.special.first(where: { $0.value == code })?.key ?? App.shared?.keymap.chars[code]
            guard let key else { NSSound.beep(); return }
            onRecord?(mods, key)
        }
        window?.makeFirstResponder(nil)
    }
}
