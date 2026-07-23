import Foundation
import Testing
@testable import BreathCore

@Suite("Workbench application use cases")
struct WorkbenchTests {
    @Test("a branch-backed worktree session launches and splits in its own checkout")
    func branchBackedWorktreeSessionUsesItsOwnCheckout() async throws {
        let runtime = RecordingTerminalRuntime()
        let worktreeManager = RecordingManagedWorktreeManager()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: runtime,
            managedWorktreeManager: worktreeManager,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )

        let sessionID = try await workbench.createManagedWorktreeSession(
            in: workspaceID,
            branchName: "task/123"
        )
        let firstPaneID = try #require(
            await workbench.snapshot().workSessions.first?.pane.id
        )
        _ = try await workbench.splitPane(firstPaneID, orientation: .vertical)

        let session = try #require(
            await workbench.snapshot().workSessions.first
        )
        #expect(session.id == sessionID)
        #expect(session.managedWorktree?.branchName == "task/123")
        #expect(
            session.workingDirectory(workspacePath: "/tmp/example-project")
                == "/tmp/breath-worktrees/workspace/session/apps/client"
        )
        #expect(await runtime.launches.map(\.workingDirectory) == [
            "/tmp/breath-worktrees/workspace/session/apps/client",
            "/tmp/breath-worktrees/workspace/session/apps/client",
        ])
        #expect(await worktreeManager.createdBranchNames == ["task/123"])
    }

    @Test("a worktree session launches before its completed state is persisted")
    func worktreeSessionLaunchesBeforePersistence() async throws {
        let effects = EffectLog()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(effects: effects),
            terminalRuntime: RecordingTerminalRuntime(effects: effects),
            managedWorktreeManager: RecordingManagedWorktreeManager(),
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        await effects.clear()

        _ = try await workbench.createManagedWorktreeSession(
            in: workspaceID,
            branchName: "task/persist-first"
        )

        let recordedEffects = await effects.values
        #expect(recordedEffects.count == 2)
        guard recordedEffects.count == 2,
              case .launched = recordedEffects[0]
        else {
            Issue.record("expected terminal launch before persistence")
            return
        }
        #expect(recordedEffects[1] == .saved)
    }

    @Test("a worktree session stays hidden until its first terminal is ready")
    func worktreeSessionIsHiddenDuringTerminalLaunch() async throws {
        let runtime = SuspendedLaunchTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: runtime,
            managedWorktreeManager: RecordingManagedWorktreeManager(),
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let creation = Task {
            try await workbench.createManagedWorktreeSession(
                in: workspaceID,
                branchName: "task/hidden-until-ready"
            )
        }
        while await runtime.launchCallCount == 0 {
            await Task.yield()
        }

        #expect(await workbench.snapshot().workSessions.isEmpty)

        await runtime.allowLaunches()
        let sessionID = try await creation.value
        #expect(
            await workbench.snapshot().workSessions.map(\.id) == [sessionID]
        )
    }

    @Test("a worktree session stays hidden while its snapshot is saving")
    func worktreeSessionIsHiddenDuringPersistence() async throws {
        let repository = SuspendedSaveRepository(suspendedSave: 2)
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: RecordingTerminalRuntime(),
            managedWorktreeManager: RecordingManagedWorktreeManager(),
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let creation = Task {
            try await workbench.createManagedWorktreeSession(
                in: workspaceID,
                branchName: "task/hidden-while-saving"
            )
        }
        while await repository.saveCallCount < 2 {
            await Task.yield()
        }

        #expect(await workbench.snapshot().workSessions.isEmpty)

        await repository.allowSaves()
        let sessionID = try await creation.value
        #expect(
            await workbench.snapshot().workSessions.map(\.id) == [sessionID]
        )
    }

    @Test("a failed worktree session save stops its terminal and removes its checkout")
    func failedWorktreeSaveCompensatesLaunch() async throws {
        let worktreeManager = RecordingManagedWorktreeManager()
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: FailingSaveRepository(failingSaveNumbers: [2]),
            terminalRuntime: runtime,
            managedWorktreeManager: worktreeManager,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )

        await #expect(throws: TestPersistenceError.saveFailed) {
            try await workbench.createManagedWorktreeSession(
                in: workspaceID,
                branchName: "task/persistence-failure"
            )
        }

        let launchedPaneID = try #require(await runtime.launches.first?.paneID)
        #expect(await runtime.stoppedPaneIDs == [launchedPaneID])
        #expect(await workbench.snapshot().workSessions.isEmpty)
        #expect(
            await worktreeManager.removedBranchNames
                == ["task/persistence-failure"]
        )
    }

    @Test("a failed first terminal is stopped before its checkout is removed")
    func failedWorktreeLaunchIsCompensated() async throws {
        let worktreeManager = RecordingManagedWorktreeManager()
        let runtime = FailingNthLaunchRuntime(failingLaunch: 1)
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: runtime,
            managedWorktreeManager: worktreeManager,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )

        await #expect(throws: FailingNthLaunchRuntime.Failure.launchFailed) {
            try await workbench.createManagedWorktreeSession(
                in: workspaceID,
                branchName: "task/launch-failure"
            )
        }

        #expect(await runtime.stoppedPaneIDs.count == 1)
        #expect(await workbench.snapshot().workSessions.isEmpty)
        #expect(
            await worktreeManager.removedBranchNames == ["task/launch-failure"]
        )
    }

    @Test("a failed creation reports when its checkout cannot be rolled back")
    func failedWorktreeRollbackIsReported() async throws {
        let worktreeManager = RecordingManagedWorktreeManager(
            removalError: TestManagedWorktreeError.cleanupFailed
        )
        let runtime = FailingNthLaunchRuntime(failingLaunch: 1)
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: runtime,
            managedWorktreeManager: worktreeManager,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )

        do {
            _ = try await workbench.createManagedWorktreeSession(
                in: workspaceID,
                branchName: "task/cleanup-failure"
            )
            Issue.record("expected rollback failure")
        } catch let error as WorkbenchError {
            guard case .managedWorktreeCreationRollbackFailed(
                let worktreePath,
                _,
                _
            ) = error else {
                Issue.record("unexpected Workbench error: \(error)")
                return
            }
            #expect(
                worktreePath == "/tmp/breath-worktrees/workspace/session"
            )
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(await workbench.snapshot().workSessions.isEmpty)
    }

    @Test("a valid managed worktree restores when the original checkout is unavailable")
    func managedWorktreeRestoresWithoutOriginalCheckout() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [
                Workspace(
                    id: workspaceID,
                    path: "/missing/example-project/apps/client",
                    displayName: "client"
                ),
            ],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Task 123",
                    pane: TerminalPane(id: paneID),
                    managedWorktree: ManagedWorktree(
                        workspaceID: workspaceID,
                        workSessionID: sessionID,
                        rootPath: "/tmp/breath-worktrees/workspace/session",
                        gitCommonDirectory: "/tmp/example-project/.git",
                        baselineCommit: "0123456789abcdef",
                        workspaceRelativePath: "apps/client",
                        branchName: "task/123"
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: snapshot),
            terminalRuntime: runtime,
            managedWorktreeManager: RecordingManagedWorktreeManager(),
            defaultShell: { "/bin/zsh" },
            workspaceAvailable: { _ in false }
        )

        try await workbench.restoreFromRepository()

        #expect(await workbench.snapshot().selectedWorkSessionID == sessionID)
        #expect(await runtime.launches.map(\.workingDirectory) == [
            "/tmp/breath-worktrees/workspace/session/apps/client",
        ])
    }

    @Test("permanently deleting an archived worktree session removes its checkout")
    func deletingArchivedWorktreeSessionRemovesCheckout() async throws {
        let worktreeManager = RecordingManagedWorktreeManager()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            managedWorktreeManager: worktreeManager,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let sessionID = try await workbench.createManagedWorktreeSession(
            in: workspaceID,
            branchName: "task/123"
        )
        try await workbench.archiveWorkSession(sessionID)

        try await workbench.deleteArchivedWorkSession(sessionID)

        #expect(await workbench.snapshot().workSessions.isEmpty)
        #expect(await worktreeManager.removedBranchNames == ["task/123"])
    }

    @Test("a failed archive deletion save retains an unavailable worktree record")
    func failedArchivedWorktreeDeletionRetainsRecoveryRecord() async throws {
        let worktreeManager = RecordingManagedWorktreeManager()
        let workbench = Workbench(
            repository: FailingSaveRepository(failingSaveNumbers: [4]),
            terminalRuntime: RecordingTerminalRuntime(),
            managedWorktreeManager: worktreeManager,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let sessionID = try await workbench.createManagedWorktreeSession(
            in: workspaceID,
            branchName: "task/123"
        )
        try await workbench.archiveWorkSession(sessionID)

        await #expect(throws: TestPersistenceError.saveFailed) {
            try await workbench.deleteArchivedWorkSession(sessionID)
        }

        let retainedSession = try #require(
            await workbench.snapshot().workSessions.first
        )
        #expect(retainedSession.id == sessionID)
        #expect(retainedSession.managedWorktree?.state == .unavailable)
        #expect(await worktreeManager.removedBranchNames == ["task/123"])
    }

    @Test("removing a workspace safely removes all managed checkouts first")
    func removingWorkspaceRemovesManagedCheckouts() async throws {
        let worktreeManager = RecordingManagedWorktreeManager()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            managedWorktreeManager: worktreeManager,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        _ = try await workbench.createManagedWorktreeSession(
            in: workspaceID,
            branchName: "task/one"
        )
        _ = try await workbench.createManagedWorktreeSession(
            in: workspaceID,
            branchName: "task/two"
        )

        try await workbench.removeWorkspace(workspaceID)

        #expect(await workbench.snapshot() == .empty)
        #expect(await worktreeManager.validatedBranchNames == [
            "task/one",
            "task/two",
        ])
        #expect(await worktreeManager.removedBranchNames == [
            "task/one",
            "task/two",
        ])
    }

    @Test("startup marks a missing managed worktree unavailable without launching it")
    func missingManagedWorktreeBecomesUnavailable() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [
                Workspace(
                    id: workspaceID,
                    path: "/tmp/example-project",
                    displayName: "example-project"
                ),
            ],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Missing task",
                    pane: TerminalPane(id: paneID),
                    managedWorktree: ManagedWorktree(
                        workspaceID: workspaceID,
                        workSessionID: sessionID,
                        rootPath: "/tmp/missing-worktree",
                        gitCommonDirectory: "/tmp/example-project/.git",
                        baselineCommit: "0123456789abcdef",
                        workspaceRelativePath: "",
                        branchName: "task/missing"
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: snapshot),
            terminalRuntime: runtime,
            managedWorktreeManager: RecordingManagedWorktreeManager(
                isAvailable: false
            ),
            defaultShell: { "/bin/zsh" }
        )

        try await workbench.restoreFromRepository()

        #expect(await workbench.snapshot().selectedWorkSessionID == nil)
        #expect(
            await workbench.snapshot().workSessions.first?
                .managedWorktree?.state == .unavailable
        )
        #expect(await runtime.launches.isEmpty)
    }

    @Test("a worktree owned by another session is never restored")
    func mismatchedWorktreeOwnershipBecomesUnavailable() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [
                Workspace(
                    id: workspaceID,
                    path: "/tmp/example-project",
                    displayName: "example-project"
                ),
            ],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Forged ownership",
                    pane: TerminalPane(
                        id: TerminalPaneID(rawValue: UUID())
                    ),
                    managedWorktree: ManagedWorktree(
                        workspaceID: workspaceID,
                        workSessionID: WorkSessionID(rawValue: UUID()),
                        rootPath: "/tmp/breath-worktrees/workspace/session",
                        gitCommonDirectory: "/tmp/example-project/.git",
                        baselineCommit: "0123456789abcdef",
                        workspaceRelativePath: "",
                        branchName: "task/forged"
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: snapshot),
            terminalRuntime: runtime,
            managedWorktreeManager: RecordingManagedWorktreeManager(),
            defaultShell: { "/bin/zsh" }
        )

        try await workbench.restoreFromRepository()

        #expect(await workbench.snapshot().selectedWorkSessionID == nil)
        #expect(
            await workbench.snapshot().workSessions.first?
                .managedWorktree?.state == .unavailable
        )
        #expect(await runtime.launches.isEmpty)
    }

    @Test("a failed live worktree check updates the persisted session state")
    func liveWorktreeFailureBecomesUnavailable() async throws {
        let worktreeManager = RecordingManagedWorktreeManager()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            managedWorktreeManager: worktreeManager,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let sessionID = try await workbench.createManagedWorktreeSession(
            in: workspaceID,
            branchName: "task/disappears"
        )
        let paneID = try #require(
            await workbench.snapshot().workSessions.first?.pane.id
        )
        await worktreeManager.setAvailable(false)

        await #expect(
            throws: WorkbenchError.managedWorktreeUnavailable(sessionID)
        ) {
            _ = try await workbench.splitPane(
                paneID,
                orientation: .vertical
            )
        }

        #expect(
            await workbench.snapshot().workSessions.first?
                .managedWorktree?.state == .unavailable
        )
    }

    @Test("clean exit permanently closes the worktree operation gate")
    func cleanExitRejectsNewWorktreeOperations() async throws {
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            managedWorktreeManager: RecordingManagedWorktreeManager(),
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )

        try await workbench.prepareForCleanExit()

        await #expect(throws: WorkbenchError.preparingForCleanExit) {
            try await workbench.createManagedWorktreeSession(
                in: workspaceID,
                branchName: "task/too-late"
            )
        }
    }

    @Test("user can create a work session backed by an empty login shell")
    func createFirstWorkSession() async throws {
        let repository = InMemoryWorkbenchRepository()
        let terminalRuntime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: terminalRuntime,
            defaultShell: { "/bin/zsh" },
            now: { Date(timeIntervalSince1970: 12 * 60 * 60) },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let workSessionID = try await workbench.createWorkSession(in: workspaceID)

        let snapshot = await workbench.snapshot()
        #expect(snapshot.workspaces.count == 1)
        #expect(snapshot.workspaces[0].path == "/tmp/example-project")
        #expect(snapshot.workSessions.map(\.id) == [workSessionID])
        #expect(snapshot.workSessions[0].title == "新会话 · 12:00")
        #expect(snapshot.selectedWorkSessionID == workSessionID)

        let launches = await terminalRuntime.launches
        #expect(launches.count == 1)
        #expect(launches[0].workingDirectory == "/tmp/example-project")
        #expect(launches[0].executable == "/bin/zsh")
        #expect(launches[0].arguments == ["-l"])
        #expect(launches[0].environment["BREATH_APPLICATION_INSTANCE_ID"] != nil)
        #expect(launches[0].environment["BREATH_WORKSPACE_ID"] == workspaceID.rawValue.uuidString)
        #expect(launches[0].environment["BREATH_WORK_SESSION_ID"] == workSessionID.rawValue.uuidString)
        #expect(launches[0].environment["BREATH_TERMINAL_PANE_ID"] != nil)

        let persisted = await repository.latestSnapshot
        #expect(persisted == snapshot)
    }

    @Test("switching work sessions keeps existing terminals running")
    func switchWorkSessions() async throws {
        let repository = InMemoryWorkbenchRepository()
        let terminalRuntime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: terminalRuntime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let first = try await workbench.createWorkSession(in: workspaceID)
        _ = try await workbench.createWorkSession(in: workspaceID)

        try await workbench.selectWorkSession(first)

        let snapshot = await workbench.snapshot()
        #expect(snapshot.workSessions.count == 2)
        #expect(snapshot.selectedWorkSessionID == first)
        #expect(await terminalRuntime.launches.count == 2)
        #expect(await terminalRuntime.stoppedPaneIDs.isEmpty)
    }

    @Test("splitting a pane launches an independent shell in the workspace root")
    func splitPane() async throws {
        let repository = InMemoryWorkbenchRepository()
        let terminalRuntime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: terminalRuntime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let sessionID = try await workbench.createWorkSession(in: workspaceID)
        let initialPaneID = try #require(
            await workbench.snapshot().workSessions.first?.pane.id
        )

        let newPaneID = try await workbench.splitPane(
            initialPaneID,
            orientation: .horizontal
        )

        let session = try #require(
            await workbench.snapshot().workSessions.first(where: { $0.id == sessionID })
        )
        #expect(session.layout.paneIDs == [initialPaneID, newPaneID])
        guard case .split(let orientation, let fraction, _, _) = session.layout else {
            Issue.record("expected a split layout")
            return
        }
        #expect(orientation == .horizontal)
        #expect(fraction == 0.5)

        let launches = await terminalRuntime.launches
        #expect(launches.count == 2)
        #expect(launches[1].paneID == newPaneID)
        #expect(launches[1].workingDirectory == "/tmp/example-project")
    }

    @Test("clean exit persists before stopping every terminal pane")
    func cleanExit() async throws {
        let effects = EffectLog()
        let repository = InMemoryWorkbenchRepository(effects: effects)
        let terminalRuntime = RecordingTerminalRuntime(effects: effects)
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: terminalRuntime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        _ = try await workbench.createWorkSession(in: workspaceID)
        let initialPaneID = try #require(
            await workbench.snapshot().workSessions.first?.pane.id
        )
        let secondPaneID = try await workbench.splitPane(
            initialPaneID,
            orientation: .vertical
        )
        await effects.clear()

        try await workbench.prepareForCleanExit()

        #expect(
            await effects.values == [
                .saved,
                .stopped(initialPaneID),
                .stopped(secondPaneID),
            ]
        )
    }

    @Test("failed startup cleanup stops terminals without saving a snapshot")
    func failedStartupCleanupDoesNotSave() async throws {
        let effects = EffectLog()
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp/project", displayName: "project")],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Session",
                    pane: TerminalPane(id: paneID)
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let repository = InMemoryWorkbenchRepository(snapshot: snapshot, effects: effects)
        let runtime = RecordingTerminalRuntime(effects: effects)
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" }
        )
        try await workbench.restoreFromRepository()
        await effects.clear()

        await workbench.stopAllTerminalsWithoutSaving()

        #expect(await effects.values == [.stopped(paneID)])
        #expect(await repository.latestSnapshot == snapshot)
    }

    @Test("cold start materializes only the previously selected work session")
    func lazyRestore() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let firstSessionID = WorkSessionID(rawValue: UUID())
        let secondSessionID = WorkSessionID(rawValue: UUID())
        let firstPaneID = TerminalPaneID(rawValue: UUID())
        let secondPaneID = TerminalPaneID(rawValue: UUID())
        let stored = WorkbenchSnapshot(
            workspaces: [
                Workspace(
                    id: workspaceID,
                    path: "/tmp/example-project",
                    displayName: "example-project"
                ),
            ],
            workSessions: [
                WorkSession(
                    id: firstSessionID,
                    workspaceID: workspaceID,
                    title: "first",
                    pane: TerminalPane(id: firstPaneID)
                ),
                WorkSession(
                    id: secondSessionID,
                    workspaceID: workspaceID,
                    title: "second",
                    pane: TerminalPane(id: secondPaneID)
                ),
            ],
            selectedWorkSessionID: firstSessionID
        )
        let repository = InMemoryWorkbenchRepository(snapshot: stored)
        let terminalRuntime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: terminalRuntime,
            defaultShell: { "/bin/zsh" }
        )

        try await workbench.restoreFromRepository()
        #expect(await terminalRuntime.launches.map(\.paneID) == [firstPaneID])

        try await workbench.selectWorkSession(secondSessionID)
        #expect(
            await terminalRuntime.launches.map(\.paneID) == [firstPaneID, secondPaneID]
        )

        try await workbench.selectWorkSession(firstSessionID)
        #expect(
            await terminalRuntime.launches.map(\.paneID) == [firstPaneID, secondPaneID]
        )
    }

    @Test("cold start exposes saved layout before restoring the selected Agent")
    func restoreLayoutBeforeAgentMaterialization() async throws {
        let fixture = recoveryFixture()
        let runtime = SuspendedLaunchTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: fixture.snapshot),
            terminalRuntime: runtime,
            agentResumeCommands: FixedAgentResumeCommands(),
            defaultShell: { "/bin/zsh" }
        )

        try await workbench.restoreSnapshotFromRepository()

        #expect(await workbench.snapshot() == fixture.snapshot)
        #expect(await runtime.launchCallCount == 0)

        let materialization = Task {
            try await workbench.materializeSelectedWorkSession()
        }
        for _ in 0..<1_000 {
            if await runtime.launchCallCount == 1 { break }
            await Task.yield()
        }

        #expect(await runtime.launchCallCount == 1)
        await runtime.allowLaunches()
        try await materialization.value
    }

    @Test("an unavailable selected workspace is retained but not materialized")
    func unavailableWorkspaceRestore() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let stored = WorkbenchSnapshot(
            workspaces: [
                Workspace(id: workspaceID, path: "/missing/project", displayName: "project"),
            ],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Missing",
                    pane: TerminalPane(id: paneID)
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: stored),
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" },
            workspaceAvailable: { _ in false }
        )

        try await workbench.restoreFromRepository()

        let snapshot = await workbench.snapshot()
        #expect(snapshot.workspaces.map(\.id) == [workspaceID])
        #expect(snapshot.workSessions.map(\.id) == [sessionID])
        #expect(snapshot.selectedWorkSessionID == nil)
        #expect(await runtime.launches.isEmpty)
    }

    @Test("restoring an archive returns it to the tree without launching terminals")
    func archiveAndRestore() async throws {
        let repository = InMemoryWorkbenchRepository()
        let terminalRuntime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: terminalRuntime,
            defaultShell: { "/bin/zsh" },
            now: { Date(timeIntervalSince1970: 100) }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let sessionID = try await workbench.createWorkSession(in: workspaceID)
        let paneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)
        let secondPaneID = try await workbench.splitPane(paneID, orientation: .horizontal)

        try await workbench.archiveWorkSession(sessionID)

        var snapshot = await workbench.snapshot()
        #expect(snapshot.activeWorkSessions.isEmpty)
        #expect(snapshot.archivedWorkSessions.map(\.id) == [sessionID])
        #expect(snapshot.selectedWorkSessionID == nil)
        #expect(await terminalRuntime.stoppedPaneIDs == [paneID, secondPaneID])

        let launchCountBeforeRestore = await terminalRuntime.launches.count
        try await workbench.restoreArchivedWorkSession(sessionID)

        snapshot = await workbench.snapshot()
        #expect(snapshot.activeWorkSessions.map(\.id) == [sessionID])
        #expect(snapshot.archivedWorkSessions.isEmpty)
        #expect(snapshot.selectedWorkSessionID == nil)
        #expect(await terminalRuntime.launches.count == launchCountBeforeRestore)
    }

    @Test("Codex events update the pane binding, title, and four-state lifecycle")
    func codexLifecycle() async throws {
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        let repository = InMemoryWorkbenchRepository()
        let terminalRuntime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: terminalRuntime,
            applicationInstanceID: applicationInstanceID,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let sessionID = try await workbench.createWorkSession(in: workspaceID)
        let paneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)

        try await workbench.handleAgentEvent(
            AgentEvent(
                applicationInstanceID: applicationInstanceID,
                agent: .codex,
                version: "1.2.3",
                lifecycle: .turnStarted,
                occurredAt: Date(timeIntervalSince1970: 200),
                workspaceID: workspaceID,
                workSessionID: sessionID,
                paneID: paneID,
                sessionID: "codex-session-1",
                nativeTitle: "Implement workspace navigation",
                workingDirectory: "/tmp/example-project"
            )
        )

        var session = try #require(await workbench.snapshot().workSessions.first)
        #expect(session.title == "Implement workspace navigation")
        #expect(session.pane.state == .running)
        #expect(session.pane.agentBinding?.agent == .codex)
        #expect(session.pane.agentBinding?.sessionID == "codex-session-1")
        #expect(session.pane.agentBinding?.nativeTitle == "Implement workspace navigation")

        try await workbench.handleAgentEvent(
            AgentEvent(
                applicationInstanceID: applicationInstanceID,
                agent: .codex,
                lifecycle: .needsAttention,
                occurredAt: Date(timeIntervalSince1970: 201),
                workspaceID: workspaceID,
                workSessionID: sessionID,
                paneID: paneID,
                workingDirectory: "/tmp/example-project"
            )
        )
        session = try #require(await workbench.snapshot().workSessions.first)
        #expect(session.pane.state == .needsAttention)

        try await workbench.handleAgentEvent(
            AgentEvent(
                applicationInstanceID: applicationInstanceID,
                agent: .codex,
                lifecycle: .turnCompleted,
                occurredAt: Date(timeIntervalSince1970: 202),
                workspaceID: workspaceID,
                workSessionID: sessionID,
                paneID: paneID,
                workingDirectory: "/tmp/example-project"
            )
        )
        session = try #require(await workbench.snapshot().workSessions.first)
        #expect(session.pane.state == .turnCompleted)

        try await workbench.handleAgentEvent(
            AgentEvent(
                applicationInstanceID: applicationInstanceID,
                agent: .codex,
                lifecycle: .sessionEnded,
                occurredAt: Date(timeIntervalSince1970: 203),
                workspaceID: workspaceID,
                workSessionID: sessionID,
                paneID: paneID,
                workingDirectory: "/tmp/example-project"
            )
        )
        session = try #require(await workbench.snapshot().workSessions.first)
        #expect(session.pane.state == .idle)
        #expect(session.pane.agentBinding?.isActive == false)
    }

    @Test("late events from an older Agent session cannot steal the pane binding")
    func staleAgentEventsAreIgnored() async throws {
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            applicationInstanceID: applicationInstanceID,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let workSessionID = try await workbench.createWorkSession(in: workspaceID)
        let paneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)

        for (sessionID, time) in [("old", 100.0), ("new", 200.0)] {
            try await workbench.handleAgentEvent(
                AgentEvent(
                    applicationInstanceID: applicationInstanceID,
                    agent: .codex,
                    lifecycle: .turnStarted,
                    occurredAt: Date(timeIntervalSince1970: time),
                    workspaceID: workspaceID,
                    workSessionID: workSessionID,
                    paneID: paneID,
                    sessionID: sessionID,
                    workingDirectory: "/tmp/example-project"
                )
            )
        }
        try await workbench.handleAgentEvent(
            AgentEvent(
                applicationInstanceID: applicationInstanceID,
                agent: .codex,
                lifecycle: .sessionEnded,
                occurredAt: Date(timeIntervalSince1970: 150),
                workspaceID: workspaceID,
                workSessionID: workSessionID,
                paneID: paneID,
                sessionID: "old",
                workingDirectory: "/tmp/example-project"
            )
        )

        let pane = try #require(await workbench.snapshot().workSessions.first?.pane)
        #expect(pane.agentBinding?.sessionID == "new")
        #expect(pane.agentBinding?.isActive == true)
        #expect(pane.state == .running)
    }

    @Test("events from another Breath application instance are rejected")
    func foreignApplicationEvent() async throws {
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            applicationInstanceID: applicationInstanceID,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let workSessionID = try await workbench.createWorkSession(in: workspaceID)
        let paneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)

        await #expect(throws: WorkbenchError.agentEventTargetMismatch) {
            try await workbench.handleAgentEvent(
                AgentEvent(
                    applicationInstanceID: ApplicationInstanceID(rawValue: UUID()),
                    agent: .codex,
                    lifecycle: .turnStarted,
                    occurredAt: Date(),
                    workspaceID: workspaceID,
                    workSessionID: workSessionID,
                    paneID: paneID,
                    sessionID: "foreign",
                    workingDirectory: "/tmp/example-project"
                )
            )
        }
    }

    @Test("the same normalized workspace directory cannot be added twice")
    func duplicateWorkspace() async throws {
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            defaultShell: { "/bin/zsh" }
        )
        _ = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )

        await #expect(throws: WorkbenchError.workspaceAlreadyExists("/tmp/example-project")) {
            try await workbench.addWorkspace(
                at: URL(fileURLWithPath: "/tmp/./example-project/", isDirectory: true)
            )
        }
        #expect(await workbench.snapshot().workspaces.count == 1)
    }

    @Test("a symbolic-link alias cannot add the same workspace twice")
    func duplicateWorkspaceSymlink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-workspace-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
        defer { try? FileManager.default.removeItem(at: root) }
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            defaultShell: { "/bin/zsh" }
        )

        _ = try await workbench.addWorkspace(at: project)
        await #expect(throws: WorkbenchError.workspaceAlreadyExists(project.path)) {
            try await workbench.addWorkspace(at: alias)
        }
    }

    @Test("removing a workspace stops its terminals and deletes only Breath metadata")
    func removeWorkspace() async throws {
        let repository = InMemoryWorkbenchRepository()
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        _ = try await workbench.createWorkSession(in: workspaceID)
        let firstPaneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)
        let secondPaneID = try await workbench.splitPane(firstPaneID, orientation: .vertical)

        try await workbench.removeWorkspace(workspaceID)

        #expect(await runtime.stoppedPaneIDs == [firstPaneID, secondPaneID])
        #expect(await workbench.snapshot() == .empty)
        #expect(await repository.latestSnapshot == .empty)
    }

    @Test("split ratios can be changed and are persisted")
    func resizeSplit() async throws {
        let repository = InMemoryWorkbenchRepository()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: RecordingTerminalRuntime(),
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        _ = try await workbench.createWorkSession(in: workspaceID)
        let paneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)
        _ = try await workbench.splitPane(paneID, orientation: .horizontal)

        try await workbench.resizeSplit(containing: paneID, fraction: 0.7)

        let layout = try #require(await workbench.snapshot().workSessions.first?.layout)
        guard case .split(_, let fraction, _, _) = layout else {
            Issue.record("expected split layout")
            return
        }
        #expect(fraction == 0.7)
        #expect(await repository.latestSnapshot?.workSessions.first?.layout == layout)
    }

    @Test("a nested divider resizes only its own recursive split")
    func resizeNestedSplit() async throws {
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: RecordingTerminalRuntime(),
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let sessionID = try await workbench.createWorkSession(in: workspaceID)
        let firstPaneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)
        _ = try await workbench.splitPane(firstPaneID, orientation: .horizontal)
        _ = try await workbench.splitPane(firstPaneID, orientation: .vertical)

        try await workbench.resizeSplit(
            in: sessionID,
            path: [.first],
            fraction: 0.7
        )

        let layout = try #require(await workbench.snapshot().workSessions.first?.layout)
        guard case .split(_, let rootFraction, let first, _) = layout,
              case .split(_, let nestedFraction, _, _) = first
        else {
            Issue.record("expected nested split")
            return
        }
        #expect(rootFraction == 0.5)
        #expect(nestedFraction == 0.7)
    }

    @Test("closing one pane collapses its split and stops only that terminal")
    func closePane() async throws {
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        _ = try await workbench.createWorkSession(in: workspaceID)
        let firstPaneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)
        let secondPaneID = try await workbench.splitPane(firstPaneID, orientation: .vertical)

        try await workbench.closePane(secondPaneID)

        #expect(await workbench.snapshot().workSessions.first?.layout.paneIDs == [firstPaneID])
        #expect(await runtime.stoppedPaneIDs == [secondPaneID])
    }

    @Test("closing a pane publishes the collapsed layout before destroying its terminal")
    func closePanePublishesLayoutBeforeStop() async throws {
        let runtime = SuspendedStopTerminalRuntime()
        let changes = ChangeRecorder()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        _ = try await workbench.createWorkSession(in: workspaceID)
        let firstPaneID = try #require(
            await workbench.snapshot().workSessions.first?.pane.id
        )
        let secondPaneID = try await workbench.splitPane(
            firstPaneID,
            orientation: .vertical
        )
        await workbench.setSnapshotChangeHandler {
            await changes.record()
        }

        let close = Task {
            try await workbench.closePane(secondPaneID)
        }
        for _ in 0..<1_000 {
            if await runtime.stopCallCount == 1 { break }
            await Task.yield()
        }

        #expect(await runtime.stopCallCount == 1)
        #expect(await changes.count == 1)
        await runtime.allowStops()
        try await close.value
    }

    @Test("the last pane cannot be closed independently")
    func rejectClosingLastPane() async throws {
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(),
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        _ = try await workbench.createWorkSession(in: workspaceID)
        let paneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)

        await #expect(throws: WorkbenchError.cannotCloseLastPane) {
            try await workbench.closePane(paneID)
        }
        #expect(await runtime.stoppedPaneIDs.isEmpty)
    }

    @Test("permanently deleting an archive removes only its Breath metadata")
    func deleteArchivedWorkSession() async throws {
        let repository = InMemoryWorkbenchRepository()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: RecordingTerminalRuntime(),
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
        )
        let sessionID = try await workbench.createWorkSession(in: workspaceID)
        try await workbench.archiveWorkSession(sessionID)

        try await workbench.deleteArchivedWorkSession(sessionID)

        #expect(await workbench.snapshot().workSessions.isEmpty)
        #expect(await repository.latestSnapshot?.workSessions.isEmpty == true)
    }

    @Test("lazy restore resumes bound Agents while plain panes open empty shells")
    func restoreAgentAndShellPanes() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let agentPaneID = TerminalPaneID(rawValue: UUID())
        let shellPaneID = TerminalPaneID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp/project", displayName: "project")],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Agent work",
                    layout: .split(
                        orientation: .horizontal,
                        fraction: 0.5,
                        first: .pane(
                            TerminalPane(
                                id: agentPaneID,
                                agentBinding: AgentBinding(
                                    agent: .codex,
                                    sessionID: "thread-123",
                                    isActive: true
                                )
                            )
                        ),
                        second: .pane(TerminalPane(id: shellPaneID))
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: snapshot),
            terminalRuntime: runtime,
            agentResumeCommands: FixedAgentResumeCommands(),
            defaultShell: { "/bin/zsh" }
        )

        try await workbench.restoreFromRepository()

        let launches = await runtime.launches
        #expect(launches[0].executable == "/usr/local/bin/codex")
        #expect(launches[0].arguments == ["resume", "thread-123"])
        #expect(launches[1].executable == "/bin/zsh")
        #expect(launches[1].arguments == ["-l"])
    }

    @Test("an Agent resume launch failure falls back to an idle shell in the saved layout")
    func failedAgentResumeFallsBackToShell() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp/project", displayName: "project")],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Agent work",
                    pane: TerminalPane(
                        id: paneID,
                        state: .running,
                        agentBinding: AgentBinding(
                            agent: .codex,
                            sessionID: "missing-thread",
                            isActive: true
                        )
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let repository = InMemoryWorkbenchRepository(snapshot: snapshot)
        let runtime = FailingAgentResumeRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            agentResumeCommands: FixedAgentResumeCommands(),
            defaultShell: { "/bin/zsh" }
        )

        try await workbench.restoreFromRepository()

        let attempts = await runtime.launchAttempts
        #expect(attempts.map(\.executable) == ["/usr/local/bin/codex", "/bin/zsh"])
        #expect(attempts[1].arguments == ["-l"])
        #expect(attempts[1].paneID == paneID)
        #expect(await workbench.snapshot().workSessions.first?.pane.state == .idle)
        #expect(await repository.latestSnapshot?.workSessions.first?.pane.state == .idle)
    }

    @Test("an asynchronously failed Agent recovery reopens the pane as an empty shell")
    func asynchronousAgentResumeFailureFallsBackToShell() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp/project", displayName: "project")],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Agent work",
                    pane: TerminalPane(
                        id: paneID,
                        state: .running,
                        agentBinding: AgentBinding(
                            agent: .codex,
                            sessionID: "missing-thread",
                            isActive: true
                        )
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let repository = InMemoryWorkbenchRepository(snapshot: snapshot)
        let runtime = ProcessExitTerminalRuntime()
        let changes = ChangeRecorder()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            agentResumeCommands: FixedAgentResumeCommands(),
            defaultShell: { "/bin/zsh" }
        )
        await workbench.setSnapshotChangeHandler {
            Task { await changes.record() }
        }

        try await workbench.restoreFromRepository()
        await runtime.emitProcessExit(paneID)
        for _ in 0..<1_000 {
            if await runtime.launches.count == 2 { break }
            await Task.yield()
        }

        #expect(await runtime.launches.map(\.executable) == ["/usr/local/bin/codex", "/bin/zsh"])
        #expect(await workbench.snapshot().workSessions.first?.pane.state == .idle)
        #expect(await workbench.snapshot().workSessions.first?.pane.agentBinding?.isActive == false)
        for _ in 0..<1_000 {
            if await changes.count == 1 { break }
            await Task.yield()
        }
        #expect(await changes.count == 1)
    }

    @Test("an Agent that exits before launch returns still falls back to a shell")
    func immediateAgentExitFallsBackToShell() async throws {
        let fixture = recoveryFixture()
        let runtime = ImmediateExitTerminalRuntime(agentExecutable: "/usr/local/bin/codex")
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: fixture.snapshot),
            terminalRuntime: runtime,
            agentResumeCommands: FixedAgentResumeCommands(),
            defaultShell: { "/bin/zsh" }
        )

        try await workbench.restoreFromRepository()
        for _ in 0..<1_000 {
            if await runtime.launches.count == 2 { break }
            await Task.yield()
        }

        #expect(await runtime.launches.map(\.executable) == ["/usr/local/bin/codex", "/bin/zsh"])
        #expect(await workbench.snapshot().workSessions.first?.pane.state == .idle)
    }

    @Test("multi-pane restore stops earlier panes when a later launch fails")
    func multiPaneRestoreIsAtomic() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let firstPaneID = TerminalPaneID(rawValue: UUID())
        let secondPaneID = TerminalPaneID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp/project", displayName: "project")],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Two shells",
                    layout: .split(
                        orientation: .horizontal,
                        fraction: 0.5,
                        first: .pane(TerminalPane(id: firstPaneID)),
                        second: .pane(TerminalPane(id: secondPaneID))
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let runtime = FailingNthLaunchRuntime(failingLaunch: 2)
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: snapshot),
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" }
        )

        await #expect(throws: FailingNthLaunchRuntime.Failure.launchFailed) {
            try await workbench.restoreFromRepository()
        }

        #expect(await runtime.stoppedPaneIDs.contains(firstPaneID))
    }

    @Test("archiving during recovery fallback cannot relaunch a hidden shell")
    func archiveCancelsRecoveryFallback() async throws {
        let fixture = recoveryFixture()
        let runtime = SuspendedStopTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: fixture.snapshot),
            terminalRuntime: runtime,
            agentResumeCommands: FixedAgentResumeCommands(),
            defaultShell: { "/bin/zsh" }
        )
        try await workbench.restoreFromRepository()

        await runtime.emitProcessExit(fixture.paneID)
        for _ in 0..<1_000 {
            if await runtime.stopCallCount > 0 { break }
            await Task.yield()
        }
        async let archive: Void = workbench.archiveWorkSession(fixture.sessionID)
        for _ in 0..<1_000 {
            if await workbench.snapshot().archivedWorkSessions.count == 1 { break }
            await Task.yield()
        }
        await runtime.allowStops()
        try await archive
        for _ in 0..<1_000 { await Task.yield() }

        #expect(await runtime.launches.map(\.executable) == ["/usr/local/bin/codex"])
        #expect(await workbench.snapshot().archivedWorkSessions.map(\.id) == [fixture.sessionID])
    }

    @Test("a fallback save failure stops the replacement shell")
    func fallbackSaveFailureStopsShell() async throws {
        let fixture = recoveryFixture()
        let repository = FailingSaveRepository(
            failingSaveNumbers: [1],
            snapshot: fixture.snapshot
        )
        let runtime = ProcessExitTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            agentResumeCommands: FixedAgentResumeCommands(),
            defaultShell: { "/bin/zsh" }
        )
        try await workbench.restoreFromRepository()

        await runtime.emitProcessExit(fixture.paneID)
        for _ in 0..<1_000 {
            if await runtime.stoppedPaneIDs.count >= 2 { break }
            await Task.yield()
        }

        #expect(await runtime.launches.map(\.executable) == ["/usr/local/bin/codex", "/bin/zsh"])
        #expect(await runtime.stoppedPaneIDs.count >= 2)
    }

    @Test("a cleanly ended Agent restores as an empty shell")
    func endedAgentRestoresAsShell() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp/project", displayName: "project")],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Ended Agent",
                    pane: TerminalPane(
                        id: paneID,
                        agentBinding: AgentBinding(
                            agent: .codex,
                            sessionID: "ended-thread",
                            isActive: false
                        )
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: InMemoryWorkbenchRepository(snapshot: snapshot),
            terminalRuntime: runtime,
            agentResumeCommands: FixedAgentResumeCommands(),
            defaultShell: { "/bin/zsh" }
        )

        try await workbench.restoreFromRepository()

        #expect(await runtime.launches.map(\.executable) == ["/bin/zsh"])
    }

    @Test("a failed session save rolls back metadata and stops the untracked terminal")
    func failedSessionSaveCompensatesLaunch() async throws {
        let repository = FailingSaveRepository(failingSaveNumbers: [2])
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        )

        await #expect(throws: TestPersistenceError.saveFailed) {
            try await workbench.createWorkSession(in: workspaceID)
        }

        #expect(await workbench.snapshot().workSessions.isEmpty)
        let launchedPaneID = try #require(await runtime.launches.first?.paneID)
        #expect(await runtime.stoppedPaneIDs == [launchedPaneID])
    }

    @Test("a failed workspace removal save retains metadata and running terminals")
    func failedWorkspaceRemovalRollsBack() async throws {
        let repository = FailingSaveRepository(failingSaveNumbers: [3])
        let runtime = RecordingTerminalRuntime()
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(
            at: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        )
        let sessionID = try await workbench.createWorkSession(in: workspaceID)

        await #expect(throws: TestPersistenceError.saveFailed) {
            try await workbench.removeWorkspace(workspaceID)
        }

        let snapshot = await workbench.snapshot()
        #expect(snapshot.workspaces.map(\.id) == [workspaceID])
        #expect(snapshot.workSessions.map(\.id) == [sessionID])
        #expect(await runtime.stoppedPaneIDs.isEmpty)
    }
}

