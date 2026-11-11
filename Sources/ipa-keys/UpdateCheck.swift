import Foundation
import IPAKeysCore

/// Gathers UpdateFacts with git. Only `git fetch` touches anything, and it
/// only updates remote-tracking refs: the working tree is never changed.
/// Blocking: call off the main thread and off the tap's thread.
enum UpdateCheck {
    static let fetchTimeout: TimeInterval = 20
    static let localTimeout: TimeInterval = 5

    static func facts(source root: String, installed: String?) -> UpdateFacts {
        var f = UpdateFacts()
        f.installed = installed
        // /usr/bin/git is a stub that pops up an installer when the tools
        // are missing; xcode-select -p only answers.
        if run("/usr/bin/xcode-select", ["-p"], timeout: localTimeout)?.status != 0 {
            f.toolsMissing = true
            return f
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue,
              git(["rev-parse", "--git-dir"], root)?.status == 0
        else {
            f.sourceMissing = true
            return f
        }
        f.hasRemote = !(git(["remote"], root)?.out.isEmpty ?? true)
        guard f.hasRemote else { return f }
        guard let up = git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], root), up.status == 0 else {
            f.upstream = nil
            return f
        }
        f.upstream = up.out
        if let r = git(["fetch", "--quiet", "--no-write-fetch-head"], root, timeout: fetchTimeout) {
            if r.status != 0 {
                f.fetchError = r.err.split(separator: "\n").first.map(String.init) ?? "git fetch failed (\(r.status))"
            }
        } else {
            f.fetchError = "no answer from the remote in \(Int(fetchTimeout)) s"
        }
        // Tracked files that differ from HEAD, staged or not (as update.sh checks).
        f.changedFiles = (git(["diff", "--name-only", "HEAD"], root)?.out ?? "")
            .split(separator: "\n").map(String.init)
        if let counts = git(["rev-list", "--left-right", "--count", "HEAD...@{u}"], root)?.out {
            let parts = counts.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
            if parts.count == 2 { f.ahead = parts[0]; f.behind = parts[1] }
        }
        f.head = git(["rev-parse", "HEAD"], root)?.out ?? ""
        return f
    }

    private static func git(_ args: [String], _ root: String, timeout: TimeInterval = localTimeout)
        -> (status: Int32, out: String, err: String)?
    {
        run("/usr/bin/git", ["-C", root] + args, timeout: timeout)
    }

    /// Runs a command with no terminal and no way to ask for a password,
    /// killing it after `timeout`. Nil when it timed out or could not start.
    static func run(_ tool: String, _ args: [String], timeout: TimeInterval) -> (status: Int32, out: String, err: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_ASKPASS"] = "/usr/bin/false"
        env["SSH_ASKPASS"] = "/usr/bin/false"
        env["SSH_ASKPASS_REQUIRE"] = "never"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        // Read while it runs so a full pipe can't stall it.
        var outData = Data(), errData = Data()
        let readers = DispatchGroup()
        DispatchQueue.global().async(group: readers) { outData = out.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(group: readers) { errData = err.fileHandleForReading.readDataToEndOfFile() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 2)
            return nil
        }
        _ = readers.wait(timeout: .now() + 2)
        let trim = { (d: Data) in String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        return (p.terminationStatus, trim(outData), trim(errData))
    }
}
