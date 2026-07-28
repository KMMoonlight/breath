import BreathAutomation
import BreathCore
import BreathPersistence
import Foundation
import Testing

@Suite("SQLite automation repository")
struct SQLiteAutomationRepositoryTests {
    @Test("automation snapshot survives reopening the database")
    func automationSnapshotRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-automation-database-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("breath.sqlite")
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let workspaceID = WorkspaceID(rawValue: UUID())
        let automationID = AutomationID(rawValue: UUID())
        let expected = AutomationSnapshot(
            automations: [
                Automation(
                    id: automationID,
                    name: "Review",
                    workspaceID: workspaceID,
                    workspaceDisplayName: "Project",
                    workspacePath: "/project",
                    prompt: "Review this project",
                    agent: .codex,
                    trigger: .manual,
                    maximumDurationMinutes: 60,
                    isEnabled: true,
                    createdAt: timestamp,
                    updatedAt: timestamp
                ),
            ],
            runs: [
                AutomationRun(
                    id: AutomationRunID(rawValue: UUID()),
                    automationID: automationID,
                    status: .succeeded,
                    triggerSource: .manual,
                    queuedAt: timestamp,
                    startedAt: timestamp,
                    endedAt: timestamp,
                    effectiveDuration: 0,
                    agent: .codex,
                    finalOutput: "Done",
                    isViewed: false
                ),
            ],
            concurrencyLimit: 2
        )

        let repository = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        try await repository.saveAutomationSnapshot(expected)
        let reopened = try SQLiteWorkbenchRepository(databaseURL: databaseURL)

        #expect(try await reopened.loadAutomationSnapshot() == expected)
    }

    @Test("Automation service state machine persists through real SQLite")
    func serviceStateMachineRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-automation-service-database-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: directory.path,
            displayName: "SQLite project"
        )
        let databaseURL = directory.appendingPathComponent("breath.sqlite")
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: databaseURL
        )
        let service = AutomationService(
            repository: repository,
            runner: SQLiteAutomationRunner(),
            schedulesAutomatically: false
        )
        let availability: [AgentKind: AutomationAgentAvailability] = [
            .codex: .available(
                executablePath: "/usr/bin/true",
                currentVersion: "1.0.0"
            ),
        ]
        try await service.start(
            workspaces: [workspace],
            agentAvailabilities: availability
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Persisted run",
                workspaceID: workspace.id,
                prompt: "Return output",
                agent: .codex,
                trigger: .manual
            )
        )
        let runID = try await service.trigger(
            automationID,
            source: .manual
        )
        for _ in 0..<200 {
            if await service.snapshot().runs.first(where: {
                $0.id == runID
            })?.status == .succeeded {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await service.markViewed(runID)

        let reopened = AutomationService(
            repository: try SQLiteWorkbenchRepository(
                databaseURL: databaseURL
            ),
            runner: SQLiteAutomationRunner(),
            schedulesAutomatically: false
        )
        try await reopened.start(
            workspaces: [workspace],
            agentAvailabilities: availability
        )
        let snapshot = await reopened.snapshot()

        #expect(snapshot.automations.map(\.id) == [automationID])
        #expect(snapshot.runs.first?.id == runID)
        #expect(snapshot.runs.first?.status == .succeeded)
        #expect(snapshot.runs.first?.finalOutput == "SQLite result")
        #expect(snapshot.unreadCount == 0)
    }
}

private struct SQLiteAutomationRunner: AutomationRunning {
    func run(
        _ request: AutomationRunRequest
    ) async throws -> AutomationAgentResult {
        AutomationAgentResult(finalOutput: "SQLite result")
    }
}