private struct FixedAgentResumeCommands: AgentResumeCommandProviding {
    func resumeCommand(for binding: AgentBinding) -> AgentResumeCommand? {
        guard binding.agent == .codex, let sessionID = binding.sessionID else { return nil }
        return AgentResumeCommand(
            executable: "/usr/local/bin/codex",
            arguments: ["resume", sessionID]
        )
    }
}

private actor InMemoryWorkbenchRepository: WorkbenchRepository {
    private let effects: EffectLog?
    private(set) var latestSnapshot: WorkbenchSnapshot?

    init(snapshot: WorkbenchSnapshot? = nil, effects: EffectLog? = nil) {
        latestSnapshot = snapshot
        self.effects = effects
    }

    func load() async throws -> WorkbenchSnapshot {
        latestSnapshot ?? .empty
    }

    func save(_ snapshot: WorkbenchSnapshot) async throws {
        latestSnapshot = snapshot
        await effects?.append(.saved)
    }
}

private enum TestPersistenceError: Error {
    case saveFailed
}

private enum TestManagedWorktreeError: Error {
    case cleanupFailed
}

private actor FailingSaveRepository: WorkbenchRepository {
    private let failingSaveNumbers: Set<Int>
    private var saveCount = 0
    private var snapshot: WorkbenchSnapshot

    init(
        failingSaveNumbers: Set<Int>,
        snapshot: WorkbenchSnapshot = .empty
    ) {
        self.failingSaveNumbers = failingSaveNumbers
        self.snapshot = snapshot
    }

    func load() async throws -> WorkbenchSnapshot {
        snapshot
    }

    func save(_ snapshot: WorkbenchSnapshot) async throws {
        saveCount += 1
        guard !failingSaveNumbers.contains(saveCount) else {
            throw TestPersistenceError.saveFailed
        }
        self.snapshot = snapshot
    }
}

