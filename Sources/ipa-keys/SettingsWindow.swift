import AppKit
import IPAKeysCore
import SwiftUI

/// The settings that live in [settings], shown and saved back to config.txt.
final class SettingsModel: ObservableObject {
    @Published var config = Config()
    @Published var prefixDraft = ";"
    @Published var problem: String?
    /// Writes `key = value` into the file; returns a problem or nil.
    var save: (String, String) -> String? = { _, _ in nil }

    func load(_ c: Config) {
        config = c
        prefixDraft = c.prefix
    }

    func setChord(_ m: Modifiers) {
        if let p = Config.chordProblem(m) { problem = "Chord: \(p)"; return }
        problem = save("chord", m.configString)
    }

    func setPrefix() {
        guard prefixDraft != config.prefix else { return }
        if let p = Config.prefixProblem(prefixDraft) { problem = "Prefix: \(p)"; return }
        problem = save("prefix", prefixDraft)
    }

    func setShortcut(_ setting: String, _ s: Shortcut?) {
        guard let s else { problem = save(setting, ""); return }
        if let p = config.shortcutProblem(s, for: setting) { problem = "\(setting.capitalized): \(p)"; return }
        problem = save(setting, s.configString)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @FocusState private var prefixFocused: Bool

    var body: some View {
        Form {
            row("Chord") {
                ShortcutField(text: model.config.chord.glyphs + " + key", modifiersOnly: true) { m, _ in model.setChord(m) }
                    .frame(width: 180, height: 24)
            }
            row("Prefix") {
                TextField("", text: $model.prefixDraft)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 180, maxWidth: 180)
                    .focused($prefixFocused)
                    .onSubmit { model.setPrefix() }
                    .onChange(of: prefixFocused) { _, focused in if !focused { model.setPrefix() } }
            }
            shortcutRow("Toggle", "toggle", model.config.toggle)
            if let p = model.problem {
                Text(p).foregroundStyle(.red)
            }
            Text("Saved in config.txt").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label)
            Spacer()
            content()
        }
    }

    private func shortcutRow(_ label: String, _ setting: String, _ value: Shortcut?) -> some View {
        row(label) {
            HStack {
                ShortcutField(text: value?.display ?? "None") { m, k in
                    model.setShortcut(setting, k.map { Shortcut(m, $0) })
                }
                .frame(width: 180, height: 24)
                Button("Clear") { model.setShortcut(setting, nil) }
                    .disabled(value == nil)
                    .fixedSize()
            }
        }
    }
}

final class SettingsWindow {
    private var window: NSWindow?
    let model: SettingsModel

    init(model: SettingsModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "ipa-keys Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        model.problem = nil
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
