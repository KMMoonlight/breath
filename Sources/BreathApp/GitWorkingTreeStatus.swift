import Foundation

enum GitWorkingTreeState: Equatable, Sendable {
    case repository(GitWorkingTreeStatus)
    case notRepository
    case unavailable
}

struct GitWorkingTreeStatus: Equatable, Sendable {
    let branch: String
    let modifiedCount: Int
    let addedCount: Int
    let deletedCount: Int
    let untrackedCount: Int
    let aheadCount: Int
    let behindCount: Int

    var isClean: Bool {
        modifiedCount == 0
            && addedCount == 0
            && deletedCount == 0
            && untrackedCount == 0
    }
}

struct GitWorkingTreeStatusReader: Sendable {
    func read(at workspacePath: String) async -> GitWorkingTreeState {
        await Task.detached(priority: .utility) {
            readSynchronously(at: workspacePath)
        }.value
    }

    private func readSynchronously(at workspacePath: String) -> GitWorkingTreeState {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C",
            workspacePath,
            "status",
            "--porcelain=v2",
            "--branch",
            "--untracked-files=normal",
        ]
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            _ = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return .notRepository }
            return .repository(
                GitPorcelainV2StatusParser().parse(
                    String(decoding: outputData, as: UTF8.self)
                )
            )
        } catch {
            return .unavailable
        }
    }
}

struct GitPorcelainV2StatusParser: Sendable {
    func parse(_ output: String) -> GitWorkingTreeStatus {
        var branch = "HEAD"
        var objectID = ""
        var modifiedCount = 0
        var addedCount = 0
        var deletedCount = 0
        var untrackedCount = 0
        var aheadCount = 0
        var behindCount = 0

        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                branch = String(line.dropFirst("# branch.head ".count))
                continue
            }
            if line.hasPrefix("# branch.oid ") {
                objectID = String(line.dropFirst("# branch.oid ".count))
                continue
            }
            if line.hasPrefix("# branch.ab ") {
                let counts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                aheadCount = parseCount(counts.first, prefix: "+")
                behindCount = parseCount(counts.dropFirst().first, prefix: "-")
                continue
            }
            if line.hasPrefix("? ") {
                untrackedCount += 1
                continue
            }
            guard line.hasPrefix("1 ")
                    || line.hasPrefix("2 ")
                    || line.hasPrefix("u ")
            else {
                continue
            }
            let fields = line.split(separator: " ", maxSplits: 2)
            guard fields.count > 1 else { continue }
            let state = fields[1]
            if state.contains("A") { addedCount += 1 }
            if state.contains("D") { deletedCount += 1 }
            if state.contains("M")
                || state.contains("T")
                || state.contains("R")
                || state.contains("C")
                || line.hasPrefix("u ")
            {
                modifiedCount += 1
            }
        }

        if branch == "(detached)", !objectID.isEmpty {
            branch = String(objectID.prefix(7))
        }
        return GitWorkingTreeStatus(
            branch: branch,
            modifiedCount: modifiedCount,
            addedCount: addedCount,
            deletedCount: deletedCount,
            untrackedCount: untrackedCount,
            aheadCount: aheadCount,
            behindCount: behindCount
        )
    }

    private func parseCount(_ value: Substring?, prefix: Character) -> Int {
        guard let value, value.first == prefix else { return 0 }
        return Int(value.dropFirst()) ?? 0
    }
}