private actor SuspendedSaveRepository: WorkbenchRepository {
    private let suspendedSave: Int
    private var savesAllowed = false
    private var snapshot = WorkbenchSnapshot.empty
    private(set) var saveCallCount = 0

    init(suspendedSave: Int) {
        self.suspendedSave = suspendedSave
    }

    func load() async throws -> WorkbenchSnapshot {
        snapshot
    }

    func save(_ snapshot: WorkbenchSnapshot) async throws {
        saveCallCount += 1
        if saveCallCount == suspendedSave {
            while !savesAllowed { await Task.yield() }
        }
        self.snapshot = snapshot
    }

    func allowSaves() {
        savesAllowed = true
    }
}

private actor RecordingTerminalRuntime: TerminalRuntime {
    private let effects: EffectLog?
    private(set) var launches: [TerminalLaunch] = []
    private(set) var stoppedPaneIDs: [TerminalPaneID] = []

    init(effects: EffectLog? = nil) {
        self.effects = effects
    }

    func launch(_ request: TerminalLaunch) async throws {
        launches.append(request)
        await effects?.append(.launched(request.paneID))
    }

    func stop(paneID: TerminalPaneID) async {
        stoppedPaneIDs.append(paneID)
        await effects?.append(.stopped(paneID))
    }
}

