import Foundation
import Testing
@testable import BreathApp

@Suite("Git working tree status", .serialized)
struct GitWorkingTreeStatusTests {
    @Test("a workspace outside a Git repository is identified")
    func nonRepositoryWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-git-status-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = await GitWorkingTreeStatusReader().read(at: directory.path)

        #expect(state == .notRepository)
    }

    @Test("a Git workspace reports its branch and working tree changes")
    func repositoryStatus() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-git-status-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        try runGit(["init", "-b", "main"], at: directory)
        try Data("tracked\n".utf8).write(
            to: directory.appendingPathComponent("tracked.txt")
        )
        try Data("removed\n".utf8).write(
            to: directory.appendingPathComponent("removed.txt")
        )
        try runGit(["add", "tracked.txt", "removed.txt"], at: directory)
        try runGit(
            [
                "-c", "user.name=Breath Tests",
                "-c", "user.email=breath-tests@example.invalid",
                "commit", "-m", "Initial",
            ],
            at: directory
        )

        try Data("modified\n".utf8).write(
            to: directory.appendingPathComponent("tracked.txt")
        )
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("removed.txt")
        )
        try Data("added\n".utf8).write(
            to: directory.appendingPathComponent("added.txt")
        )
        try runGit(["add", "added.txt"], at: directory)
        try Data("untracked\n".utf8).write(
            to: directory.appendingPathComponent("untracked.txt")
        )

        let state = await GitWorkingTreeStatusReader().read(at: directory.path)

        #expect(
            state == .repository(
                GitWorkingTreeStatus(
                    branch: "main",
                    modifiedCount: 1,
                    addedCount: 1,
                    deletedCount: 1,
                    untrackedCount: 1,
                    aheadCount: 0,
                    behindCount: 0
                )
            )
        )
    }

    @Test("porcelain branch metadata reports upstream divergence")
    func upstreamDivergence() {
        let status = GitPorcelainV2StatusParser().parse(
            """
            # branch.oid 0123456789abcdef
            # branch.head main
            # branch.upstream origin/main
            # branch.ab +1 -2

            """
        )

        #expect(
            status == GitWorkingTreeStatus(
                branch: "main",
                modifiedCount: 0,
                addedCount: 0,
                deletedCount: 0,
                untrackedCount: 0,
                aheadCount: 1,
                behindCount: 2
            )
        )
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
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
            let message = String(decoding: outputData + errorData, as: UTF8.self)
            throw GitStatusTestError.commandFailed(message)
        }
    }
}

private enum GitStatusTestError: Error {
    case commandFailed(String)
}
