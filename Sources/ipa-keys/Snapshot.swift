import AppKit
import IPAKeysCore
import SwiftUI

/// `ipa-keys --snapshot DIR`: draws the windows offscreen, in light and
/// dark, to PNGs, so their layout can be checked without showing them.
enum Snapshot {
    static func run(into dir: String) {
        _ = NSApplication.shared
        let text = (try? String(contentsOf: App.configURL, encoding: .utf8)) ?? defaultConfigText
        let config = Config.parse(text)
        let settings = SettingsModel()
        settings.load(config)
        settings.problem = "Toggle: ⌃⇧E is the chord for group E"
        let palette = PaletteModel()
        palette.palette = Palette(config)
        let size = NSSize(width: 980, height: 640)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(SettingsView(model: settings), appearance, to: "\(dir)/settings-\(name).png")
            palette.query = ""
            palette.hovered = palette.palette.tiles.first { $0.key == "5" }?.symbols.last
            render(PaletteView(model: palette), appearance, size: size, to: "\(dir)/palette-\(name).png")
        }
        palette.query = "schwa"
        palette.hovered = nil
        render(PaletteView(model: palette), .aqua, size: size, to: "\(dir)/palette-search.png")
    }

    static func render<V: View>(_ view: V, _ appearance: NSAppearance.Name, size: NSSize? = nil, to path: String) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size ?? host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        if let size { host.frame.size = size } else { host.frame.size = host.fittingSize }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
