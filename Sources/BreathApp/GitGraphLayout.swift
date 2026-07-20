import Foundation

struct GitGraphSegment: Equatable, Sendable {
    let fromLane: Int
    let toLane: Int
    let isParentEdge: Bool
}

struct GitGraphRow: Equatable, Sendable {
    let nodeLane: Int
    let laneCount: Int
    let connectsFromPreviousRow: Bool
    let segments: [GitGraphSegment]

    var parentSegments: [GitGraphSegment] {
        segments.filter(\.isParentEdge)
    }
}

struct GitGraphLayout: Equatable, Sendable {
    let rows: [String: GitGraphRow]

    init(commits: [GitCommitSummary]) {
        var lanesByRoot: [GitRootID: [String]] = [:]
        var resolvedRows: [String: GitGraphRow] = [:]

        for commit in commits {
            var incoming = lanesByRoot[commit.rootID] ?? []
            let nodeLane: Int
            let connectsFromPreviousRow: Bool
            if let existing = incoming.firstIndex(of: commit.objectID) {
                nodeLane = existing
                connectsFromPreviousRow = true
            } else {
                nodeLane = 0
                connectsFromPreviousRow = false
                incoming.insert(commit.objectID, at: 0)
            }

            var outgoing = incoming
            outgoing.remove(at: nodeLane)
            var insertionLane = min(nodeLane, outgoing.count)
            for parent in commit.parentIDs {
                if !outgoing.contains(parent) {
                    outgoing.insert(parent, at: insertionLane)
                    insertionLane += 1
                }
            }

            var segments: [GitGraphSegment] = []
            for (fromLane, objectID) in incoming.enumerated()
                where objectID != commit.objectID
            {
                if let toLane = outgoing.firstIndex(of: objectID) {
                    segments.append(
                        GitGraphSegment(
                            fromLane: fromLane,
                            toLane: toLane,
                            isParentEdge: false
                        )
                    )
                }
            }
            for parent in commit.parentIDs {
                if let toLane = outgoing.firstIndex(of: parent) {
                    segments.append(
                        GitGraphSegment(
                            fromLane: nodeLane,
                            toLane: toLane,
                            isParentEdge: true
                        )
                    )
                }
            }
            resolvedRows[commit.id] = GitGraphRow(
                nodeLane: nodeLane,
                laneCount: max(1, incoming.count, outgoing.count),
                connectsFromPreviousRow: connectsFromPreviousRow,
                segments: segments
            )
            lanesByRoot[commit.rootID] = outgoing
        }
        rows = resolvedRows
    }
}
