import BreathAutomation
import BreathCore
import Foundation
import Testing

@Suite("Automation service")
struct AutomationServiceTests {
    @Test("user can save and run a manual Codex automation without changing the Workspace")
    func saveAndRunManualCodexAutomation() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let repository = InMemoryAutomationRepository()
        let runner = RecordingAutomationRunner(
            result: AutomationAgentResult(
                finalOutput: "# Review\n\nThe project is healthy.",
                model: "test-model"
            )
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let service = AutomationService(
            repository: repository,
            runner: runner,
            now: { now },
            schedulesAutomatically: false,
            startingGitCommit: { _ in "abc123" }
        )

        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Review project",
                workspaceID: fixture.workspace.id,
                prompt: "Review this project",
                agent: .codex,
                trigger: .manual,
                maximumDurationMinutes: 60
            )
        )

        let created = await service.snapshot()
        #expect(created.automations.map(\.id) == [automationID])
        #expect(created.automations.first?.isEnabled == true)
        #expect(created.runs.isEmpty)

        let runID = try await service.trigger(automationID, source: .manual)
        let completed = try await terminalRun(runID, from: service)
        let requests = await runner.recordedRequests()

        #expect(completed.status == .succeeded)
        #expect(completed.finalOutput == "# Review\n\nThe project is healthy.")
        #expect(completed.model == "test-model")
        #expect(completed.startingGitCommit == "abc123")
        #expect(requests.count == 1)
        #expect(requests.first?.workspacePath == fixture.workspace.path)
        #expect(requests.first?.prompt.contains("Review this project") == true)
        #expect(try String(contentsOf: fixture.projectFile, encoding: .utf8) == "original")

        let reopened = AutomationService(
            repository: repository,
            runner: runner,
            now: { now },
            schedulesAutomatically: false
        )
        try await reopened.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let reopenedSnapshot = await reopened.snapshot()
        let originalSnapshot = await service.snapshot()
        #expect(reopenedSnapshot == originalSnapshot)
    }

    @Test("user can manage duplicate automations and explicitly recover dependencies")
    func manageAutomationsAndDependencies() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let clock = TestNow(Date(timeIntervalSince1970: 1_800_000_000))
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: RecordingAutomationRunner(
                result: AutomationAgentResult(finalOutput: "Done")
            ),
            now: { clock.value },
            schedulesAutomatically: false
        )
        let availability: [AgentKind: AutomationAgentAvailability] = [
            .codex: .available(
                executablePath: "/usr/bin/true",
                currentVersion: "1.0.0"
            ),
        ]
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: availability
        )

        let firstID = try await service.create(
            AutomationDraft(
                name: "Duplicate",
                workspaceID: fixture.workspace.id,
                prompt: "First",
                agent: .codex,
                trigger: .manual
            )
        )
        clock.advance(by: 1)
        let secondID = try await service.create(
            AutomationDraft(
                name: "Duplicate",
                workspaceID: fixture.workspace.id,
                prompt: "Second",
                agent: .codex,
                trigger: .manual
            )
        )
        #expect(await service.snapshot().automations.map(\.id) == [secondID, firstID])

        try await service.update(
            firstID,
            with: AutomationDraft(
                name: "Duplicate",
                workspaceID: fixture.workspace.id,
                prompt: "Edited",
                agent: .codex,
                trigger: .manual,
                maximumDurationMinutes: 30
            )
        )
        try await service.setEnabled(false, for: firstID)
        let edited = try #require(
            await service.snapshot().automations.first { $0.id == firstID }
        )
        #expect(edited.prompt == "Edited")
        #expect(edited.maximumDurationMinutes == 30)
        #expect(edited.isEnabled == false)

        try await service.updateEnvironment(
            workspaces: [],
            agentAvailabilities: availability
        )
        let paused = try #require(
            await service.snapshot().automations.first { $0.id == firstID }
        )
        #expect(paused.dependencyPauseReason != nil)
        #expect(!paused.isEnabled)
        #expect(paused.requiresExplicitReenable)

        try await service.updateEnvironment(
            workspaces: [fixture.workspace],
            agentAvailabilities: availability
        )
        let restored = try #require(
            await service.snapshot().automations.first { $0.id == firstID }
        )
        #expect(restored.dependencyPauseReason == nil)
        #expect(!restored.isEnabled)
        #expect(restored.requiresExplicitReenable)

        try await service.setEnabled(true, for: firstID)
        let reenabled = try #require(
            await service.snapshot().automations.first { $0.id == firstID }
        )
        #expect(reenabled.isEnabled)
        #expect(!reenabled.requiresExplicitReenable)

        try await service.delete(secondID)
        #expect(await service.snapshot().automations.map(\.id) == [firstID])
    }

    @Test("runs respect the global queue and only completed results count as unread")
    func queueCancelSkipAndUnread() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let runner = SuspendingAutomationRunner()
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: runner,
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        try await service.setConcurrencyLimit(1)
        let firstID = try await service.create(
            AutomationDraft(
                name: "First",
                workspaceID: fixture.workspace.id,
                prompt: "First",
                agent: .codex,
                trigger: .manual
            )
        )
        let secondID = try await service.create(
            AutomationDraft(
                name: "Second",
                workspaceID: fixture.workspace.id,
                prompt: "Second",
                agent: .codex,
                trigger: .manual
            )
        )

        let activeRunID = try await service.trigger(firstID, source: .manual)
        let queuedRunID = try await service.trigger(secondID, source: .manual)
        let skippedRunID = try await service.trigger(firstID, source: .manual)
        var snapshot = await service.snapshot()
        #expect(snapshot.runs.first { $0.id == activeRunID }?.status == .running)
        #expect(snapshot.runs.first { $0.id == queuedRunID }?.status == .queued)
        #expect(snapshot.runs.first { $0.id == skippedRunID }?.status == .skipped)

        try await service.cancel(queuedRunID)
        await runner.complete(
            activeRunID,
            with: AutomationAgentResult(finalOutput: "Complete")
        )
        let completed = try await terminalRun(activeRunID, from: service)
        snapshot = await service.snapshot()

        #expect(completed.status == .succeeded)
        #expect(snapshot.runs.first { $0.id == queuedRunID }?.status == .canceled)
        #expect(snapshot.unreadCount == 1)

        try await service.markViewed(activeRunID)
        #expect(await service.snapshot().unreadCount == 0)
    }

    @Test("external shortcodes are stable, regenerable, and honor enabled state")
    func externalShortcodes() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: RecordingAutomationRunner(
                result: AutomationAgentResult(finalOutput: "Triggered")
            ),
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "External",
                workspaceID: fixture.workspace.id,
                prompt: "Run externally",
                agent: .codex,
                trigger: .external
            )
        )
        let originalCode = try #require(
            await service.snapshot().automations.first {
                $0.id == automationID
            }?.externalShortcode
        )

        let firstRunID = try await service.trigger(shortcode: originalCode)
        _ = try await terminalRun(firstRunID, from: service)
        let regenerated = try await service.regenerateShortcode(for: automationID)

        #expect(regenerated != originalCode)
        await #expect(throws: AutomationError.invalidShortcode) {
            try await service.trigger(shortcode: originalCode)
        }

        try await service.setEnabled(false, for: automationID)
        await #expect(throws: AutomationError.disabled) {
            try await service.trigger(shortcode: regenerated)
        }
    }

    @Test("runner timeout is a distinct unread terminal result")
    func timeoutStatus() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: FailingAutomationRunner(error: .timedOut),
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Timeout",
                workspaceID: fixture.workspace.id,
                prompt: "Keep working",
                agent: .codex,
                trigger: .manual
            )
        )

        let runID = try await service.trigger(automationID, source: .manual)
        let run = try await terminalRun(runID, from: service)

        #expect(run.status == .timedOut)
        #expect(run.errorSummary == "Agent 运行超过最大时长。")
        #expect(await service.snapshot().unreadCount == 1)
    }

    @Test("empty final output is a failed unread result")
    func emptyFinalOutputIsUnreadFailure() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: RecordingAutomationRunner(
                result: AutomationAgentResult(finalOutput: " \n ")
            ),
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Empty",
                workspaceID: fixture.workspace.id,
                prompt: "Return a result",
                agent: .codex,
                trigger: .manual
            )
        )

        let runID = try await service.trigger(automationID, source: .manual)
        let run = try await terminalRun(runID, from: service)

        #expect(run.status == .failed)
        #expect(!run.isViewed)
        #expect(await service.snapshot().unreadCount == 1)
    }

    @Test("only five UTF-8 bounded final results are retained")
    func retainsFiveBoundedResults() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let oversizedOutput = String(repeating: "🙂", count: 70_000)
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: RecordingAutomationRunner(
                result: AutomationAgentResult(finalOutput: oversizedOutput)
            ),
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Bounded history",
                workspaceID: fixture.workspace.id,
                prompt: "Return a long result",
                agent: .codex,
                trigger: .manual
            )
        )

        for _ in 0..<6 {
            let runID = try await service.trigger(
                automationID,
                source: .manual
            )
            _ = try await terminalRun(runID, from: service)
        }
        let snapshot = await service.snapshot()
        let runs = snapshot.runs(for: automationID)

        #expect(runs.count == 5)
        #expect(snapshot.unreadCount == 5)
        #expect(runs.allSatisfy { $0.outputWasTruncated })
        #expect(
            runs.allSatisfy {
                ($0.finalOutput?.utf8.count ?? 0) <= 256 * 1_024
            }
        )
    }

    @Test("startup repairs stale runs without restarting them")
    func repairsStaleRuns() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let automationID = AutomationID(rawValue: UUID())
        let staleRunningID = AutomationRunID(rawValue: UUID())
        let staleQueuedID = AutomationRunID(rawValue: UUID())
        let repository = InMemoryAutomationRepository(
            stored: AutomationSnapshot(
                automations: [
                    Automation(
                        id: automationID,
                        name: "Recover",
                        workspaceID: fixture.workspace.id,
                        workspaceDisplayName: fixture.workspace.displayName,
                        workspacePath: fixture.workspace.path,
                        prompt: "Check",
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
                        id: staleRunningID,
                        automationID: automationID,
                        status: .running,
                        triggerSource: .manual,
                        queuedAt: timestamp,
                        startedAt: timestamp,
                        agent: .codex
                    ),
                    AutomationRun(
                        id: staleQueuedID,
                        automationID: automationID,
                        status: .queued,
                        triggerSource: .scheduled,
                        queuedAt: timestamp,
                        agent: .codex
                    ),
                ],
                concurrencyLimit: 2
            )
        )
        let runner = RecordingAutomationRunner(
            result: AutomationAgentResult(finalOutput: "must not run")
        )
        let service = AutomationService(
            repository: repository,
            runner: runner,
            now: { timestamp.addingTimeInterval(30) },
            schedulesAutomatically: false
        )

        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )

        let snapshot = await service.snapshot()
        #expect(snapshot.runs.first { $0.id == staleRunningID }?.status == .interrupted)
        #expect(snapshot.runs.first { $0.id == staleQueuedID }?.status == .canceled)
        #expect(snapshot.unreadCount == 1)
        #expect(await runner.recordedRequests().isEmpty)
    }

    @Test("confirmed termination interrupts active runs and cancels queued runs")
    func preparesForTermination() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let runner = SuspendingAutomationRunner()
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: runner,
            schedulesAutomatically: false
        )
        let availability: [AgentKind: AutomationAgentAvailability] = [
            .codex: .available(
                executablePath: "/usr/bin/true",
                currentVersion: "1.0.0"
            ),
        ]
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: availability
        )
        try await service.setConcurrencyLimit(1)
        let first = try await service.create(
            AutomationDraft(
                name: "Running",
                workspaceID: fixture.workspace.id,
                prompt: "Wait",
                agent: .codex,
                trigger: .manual
            )
        )
        let second = try await service.create(
            AutomationDraft(
                name: "Queued",
                workspaceID: fixture.workspace.id,
                prompt: "Wait",
                agent: .codex,
                trigger: .manual
            )
        )
        let runningID = try await service.trigger(first, source: .manual)
        let queuedID = try await service.trigger(second, source: .manual)

        #expect(await service.hasActiveRuns)
        try await service.prepareForTermination()

        let snapshot = await service.snapshot()
        #expect(snapshot.runs.first { $0.id == runningID }?.status == .interrupted)
        #expect(snapshot.runs.first { $0.id == queuedID }?.status == .canceled)
        #expect(snapshot.unreadCount == 1)
        #expect(!(await service.hasActiveRuns))
    }

    @Test("a rejected persistence write cannot leave a runnable ghost run")
    func failedTriggerPersistenceRollsBack() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let repository = FailingAutomationRepository()
        let runner = RecordingAutomationRunner(
            result: AutomationAgentResult(finalOutput: "Must not run")
        )
        let service = AutomationService(
            repository: repository,
            runner: runner,
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Persist first",
                workspaceID: fixture.workspace.id,
                prompt: "Do not start after rejection",
                agent: .codex,
                trigger: .manual
            )
        )
        await repository.failNextSave()

        await #expect(throws: FailingRepositoryError.saveRejected) {
            _ = try await service.trigger(automationID, source: .manual)
        }

        #expect(await service.snapshot().runs.isEmpty)
        #expect(await runner.recordedRequests().isEmpty)
    }

    @Test("shortcode regeneration is atomic when persistence fails")
    func failedShortcodePersistenceRollsBack() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let repository = FailingAutomationRepository()
        let service = AutomationService(
            repository: repository,
            runner: RecordingAutomationRunner(
                result: AutomationAgentResult(finalOutput: "Done")
            ),
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "External",
                workspaceID: fixture.workspace.id,
                prompt: "Trigger",
                agent: .codex,
                trigger: .external
            )
        )
        let original = try #require(
            await service.snapshot().automations.first?
                .externalShortcode
        )
        await repository.failNextSave()

        await #expect(throws: FailingRepositoryError.saveRejected) {
            _ = try await service.regenerateShortcode(for: automationID)
        }

        #expect(
            await service.snapshot().automations.first?
                .externalShortcode == original
        )
    }

    @Test("queued runs start in global FIFO order")
    func queuedRunsUseFIFO() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let runner = SuspendingAutomationRunner()
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: runner,
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        try await service.setConcurrencyLimit(1)
        var automationIDs: [AutomationID] = []
        for name in ["A", "B", "C"] {
            automationIDs.append(
                try await service.create(
                    AutomationDraft(
                        name: name,
                        workspaceID: fixture.workspace.id,
                        prompt: name,
                        agent: .codex,
                        trigger: .manual
                    )
                )
            )
        }
        var runIDs: [AutomationRunID] = []
        for automationID in automationIDs {
            runIDs.append(
                try await service.trigger(
                    automationID,
                    source: .manual
                )
            )
        }

        await runner.complete(
            runIDs[0],
            with: AutomationAgentResult(finalOutput: "A")
        )
        try await waitForStartedRuns(2, runner: runner)
        await runner.complete(
            runIDs[1],
            with: AutomationAgentResult(finalOutput: "B")
        )
        try await waitForStartedRuns(3, runner: runner)

        #expect(await runner.startedRunIDs() == runIDs)
        await runner.complete(
            runIDs[2],
            with: AutomationAgentResult(finalOutput: "C")
        )
    }

    @Test("termination closes the service to late triggers")
    func terminationRejectsLateTriggers() async throws {
        let fixture = try AutomationFixture()
        defer { fixture.remove() }
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: RecordingAutomationRunner(
                result: AutomationAgentResult(finalOutput: "Done")
            ),
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Closing",
                workspaceID: fixture.workspace.id,
                prompt: "Do not start",
                agent: .codex,
                trigger: .manual
            )
        )
        try await service.prepareForTermination()

        await #expect(throws: AutomationError.notStarted) {
            _ = try await service.trigger(automationID, source: .manual)
        }
    }

    @Test("trigger revalidates a workspace that disappeared after detection")
    func triggerPausesMissingWorkspace() async throws {
        let fixture = try AutomationFixture()
        let service = AutomationService(
            repository: InMemoryAutomationRepository(),
            runner: RecordingAutomationRunner(
                result: AutomationAgentResult(finalOutput: "Must not run")
            ),
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: [
                .codex: .available(
                    executablePath: "/usr/bin/true",
                    currentVersion: "1.0.0"
                ),
            ]
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Missing workspace",
                workspaceID: fixture.workspace.id,
                prompt: "Check",
                agent: .codex,
                trigger: .manual
            )
        )
        fixture.remove()

        await #expect(throws: AutomationError.self) {
            _ = try await service.trigger(automationID, source: .manual)
        }
        let automation = try #require(
            await service.snapshot().automations.first
        )
        #expect(!automation.isEnabled)
        #expect(automation.requiresExplicitReenable)
        #expect(automation.dependencyPauseReason != nil)
        #expect(await service.snapshot().runs.isEmpty)
    }

    private func terminalRun(
        _ runID: AutomationRunID,
        from service: AutomationService
    ) async throws -> AutomationRun {
        for _ in 0..<200 {
            if let run = await service.snapshot().runs.first(where: { $0.id == runID }),
               run.status.isTerminal
            {
                return run
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw AutomationTestError.runDidNotFinish
    }

    private func waitForStartedRuns(
        _ count: Int,
        runner: SuspendingAutomationRunner
    ) async throws {
        for _ in 0..<200 {
            if await runner.startedRunIDs().count >= count {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw AutomationTestError.runDidNotFinish
    }
}

private enum AutomationTestError: Error {
    case runDidNotFinish
}

private struct AutomationFixture {
    let root: URL
    let projectFile: URL
    let workspace: Workspace

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-automation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        projectFile = root.appendingPathComponent("project.txt")
        try Data("original".utf8).write(to: projectFile)
        workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: root.path,
            displayName: "Project"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor InMemoryAutomationRepository: AutomationRepository {
    private var stored: AutomationSnapshot

    init(stored: AutomationSnapshot = .empty) {
        self.stored = stored
    }

    func loadAutomationSnapshot() async throws -> AutomationSnapshot {
        stored
    }

    func saveAutomationSnapshot(_ snapshot: AutomationSnapshot) async throws {
        stored = snapshot
    }
}

private enum FailingRepositoryError: Error {
    case saveRejected
}

private actor FailingAutomationRepository: AutomationRepository {
    private var stored = AutomationSnapshot.empty
    private var rejectsNextSave = false

    func loadAutomationSnapshot() async throws -> AutomationSnapshot {
        stored
    }

    func saveAutomationSnapshot(_ snapshot: AutomationSnapshot) async throws {
        if rejectsNextSave {
            rejectsNextSave = false
            throw FailingRepositoryError.saveRejected
        }
        stored = snapshot
    }

    func failNextSave() {
        rejectsNextSave = true
    }
}

private actor RecordingAutomationRunner: AutomationRunning {
    private let result: AutomationAgentResult
    private var requests: [AutomationRunRequest] = []

    init(result: AutomationAgentResult) {
        self.result = result
    }

    func run(_ request: AutomationRunRequest) async throws -> AutomationAgentResult {
        requests.append(request)
        return result
    }

    func recordedRequests() -> [AutomationRunRequest] {
        requests
    }
}

private actor SuspendingAutomationRunner: AutomationRunning {
    private var continuations:
        [AutomationRunID: CheckedContinuation<AutomationAgentResult, Error>] = [:]
    private var pendingResults: [AutomationRunID: AutomationAgentResult] = [:]
    private var starts: [AutomationRunID] = []

    func run(_ request: AutomationRunRequest) async throws -> AutomationAgentResult {
        starts.append(request.runID)
        if let result = pendingResults.removeValue(forKey: request.runID) {
            return result
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[request.runID] = continuation
            }
        } onCancel: {
            Task {
                await self.cancel(request.runID)
            }
        }
    }

    func complete(
        _ runID: AutomationRunID,
        with result: AutomationAgentResult
    ) {
        if let continuation = continuations.removeValue(forKey: runID) {
            continuation.resume(returning: result)
        } else {
            pendingResults[runID] = result
        }
    }

    func startedRunIDs() -> [AutomationRunID] {
        starts
    }

    private func cancel(_ runID: AutomationRunID) {
        continuations.removeValue(forKey: runID)?.resume(throwing: CancellationError())
    }
}

private struct FailingAutomationRunner: AutomationRunning {
    let error: AutomationRunnerError

    func run(_ request: AutomationRunRequest) async throws -> AutomationAgentResult {
        throw error
    }
}

private final class TestNow: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(_ value: Date) {
        stored = value
    }

    var value: Date {
        lock.withLock { stored }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock {
            stored = stored.addingTimeInterval(seconds)
        }
    }
}
