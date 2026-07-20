import Foundation
import Testing
@testable import BreathApp

@Suite("Git diff reader", .serialized)
struct GitDiffReaderTests {
    @Test("a workspace lists its added, modified, deleted, and untracked files")
    func changedFiles() async throws {
        let repository = try GitDiffTestRepository()
        defer { repository.remove() }

        try repository.write("before\n", to: "modified.txt")
        try repository.write("removed\n", to: "deleted.txt")
        try repository.runGit(["add", "modified.txt", "deleted.txt"])
        try repository.commit("Initial")

        try repository.write("after\n", to: "modified.txt")
        try repository.remove("deleted.txt")
        try repository.write("added\n", to: "added.txt")
        try repository.runGit(["add", "added.txt"])
        try repository.write("untracked\n", to: "untracked.txt")

        let files = await GitDiffReader().changedFiles(at: repository.path)

        #expect(
            files == [
                GitChangedFile(path: "added.txt", kind: .added),
                GitChangedFile(path: "deleted.txt", kind: .deleted),
                GitChangedFile(path: "modified.txt", kind: .modified),
                GitChangedFile(path: "untracked.txt", kind: .untracked),
            ]
        )
    }

    @Test("a changed file returns its unified diff")
    func changedFileDiff() async throws {
        let repository = try GitDiffTestRepository()
        defer { repository.remove() }

        try repository.write("before\n", to: "notes.txt")
        try repository.runGit(["add", "notes.txt"])
        try repository.commit("Initial")
        try repository.write("after\n", to: "notes.txt")
        let file = GitChangedFile(path: "notes.txt", kind: .modified)

        let diff = await GitDiffReader().diff(for: file, at: repository.path)

        #expect(diff?.contains("--- a/notes.txt") == true)
        #expect(diff?.contains("+++ b/notes.txt") == true)
        #expect(diff?.contains("-before") == true)
        #expect(diff?.contains("+after") == true)
    }

    @Test("an untracked file returns a unified diff against an empty file")
    func untrackedFileDiff() async throws {
        let repository = try GitDiffTestRepository()
        defer { repository.remove() }

        try repository.write("new line\n", to: "new.txt")
        let file = GitChangedFile(path: "new.txt", kind: .untracked)

        let diff = await GitDiffReader().diff(for: file, at: repository.path)

        #expect(diff?.contains("+++ b/new.txt") == true)
        #expect(diff?.contains("+new line") == true)
    }
}

private struct GitDiffTestRepository {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-git-diff-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        try runGit(["init", "-b", "main"])
    }

    var path: String { directory.path }

    func write(_ contents: String, to path: String) throws {
        try Data(contents.utf8).write(to: directory.appendingPathComponent(path))
    }

    func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(path))
    }

    func commit(_ message: String) throws {
        try runGit([
            "-c", "user.name=Breath Tests",
            "-c", "user.email=breath-tests@example.invalid",
            "commit", "-m", message,
        ])
    }

    func runGit(_ arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitDiffTestError.commandFailed(
                String(decoding: outputData + errorData, as: UTF8.self)
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum GitDiffTestError: Error {
    case commandFailed(String)
}
