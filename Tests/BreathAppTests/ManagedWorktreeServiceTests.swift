import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Managed worktree service")
struct ManagedWorktreeServiceTests {
    @Test("creates a linked checkout bound to the requested task branch")
    func createsBranchBackedWorktree() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        let worktree = try await service.create(
            workspace: Workspace(
                id: workspaceID,
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: sessionID,
            branchName: "task/123"
        )

        let expectedRoot = fixture.managedRootURL
            .resolvingSymlinksInPath()
            .appendingPathComponent(workspaceID.rawValue.uuidString)
            .appendingPathComponent(sessionID.rawValue.uuidString)
            .path
        #expect(worktree.rootPath == expectedRoot)
        #expect(worktree.workspaceRelativePath == "apps/client")
        #expect(worktree.branchName == "task/123")
        #expect(
            try fixture.git([
                "-C", worktree.rootPath,
                "branch", "--show-current",
            ]).trimmingCharacters(in: .whitespacesAndNewlines)
                == "task/123"
        )
        #expect(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: worktree.workingDirectory)
                    .appendingPathComponent("tracked.txt")
                    .path
            )
        )
        #expect(await service.isAvailable(worktree))
    }

    @Test("checks out an existing local task branch without moving it")
    func checksOutExistingTaskBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "task/existing",
        ])
        let expectedCommit = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "rev-parse", "task/existing",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        let worktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/existing"
        )

        #expect(worktree.baselineCommit == expectedCommit)
        #expect(
            try fixture.git([
                "-C", worktree.rootPath,
                "branch", "--show-current",
            ]).trimmingCharacters(in: .whitespacesAndNewlines)
                == "task/existing"
        )
    }

    @Test("removing a clean worktree preserves its task branch")
    func cleanRemovalPreservesTaskBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/keep-after-removal"
        )

        try await service.remove(worktree)

        #expect(!FileManager.default.fileExists(atPath: worktree.rootPath))
        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "show-ref", "--verify", "--quiet",
                "refs/heads/task/keep-after-removal",
            ]).isEmpty
        )
        #expect(!(await service.isAvailable(worktree)))
    }

    @Test("removal explicitly refuses a worktree with uncommitted changes")
    func dirtyWorktreeIsNotRemoved() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/dirty"
        )
        let changedFile = URL(fileURLWithPath: worktree.workingDirectory)
            .appendingPathComponent("uncommitted.txt")
        try Data("keep me".utf8).write(to: changedFile)

        await #expect(
            throws: ManagedWorktreeServiceError.worktreeContainsChanges
        ) {
            try await service.remove(worktree)
        }
        #expect(FileManager.default.fileExists(atPath: changedFile.path))
    }

    @Test("a locked worktree cannot be removed")
    func lockedWorktreeIsNotRemoved() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/locked"
        )
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "worktree", "lock", "--reason", "kept by test",
            worktree.rootPath,
        ])

        await #expect(
            throws: ManagedWorktreeServiceError.worktreeLocked(
                "kept by test"
            )
        ) {
            try await service.remove(worktree)
        }
        #expect(FileManager.default.fileExists(atPath: worktree.rootPath))
    }

    @Test("persisted owner identifiers must match the managed path")
    func mismatchedOwnerMetadataIsRejected() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/owned"
        )
        let forgedMetadata = ManagedWorktree(
            workspaceID: WorkspaceID(rawValue: UUID()),
            workSessionID: worktree.workSessionID,
            rootPath: worktree.rootPath,
            gitCommonDirectory: worktree.gitCommonDirectory,
            baselineCommit: worktree.baselineCommit,
            workspaceRelativePath: worktree.workspaceRelativePath,
            branchName: worktree.branchName
        )

        #expect(!(await service.isAvailable(forgedMetadata)))
        await #expect(
            throws: ManagedWorktreeServiceError.unsafeManagedPath(
                worktree.rootPath
            )
        ) {
            try await service.remove(forgedMetadata)
        }
        #expect(FileManager.default.fileExists(atPath: worktree.rootPath))
    }

    @Test("checkout uses a fresh empty hooks directory")
    func checkoutDoesNotReuseMutableHooksDirectory() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let sharedHooksURL = fixture.managedRootURL
            .appendingPathComponent(".disabled-hooks", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sharedHooksURL,
            withIntermediateDirectories: true
        )
        let plantedHookURL = sharedHooksURL.appendingPathComponent(
            "post-checkout"
        )
        try Data(
            "#!/bin/sh\ntouch planted-hook-ran\n".utf8
        ).write(to: plantedHookURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: plantedHookURL.path
        )
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        let worktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/empty-hooks"
        )

        #expect(
            !FileManager.default.fileExists(
                atPath: URL(
                    fileURLWithPath: worktree.rootPath,
                    isDirectory: true
                ).appendingPathComponent("planted-hook-ran").path
            )
        )
    }

    @Test("a failed git add is rolled back without leaving a managed checkout")
    func failedGitAddRollsBackManagedCheckout() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL,
            gitExecutableURL: try fixture.gitWrapperFailingAfterWorktreeAdd()
        )
        let expectedRoot = fixture.managedRootURL
            .resolvingSymlinksInPath()
            .appendingPathComponent(workspaceID.rawValue.uuidString)
            .appendingPathComponent(sessionID.rawValue.uuidString)
            .path

        await #expect(throws: ManagedWorktreeServiceError.self) {
            try await service.create(
                workspace: Workspace(
                    id: workspaceID,
                    path: fixture.workspaceURL.path,
                    displayName: "client"
                ),
                workSessionID: sessionID,
                branchName: "task/reported-failure"
            )
        }

        #expect(!FileManager.default.fileExists(atPath: expectedRoot))
        #expect(
            try !fixture.git([
                "-C", fixture.repositoryURL.path,
                "worktree", "list", "--porcelain",
            ]).contains(expectedRoot)
        )
    }

    @Test("removing an externally deleted checkout also clears git metadata")
    func missingCheckoutRemovalClearsGitMetadata() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/missing-checkout"
        )
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: worktree.rootPath, isDirectory: true)
        )

        try await service.remove(worktree)

        #expect(
            try !fixture.git([
                "-C", fixture.repositoryURL.path,
                "worktree", "list", "--porcelain",
            ]).contains(worktree.rootPath)
        )
    }
}

