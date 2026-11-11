import Testing
@testable import IPAKeysCore

struct UpdateStatusTests {
    static let head = "db28650aa1b2c3d4e5f60718293a4b5c6d7e8f90"

    func facts(_ change: (inout UpdateFacts) -> Void = { _ in }) -> UpdateFacts {
        var f = UpdateFacts()
        f.head = Self.head
        f.installed = "db28650"
        change(&f)
        return f
    }

    @Test func upToDate() {
        let s = UpdateState(facts())
        #expect(s == .upToDate("db28650"))
        #expect(s.label == "Up to Date (db28650)")
        #expect(!s.canUpdate && !s.isProblem)
    }

    @Test func behindOffersTheUpdate() {
        let s = UpdateState(facts { $0.behind = 3 })
        #expect(s == .available(3))
        #expect(s.label == "Update Available (3)")
        #expect(s.canUpdate)
    }

    @Test func pulledButNotInstalled() {
        #expect(UpdateState(facts { $0.installed = "be6397b" }) == .needsInstall)
        #expect(UpdateState(facts { $0.installed = "be6397b" }).label == "Install Update")
        #expect(UpdateState(facts { $0.installed = "be6397b" }).canUpdate)
    }

    /// Built from uncommitted edits that have since been undone.
    @Test func dirtyBuildNeedsInstall() {
        #expect(UpdateState(facts { $0.installed = "db28650-dirty" }) == .needsInstall)
    }

    @Test func unknownInstalledCommitIsNotAnInstall() {
        #expect(UpdateState(facts { $0.installed = nil }) == .upToDate("db28650"))
        #expect(UpdateState(facts { $0.installed = "unknown" }) == .upToDate("db28650"))
    }

    @Test func behindBeatsNeedsInstall() {
        #expect(UpdateState(facts { $0.behind = 2; $0.installed = "be6397b" }) == .available(2))
    }

    @Test func localChangesBlock() {
        let s = UpdateState(facts { $0.changedFiles = ["README.md"]; $0.behind = 2 })
        #expect(s == .localChanges(["README.md"]))
        #expect(s.label == "Update: Local Changes")
        #expect(s.isProblem && !s.canUpdate)
        #expect(s.explanation(source: "/src").contains("  README.md"))
        #expect(s.explanation(source: "/src").contains("git -C \"/src\" checkout -- ."))
    }

    @Test func aheadAndDiverged() {
        #expect(UpdateState(facts { $0.ahead = 1 }) == .ahead(1))
        #expect(UpdateState(facts { $0.ahead = 1 }).label == "Update: Local Commits")
        let d = UpdateState(facts { $0.ahead = 1; $0.behind = 4 })
        #expect(d == .diverged(ahead: 1, behind: 4))
        #expect(d.label == "Update: Diverged")
        #expect(d.explanation(source: "/src").contains("1 local commit and 4 new"))
    }

    @Test func fetchFailure() {
        let s = UpdateState(facts { $0.fetchError = "timed out" })
        #expect(s == .offline("timed out"))
        #expect(s.label == "Update: Check Failed")
        #expect(s.isProblem)
    }

    /// Order: missing tools, missing folder, no remote, no upstream come
    /// before anything about commits.
    @Test func precedence() {
        #expect(UpdateState(facts { $0.toolsMissing = true; $0.sourceMissing = true }) == .toolsMissing)
        #expect(UpdateState(facts { $0.sourceMissing = true; $0.hasRemote = false }) == .sourceMissing)
        #expect(UpdateState(facts { $0.hasRemote = false; $0.upstream = nil }) == .noRemote)
        #expect(UpdateState(facts { $0.upstream = nil; $0.changedFiles = ["x"] }) == .noUpstream)
        #expect(UpdateState(facts { $0.changedFiles = ["x"]; $0.ahead = 2 }) == .localChanges(["x"]))
        #expect(UpdateState(facts { $0.ahead = 2; $0.fetchError = "e" }) == .ahead(2))
        #expect(UpdateState(facts { $0.fetchError = "e"; $0.behind = 1 }) == .offline("e"))
    }

    @Test func labelsAreShort() {
        let all: [UpdateState] = [.toolsMissing, .sourceMissing, .noRemote, .noUpstream, .localChanges(["a"]),
                                  .ahead(1), .diverged(ahead: 1, behind: 1), .offline("x"), .available(12),
                                  .needsInstall, .upToDate("db28650")]
        for s in all { #expect(s.label.count <= 24, "\(s.label)") }
    }
}
