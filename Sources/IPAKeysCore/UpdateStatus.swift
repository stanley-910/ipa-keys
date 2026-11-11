/// What a check of the source folder found. Gathered with git elsewhere;
/// turned into a state here, so the rules can be tested without git.
public struct UpdateFacts: Equatable, Sendable {
    /// Apple's command line tools (git) are not installed.
    public var toolsMissing = false
    /// The recorded source folder is gone or is not a git checkout.
    public var sourceMissing = false
    public var hasRemote = true
    /// The branch HEAD follows on the remote, e.g. origin/main.
    public var upstream: String? = "origin/main"
    /// Why `git fetch` failed, if it did.
    public var fetchError: String?
    /// Tracked files changed by hand.
    public var changedFiles: [String] = []
    /// Commits on HEAD not on the upstream, and the other way round.
    public var ahead = 0
    public var behind = 0
    /// The full commit hash of HEAD.
    public var head = ""
    /// The commit the running app was built from, as recorded at build
    /// time ("db28650", "db28650-dirty"), or nil when unknown.
    public var installed: String?

    public init() {}
}

public enum UpdateState: Equatable, Sendable {
    case toolsMissing
    case sourceMissing
    case noRemote
    case noUpstream
    case localChanges([String])
    case ahead(Int)
    case diverged(ahead: Int, behind: Int)
    case offline(String)
    /// The remote has this many commits the source folder lacks.
    case available(Int)
    /// The source folder is newer than the running app (pulled, not installed).
    case needsInstall
    case upToDate(String)

    public init(_ f: UpdateFacts) {
        if f.toolsMissing { self = .toolsMissing; return }
        if f.sourceMissing { self = .sourceMissing; return }
        if !f.hasRemote { self = .noRemote; return }
        if f.upstream == nil { self = .noUpstream; return }
        if !f.changedFiles.isEmpty { self = .localChanges(f.changedFiles); return }
        if f.ahead > 0, f.behind > 0 { self = .diverged(ahead: f.ahead, behind: f.behind); return }
        if f.ahead > 0 { self = .ahead(f.ahead); return }
        if let e = f.fetchError { self = .offline(e); return }
        if f.behind > 0 { self = .available(f.behind); return }
        if let installed = f.installed, installed != "unknown" {
            let dirty = installed.hasSuffix("-dirty")
            let hash = dirty ? String(installed.dropLast("-dirty".count)) : installed
            // Built from changes that are no longer there, or from another commit.
            if dirty || hash.isEmpty || !f.head.hasPrefix(hash) { self = .needsInstall; return }
        }
        self = .upToDate(String(f.head.prefix(7)))
    }

    /// The menu item's title.
    public var label: String {
        switch self {
        case .toolsMissing: return "Update: Tools Missing"
        case .sourceMissing: return "Update: Source Missing"
        case .noRemote: return "Update: No Remote"
        case .noUpstream: return "Update: No Upstream"
        case .localChanges: return "Update: Local Changes"
        case .ahead: return "Update: Local Commits"
        case .diverged: return "Update: Diverged"
        case .offline: return "Update: Check Failed"
        case .available(let n): return "Update Available (\(n))"
        case .needsInstall: return "Install Update"
        case .upToDate(let c): return "Up to Date (\(c))"
        }
    }

    /// Choosing the item runs the update script.
    public var canUpdate: Bool {
        switch self {
        case .available, .needsInstall: return true
        default: return false
        }
    }

    /// Choosing the item explains what is wrong.
    public var isProblem: Bool {
        switch self {
        case .available, .needsInstall, .upToDate: return false
        default: return true
        }
    }

    /// The plain-English explanation behind a problem label.
    public func explanation(source root: String) -> String {
        let q = "\"\(root)\""
        switch self {
        case .toolsMissing:
            return "Apple's command line tools are missing, so ipa-keys can't check for updates.\n\nIn Terminal, run:\n  xcode-select --install\nand finish the window it opens."
        case .sourceMissing:
            return "The ipa-keys folder this copy was installed from is gone, or isn't a git copy:\n  \(root)\n\nTo update, download ipa-keys again (git clone) and run scripts/install.sh from the new folder."
        case .noRemote:
            return "The ipa-keys folder has nowhere to update from (no git remote).\n\nAsk for the ipa-keys address, then in Terminal run:\n  git -C \(q) remote add origin <address>"
        case .noUpstream:
            return "The ipa-keys folder isn't linked to a branch on the remote.\n\nIn Terminal, run:\n  git -C \(q) branch --set-upstream-to=origin/main"
        case .localChanges(let files):
            let list = files.prefix(8).map { "  " + $0 }.joined(separator: "\n") + (files.count > 8 ? "\n  …" : "")
            return "Files in the ipa-keys folder were changed by hand, and updating would overwrite them:\n\(list)\n\nYour settings file is not one of them; it lives in ~/.config/ipa-keys.\n\nTo undo those changes, in Terminal run:\n  git -C \(q) checkout -- ."
        case .ahead(let n):
            return "The ipa-keys folder has \(n) commit\(n == 1 ? "" : "s") that \(n == 1 ? "is" : "are") not on the remote, so there is nothing to download.\n\nTo install the folder as it is, in Terminal run:\n  \(root)/scripts/install.sh"
        case .diverged(let a, let b):
            return "The ipa-keys folder and the remote have both changed: \(a) local commit\(a == 1 ? "" : "s") and \(b) new on the remote. It can't simply move forward.\n\nAsk for help merging them."
        case .offline(let e):
            return "Couldn't reach the remote to check for updates:\n  \(e)\n\nCheck the internet connection; ipa-keys will check again later."
        case .available(let n):
            return "\(n) new commit\(n == 1 ? "" : "s") on the remote. Choose Update Available to download and install."
        case .needsInstall:
            return "The ipa-keys folder is newer than the running app. Choose Install Update to build and install it."
        case .upToDate(let c):
            return "ipa-keys is up to date (\(c))."
        }
    }
}