private actor RecordingManagedWorktreeManager: ManagedWorktreeManaging {
    private var available: Bool
    private let removalError: TestManagedWorktreeError?
    private(set) var createdBranchNames: [String] = []
    private(set) var validatedBranchNames: [String] = []
    private(set) var removedBranchNames: [String] = []

    init(
        isAvailable: Bool = true,
        removalError: TestManagedWorktreeError? = nil
    ) {
        available = isAvailable
        self.removalError = removalError
    }

    func setAvailable(_ isAvailable: Bool) {
        available = isAvailable
    }

    func create(
        workspace: Workspace,
        workSessionID: WorkSessionID,
        branchName: String
    ) async throws -> ManagedWorktree {
        createdBranchNames.append(branchName)
        return ManagedWorktree(
            workspaceID: workspace.id,
            workSessionID: workSessionID,
            rootPath: "/tmp/breath-worktrees/workspace/session",
            gitCommonDirectory: "/tmp/example-project/.git",
            baselineCommit: "0123456789abcdef",
            workspaceRelativePath: "apps/client",
            branchName: branchName
        )
    }

    func isAvailable(_ worktree: ManagedWorktree) async -> Bool {
        available
    }

    func validateRemoval(_ worktree: ManagedWorktree) async throws {
        validatedBranchNames.append(worktree.branchName)
    }

    func remove(_ worktree: ManagedWorktree) async throws {
        removedBranchNames.append(worktree.branchName)
        if let removalError {
            throw removalError
        }
    }
}

