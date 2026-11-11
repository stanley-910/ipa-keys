import Foundation

/// Appends timestamped lines to ~/.local/state/ipa-keys/ipa-keys.log.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/ipa-keys/ipa-keys.log")
    private static let queue = DispatchQueue(label: "ipa-keys.log")
    private static var handle: FileHandle?
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Opens the log, moving a big old one to ipa-keys.log.old.
    static func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000 {
            let old = url.appendingPathExtension("old")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    static func write(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            if let handle { try? handle.write(contentsOf: Data(line.utf8)) } else { FileHandle.standardError.write(Data(line.utf8)) }
        }
    }

    /// Text with each code point spelled out, since marks are invisible alone.
    static func show(_ s: String) -> String {
        let codes = s.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        return "\"\(s)\" (\(codes))"
    }
}
