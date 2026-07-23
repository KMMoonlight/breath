import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Managed worktree service")
struct ManagedWorktreeServiceTests {
    @Test("inventory cleanup summarizes Git failures without stderr")
    func inventoryCleanupUsesBriefGitFailureMessage() {
        let error = ManagedWorktreeServiceError.gitFailed(
            exitCode: 73,
            output: "fatal: secret repository detail"
        )

        #expect(
            error.inventoryErrorDescription
                == "Git 操作失败（退出码 73），未执行清理。"
        )
        #expect(!error.inventoryErrorDescription.contains("secret"))
    }

    @Test("lists the current branch and other worktree start branches")
    func listsWorktreeStartBranches() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let currentBranch = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "--show-current",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "feature/other",
        ])
        let headCommit = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "update-ref", "refs/remotes/origin/release", headCommit,
        ])
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "symbolic-ref",
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/release",
        ])
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        let startBranches = try await service.startBranches(
            for: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            )
        )

        #expect(
            startBranches.contains {
                $0.name == currentBranch
                    && $0.reference == "refs/heads/\(currentBranch)"
                    && $0.kind == .localBranch
                    && $0.isCurrent
            }
        )
        #expect(
            startBranches.contains {
                $0.name == "feature/other"
                    && $0.reference == "refs/heads/feature/other"
                    && $0.kind == .localBranch
                    && !$0.isCurrent
            }
        )
        #expect(
            startBranches.contains {
                $0.name == "origin/release"
                    && $0.reference == "refs/remotes/origin/release"
                    && $0.kind == .remoteBranch
            }
        )
        #expect(!startBranches.contains { $0.name == "origin/HEAD" })
    }

    @Test("inventory distinguishes a session checkout from a retained branch")
    func inventoryDistinguishesCheckoutFromRetainedBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let activeSessionID = WorkSessionID(rawValue: UUID())
        let removedSessionID = WorkSessionID(rawValue: UUID())
        let activeBranchName = ManagedWorktree.sessionBranchName(
            for: activeSessionID
        )
        let removedBranchName = ManagedWorktree.sessionBranchName(
            for: removedSessionID
        )
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let activeWorktree = try await service.create(
            workspace: workspace,
            workSessionID: activeSessionID,
            branchName: activeBranchName
        )
        let removedWorktree = try await service.create(
            workspace: workspace,
            workSessionID: removedSessionID,
            branchName: removedBranchName
        )
        try await service.remove(removedWorktree)
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "breath/not-a-session",
        ])

        let inventory = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: [activeWorktree]
        )

        #expect(
            inventory.items.contains {
                $0.branchName == activeBranchName
                    && $0.directoryPath == activeWorktree.rootPath
                    && $0.state == .tracked
            }
        )
        #expect(
            inventory.items.contains {
                $0.branchName == removedBranchName
                    && $0.directoryPath == nil
                    && $0.state == .branchOnly
            }
        )
        #expect(
            !inventory.items.contains {
                $0.branchName == "breath/not-a-session"
            }
        )
    }

    @Test("inventory retains repository discovery after workspace removal")
    func inventoryRetainsRepositoryAfterWorkspaceRemoval() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        try await service.remove(worktree)

        let inventory = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )

        #expect(
            inventory.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath == nil
                    && $0.state == .branchOnly
            }
        )
    }

    @Test("a retained inventory branch can be deleted")
    func deletesRetainedInventoryBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        try await service.remove(worktree)
        let beforeDeletion = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        let branchItem = try #require(
            beforeDeletion.items.first {
                $0.branchName == branchName && $0.state == .branchOnly
            }
        )

        try await service.deleteInventoryBranch(branchItem)

        let afterDeletion = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        #expect(
            !afterDeletion.items.contains {
                $0.branchName == branchName
            }
        )
    }

    @Test("an inventory branch that became checked out is not deleted")
    func refusesInventoryBranchThatBecameCheckedOut() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        try await service.remove(worktree)
        let inventory = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        let branchItem = try #require(
            inventory.items.first {
                $0.branchName == branchName && $0.state == .branchOnly
            }
        )
        let externalCheckout = fixture.rootURL.appendingPathComponent(
            "external-checkout",
            isDirectory: true
        )
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "worktree", "add", externalCheckout.path, branchName,
        ])

        await #expect(
            throws: ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "该分支已被 Git Worktree 检出，请刷新库存后重试。"
            )
        ) {
            try await service.deleteInventoryBranch(branchItem)
        }
    }

    @Test("an inventory branch that moved after scanning is not deleted")
    func refusesInventoryBranchThatMovedAfterScanning() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        try await service.remove(worktree)
        let beforeMove = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        let branchItem = try #require(
            beforeMove.items.first {
                $0.branchName == branchName && $0.state == .branchOnly
            }
        )
        let movedCommit = try fixture.createAlternateCommit()
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "update-ref", "refs/heads/\(branchName)", movedCommit,
        ])

        await #expect(throws: ManagedWorktreeServiceError.self) {
            try await service.deleteInventoryBranch(branchItem)
        }
        let afterAttempt = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        #expect(
            afterAttempt.items.contains {
                $0.branchName == branchName
                    && $0.state == .branchOnly
            }
        )
    }

    @Test("a clean orphaned checkout can be removed from inventory")
    func removesCleanOrphanedInventoryCheckout() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        let beforeDeletion = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: []
        )
        let checkoutItem = try #require(
            beforeDeletion.items.first {
                $0.directoryPath.map {
                    URL(fileURLWithPath: $0)
                        .resolvingSymlinksInPath()
                        .standardizedFileURL.path
                        == URL(fileURLWithPath: worktree.rootPath)
                            .resolvingSymlinksInPath()
                            .standardizedFileURL.path
                } == true
                    && $0.state == .orphanedCheckout
            }
        )

        try await service.deleteInventoryDirectory(
            checkoutItem,
            knownWorktrees: []
        )

        #expect(
            !FileManager.default.fileExists(atPath: worktree.rootPath)
        )
        let afterDeletion = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: []
        )
        #expect(
            afterDeletion.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath == nil
                    && $0.state == .branchOnly
            }
        )
    }

    @Test("a dirty orphaned checkout is not removed from inventory")
    func refusesDirtyOrphanedInventoryCheckout() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: ManagedWorktree.sessionBranchName(for: sessionID)
        )
        try Data("uncommitted".utf8).write(
            to: URL(
                fileURLWithPath: worktree.rootPath,
                isDirectory: true
            ).appendingPathComponent("untracked.txt")
        )
        let inventory = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: []
        )
        let checkoutItem = try #require(
            inventory.items.first {
                $0.directoryPath.map {
                    URL(fileURLWithPath: $0)
                        .resolvingSymlinksInPath()
                        .standardizedFileURL.path
                        == URL(fileURLWithPath: worktree.rootPath)
                            .resolvingSymlinksInPath()
                            .standardizedFileURL.path
                } == true
                    && $0.state == .orphanedCheckout
            }
        )

        await #expect(
            throws: ManagedWorktreeServiceError.worktreeContainsChanges
        ) {
            try await service.deleteInventoryDirectory(
                checkoutItem,
                knownWorktrees: []
            )
        }
        #expect(FileManager.default.fileExists(atPath: worktree.rootPath))
    }

    @Test("an orphaned checkout that became known is not removed")
    func refusesOrphanedCheckoutThatBecameKnown() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: ManagedWorktree.sessionBranchName(for: sessionID)
        )
        let inventory = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: []
        )
        let checkoutItem = try #require(
            inventory.items.first {
                $0.directoryPath.map {
                    URL(fileURLWithPath: $0)
                        .resolvingSymlinksInPath()
                        .standardizedFileURL.path
                        == URL(fileURLWithPath: worktree.rootPath)
                            .resolvingSymlinksInPath()
                            .standardizedFileURL.path
                } == true
                    && $0.state == .orphanedCheckout
            }
        )

        await #expect(
            throws: ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "该 Worktree 已重新关联工作会话，请刷新库存。"
            )
        ) {
            try await service.deleteInventoryDirectory(
                checkoutItem,
                knownWorktrees: [worktree]
            )
        }
        #expect(FileManager.default.fileExists(atPath: worktree.rootPath))
    }

    @Test("an unregistered residual directory is moved to Trash")
    func trashesUnregisteredInventoryDirectory() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let residualDirectory = fixture.managedRootURL
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: residualDirectory,
            withIntermediateDirectories: true
        )
        try Data("residual".utf8).write(
            to: residualDirectory.appendingPathComponent("keep.txt")
        )
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL,
            directoryTrash: RemovingTestWorktreeTrash()
        )
        let beforeDeletion = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        let directoryItem = try #require(
            beforeDeletion.items.first {
                $0.directoryPath == residualDirectory.path
                    && $0.state == .directoryOnly
            }
        )

        try await service.deleteInventoryDirectory(
            directoryItem,
            knownWorktrees: []
        )

        #expect(
            !FileManager.default.fileExists(
                atPath: residualDirectory.path
            )
        )
        let afterDeletion = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        #expect(
            !afterDeletion.items.contains {
                $0.directoryPath == residualDirectory.path
            }
        )
    }

    @Test("a valid Git checkout is never trashed as a directory residual")
    func refusesToTrashValidGitCheckout() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let checkoutDirectory = fixture.managedRootURL
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        _ = try fixture.git([
            "clone", "--quiet",
            fixture.repositoryURL.path,
            checkoutDirectory.path,
        ])
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL,
            directoryTrash: RemovingTestWorktreeTrash()
        )
        let inventory = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        let directoryItem = try #require(
            inventory.items.first {
                $0.directoryPath == checkoutDirectory.path
                    && $0.state == .directoryOnly
            }
        )

        await #expect(
            throws: ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "该目录仍是有效的 Git Worktree，请刷新库存后重试。"
            )
        ) {
            try await service.deleteInventoryDirectory(
                directoryItem,
                knownWorktrees: []
            )
        }
        #expect(
            FileManager.default.fileExists(atPath: checkoutDirectory.path)
        )
    }

    @Test("an inconclusive Git probe never trashes a directory residual")
    func refusesToTrashDirectoryWhenGitProbeFails() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let residualDirectory = fixture.managedRootURL
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: residualDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: residualDirectory.appendingPathComponent(
                ".git",
                isDirectory: true
            ),
            withIntermediateDirectories: false
        )
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL,
            gitExecutableURL: try fixture.gitWrapperRejectingAllCommands(),
            directoryTrash: RemovingTestWorktreeTrash()
        )
        let inventory = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        let directoryItem = try #require(
            inventory.items.first {
                $0.directoryPath == residualDirectory.path
                    && $0.state == .directoryOnly
            }
        )

        await #expect(
            throws: ManagedWorktreeServiceError.gitFailed(
                exitCode: 99,
                output: ""
            )
        ) {
            try await service.deleteInventoryDirectory(
                directoryItem,
                knownWorktrees: []
            )
        }
        #expect(
            FileManager.default.fileExists(atPath: residualDirectory.path)
        )
    }

    @Test("Git metadata casing follows the file system")
    func refusesToTrashDirectoryWithCaseVariantGitMetadata() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let residualDirectory = fixture.managedRootURL
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: residualDirectory.appendingPathComponent(
                ".GIT",
                isDirectory: true
            ),
            withIntermediateDirectories: true
        )
        let lowercaseMetadataPath = residualDirectory
            .appendingPathComponent(".git", isDirectory: true)
            .path
        guard FileManager.default.fileExists(
            atPath: lowercaseMetadataPath
        ) else {
            return
        }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL,
            gitExecutableURL: try fixture.gitWrapperRejectingAllCommands(),
            directoryTrash: RemovingTestWorktreeTrash()
        )
        let inventory = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )
        let directoryItem = try #require(
            inventory.items.first {
                $0.directoryPath == residualDirectory.path
                    && $0.state == .directoryOnly
            }
        )

        await #expect(
            throws: ManagedWorktreeServiceError.gitFailed(
                exitCode: 99,
                output: ""
            )
        ) {
            try await service.deleteInventoryDirectory(
                directoryItem,
                knownWorktrees: []
            )
        }
        #expect(
            FileManager.default.fileExists(atPath: residualDirectory.path)
        )
    }

    @Test("inventory reports a missing known checkout once as unavailable")
    func inventoryReportsMissingKnownCheckoutOnce() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        try await service.remove(worktree)

        let inventory = await service.inventory(
            workspaces: [],
            knownWorktrees: [worktree]
        )
        let sessionItems = inventory.items.filter {
            $0.branchName == branchName
        }

        #expect(sessionItems.count == 1)
        #expect(sessionItems.first?.directoryPath == nil)
        #expect(sessionItems.first?.state == .unavailable)
    }

    @Test("inventory keeps a switched known checkout as one tracked session")
    func inventoryKeepsSwitchedKnownCheckoutTracked() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        _ = try fixture.git([
            "-C", worktree.rootPath,
            "switch", "-c", "feature/switched",
        ])

        let inventory = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: [worktree]
        )
        let checkoutItems = inventory.items.filter {
            $0.directoryPath == worktree.rootPath
        }

        #expect(checkoutItems.count == 1)
        #expect(checkoutItems.first?.branchName == branchName)
        #expect(checkoutItems.first?.state == .tracked)
    }

    @Test("inventory separates a stale session path from the actual checkout")
    func inventorySeparatesStalePathFromActualCheckout() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        let staleWorktree = ManagedWorktree(
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID,
            rootPath: fixture.managedRootURL
                .appendingPathComponent("stale", isDirectory: true).path,
            gitCommonDirectory: worktree.gitCommonDirectory,
            baselineCommit: worktree.baselineCommit,
            workspaceRelativePath: worktree.workspaceRelativePath,
            branchName: worktree.branchName,
            createdBranch: worktree.createdBranch
        )

        let inventory = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: [staleWorktree]
        )

        #expect(
            inventory.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath.map {
                        URL(fileURLWithPath: $0)
                            .resolvingSymlinksInPath()
                            .standardizedFileURL.path
                            == URL(fileURLWithPath: worktree.rootPath)
                                .resolvingSymlinksInPath()
                                .standardizedFileURL.path
                    } == true
                    && $0.state == .orphanedCheckout
            }
        )
        #expect(
            inventory.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath == nil
                    && $0.state == .unavailable
            }
        )
    }

    @Test("inventory uses a known checkout when its workspace is unavailable")
    func inventoryUsesKnownCheckoutWhenWorkspaceUnavailable() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        let unavailableWorkspace = Workspace(
            id: workspace.id,
            path: fixture.rootURL.appendingPathComponent("missing").path,
            displayName: workspace.displayName
        )

        let inventory = await service.inventory(
            workspaces: [unavailableWorkspace],
            knownWorktrees: [worktree]
        )

        #expect(
            inventory.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath == worktree.rootPath
                    && $0.state == .tracked
            }
        )

        let unavailableWorktree = ManagedWorktree(
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID,
            rootPath: worktree.rootPath,
            gitCommonDirectory: worktree.gitCommonDirectory,
            baselineCommit: worktree.baselineCommit,
            workspaceRelativePath: worktree.workspaceRelativePath,
            branchName: worktree.branchName,
            createdBranch: worktree.createdBranch,
            state: .unavailable
        )
        let unavailableInventory = await service.inventory(
            workspaces: [unavailableWorkspace],
            knownWorktrees: [unavailableWorktree]
        )
        #expect(
            unavailableInventory.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath == worktree.rootPath
                    && $0.state == .unavailable
            }
        )
    }

    @Test("inventory revalidates a known checkout before marking it tracked")
    func inventoryRevalidatesKnownCheckout() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        try FileManager.default.removeItem(
            at: URL(
                fileURLWithPath: worktree.workingDirectory,
                isDirectory: true
            )
        )

        let inventory = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: [worktree]
        )

        #expect(
            inventory.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath == worktree.rootPath
                    && $0.state == .unavailable
            }
        )
        #expect(!inventory.warnings.isEmpty)
    }

    @Test("inventory requires managed path ownership before marking tracked")
    func inventoryRequiresManagedPathOwnership() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        let mismatchedOwner = ManagedWorktree(
            workspaceID: WorkspaceID(rawValue: UUID()),
            workSessionID: worktree.workSessionID,
            rootPath: worktree.rootPath,
            gitCommonDirectory: worktree.gitCommonDirectory,
            baselineCommit: worktree.baselineCommit,
            workspaceRelativePath: worktree.workspaceRelativePath,
            branchName: worktree.branchName,
            createdBranch: worktree.createdBranch
        )

        let inventory = await service.inventory(
            workspaces: [workspace],
            knownWorktrees: [mismatchedOwner]
        )

        #expect(
            inventory.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath == worktree.rootPath
                    && $0.state == .unavailable
            }
        )
        #expect(!inventory.warnings.isEmpty)
    }

    @Test("inventory exposes an unregistered managed directory")
    func inventoryExposesUnregisteredManagedDirectory() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let orphanedDirectory = fixture.managedRootURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: orphanedDirectory,
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(
            to: orphanedDirectory.appendingPathComponent("untracked.txt")
        )
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        let inventory = await service.inventory(
            workspaces: [
                Workspace(
                    id: WorkspaceID(rawValue: UUID()),
                    path: fixture.workspaceURL.path,
                    displayName: "client"
                ),
                Workspace(
                    id: WorkspaceID(rawValue: UUID()),
                    path: fixture.rootURL
                        .appendingPathComponent("missing-workspace").path,
                    displayName: "missing"
                ),
            ],
            knownWorktrees: []
        )

        #expect(
            inventory.items.contains {
                $0.branchName == nil
                    && $0.directoryPath == orphanedDirectory.path
                    && $0.state == .directoryOnly
            }
        )
        #expect(!inventory.warnings.isEmpty)
        #expect(
            inventory.warnings.allSatisfy {
                !$0.localizedCaseInsensitiveContains("fatal:")
                    && !$0.localizedCaseInsensitiveContains(
                        "not a git repository"
                    )
            }
        )
    }

    @Test("inventory scan does not create a repository index")
    func inventoryScanIsReadOnly() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let repositoryIndexURL = fixture.managedRootURL
            .appendingPathComponent(".repositories.json")

        _ = await service.inventory(
            workspaces: [
                Workspace(
                    id: WorkspaceID(rawValue: UUID()),
                    path: fixture.workspaceURL.path,
                    displayName: "client"
                ),
            ],
            knownWorktrees: []
        )

        #expect(
            !FileManager.default.fileExists(
                atPath: repositoryIndexURL.path
            )
        )
    }

    @Test("workspace removal preparation preserves pre-index Breath branches")
    func workspaceRemovalPreparationPreservesExistingBranches() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let branchName = ManagedWorktree.sessionBranchName(
            for: WorkSessionID(rawValue: UUID())
        )
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", branchName,
        ])
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        let didPreserve = try await service
            .preserveInventoryRepository(
                for: workspace,
                knownWorktrees: []
            )
        let inventory = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )

        #expect(didPreserve)
        #expect(
            inventory.items.contains {
                $0.branchName == branchName
                    && $0.state == .branchOnly
            }
        )
    }

    @Test("removal preparation can preserve from an existing managed checkout")
    func removalPreparationUsesManagedCheckoutWhenWorkspaceMissing()
        async throws
    {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = ManagedWorktree.sessionBranchName(for: sessionID)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await service.create(
            workspace: workspace,
            workSessionID: sessionID,
            branchName: branchName
        )
        try FileManager.default.removeItem(
            at: fixture.managedRootURL.appendingPathComponent(
                ".repositories.json"
            )
        )
        let unavailableWorkspace = Workspace(
            id: workspace.id,
            path: fixture.rootURL.appendingPathComponent("missing").path,
            displayName: workspace.displayName
        )

        let didPreserve = try await service.preserveInventoryRepository(
            for: unavailableWorkspace,
            knownWorktrees: [worktree]
        )
        try await service.remove(worktree)
        let inventory = await service.inventory(
            workspaces: [],
            knownWorktrees: []
        )

        #expect(didPreserve)
        #expect(
            inventory.items.contains {
                $0.branchName == branchName
                    && $0.directoryPath == nil
                    && $0.state == .branchOnly
            }
        )
    }

    @Test("repository index refuses a managed root replaced by a symlink")
    func repositoryIndexRejectsSymlinkedManagedRoot() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let externalURL = fixture.rootURL.appendingPathComponent(
            "external-index-target",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: externalURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.managedRootURL,
            withDestinationURL: externalURL
        )
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )

        await #expect(
            throws: ManagedWorktreeServiceError.unsafeManagedPath(
                fixture.managedRootURL.path
            )
        ) {
            try await service.preserveInventoryRepository(
                for: workspace,
                knownWorktrees: []
            )
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: externalURL
                    .appendingPathComponent(".repositories.json").path
            )
        )
    }

    @Test("repository index rejects a managed root symlink present at startup")
    func repositoryIndexRejectsStartupSymlinkedManagedRoot() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let externalURL = fixture.rootURL.appendingPathComponent(
            "startup-index-target",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: externalURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.managedRootURL,
            withDestinationURL: externalURL
        )
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: fixture.workspaceURL.path,
            displayName: "client"
        )

        await #expect(
            throws: ManagedWorktreeServiceError.unsafeManagedPath(
                fixture.managedRootURL.path
            )
        ) {
            try await service.preserveInventoryRepository(
                for: workspace,
                knownWorktrees: []
            )
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: externalURL
                    .appendingPathComponent(".repositories.json").path
            )
        )
    }

    @Test("removal preparation rejects an unpreservable known repository")
    func removalPreparationRejectsUnpreservableKnownRepository() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let workspace = Workspace(
            id: workspaceID,
            path: fixture.rootURL.appendingPathComponent("missing").path,
            displayName: "client"
        )
        let knownWorktree = ManagedWorktree(
            workspaceID: workspaceID,
            workSessionID: sessionID,
            rootPath: fixture.managedRootURL
                .appendingPathComponent(
                    workspaceID.rawValue.uuidString,
                    isDirectory: true
                )
                .appendingPathComponent(
                    sessionID.rawValue.uuidString,
                    isDirectory: true
                ).path,
            gitCommonDirectory: fixture.rootURL
                .appendingPathComponent("missing-git-common").path,
            baselineCommit: String(repeating: "0", count: 40),
            workspaceRelativePath: "",
            branchName: ManagedWorktree.sessionBranchName(for: sessionID),
            createdBranch: true
        )
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        await #expect(throws: ManagedWorktreeServiceError.self) {
            try await service.preserveInventoryRepository(
                for: workspace,
                knownWorktrees: [knownWorktree]
            )
        }
    }

    @Test("rejects detached HEAD instead of selecting an unrelated branch")
    func rejectsDetachedHead() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let headCommit = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "aaa-unrelated",
        ])
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "checkout", "--detach", headCommit,
        ])
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        await #expect(
            throws: ManagedWorktreeServiceError.unsupportedRepository(
                "当前 Git 仓库处于 detached HEAD 状态，请先检出一个分支。"
            )
        ) {
            try await service.startBranches(
                for: Workspace(
                    id: WorkspaceID(rawValue: UUID()),
                    path: fixture.workspaceURL.path,
                    displayName: "client"
                )
            )
        }
    }

    @Test("creates a dedicated session branch from a checked-out start branch")
    func createsDedicatedSessionBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let currentBranch = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "--show-current",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedBaseline = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedSessionBranch = ManagedWorktree.sessionBranchName(
            for: sessionID
        )
        let startBranch = ManagedWorktreeStartBranch(
            reference: "refs/heads/\(currentBranch)",
            name: currentBranch,
            kind: .localBranch,
            isCurrent: true
        )
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
            branchName: expectedSessionBranch,
            startBranch: startBranch
        )

        #expect(worktree.baselineCommit == expectedBaseline)
        #expect(worktree.branchName == expectedSessionBranch)
        #expect(worktree.createdBranch == true)
        #expect(
            try fixture.git([
                "-C", worktree.rootPath,
                "branch", "--show-current",
            ]).trimmingCharacters(in: .whitespacesAndNewlines)
                == expectedSessionBranch
        )
        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "branch", "--show-current",
            ]).trimmingCharacters(in: .whitespacesAndNewlines)
                == currentBranch
        )
    }

    @Test("rejects revision expressions masquerading as start branches")
    func rejectsRevisionExpressionStartBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let currentBranch = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "--show-current",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidReference = "refs/heads/\(currentBranch)~1"
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        await #expect(
            throws: ManagedWorktreeServiceError.invalidStartBranch(
                invalidReference
            )
        ) {
            try await service.create(
                workspace: Workspace(
                    id: workspaceID,
                    path: fixture.workspaceURL.path,
                    displayName: "client"
                ),
                workSessionID: sessionID,
                branchName: ManagedWorktree.sessionBranchName(
                    for: sessionID
                ),
                startBranch: ManagedWorktreeStartBranch(
                    reference: invalidReference,
                    name: "\(currentBranch)~1",
                    kind: .localBranch,
                    isCurrent: false
                )
            )
        }
    }

    @Test("rejects a checked-out workspace path containing a symlink")
    func rejectsSymlinkWorkspacePath() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let branchName = "feature/symlink-workspace"
        try fixture.createBranchReplacingWorkspaceWithSymlink(
            named: branchName
        )
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let sessionBranch = ManagedWorktree.sessionBranchName(for: sessionID)
        let expectedRoot = fixture.managedRootURL
            .resolvingSymlinksInPath()
            .appendingPathComponent(workspaceID.rawValue.uuidString)
            .appendingPathComponent(sessionID.rawValue.uuidString)
            .path
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        await #expect(throws: ManagedWorktreeServiceError.self) {
            try await service.create(
                workspace: Workspace(
                    id: workspaceID,
                    path: fixture.workspaceURL.path,
                    displayName: "client"
                ),
                workSessionID: sessionID,
                branchName: sessionBranch,
                startBranch: ManagedWorktreeStartBranch(
                    reference: "refs/heads/\(branchName)",
                    name: branchName,
                    kind: .localBranch,
                    isCurrent: false
                )
            )
        }

        #expect(!FileManager.default.fileExists(atPath: expectedRoot))
    }

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
        #expect(worktree.createdBranch == true)
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
        #expect(worktree.createdBranch == false)
        #expect(
            try fixture.git([
                "-C", worktree.rootPath,
                "branch", "--show-current",
            ]).trimmingCharacters(in: .whitespacesAndNewlines)
                == "task/existing"
        )
    }

    @Test("merges a clean session branch into the checked-out target branch")
    func mergesIntoCheckedOutTargetBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let targetBranchName = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "--show-current",
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
            branchName: "task/merge-checked-out"
        )
        let mergedFile = URL(fileURLWithPath: worktree.workingDirectory)
            .appendingPathComponent("merged.txt")
        try Data("merged".utf8).write(to: mergedFile)
        _ = try fixture.git(["-C", worktree.rootPath, "add", "."])
        _ = try fixture.git([
            "-C", worktree.rootPath,
            "-c", "user.name=Breath Tests",
            "-c", "user.email=breath@example.invalid",
            "commit", "-m", "worktree change",
        ])

        try await service.merge(
            worktree,
            into: ManagedWorktreeStartBranch(
                reference: "refs/heads/\(targetBranchName)",
                name: targetBranchName,
                kind: .localBranch,
                isCurrent: true
            )
        )

        #expect(
            FileManager.default.fileExists(
                atPath: fixture.workspaceURL
                    .appendingPathComponent("merged.txt").path
            )
        )
        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "merge-base", "--is-ancestor",
                "task/merge-checked-out", targetBranchName,
            ]).isEmpty
        )
        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "status", "--porcelain",
            ]).isEmpty
        )
        #expect(FileManager.default.fileExists(atPath: worktree.rootPath))
    }

    @Test("merges into an unchecked local branch using a temporary worktree")
    func mergesIntoUncheckedTargetBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "release",
        ])
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
            branchName: "task/merge-unchecked"
        )
        let mergedFile = URL(fileURLWithPath: worktree.workingDirectory)
            .appendingPathComponent("release.txt")
        try Data("release".utf8).write(to: mergedFile)
        _ = try fixture.git(["-C", worktree.rootPath, "add", "."])
        _ = try fixture.git([
            "-C", worktree.rootPath,
            "-c", "user.name=Breath Tests",
            "-c", "user.email=breath@example.invalid",
            "commit", "-m", "release change",
        ])

        try await service.merge(
            worktree,
            into: ManagedWorktreeStartBranch(
                reference: "refs/heads/release",
                name: "release",
                kind: .localBranch,
                isCurrent: false
            )
        )

        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "merge-base", "--is-ancestor",
                "task/merge-unchecked", "release",
            ]).isEmpty
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.managedRootURL
                    .appendingPathComponent(".merge").path
            )
        )
    }

    @Test("a conflicting merge is aborted and leaves the target clean")
    func conflictingMergeIsAborted() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let targetBranchName = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "--show-current",
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
            branchName: "task/conflict"
        )
        try Data("source".utf8).write(
            to: URL(fileURLWithPath: worktree.workingDirectory)
                .appendingPathComponent("tracked.txt")
        )
        _ = try fixture.git(["-C", worktree.rootPath, "add", "."])
        _ = try fixture.git([
            "-C", worktree.rootPath,
            "-c", "user.name=Breath Tests",
            "-c", "user.email=breath@example.invalid",
            "commit", "-m", "source conflict",
        ])
        try Data("target".utf8).write(
            to: fixture.workspaceURL.appendingPathComponent("tracked.txt")
        )
        _ = try fixture.git(["-C", fixture.repositoryURL.path, "add", "."])
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "-c", "user.name=Breath Tests",
            "-c", "user.email=breath@example.invalid",
            "commit", "-m", "target conflict",
        ])

        await #expect(throws: ManagedWorktreeServiceError.self) {
            try await service.merge(
                worktree,
                into: ManagedWorktreeStartBranch(
                    reference: "refs/heads/\(targetBranchName)",
                    name: targetBranchName,
                    kind: .localBranch,
                    isCurrent: true
                )
            )
        }

        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "status", "--porcelain",
            ]).isEmpty
        )
        #expect(
            try Data(
                contentsOf: fixture.workspaceURL
                    .appendingPathComponent("tracked.txt")
            ) == Data("target".utf8)
        )
        #expect(
            throws: GitWorktreeFixtureError.self
        ) {
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "rev-parse", "--verify", "MERGE_HEAD",
            ])
        }
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

    @Test("creation rollback removes only a branch created by that operation")
    func creationRollbackRemovesOnlyCreatedBranch() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        _ = try fixture.git([
            "-C", fixture.repositoryURL.path,
            "branch", "task/existing-rollback",
        ])
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let createdWorktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/new-rollback"
        )
        let existingWorktree = try await service.create(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: fixture.workspaceURL.path,
                displayName: "client"
            ),
            workSessionID: WorkSessionID(rawValue: UUID()),
            branchName: "task/existing-rollback"
        )

        try await service.rollbackCreation(createdWorktree)
        try await service.rollbackCreation(existingWorktree)

        #expect(throws: GitWorktreeFixtureError.self) {
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "show-ref", "--verify", "--quiet",
                "refs/heads/task/new-rollback",
            ])
        }
        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "show-ref", "--verify", "--quiet",
                "refs/heads/task/existing-rollback",
            ]).isEmpty
        )
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

    @Test("removal verifies the checkout's actual git common directory")
    func removalRejectsMismatchedGitCommonDirectory() async throws {
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
            branchName: "task/wrong-common-directory"
        )
        let cloneURL = try fixture.cloneRepository()
        let forgedMetadata = ManagedWorktree(
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID,
            rootPath: worktree.rootPath,
            gitCommonDirectory: cloneURL
                .appendingPathComponent(".git", isDirectory: true)
                .path,
            baselineCommit: worktree.baselineCommit,
            workspaceRelativePath: worktree.workspaceRelativePath,
            branchName: worktree.branchName,
            createdBranch: worktree.createdBranch
        )

        await #expect(throws: ManagedWorktreeServiceError.self) {
            try await service.validateRemoval(forgedMetadata)
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
        #expect(throws: GitWorktreeFixtureError.self) {
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "show-ref", "--verify", "--quiet",
                "refs/heads/task/reported-failure",
            ])
        }
    }

    @Test("a competing branch creation is never mistaken for owned state")
    func competingBranchCreationIsPreserved() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL,
            gitExecutableURL:
                try fixture.gitWrapperCreatingCompetingBranchBeforeUpdate()
        )

        await #expect(throws: ManagedWorktreeServiceError.self) {
            try await service.create(
                workspace: Workspace(
                    id: WorkspaceID(rawValue: UUID()),
                    path: fixture.workspaceURL.path,
                    displayName: "client"
                ),
                workSessionID: WorkSessionID(rawValue: UUID()),
                branchName: "task/competing"
            )
        }

        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "show-ref", "--verify", "--quiet",
                "refs/heads/task/competing",
            ]).isEmpty
        )
    }

    @Test("creation rejects a session branch moved before worktree add")
    func movedSessionBranchBeforeCheckoutIsRejected() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let movedCommit = try fixture.createAlternateCommit()
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let branchName = "task/ref-moved"
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL,
            gitExecutableURL: try fixture
                .gitWrapperMovingBranchBeforeWorktreeAdd(
                    branchName: branchName,
                    targetCommit: movedCommit
                )
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
                branchName: branchName
            )
        }

        #expect(!FileManager.default.fileExists(atPath: expectedRoot))
        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "rev-parse", "refs/heads/\(branchName)",
            ]).trimmingCharacters(in: .whitespacesAndNewlines) == movedCommit
        )
    }

    @Test("a missing checkout is forgotten without trusting stored git metadata")
    func missingCheckoutRemovalDoesNotUseStoredRepository() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let creationService = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )
        let worktree = try await creationService.create(
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
        let removalService = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL,
            gitExecutableURL: try fixture.gitWrapperRejectingAllCommands()
        )

        try await removalService.remove(worktree)

        #expect(
            try fixture.git([
                "-C", fixture.repositoryURL.path,
                "worktree", "list", "--porcelain",
            ]).contains(worktree.rootPath)
        )
    }

    @Test("failed preparation never removes a pre-existing hooks directory")
    func failedPreparationPreservesExistingHooksDirectory() async throws {
        let fixture = try GitWorktreeFixture()
        defer { fixture.remove() }
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let hooksURL = fixture.managedRootURL
            .appendingPathComponent(".disabled-hooks", isDirectory: true)
            .appendingPathComponent(
                sessionID.rawValue.uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: hooksURL,
            withIntermediateDirectories: true
        )
        let markerURL = hooksURL.appendingPathComponent("do-not-delete")
        try Data("owned elsewhere".utf8).write(to: markerURL)
        let service = ManagedWorktreeService(
            managedRootURL: fixture.managedRootURL
        )

        await #expect(throws: ManagedWorktreeServiceError.self) {
            try await service.create(
                workspace: Workspace(
                    id: workspaceID,
                    path: fixture.workspaceURL.path,
                    displayName: "client"
                ),
                workSessionID: sessionID,
                branchName: "task/preserve-existing-hooks"
            )
        }

        #expect(FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test("a missing checkout and repository can still be forgotten")
    func missingCheckoutAndRepositoryCanBeRemoved() async throws {
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
            branchName: "task/missing-repository"
        )
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: worktree.rootPath, isDirectory: true)
        )
        try FileManager.default.removeItem(at: fixture.repositoryURL)

        try await service.remove(worktree)
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

    func createBranchReplacingWorkspaceWithSymlink(
        named branchName: String
    ) throws {
        let originalBranch = try git([
            "-C", repositoryURL.path,
            "branch", "--show-current",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try git([
            "-C", repositoryURL.path,
            "switch", "-c", branchName,
        ])
        try FileManager.default.removeItem(at: workspaceURL)
        let externalURL = rootURL.appendingPathComponent(
            "external-workspace",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: externalURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: workspaceURL,
            withDestinationURL: externalURL
        )
        _ = try git(["-C", repositoryURL.path, "add", "-A"])
        _ = try git([
            "-C", repositoryURL.path,
            "-c", "user.name=Breath Tests",
            "-c", "user.email=breath@example.invalid",
            "commit", "-m", "replace workspace with symlink",
        ])
        _ = try git([
            "-C", repositoryURL.path,
            "switch", originalBranch,
        ])
    }

    func cloneRepository() throws -> URL {
        let cloneURL = rootURL.appendingPathComponent(
            "repository-clone",
            isDirectory: true
        )
        _ = try git(["clone", "--quiet", repositoryURL.path, cloneURL.path])
        return cloneURL
    }

    func createAlternateCommit() throws -> String {
        let originalBranch = try git([
            "-C", repositoryURL.path,
            "branch", "--show-current",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try git([
            "-C", repositoryURL.path,
            "switch", "-c", "alternate",
        ])
        try Data("alternate".utf8).write(
            to: workspaceURL.appendingPathComponent("tracked.txt")
        )
        _ = try git(["-C", repositoryURL.path, "add", "."])
        _ = try git([
            "-C", repositoryURL.path,
            "-c", "user.name=Breath Tests",
            "-c", "user.email=breath@example.invalid",
            "commit", "-m", "alternate",
        ])
        let commit = try git([
            "-C", repositoryURL.path,
            "rev-parse", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try git([
            "-C", repositoryURL.path,
            "switch", originalBranch,
        ])
        return commit
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

    func gitWrapperRejectingAllCommands() throws -> URL {
        let wrapperURL = rootURL.appendingPathComponent(
            "git-wrapper-rejecting-all-commands"
        )
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: wrapperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: wrapperURL.path
        )
        return wrapperURL
    }

    func gitWrapperCreatingCompetingBranchBeforeUpdate() throws -> URL {
        let wrapperURL = rootURL.appendingPathComponent(
            "git-wrapper-competing-branch"
        )
        let script = """
        #!/bin/sh
        if [ "$3" = "update-ref" ] && [ "$4" = "refs/heads/task/competing" ]; then
          /usr/bin/git -C "$2" update-ref "$4" "$5" "$6"
        fi
        exec /usr/bin/git "$@"
        """
        try Data(script.utf8).write(to: wrapperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: wrapperURL.path
        )
        return wrapperURL
    }

    func gitWrapperMovingBranchBeforeWorktreeAdd(
        branchName: String,
        targetCommit: String
    ) throws -> URL {
        let wrapperURL = rootURL.appendingPathComponent(
            "git-wrapper-moving-branch"
        )
        let repositoryPath = repositoryURL.path.replacingOccurrences(
            of: "'",
            with: "'\"'\"'"
        )
        let script = """
        #!/bin/sh
        previous=
        for argument in "$@"; do
          if [ "$previous" = "worktree" ] && [ "$argument" = "add" ]; then
            /usr/bin/git -C '\(repositoryPath)' update-ref \
              'refs/heads/\(branchName)' '\(targetCommit)'
            break
          fi
          previous="$argument"
        done
        exec /usr/bin/git "$@"
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

private struct RemovingTestWorktreeTrash:
    ManagedWorktreeDirectoryTrashing,
    Sendable
{
    func moveToTrash(_ url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }
}