private struct GitWorktreeFixture {
    let rootURL: URL
    let repositoryURL: URL
    let workspaceURL: URL
    let managedRootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-managed-worktree-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        repositoryURL = rootURL.appendingPathComponent("repository", isDirectory: true)
        workspaceURL = repositoryURL
            .appendingPathComponent("apps/client", isDirectory: true)
        managedRootURL = rootURL.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        _ = try git(["init", repositoryURL.path])
        try Data("initial".utf8).write(
            to: workspaceURL.appendingPathComponent("tracked.txt")
        )
        _ = try git(["-C", repositoryURL.path, "add", "."])
        _ = try git([
            "-C", repositoryURL.path,
            "-c", "user.name=Breath Tests",
            "-c", "user.email=breath@example.invalid",
            "commit", "-m", "initial",
        ])
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func gitWrapperFailingAfterWorktreeAdd() throws -> URL {
        let wrapperURL = rootURL.appendingPathComponent("git-wrapper")
        let script = """
        #!/bin/sh
        /usr/bin/git "$@"
        exit_code=$?
        if [ "$exit_code" -eq 0 ]; then
          case " $* " in
            *" worktree add "*) exit 72 ;;
          esac
        fi
        exit "$exit_code"
        """
        try Data(script.utf8).write(to: wrapperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: wrapperURL.path
        )
        return wrapperURL
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitWorktreeFixtureError.commandFailed(
                arguments: arguments,
                exitCode: process.terminationStatus,
                output: output + error
            )
        }
        return output
    }
}

private enum GitWorktreeFixtureError: Error {
    case commandFailed(arguments: [String], exitCode: Int32, output: String)
}
