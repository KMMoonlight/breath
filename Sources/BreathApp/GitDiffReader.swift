import Foundation

enum GitChangedFileKind: String, Equatable, Sendable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case untracked = "?"
}

struct GitChangedFile: Identifiable, Equatable, Sendable {
    let path: String
    let kind: GitChangedFileKind

    var id: String { path }
}

struct GitDiffReader: Sendable {
    func changedFiles(at workspacePath: String) async -> [GitChangedFile] {
        await Task.detached(priority: .utility) {
            changedFilesSynchronously(at: workspacePath)
        }.value
    }

    func diff(
        for file: GitChangedFile,
        at workspacePath: String
    ) async -> String? {
        await Task.detached(priority: .utility) {
            diffSynchronously(for: file, at: workspacePath)
        }.value
    }

    private func changedFilesSynchronously(
        at workspacePath: String
    ) -> [GitChangedFile] {
        guard let result = runGit(
            at: workspacePath,
            arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
        ), result.status == 0
        else {
            return []
        }

        let records = result.output.split(separator: 0, omittingEmptySubsequences: true)
        var files: [GitChangedFile] = []
        var recordIndex = 0
        while recordIndex < records.count {
            let record = records[recordIndex]
            guard record.count >= 4 else {
                recordIndex += 1
                continue
            }
            let status = record.prefix(2)
            let pathData = record.dropFirst(3)
            let path = String(decoding: pathData, as: UTF8.self)
            files.append(
                GitChangedFile(path: path, kind: kind(for: status))
            )

            if status.contains(UInt8(ascii: "R"))
                || status.contains(UInt8(ascii: "C"))
            {
                recordIndex += 1
            }
            recordIndex += 1
        }

        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func diffSynchronously(
        for file: GitChangedFile,
        at workspacePath: String
    ) -> String? {
        let arguments: [String]
        let acceptedStatuses: Set<Int32>
        if file.kind == .untracked {
            arguments = [
                "--no-pager",
                "diff",
                "--no-index",
                "--no-ext-diff",
                "--no-textconv",
                "--no-color",
                "--",
                "/dev/null",
                file.path,
            ]
            acceptedStatuses = [0, 1]
        } else {
            arguments = [
                "--no-pager",
                "diff",
                "--no-ext-diff",
                "--no-textconv",
                "--no-color",
                "HEAD",
                "--",
                file.path,
            ]
            acceptedStatuses = [0]
        }

        guard let result = runGit(at: workspacePath, arguments: arguments),
              acceptedStatuses.contains(result.status)
        else {
            return nil
        }
        return String(decoding: result.output, as: UTF8.self)
    }

    private func kind(for status: Data.SubSequence) -> GitChangedFileKind {
        if status == Data("??".utf8) { return .untracked }
        if status.contains(UInt8(ascii: "D")) { return .deleted }
        if status.contains(UInt8(ascii: "A")) { return .added }
        return .modified
    }

    private func runGit(
        at workspacePath: String,
        arguments: [String]
    ) -> (status: Int32, output: Data)? {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", workspacePath] + arguments
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            _ = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, outputData)
        } catch {
            return nil
        }
    }
}
