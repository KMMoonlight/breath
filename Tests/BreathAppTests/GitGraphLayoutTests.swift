import Foundation
import Testing
@testable import BreathApp

@Suite("Git graph layout")
struct GitGraphLayoutTests {
    @Test("merge commits expose distinct parent lanes and reconnect topology")
    func laysOutMergeTopology() throws {
        let root = GitRootID(rawValue: "/tmp/repository")
        let commits = [
            commit("merge", parents: ["left", "right"], root: root),
            commit("left", parents: ["base"], root: root),
            commit("right", parents: ["base"], root: root),
            commit("base", parents: [], root: root),
        ]

        let layout = GitGraphLayout(commits: commits)
        let merge = try #require(layout.rows[commits[0].id])
        let left = try #require(layout.rows[commits[1].id])
        let right = try #require(layout.rows[commits[2].id])
        let base = try #require(layout.rows[commits[3].id])

        #expect(merge.parentSegments.count == 2)
        #expect(Set(merge.parentSegments.map(\.toLane)) == [0, 1])
        #expect(merge.laneCount >= 2)
        #expect(!merge.connectsFromPreviousRow)
        #expect(left.connectsFromPreviousRow)
        #expect(right.nodeLane == 1)
        #expect(right.connectsFromPreviousRow)
        #expect(base.connectsFromPreviousRow)
        #expect(right.parentSegments == [
            GitGraphSegment(fromLane: 1, toLane: 0, isParentEdge: true),
        ])
    }

    @Test("all-repositories rows never connect commits from different roots")
    func keepsRootsIndependent() throws {
        let firstRoot = GitRootID(rawValue: "/tmp/first")
        let secondRoot = GitRootID(rawValue: "/tmp/second")
        let commits = [
            commit("first-head", parents: ["first-base"], root: firstRoot),
            commit("second-head", parents: ["second-base"], root: secondRoot),
            commit("first-base", parents: [], root: firstRoot),
            commit("second-base", parents: [], root: secondRoot),
        ]

        let layout = GitGraphLayout(commits: commits)

        #expect(layout.rows[commits[0].id]?.nodeLane == 0)
        #expect(layout.rows[commits[1].id]?.nodeLane == 0)
        #expect(layout.rows[commits[0].id]?.laneCount == 1)
        #expect(layout.rows[commits[1].id]?.laneCount == 1)
        #expect(layout.rows[commits[0].id]?.connectsFromPreviousRow == false)
        #expect(layout.rows[commits[1].id]?.connectsFromPreviousRow == false)
        #expect(layout.rows[commits[2].id]?.connectsFromPreviousRow == true)
        #expect(layout.rows[commits[3].id]?.connectsFromPreviousRow == true)
    }

    private func commit(
        _ objectID: String,
        parents: [String],
        root: GitRootID
    ) -> GitCommitSummary {
        GitCommitSummary(
            objectID: objectID,
            parentIDs: parents,
            authorName: "Breath",
            authorEmail: "breath@example.com",
            authoredAt: nil,
            decorations: [],
            subject: objectID,
            body: "",
            rootID: root
        )
    }
}
