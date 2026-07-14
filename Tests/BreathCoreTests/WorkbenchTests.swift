import Foundation
import Testing
@testable import BreathCore

@Suite("Workbench application use cases")
struct WorkbenchTests {
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
        let paneID = try #require(await workbench.snapshot().workSessions.first?.pane.id)

        try await workbench.handleAgentEvent(
            AgentEvent(
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
                                agentBinding: AgentBinding(agent: .codex, sessionID: "thread-123")
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
                        agentBinding: AgentBinding(agent: .codex, sessionID: "missing-thread")
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

private actor RecordingTerminalRuntime: TerminalRuntime {
    private let effects: EffectLog?
    private(set) var launches: [TerminalLaunch] = []
    private(set) var stoppedPaneIDs: [TerminalPaneID] = []

    init(effects: EffectLog? = nil) {
        self.effects = effects
    }

    func launch(_ request: TerminalLaunch) async throws {
        launches.append(request)
    }

    func stop(paneID: TerminalPaneID) async {
        stoppedPaneIDs.append(paneID)
        await effects?.append(.stopped(paneID))
    }
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
