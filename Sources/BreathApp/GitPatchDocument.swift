import Foundation

struct GitPatchDocument: Equatable, Sendable {
    let files: [GitPatchFile]

    init(patch: String) {
        files = GitPatchParser().parse(patch)
    }

    func fileID(matching path: String) -> GitPatchFile.ID? {
        files.first {
            $0.newPath == path || $0.oldPath == path
        }?.id
    }
}

enum GitPatchRemapper {
    static func requiresConfirmation(
        selectedPatch: String,
        currentPatch: String
    ) -> Bool {
        let selected = mutationLineCounts(selectedPatch)
        guard !selected.isEmpty else { return true }
        let current = mutationLineCounts(currentPatch)
        return selected.contains { signature, count in
            current[signature] != count
        }
    }

    private static func mutationLineCounts(_ patch: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            guard (line.hasPrefix("+") && !line.hasPrefix("+++"))
                    || (line.hasPrefix("-") && !line.hasPrefix("---"))
            else {
                continue
            }
            counts[String(line), default: 0] += 1
        }
        return counts
    }
}

struct GitPatchFile: Equatable, Identifiable, Sendable {
    var id: String { newPath ?? oldPath ?? header.hashValue.description }

    let oldPath: String?
    let newPath: String?
    let header: String
    let hunks: [GitPatchHunk]

    var patch: String {
        ([header] + hunks.map(\.text)).joined()
    }
}

struct GitPatchHunk: Equatable, Identifiable, Sendable {
    let id: UUID
    let header: String
    let oldStart: Int
    let newStart: Int
    let lines: [GitPatchLine]

    var text: String {
        header + lines.map(\.raw).joined()
    }

    func patch(fileHeader: String, selectedLineIDs: Set<UUID>? = nil) -> String {
        guard let selectedLineIDs else {
            return fileHeader + text
        }
        var transformed: [String] = []
        for line in lines {
            switch line.kind {
            case .context, .metadata:
                transformed.append(line.raw)
            case .addition:
                if selectedLineIDs.contains(line.id) {
                    transformed.append(line.raw)
                }
            case .deletion:
                if selectedLineIDs.contains(line.id) {
                    transformed.append(line.raw)
                } else {
                    transformed.append(" " + line.content + "\n")
                }
            }
        }
        let oldCount = transformed.reduce(0) { count, raw in
            raw.first == "+" ? count : count + (raw.first == "\\" ? 0 : 1)
        }
        let newCount = transformed.reduce(0) { count, raw in
            raw.first == "-" ? count : count + (raw.first == "\\" ? 0 : 1)
        }
        let rewrittenHeader = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
        return fileHeader + rewrittenHeader + transformed.joined()
    }
}

enum GitPatchLineKind: Equatable, Sendable {
    case context
    case addition
    case deletion
    case metadata
}

struct GitPatchLine: Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: GitPatchLineKind
    let raw: String

    var content: String {
        guard !raw.isEmpty else { return "" }
        return String(raw.dropFirst()).trimmingSuffix("\n")
    }
}

struct GitSideBySideRow: Equatable, Identifiable, Sendable {
    var id: String {
        "\(oldLine?.id.uuidString ?? "-"):\(newLine?.id.uuidString ?? "-")"
    }

    let oldLine: GitPatchLine?
    let newLine: GitPatchLine?
}

enum GitSideBySideLayout {
    static func rows(for lines: [GitPatchLine]) -> [GitSideBySideRow] {
        var rows: [GitSideBySideRow] = []
        var deletions: [GitPatchLine] = []
        var additions: [GitPatchLine] = []

        func flushChanges() {
            let rowCount = max(deletions.count, additions.count)
            guard rowCount > 0 else { return }
            for index in 0..<rowCount {
                rows.append(
                    GitSideBySideRow(
                        oldLine: deletions.indices.contains(index)
                            ? deletions[index]
                            : nil,
                        newLine: additions.indices.contains(index)
                            ? additions[index]
                            : nil
                    )
                )
            }
            deletions.removeAll(keepingCapacity: true)
            additions.removeAll(keepingCapacity: true)
        }

        for line in lines {
            switch line.kind {
            case .deletion:
                deletions.append(line)
            case .addition:
                additions.append(line)
            case .context, .metadata:
                flushChanges()
                rows.append(
                    GitSideBySideRow(oldLine: line, newLine: line)
                )
            }
        }
        flushChanges()
        return rows
    }
}

