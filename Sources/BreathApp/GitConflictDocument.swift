import Foundation

enum GitConflictResolutionChoice: Sendable {
    case ours
    case theirs
    case both
    case ignore
}

struct GitConflictBlock: Equatable, Identifiable, Sendable {
    let id: String
    let startLine: Int
    let endLine: Int
    let ours: [String]
    let theirs: [String]
}

struct GitConflictDocument: Equatable, Sendable {
    let contents: String
    let blocks: [GitConflictBlock]

    private let lines: [String]

    init(contents: String) {
        self.contents = contents
        lines = contents.components(separatedBy: "\n")
        blocks = Self.parse(lines)
    }

    func resolving(
        _ block: GitConflictBlock,
        with choice: GitConflictResolutionChoice
    ) -> String {
        guard block.startLine >= 0,
              block.endLine < lines.count,
              block.startLine <= block.endLine
        else {
            return contents
        }
        let replacement: [String] = switch choice {
        case .ours: block.ours
        case .theirs: block.theirs
        case .both: block.ours + block.theirs
        case .ignore: []
        }
        var resolved = lines
        resolved.replaceSubrange(
            block.startLine...block.endLine,
            with: replacement
        )
        return resolved.joined(separator: "\n")
    }

    private static func parse(_ lines: [String]) -> [GitConflictBlock] {
        var blocks: [GitConflictBlock] = []
        var index = 0
        while index < lines.count {
            guard lines[index].hasPrefix("<<<<<<<") else {
                index += 1
                continue
            }
            let start = index
            var baseMarker: Int?
            var separator: Int?
            var end: Int?
            index += 1
            while index < lines.count {
                if lines[index].hasPrefix("|||||||") {
                    baseMarker = index
                } else if lines[index].hasPrefix("=======") {
                    separator = index
                } else if lines[index].hasPrefix(">>>>>>>") {
                    end = index
                    break
                }
                index += 1
            }
            guard let separator, let end else {
                break
            }
            let oursEnd = max(start + 1, (baseMarker ?? separator))
            let ours = Array(lines[(start + 1)..<oursEnd])
            let theirs = Array(lines[(separator + 1)..<end])
            let source = lines[start...end].joined(separator: "\n")
            blocks.append(
                GitConflictBlock(
                    id: stableID(source),
                    startLine: start,
                    endLine: end,
                    ours: ours,
                    theirs: theirs
                )
            )
            index = end + 1
        }
        return blocks
    }

    private static func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
