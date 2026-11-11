import Foundation

/// Appends timestamped lines to ~/.local/state/ipa-keys/ipa-keys.log.
/// The folder is 0700 and the files 0600. The log rotates to
/// ipa-keys.log.old at 2 MB, also while running.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/ipa-keys/ipa-keys.log")
    static let limit = 2_000_000
    /// debug_log: also write typed names and inserted text.
    static var debug = false
    private static let queue = DispatchQueue(label: "ipa-keys.log")
    private static var handle: FileHandle?
    private static var size = 0
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func open() { queue.sync { reopen() } }

    /// On the log queue.
    private static func reopen() {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? handle?.close()
        handle = nil
        size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
        if size > limit {
            let old = url.appendingPathExtension("old")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: old.path)
            size = 0
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    static func write(_ message: String) {
        let data = Data("\(stamp.string(from: Date())) \(message)\n".utf8)
        queue.async {
            guard let handle else { return FileHandle.standardError.write(data) }
            try? handle.write(contentsOf: data)
            size += data.count
            if size > limit { reopen() }
        }
    }
}