private struct GitPatchParser {
    func parse(_ patch: String) -> [GitPatchFile] {
        let lines = patch.linesKeepingTerminators
        var files: [GitPatchFile] = []
        var index = 0
        while index < lines.count {
            guard !Task.isCancelled else { return [] }
            guard lines[index].hasPrefix("diff --git ") else {
                index += 1
                continue
            }
            var headerLines: [String] = []
            var oldPath: String?
            var newPath: String?
            while index < lines.count,
                  !lines[index].hasPrefix("@@ "),
                  !(lines[index].hasPrefix("diff --git ") && !headerLines.isEmpty)
            {
                let line = lines[index]
                headerLines.append(line)
                if line.hasPrefix("--- ") {
                    oldPath = normalizePath(String(line.dropFirst(4)))
                } else if line.hasPrefix("+++ ") {
                    newPath = normalizePath(String(line.dropFirst(4)))
                }
                index += 1
            }
            var hunks: [GitPatchHunk] = []
            while index < lines.count, lines[index].hasPrefix("@@ ") {
                guard !Task.isCancelled else { return [] }
                let hunkHeader = lines[index]
                let ranges = parseRanges(hunkHeader)
                index += 1
                var hunkLines: [GitPatchLine] = []
                while index < lines.count,
                      !lines[index].hasPrefix("@@ "),
                      !lines[index].hasPrefix("diff --git ")
                {
                    guard !Task.isCancelled else { return [] }
                    let raw = lines[index]
                    let kind: GitPatchLineKind
                    switch raw.first {
                    case "+": kind = .addition
                    case "-": kind = .deletion
                    case " ": kind = .context
                    default: kind = .metadata
                    }
                    hunkLines.append(
                        GitPatchLine(
                            id: GitPatchStableID.uuid(
                                headerLines.joined()
                                    + hunkHeader
                                    + "\(hunkLines.count)"
                                    + raw
                            ),
                            kind: kind,
                            raw: raw
                        )
                    )
                    index += 1
                }
                hunks.append(
                    GitPatchHunk(
                        id: GitPatchStableID.uuid(
                            headerLines.joined()
                                + hunkHeader
                                + "\(hunks.count)"
                        ),
                        header: hunkHeader,
                        oldStart: ranges.oldStart,
                        newStart: ranges.newStart,
                        lines: hunkLines
                    )
                )
            }
            files.append(
                GitPatchFile(
                    oldPath: oldPath,
                    newPath: newPath,
                    header: headerLines.joined(),
                    hunks: hunks
                )
            )
        }
        return files
    }

    private func normalizePath(_ raw: String) -> String? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path != "/dev/null" else { return nil }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    private func parseRanges(_ header: String) -> (oldStart: Int, newStart: Int) {
        let parts = header.split(separator: " ")
        let oldStart = parts.count > 1
            ? Int(parts[1].dropFirst().split(separator: ",")[0]) ?? 1
            : 1
        let newStart = parts.count > 2
            ? Int(parts[2].dropFirst().split(separator: ",")[0]) ?? 1
            : 1
        return (oldStart, newStart)
    }
}

private enum GitPatchStableID {
    static func uuid(_ seed: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_11
        for byte in seed.utf8 {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211
            second &+= UInt64(byte)
            second ^= second << 13
            second ^= second >> 7
            second ^= second << 17
        }
        let bytes = withUnsafeBytes(of: first.bigEndian, Array.init)
            + withUnsafeBytes(of: second.bigEndian, Array.init)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension String {
    var linesKeepingTerminators: [String] {
        var result: [String] = []
        var start = startIndex
        while start < endIndex {
            if let newline = self[start...].firstIndex(of: "\n") {
                result.append(String(self[start...newline]))
                start = index(after: newline)
            } else {
                result.append(String(self[start...]))
                break
            }
        }
        return result
    }

    func trimmingSuffix(_ suffix: Character) -> String {
        last == suffix ? String(dropLast()) : self
    }
}