private actor SuspendedLaunchTerminalRuntime: TerminalRuntime {
    private(set) var launchCallCount = 0
    private var launchesAllowed = false

    func launch(_ request: TerminalLaunch) async throws {
        launchCallCount += 1
        while !launchesAllowed { await Task.yield() }
    }

    func stop(paneID: TerminalPaneID) async {}

    func allowLaunches() {
        launchesAllowed = true
    }
}

private actor ProcessExitTerminalRuntime: TerminalRuntime {
    private(set) var launches: [TerminalLaunch] = []
    private(set) var stoppedPaneIDs: [TerminalPaneID] = []
    private var processExitHandler: (@Sendable (TerminalPaneID) -> Void)?

    func launch(_ request: TerminalLaunch) async throws {
        launches.append(request)
    }

    func stop(paneID: TerminalPaneID) async {
        stoppedPaneIDs.append(paneID)
    }

    func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async {
        processExitHandler = handler
    }

    func emitProcessExit(_ paneID: TerminalPaneID) {
        processExitHandler?(paneID)
    }
}

private actor ImmediateExitTerminalRuntime: TerminalRuntime {
    private let agentExecutable: String
    private(set) var launches: [TerminalLaunch] = []
    private var processExitHandler: (@Sendable (TerminalPaneID) -> Void)?

    init(agentExecutable: String) {
        self.agentExecutable = agentExecutable
    }

    func launch(_ request: TerminalLaunch) async throws {
        launches.append(request)
        if request.executable == agentExecutable {
            processExitHandler?(request.paneID)
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func stop(paneID: TerminalPaneID) async {}

    func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async {
        processExitHandler = handler
    }
}

private actor FailingNthLaunchRuntime: TerminalRuntime {
    enum Failure: Error {
        case launchFailed
    }

    private let failingLaunch: Int
    private var launchCount = 0
    private(set) var stoppedPaneIDs: [TerminalPaneID] = []

    init(failingLaunch: Int) {
        self.failingLaunch = failingLaunch
    }

    func launch(_ request: TerminalLaunch) async throws {
        launchCount += 1
        if launchCount == failingLaunch { throw Failure.launchFailed }
    }

    func stop(paneID: TerminalPaneID) async {
        stoppedPaneIDs.append(paneID)
    }
}

private actor SuspendedStopTerminalRuntime: TerminalRuntime {
    private(set) var launches: [TerminalLaunch] = []
    private(set) var stopCallCount = 0
    private var stopsAllowed = false
    private var processExitHandler: (@Sendable (TerminalPaneID) -> Void)?

    func launch(_ request: TerminalLaunch) async throws {
        launches.append(request)
    }

    func stop(paneID: TerminalPaneID) async {
        stopCallCount += 1
        while !stopsAllowed { await Task.yield() }
    }

    func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async {
        processExitHandler = handler
    }

    func emitProcessExit(_ paneID: TerminalPaneID) {
        processExitHandler?(paneID)
    }

    func allowStops() {
        stopsAllowed = true
    }
}

private func recoveryFixture() -> (
    snapshot: WorkbenchSnapshot,
    sessionID: WorkSessionID,
    paneID: TerminalPaneID
) {
    let workspaceID = WorkspaceID(rawValue: UUID())
    let sessionID = WorkSessionID(rawValue: UUID())
    let paneID = TerminalPaneID(rawValue: UUID())
    return (
        WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp/project", displayName: "project")],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Agent work",
                    pane: TerminalPane(
                        id: paneID,
                        state: .running,
                        agentBinding: AgentBinding(
                            agent: .codex,
                            sessionID: "thread",
                            isActive: true
                        )
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        ),
        sessionID,
        paneID
    )
}

private actor FailingAgentResumeRuntime: TerminalRuntime {
    enum Failure: Error {
        case unavailableAgent
    }

    private(set) var launchAttempts: [TerminalLaunch] = []

    func launch(_ request: TerminalLaunch) async throws {
        launchAttempts.append(request)
        if request.executable == "/usr/local/bin/codex" {
            throw Failure.unavailableAgent
        }
    }

    func stop(paneID: TerminalPaneID) async {}
}

private actor EffectLog {
    enum Value: Equatable, Sendable {
        case saved
        case launched(TerminalPaneID)
        case stopped(TerminalPaneID)
    }

    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }

    func clear() {
        values.removeAll()
    }
}

private actor ChangeRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
