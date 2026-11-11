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
    for (name, shortcut) in config.shortcuts {
        guard let sc = shortcut else { continue }
        let code = map.code(for: sc.key).map { "key code \($0)" } ?? "NO KEY on this layout"
        print("\(name): \(sc.display)  (\(code))")
    }
    print("\(config.names.count) names, prefix \(config.prefix)")
    exit(config.warnings.isEmpty ? 0 : 1)
}

/// `ipa-keys --missing-defaults`: list what the built-in defaults have that
/// the config file (or FILE) lacks, e.g. new symbols from an update, as
/// lines to paste.
if CommandLine.arguments.dropFirst().first == "--missing-defaults" {
    let url = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : App.configURL
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { exit(0) }
    let lines = missingDefaults(in: Config.parse(text))
    if !lines.isEmpty {
        print("The default config has symbols or names yours lacks. To add them, open Edit Config")
        print("and copy each line below into the section above it (lines starting with # explain):")
        print("")
        for l in lines { print("  " + l) }
    }
    exit(0)
}

/// `ipa-keys --update-status [SOURCE [INSTALLED]]`: run the menu's update
/// check and print the result. Defaults to this app's recorded values.
if CommandLine.arguments.dropFirst().first == "--update-status" {
    let a = CommandLine.arguments
    let root = a.count > 2 ? a[2] : (App.sourceFolder ?? "")
    let installed = a.count > 3 ? a[3] : App.installedCommit
    let state = UpdateState(UpdateCheck.facts(source: root, installed: installed))
    print(state.label)
    print(state.explanation(source: root))
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
