import BreathAutomation
import BreathCore
import Foundation
import Testing

@Suite("Automation scheduling")
struct AutomationSchedulingTests {
    @Test("one-time schedule runs once and disables itself")
    func oneTimeScheduleRunsOnce() async throws {
        let fixture = try SchedulingFixture()
        defer { fixture.remove() }
        let clock = SchedulingNow(Date(timeIntervalSince1970: 1_800_000_000))
        let repository = SchedulingRepository()
        let runner = SchedulingRunner()
        let service = AutomationService(
            repository: repository,
            runner: runner,
            now: { clock.value },
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: fixture.availability
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Once",
                workspaceID: fixture.workspace.id,
                prompt: "Run once",
                agent: .codex,
                trigger: .once(clock.value.addingTimeInterval(60))
            )
        )

        clock.advance(by: 60)
        try await service.reconcileSchedules(
            at: clock.value,
            reason: .timer
        )
        let run = try await waitForRun(in: service) { $0.status == .succeeded }
        let automation = try #require(
            await service.snapshot().automations.first { $0.id == automationID }
        )

        #expect(run.triggerSource == .scheduled)
        #expect(!automation.isEnabled)
        #expect(await runner.requestCount() == 1)
    }

    @Test("missed intervals coalesce without running or creating unread results")
    func missedIntervalsCoalesce() async throws {
        let fixture = try SchedulingFixture()
        defer { fixture.remove() }
        let clock = SchedulingNow(Date(timeIntervalSince1970: 1_800_000_000))
        let runner = SchedulingRunner()
        let service = AutomationService(
            repository: SchedulingRepository(),
            runner: runner,
            now: { clock.value },
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: fixture.availability
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "Interval",
                workspaceID: fixture.workspace.id,
                prompt: "Run repeatedly",
                agent: .codex,
                trigger: .interval(
                    AutomationInterval(value: 5, unit: .minutes)
                )
            )
        )

        clock.advance(by: 16 * 60)
        try await service.reconcileSchedules(
            at: clock.value,
            reason: .resumed
        )
        let snapshot = await service.snapshot()
        let missed = try #require(
            snapshot.runs.first {
                $0.automationID == automationID && $0.status == .missed
            }
        )

        #expect(missed.missedOccurrences?.count == 3)
        #expect(snapshot.unreadCount == 0)
        #expect(await runner.requestCount() == 0)
    }

    @Test("five-field Cron previews the next three occurrences in the selected timezone")
    func cronPreview() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(
            ISO8601DateFormatter().date(from: "2027-01-04T08:30:00Z")
        )

        let preview = try AutomationService.previewOccurrences(
            for: .cron("0 9 * * 1"),
            after: start,
            timeZone: timeZone,
            count: 3
        )

        #expect(preview.map(ISO8601DateFormatter().string(from:)) == [
            "2027-01-04T09:00:00Z",
            "2027-01-11T09:00:00Z",
            "2027-01-18T09:00:00Z",
        ])
        #expect(throws: AutomationError.invalidTrigger) {
            try AutomationService.previewOccurrences(
                for: .cron("@daily"),
                after: start,
                timeZone: timeZone,
                count: 3
            )
        }
    }

    @Test("Interval preview keeps the persisted phase anchor")
    func intervalPreviewUsesPersistedAnchor() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let anchor = try #require(
            ISO8601DateFormatter().date(from: "2027-01-04T09:00:00Z")
        )
        let current = try #require(
            ISO8601DateFormatter().date(from: "2027-01-04T09:30:00Z")
        )

        let preview = try AutomationService.previewOccurrences(
            for: .interval(
                AutomationInterval(value: 1, unit: .hours)
            ),
            anchor: anchor,
            after: current,
            timeZone: timeZone,
            count: 1
        )

        #expect(
            preview.first.map(ISO8601DateFormatter().string(from:))
                == "2027-01-04T10:00:00Z"
        )
    }

    @Test("Cron does not repeat the same local minute during daylight-saving fallback")
    func cronSkipsRepeatedLocalMinute() throws {
        let timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        let start = try #require(
            ISO8601DateFormatter().date(from: "2026-11-01T04:00:00Z")
        )

        let preview = try AutomationService.previewOccurrences(
            for: .cron("30 1 * * *"),
            after: start,
            timeZone: timeZone,
            count: 2
        )

        #expect(preview.map(ISO8601DateFormatter().string(from:)) == [
            "2026-11-01T05:30:00Z",
            "2026-11-02T06:30:00Z",
        ])
    }

    @Test("a daylight-saving gap becomes one missed local occurrence")
    func daylightSavingGapIsMissed() async throws {
        let fixture = try SchedulingFixture()
        defer { fixture.remove() }
        let timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        let start = try #require(
            ISO8601DateFormatter().date(from: "2026-03-08T05:00:00Z")
        )
        let end = try #require(
            ISO8601DateFormatter().date(from: "2026-03-08T08:00:00Z")
        )
        let clock = SchedulingNow(start)
        let runner = SchedulingRunner()
        let service = AutomationService(
            repository: SchedulingRepository(),
            runner: runner,
            now: { clock.value },
            timeZone: { timeZone },
            schedulesAutomatically: false
        )
        try await service.start(
            workspaces: [fixture.workspace],
            agentAvailabilities: fixture.availability
        )
        let automationID = try await service.create(
            AutomationDraft(
                name: "DST gap",
                workspaceID: fixture.workspace.id,
                prompt: "Run at a missing time",
                agent: .codex,
                trigger: .daily(hour: 2, minute: 30)
            )
        )

        try await service.reconcileSchedules(at: end, reason: .resumed)
        let snapshot = await service.snapshot()
        let missed = try #require(
            snapshot.runs.first {
                $0.automationID == automationID && $0.status == .missed
            }
        )

        #expect(missed.missedOccurrences?.count == 1)
        #expect(await runner.requestCount() == 0)
        #expect(snapshot.unreadCount == 0)
    }

    private func waitForRun(
        in service: AutomationService,
        matching predicate: (AutomationRun) -> Bool
    ) async throws -> AutomationRun {
        for _ in 0..<200 {
            if let run = await service.snapshot().runs.first(where: predicate) {
                return run
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw SchedulingTestError.runDidNotFinish
    }
}

private enum SchedulingTestError: Error {
    case runDidNotFinish
}

private struct SchedulingFixture {
    let root: URL
    let workspace: Workspace

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-scheduling-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: root.path,
            displayName: "Project"
        )
    }

    var availability: [AgentKind: AutomationAgentAvailability] {
        [
            .codex: .available(
                executablePath: "/usr/bin/true",
                currentVersion: "1.0.0"
            ),
        ]
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor SchedulingRepository: AutomationRepository {
    private var stored = AutomationSnapshot.empty

    func loadAutomationSnapshot() async throws -> AutomationSnapshot {
        stored
    }

    func saveAutomationSnapshot(_ snapshot: AutomationSnapshot) async throws {
        stored = snapshot
    }
}

private actor SchedulingRunner: AutomationRunning {
    private var requests: [AutomationRunRequest] = []

    func run(_ request: AutomationRunRequest) async throws -> AutomationAgentResult {
        requests.append(request)
        return AutomationAgentResult(finalOutput: "Scheduled result")
    }

    func requestCount() -> Int {
        requests.count
    }
}

private final class SchedulingNow: @unchecked Sendable {
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
