import AppKit
import IPAKeysCore

/// `ipa-keys --check`: read the config and keyboard layout, print what each
/// chord key is bound to, and exit. Needs no permission.
if CommandLine.arguments.dropFirst().first == "--check" {
    let text = (try? String(contentsOf: App.configURL, encoding: .utf8)) ?? defaultConfigText
    let config = Config.parse(text)
    let map = KeyMap.current()
    print("config: \(App.configURL.path)")
    print("layout: \(map.layoutName)")
    for w in config.warnings { print("problem: \(w)") }
    for key in config.groupOrder {
        let code = map.codes[key].map { "key code \($0)" } ?? "NO KEY on this layout"
        print("\(key)  (\(code)): \(config.groups[key]!.joined(separator: " "))")
    }
    print("\(config.names.count) names, prefix \(config.prefix)")
    exit(config.warnings.isEmpty ? 0 : 1)
}

/// `ipa-keys --missing-defaults`: list what the built-in defaults have that
/// the config file lacks (new symbols from an update), as lines to paste.
if CommandLine.arguments.dropFirst().first == "--missing-defaults" {
    guard let text = try? String(contentsOf: App.configURL, encoding: .utf8) else { exit(0) }
    let lines = missingDefaults(in: Config.parse(text))
    if !lines.isEmpty {
        print("The default config has \(lines.count) things yours lacks. To add any, open Edit Config")
        print("and paste the line under the section shown (your own lines stay as they are):")
        for l in lines { print("  " + l) }
    }
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "--snapshot", CommandLine.arguments.count > 2 {
    Snapshot.run(into: CommandLine.arguments[2])
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
