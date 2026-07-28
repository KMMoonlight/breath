import BreathCore
import Foundation

public actor AutomationService {
    public typealias SnapshotChangeHandler = @Sendable () async -> Void

    private let repository: any AutomationRepository
    private let runner: any AutomationRunning
    private let now: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone
    private let schedulesAutomatically: Bool
    private let startingGitCommit: @Sendable (String) -> String?
    private var currentSnapshot: AutomationSnapshot = .empty
    private var workspaces: [WorkspaceID: Workspace] = [:]
    private var agentAvailabilities: [AgentKind: AutomationAgentAvailability] = [:]
    private var runTasks: [AutomationRunID: Task<Void, Never>] = [:]
    private var runStartInstants:
        [AutomationRunID: SuspendingClock.Instant] = [:]
    private var scheduleTask: Task<Void, Never>?
    private var snapshotChangeHandler: SnapshotChangeHandler?
    private var started = false
    private var terminating = false
    private var lastPersistedSnapshot: AutomationSnapshot = .empty
    private let mutationGate = AutomationMutationGate()

    public init(
        repository: any AutomationRepository,
        runner: any AutomationRunning,
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        schedulesAutomatically: Bool = true,
        startingGitCommit: @escaping @Sendable (String) -> String? = { _ in nil }
    ) {
        self.repository = repository
        self.runner = runner
        self.now = now
        self.timeZone = timeZone
        self.schedulesAutomatically = schedulesAutomatically
        self.startingGitCommit = startingGitCommit
    }

    public func start(
        workspaces: [Workspace],
        agentAvailabilities: [AgentKind: AutomationAgentAvailability]
    ) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        self.workspaces = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
        self.agentAvailabilities = agentAvailabilities
        guard !started else {
            try await reconcileDependencies()
            return
        }
        currentSnapshot = try await repository.loadAutomationSnapshot()
        lastPersistedSnapshot = currentSnapshot
        try await runner.prepareForStartup()
        started = true
        try await repairStaleRuns()
        try await reconcileDependencies()
        if schedulesAutomatically {
            try await reconcileSchedulesLocked(at: now(), reason: .resumed)
            startAutomaticScheduling()
        }
        await publishSnapshotChange()
    }

    public func setSnapshotChangeHandler(
        _ handler: SnapshotChangeHandler?
    ) {
        snapshotChangeHandler = handler
    }

    public func snapshot() -> AutomationSnapshot {
        currentSnapshot
    }

    public var hasActiveRuns: Bool {
        currentSnapshot.runs.contains { $0.status == .running }
    }

    public func prepareForTermination() async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        terminating = true
        stopScheduling()
        let timestamp = now()
        var affectedAutomationIDs: Set<AutomationID> = []
        for index in currentSnapshot.runs.indices {
            switch currentSnapshot.runs[index].status {
            case .running:
                currentSnapshot.runs[index].status = .interrupted
                currentSnapshot.runs[index].endedAt = timestamp
                currentSnapshot.runs[index].effectiveDuration = effectiveDuration(
                    for: currentSnapshot.runs[index].id,
                    fallbackStart: currentSnapshot.runs[index].startedAt,
                    end: timestamp
                )
                currentSnapshot.runs[index].errorSummary =
                    "Breath 退出，运行已中断。"
                currentSnapshot.runs[index].isViewed = false
                affectedAutomationIDs.insert(
                    currentSnapshot.runs[index].automationID
                )
            case .queued:
                currentSnapshot.runs[index].status = .canceled
                currentSnapshot.runs[index].endedAt = timestamp
                currentSnapshot.runs[index].effectiveDuration = 0
                affectedAutomationIDs.insert(
                    currentSnapshot.runs[index].automationID
                )
            default:
                break
            }
        }
        let tasks = Array(runTasks.values)
        runTasks.removeAll()
        for task in tasks {
            task.cancel()
        }
        for task in tasks {
            await task.value
        }
        for automationID in affectedAutomationIDs {
            trimRuns(for: automationID)
        }
        try await persistAndPublish()
    }

    public func create(_ draft: AutomationDraft) async throws -> AutomationID {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        try requireAcceptingOperations()
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw AutomationError.invalidName }
        guard !normalizedPrompt.isEmpty else { throw AutomationError.invalidPrompt }
        guard draft.maximumDurationMinutes > 0 else {
            throw AutomationError.invalidMaximumDuration
        }
        guard let workspace = workspaces[draft.workspaceID] else {
            throw AutomationError.workspaceNotFound(draft.workspaceID)
        }
        guard let availability = agentAvailabilities[draft.agent],
              availability.executablePath != nil
        else {
            throw AutomationError.agentUnavailable(
                agentAvailabilities[draft.agent]?.unavailableReason
                    ?? "所选 Agent 当前不可用于自动化。"
            )
        }
        try validate(trigger: draft.trigger, now: now())

        let timestamp = now()
        let id = AutomationID(rawValue: UUID())
        let externalShortcode = draft.trigger == .external
            ? makeUniqueShortcode()
            : nil
        currentSnapshot.automations.append(
            Automation(
                id: id,
                name: normalizedName,
                workspaceID: workspace.id,
                workspaceDisplayName: workspace.displayName,
                workspacePath: workspace.path,
                prompt: normalizedPrompt,
                agent: draft.agent,
                trigger: draft.trigger,
                maximumDurationMinutes: draft.maximumDurationMinutes,
                isEnabled: true,
                externalShortcode: externalShortcode,
                intervalAnchor: intervalAnchor(for: draft.trigger, at: timestamp),
                lastScheduleEvaluationAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        )
        sortAutomations()
        try await persistAndPublish()
        return id
    }

    public func update(
        _ automationID: AutomationID,
        with draft: AutomationDraft
    ) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        try requireAcceptingOperations()
        guard let index = currentSnapshot.automations.firstIndex(where: {
            $0.id == automationID
        }) else {
            throw AutomationError.automationNotFound(automationID)
        }
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw AutomationError.invalidName }
        guard !normalizedPrompt.isEmpty else { throw AutomationError.invalidPrompt }
        guard draft.maximumDurationMinutes > 0 else {
            throw AutomationError.invalidMaximumDuration
        }
        guard let workspace = workspaces[draft.workspaceID] else {
            throw AutomationError.workspaceNotFound(draft.workspaceID)
        }
        guard let availability = agentAvailabilities[draft.agent],
              availability.executablePath != nil
        else {
            throw AutomationError.agentUnavailable(
                agentAvailabilities[draft.agent]?.unavailableReason
                    ?? "所选 Agent 当前不可用于自动化。"
            )
        }
        let timestamp = now()
        try validate(trigger: draft.trigger, now: timestamp)
        let previousTrigger = currentSnapshot.automations[index].trigger
        currentSnapshot.automations[index].name = normalizedName
        currentSnapshot.automations[index].workspaceID = workspace.id
        currentSnapshot.automations[index].workspaceDisplayName = workspace.displayName
        currentSnapshot.automations[index].workspacePath = workspace.path
        currentSnapshot.automations[index].prompt = normalizedPrompt
        currentSnapshot.automations[index].agent = draft.agent
        currentSnapshot.automations[index].trigger = draft.trigger
        currentSnapshot.automations[index].maximumDurationMinutes =
            draft.maximumDurationMinutes
        currentSnapshot.automations[index].updatedAt = timestamp
        currentSnapshot.automations[index].dependencyPauseReason = nil
        if previousTrigger != draft.trigger {
            currentSnapshot.automations[index].intervalAnchor = intervalAnchor(
                for: draft.trigger,
                at: timestamp
            )
            currentSnapshot.automations[index].lastScheduleEvaluationAt = timestamp
        }
        switch (previousTrigger, draft.trigger) {
        case (.external, .external):
            break
        case (_, .external):
            currentSnapshot.automations[index].externalShortcode =
                makeUniqueShortcode()
        case (.external, _):
            currentSnapshot.automations[index].externalShortcode = nil
        default:
            break
        }
        cancelQueuedRuns(for: automationID, at: timestamp)
        try await persistAndPublish()
    }

    public func setEnabled(
        _ isEnabled: Bool,
        for automationID: AutomationID
    ) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        try requireAcceptingOperations()
        guard let index = currentSnapshot.automations.firstIndex(where: {
            $0.id == automationID
        }) else {
            throw AutomationError.automationNotFound(automationID)
        }
        let timestamp = now()
        if isEnabled {
            if let reason = currentSnapshot.automations[index].dependencyPauseReason {
                throw AutomationError.dependencyPaused(reason)
            }
            try validate(
                trigger: currentSnapshot.automations[index].trigger,
                now: timestamp
            )
            currentSnapshot.automations[index].requiresExplicitReenable = false
            currentSnapshot.automations[index].intervalAnchor = intervalAnchor(
                for: currentSnapshot.automations[index].trigger,
                at: timestamp
            )
            currentSnapshot.automations[index].lastScheduleEvaluationAt = timestamp
        } else {
            cancelQueuedRuns(for: automationID, at: timestamp)
        }
        currentSnapshot.automations[index].isEnabled = isEnabled
        currentSnapshot.automations[index].updatedAt = timestamp
        try await persistAndPublish()
    }

    public func updateEnvironment(
        workspaces: [Workspace],
        agentAvailabilities: [AgentKind: AutomationAgentAvailability]
    ) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        guard !terminating else { return }
        self.workspaces = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
        self.agentAvailabilities = agentAvailabilities
        try await reconcileDependencies()
        try await drainQueue()
    }

    public func delete(_ automationID: AutomationID) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        try requireAcceptingOperations()
        guard currentSnapshot.automations.contains(where: {
            $0.id == automationID
        }) else {
            throw AutomationError.automationNotFound(automationID)
        }
        let matchingRunIDs = currentSnapshot.runs
            .filter { $0.automationID == automationID }
            .map(\.id)
        let timestamp = now()
        for index in currentSnapshot.runs.indices where
            currentSnapshot.runs[index].automationID == automationID
                && !currentSnapshot.runs[index].status.isTerminal
        {
            currentSnapshot.runs[index].status = .canceled
            currentSnapshot.runs[index].endedAt = timestamp
            currentSnapshot.runs[index].effectiveDuration = effectiveDuration(
                for: currentSnapshot.runs[index].id,
                fallbackStart: currentSnapshot.runs[index].startedAt,
                end: timestamp
            ) ?? 0
        }
        let tasks = matchingRunIDs.compactMap { runTasks[$0] }
        for runID in matchingRunIDs {
            runTasks[runID]?.cancel()
            runTasks[runID] = nil
        }
        for task in tasks {
            await task.value
        }
        currentSnapshot.automations.removeAll { $0.id == automationID }
        currentSnapshot.runs.removeAll { $0.automationID == automationID }
        try await persistAndPublish()
        try await drainQueue()
    }

    public func setConcurrencyLimit(_ limit: Int) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        try requireAcceptingOperations()
        guard (1...4).contains(limit) else {
            throw AutomationError.invalidConcurrencyLimit
        }
        currentSnapshot.concurrencyLimit = limit
        try await persistAndPublish()
        try await drainQueue()
    }

    public func cancel(_ runID: AutomationRunID) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        guard let index = currentSnapshot.runs.firstIndex(where: {
            $0.id == runID
        }) else {
            throw AutomationError.runNotFound(runID)
        }
        let status = currentSnapshot.runs[index].status
        guard status == .queued || status == .running else { return }
        let timestamp = now()
        currentSnapshot.runs[index].status = .canceled
        currentSnapshot.runs[index].endedAt = timestamp
        currentSnapshot.runs[index].effectiveDuration = effectiveDuration(
            for: runID,
            fallbackStart: currentSnapshot.runs[index].startedAt,
            end: timestamp
        ) ?? 0
        currentSnapshot.runs[index].finalOutput = nil
        currentSnapshot.runs[index].errorSummary = nil
        let task = runTasks[runID]
        task?.cancel()
        runTasks[runID] = nil
        await task?.value
        let automationID = currentSnapshot.runs[index].automationID
        trimRuns(for: automationID)
        try await persistAndPublish()
        try await drainQueue()
    }

    public func markViewed(_ runID: AutomationRunID) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        guard let index = currentSnapshot.runs.firstIndex(where: {
            $0.id == runID
        }) else {
            throw AutomationError.runNotFound(runID)
        }
        guard !currentSnapshot.runs[index].isViewed else { return }
        currentSnapshot.runs[index].isViewed = true
        try await persistAndPublish()
    }

    @discardableResult
    public func trigger(shortcode: String) async throws -> AutomationRunID {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        try requireAcceptingOperations()
        guard let automation = currentSnapshot.automations.first(where: {
            $0.trigger == .external && $0.externalShortcode == shortcode
        }) else {
            throw AutomationError.invalidShortcode
        }
        let runID = try await triggerLocked(automation.id, source: .external)
        if currentSnapshot.runs.first(where: { $0.id == runID })?.status == .skipped {
            throw AutomationError.alreadyInFlight
        }
        return runID
    }

    public func regenerateShortcode(
        for automationID: AutomationID
    ) async throws -> String {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try requireStarted()
        try requireAcceptingOperations()
        guard let index = currentSnapshot.automations.firstIndex(where: {
            $0.id == automationID
        }) else {
            throw AutomationError.automationNotFound(automationID)
        }
        guard currentSnapshot.automations[index].trigger == .external else {
            throw AutomationError.invalidTrigger
        }
        let shortcode = makeUniqueShortcode()
        currentSnapshot.automations[index].externalShortcode = shortcode
        currentSnapshot.automations[index].updatedAt = now()
        try await persistAndPublish()
        return shortcode
    }

    public nonisolated static func previewOccurrences(
        for trigger: AutomationTrigger,
        anchor: Date? = nil,
        after date: Date,
        timeZone: TimeZone,
        count: Int
    ) throws -> [Date] {
        try AutomationScheduleEvaluator.validate(trigger)
        return try AutomationScheduleEvaluator.nextOccurrences(
            for: trigger,
            anchor: anchor ?? date,
            after: date,
            timeZone: timeZone,
            count: count
        )
    }

    public func reconcileSchedules(
        at evaluationDate: Date,
        reason: AutomationScheduleReconciliationReason
    ) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try await reconcileSchedulesLocked(
            at: evaluationDate,
            reason: reason
        )
    }

    private func reconcileSchedulesLocked(
        at evaluationDate: Date,
        reason: AutomationScheduleReconciliationReason
    ) async throws {
        try requireStarted()
        guard !terminating else { return }
        var scheduledActions: [(AutomationID, Date)] = []
        var changed = false
        let currentTimeZone = timeZone()
        let automationIDs = currentSnapshot.automations.map(\.id)

        for automationID in automationIDs {
            guard let index = currentSnapshot.automations.firstIndex(where: {
                $0.id == automationID
            }) else {
                continue
            }
            let automation = currentSnapshot.automations[index]
            guard automation.trigger.participatesInScheduling else {
                continue
            }
            guard automation.isEnabled, automation.canRun else {
                continue
            }
            let evaluationStart = automation.lastScheduleEvaluationAt
                ?? automation.createdAt
            guard evaluationDate > evaluationStart else { continue }
            let occurrences = try AutomationScheduleEvaluator.nextOccurrences(
                for: automation.trigger,
                anchor: automation.intervalAnchor,
                after: evaluationStart,
                through: evaluationDate,
                timeZone: currentTimeZone,
                count: 100_000
            )
            let missingLocalOccurrences =
                try AutomationScheduleEvaluator.missingLocalOccurrences(
                    for: automation.trigger,
                    after: evaluationStart,
                    through: evaluationDate,
                    timeZone: currentTimeZone
                )
            currentSnapshot.automations[index].lastScheduleEvaluationAt =
                evaluationDate
            changed = true
            guard !occurrences.isEmpty || !missingLocalOccurrences.isEmpty
            else {
                continue
            }

            switch reason {
            case .resumed:
                appendMissedRun(
                    for: automation,
                    occurrences: (
                        occurrences + missingLocalOccurrences
                    ).sorted(),
                    at: evaluationDate
                )
            case .timer:
                let missedOccurrences = (
                    Array(occurrences.dropLast())
                        + missingLocalOccurrences
                ).sorted()
                if !missedOccurrences.isEmpty {
                    appendMissedRun(
                        for: automation,
                        occurrences: missedOccurrences,
                        at: evaluationDate
                    )
                }
                if let latest = occurrences.last {
                    scheduledActions.append((automation.id, latest))
                }
            }
            if case .once = automation.trigger {
                currentSnapshot.automations[index].isEnabled = false
            }
        }

        if changed {
            try await persistAndPublish()
        }
        for (automationID, scheduledAt) in scheduledActions {
            let runID = try await triggerLocked(
                automationID,
                source: .scheduled
            )
            if let runIndex = currentSnapshot.runs.firstIndex(where: {
                $0.id == runID
            }) {
                currentSnapshot.runs[runIndex].scheduledAt = scheduledAt
                try await persistAndPublish()
            }
        }
    }

    public func stopScheduling() {
        scheduleTask?.cancel()
        scheduleTask = nil
    }

    public func suspendForSystemSleep() {
        stopScheduling()
    }

    public func resumeAfterSystemWake(at evaluationDate: Date) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try await reconcileSchedulesLocked(
            at: evaluationDate,
            reason: .resumed
        )
        if schedulesAutomatically, !terminating {
            startAutomaticScheduling()
        }
    }

    @discardableResult
    public func trigger(
        _ automationID: AutomationID,
        source: AutomationTriggerSource
    ) async throws -> AutomationRunID {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        return try await triggerLocked(automationID, source: source)
    }

    private func triggerLocked(
        _ automationID: AutomationID,
        source: AutomationTriggerSource
    ) async throws -> AutomationRunID {
        try requireStarted()
        try requireAcceptingOperations()
        guard let automation = currentSnapshot.automations.first(where: {
            $0.id == automationID
        }) else {
            throw AutomationError.automationNotFound(automationID)
        }
        if source == .external {
            guard automation.isEnabled else { throw AutomationError.disabled }
            guard automation.trigger == .external else {
                throw AutomationError.invalidTrigger
            }
        }
        guard automation.canRun else {
            throw AutomationError.dependencyPaused(
                automation.dependencyPauseReason ?? "自动化依赖需要重新启用。"
            )
        }
        guard let workspaceID = automation.workspaceID,
              let workspace = workspaces[workspaceID]
        else {
            throw AutomationError.workspaceNotFound(
                automation.workspaceID ?? WorkspaceID(rawValue: UUID())
            )
        }
        guard let availability = agentAvailabilities[automation.agent],
              let executablePath = availability.executablePath
        else {
            throw AutomationError.agentUnavailable(
                agentAvailabilities[automation.agent]?.unavailableReason
                    ?? "所选 Agent 当前不可用于自动化。"
            )
        }
        guard workspaceIsAvailable(workspace) else {
            let reason = "绑定的工作区当前不可用。"
            try await pauseAutomation(
                automationID,
                reason: reason,
                at: now()
            )
            throw AutomationError.dependencyPaused(reason)
        }
        guard FileManager.default.isExecutableFile(
            atPath: executablePath
        ) else {
            let reason = "所选 Agent 的可执行文件当前不可用。"
            try await pauseAutomation(
                automationID,
                reason: reason,
                at: now()
            )
            throw AutomationError.agentUnavailable(reason)
        }

        let timestamp = now()
        if currentSnapshot.runs.contains(where: {
            $0.automationID == automationID && !$0.status.isTerminal
        }) {
            let skippedID = AutomationRunID(rawValue: UUID())
            currentSnapshot.runs.append(
                AutomationRun(
                    id: skippedID,
                    automationID: automationID,
                    status: .skipped,
                    triggerSource: source,
                    queuedAt: timestamp,
                    endedAt: timestamp,
                    effectiveDuration: 0,
                    agent: automation.agent
                )
            )
            trimRuns(for: automationID)
            try await persistAndPublish()
            return skippedID
        }

        let runID = AutomationRunID(rawValue: UUID())
        currentSnapshot.runs.append(
            AutomationRun(
                id: runID,
                automationID: automationID,
                status: .queued,
                triggerSource: source,
                queuedAt: timestamp,
                agent: automation.agent
            )
        )
        try await persistAndPublish()
        try await drainQueue()
        return runID
    }

    private func drainQueue() async throws {
        while activeRunCount < currentSnapshot.concurrencyLimit {
            let candidate = nextQueuedCandidate()
            guard let candidate else { return }
            try await startRun(
                id: candidate.0,
                automation: candidate.1,
                workspacePath: candidate.2,
                executablePath: candidate.3
            )
        }
    }

    private func startRun(
        id: AutomationRunID,
        automation: Automation,
        workspacePath: String,
        executablePath: String
    ) async throws {
        guard let index = currentSnapshot.runs.firstIndex(where: {
            $0.id == id && $0.status == .queued
        }) else {
            return
        }
        guard workspaceIsAvailable(
            Workspace(
                id: automation.workspaceID
                    ?? WorkspaceID(rawValue: UUID()),
                path: workspacePath,
                displayName: automation.workspaceDisplayName
            )
        ) else {
            try await pauseAutomation(
                automation.id,
                reason: "绑定的工作区当前不可用。",
                at: now()
            )
            return
        }
        guard FileManager.default.isExecutableFile(
            atPath: executablePath
        ) else {
            try await pauseAutomation(
                automation.id,
                reason: "所选 Agent 的可执行文件当前不可用。",
                at: now()
            )
            return
        }
        let startedAt = now()
        currentSnapshot.runs[index].status = .running
        currentSnapshot.runs[index].startedAt = startedAt
        runStartInstants[id] = SuspendingClock().now
        currentSnapshot.runs[index].startingGitCommit =
            startingGitCommit(workspacePath)

        let request = AutomationRunRequest(
            runID: id,
            automationID: automation.id,
            agent: automation.agent,
            executablePath: executablePath,
            workspacePath: workspacePath,
            prompt: Self.promptForAgent(automation.prompt),
            maximumDurationMinutes: automation.maximumDurationMinutes
        )
        let runner = self.runner
        let startGate = AutomationRunStartGate()
        let task = Task { [weak self] in
            await startGate.wait()
            guard !Task.isCancelled else { return }
            do {
                let result = try await runner.run(request)
                await self?.completeRun(id, result: result)
            } catch is CancellationError {
                await self?.completeCanceledRun(id)
            } catch {
                await self?.completeFailedRun(id, error: error)
            }
        }
        runTasks[id] = task
        do {
            try await persistAndPublish()
            startGate.open()
        } catch {
            task.cancel()
            runTasks[id] = nil
            startGate.open()
            throw error
        }
    }

    private func completeRun(
        _ id: AutomationRunID,
        result: AutomationAgentResult
    ) async {
        guard currentSnapshot.runs.contains(where: {
            $0.id == id && $0.status == .running
        }) else {
            runTasks[id] = nil
            return
        }
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let index = currentSnapshot.runs.firstIndex(where: {
            $0.id == id && $0.status == .running
        }) else {
            runTasks[id] = nil
            return
        }
        runTasks[id] = nil
        let output = Self.truncatedOutput(result.finalOutput)
        let normalized = output.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let endedAt = now()
        if normalized.isEmpty {
            currentSnapshot.runs[index].status = .failed
            currentSnapshot.runs[index].errorSummary = "Agent 未返回最终输出。"
            currentSnapshot.runs[index].isViewed = false
        } else {
            currentSnapshot.runs[index].status = .succeeded
            currentSnapshot.runs[index].finalOutput = output.value
            currentSnapshot.runs[index].outputWasTruncated = output.wasTruncated
            currentSnapshot.runs[index].model = result.model
            currentSnapshot.runs[index].isViewed = false
        }
        currentSnapshot.runs[index].endedAt = endedAt
        currentSnapshot.runs[index].effectiveDuration = effectiveDuration(
            for: id,
            fallbackStart: currentSnapshot.runs[index].startedAt,
            end: endedAt
        )
        let automationID = currentSnapshot.runs[index].automationID
        trimRuns(for: automationID)
        try? await persistAndPublish()
        try? await drainQueue()
    }

    private func completeFailedRun(
        _ id: AutomationRunID,
        error: Error
    ) async {
        guard currentSnapshot.runs.contains(where: {
            $0.id == id && $0.status == .running
        }) else {
            runTasks[id] = nil
            return
        }
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let index = currentSnapshot.runs.firstIndex(where: {
            $0.id == id && $0.status == .running
        }) else {
            runTasks[id] = nil
            return
        }
        runTasks[id] = nil
        let endedAt = now()
        currentSnapshot.runs[index].status =
            (error as? AutomationRunnerError) == .timedOut
                ? .timedOut
                : .failed
        currentSnapshot.runs[index].endedAt = endedAt
        currentSnapshot.runs[index].effectiveDuration = effectiveDuration(
            for: id,
            fallbackStart: currentSnapshot.runs[index].startedAt,
            end: endedAt
        )
        currentSnapshot.runs[index].errorSummary = Self.sanitizedError(error)
        currentSnapshot.runs[index].isViewed = false
        let automationID = currentSnapshot.runs[index].automationID
        trimRuns(for: automationID)
        try? await persistAndPublish()
        try? await drainQueue()
    }

    private func completeCanceledRun(_ id: AutomationRunID) async {
        guard currentSnapshot.runs.contains(where: {
            $0.id == id && $0.status == .running
        }) else {
            runTasks[id] = nil
            return
        }
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let index = currentSnapshot.runs.firstIndex(where: {
            $0.id == id && $0.status == .running
        }) else {
            runTasks[id] = nil
            return
        }
        runTasks[id] = nil
        let endedAt = now()
        currentSnapshot.runs[index].status = .canceled
        currentSnapshot.runs[index].endedAt = endedAt
        currentSnapshot.runs[index].effectiveDuration = effectiveDuration(
            for: id,
            fallbackStart: currentSnapshot.runs[index].startedAt,
            end: endedAt
        )
        let automationID = currentSnapshot.runs[index].automationID
        trimRuns(for: automationID)
        try? await persistAndPublish()
        try? await drainQueue()
    }

    private var activeRunCount: Int {
        currentSnapshot.runs.count { $0.status == .running }
    }

    private func nextQueuedCandidate() -> (
        AutomationRunID,
        Automation,
        String,
        String
    )? {
        let queued = currentSnapshot.runs
            .filter { $0.status == .queued }
            .sorted { lhs, rhs in
                if lhs.queuedAt == rhs.queuedAt {
                    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
                }
                return lhs.queuedAt < rhs.queuedAt
            }
        for run in queued {
            guard let automation = currentSnapshot.automations.first(where: {
                $0.id == run.automationID
            }),
            automation.canRun,
            let workspaceID = automation.workspaceID,
            let workspace = workspaces[workspaceID],
            let executablePath = agentAvailabilities[automation.agent]?.executablePath
            else {
                continue
            }
            return (run.id, automation, workspace.path, executablePath)
        }
        return nil
    }

    private func reconcileDependencies() async throws {
        guard started else { return }
        var changed = false
        for index in currentSnapshot.automations.indices {
            let automation = currentSnapshot.automations[index]
            let reason: String?
            if let workspaceID = automation.workspaceID,
               let workspace = workspaces[workspaceID],
               workspaceIsAvailable(workspace)
            {
                reason = agentAvailabilities[automation.agent]?.unavailableReason
            } else {
                reason = "绑定的工作区当前不可用。"
            }
            if currentSnapshot.automations[index].dependencyPauseReason != reason {
                currentSnapshot.automations[index].dependencyPauseReason = reason
                if reason != nil {
                    currentSnapshot.automations[index].requiresExplicitReenable = true
                    currentSnapshot.automations[index].isEnabled = false
                    cancelQueuedRuns(
                        for: automation.id,
                        at: now()
                    )
                }
                changed = true
            }
        }
        if changed {
            try await persistAndPublish()
        }
    }

    private func workspaceIsAvailable(_ workspace: Workspace) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: workspace.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private func repairStaleRuns() async throws {
        let timestamp = now()
        var changed = false
        var affectedAutomationIDs: Set<AutomationID> = []
        for index in currentSnapshot.runs.indices {
            switch currentSnapshot.runs[index].status {
            case .running:
                currentSnapshot.runs[index].status = .interrupted
                currentSnapshot.runs[index].endedAt = timestamp
                currentSnapshot.runs[index].effectiveDuration = duration(
                    from: currentSnapshot.runs[index].startedAt,
                    to: timestamp
                )
                currentSnapshot.runs[index].errorSummary =
                    "Breath 上次意外退出，运行已中断。"
                currentSnapshot.runs[index].isViewed = false
                affectedAutomationIDs.insert(
                    currentSnapshot.runs[index].automationID
                )
                changed = true
            case .queued:
                currentSnapshot.runs[index].status = .canceled
                currentSnapshot.runs[index].endedAt = timestamp
                currentSnapshot.runs[index].effectiveDuration = 0
                affectedAutomationIDs.insert(
                    currentSnapshot.runs[index].automationID
                )
                changed = true
            default:
                break
            }
        }
        guard changed else { return }
        for automationID in affectedAutomationIDs {
            trimRuns(for: automationID)
        }
        try await persistAndPublish()
    }

    private func appendMissedRun(
        for automation: Automation,
        occurrences: [Date],
        at timestamp: Date
    ) {
        guard let first = occurrences.first, let last = occurrences.last else {
            return
        }
        currentSnapshot.runs.append(
            AutomationRun(
                id: AutomationRunID(rawValue: UUID()),
                automationID: automation.id,
                status: .missed,
                triggerSource: .scheduled,
                scheduledAt: last,
                missedOccurrences: AutomationMissedOccurrences(
                    count: occurrences.count,
                    firstScheduledAt: first,
                    lastScheduledAt: last
                ),
                queuedAt: timestamp,
                endedAt: timestamp,
                effectiveDuration: 0,
                agent: automation.agent
            )
        )
        trimRuns(for: automation.id)
    }

    private func startAutomaticScheduling() {
        guard scheduleTask == nil else { return }
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await SuspendingClock().sleep(for: .seconds(30))
                    guard let self else { return }
                    try await self.reconcileSchedules(
                        at: self.now(),
                        reason: .timer
                    )
                } catch is CancellationError {
                    return
                } catch {
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func cancelQueuedRuns(
        for automationID: AutomationID,
        at timestamp: Date
    ) {
        for index in currentSnapshot.runs.indices where
            currentSnapshot.runs[index].automationID == automationID
                && currentSnapshot.runs[index].status == .queued
        {
            currentSnapshot.runs[index].status = .canceled
            currentSnapshot.runs[index].endedAt = timestamp
            currentSnapshot.runs[index].effectiveDuration = 0
        }
        trimRuns(for: automationID)
    }

    private func pauseAutomation(
        _ automationID: AutomationID,
        reason: String,
        at timestamp: Date
    ) async throws {
        guard let index = currentSnapshot.automations.firstIndex(where: {
            $0.id == automationID
        }) else {
            return
        }
        currentSnapshot.automations[index].dependencyPauseReason = reason
        currentSnapshot.automations[index].requiresExplicitReenable = true
        currentSnapshot.automations[index].isEnabled = false
        currentSnapshot.automations[index].updatedAt = timestamp
        cancelQueuedRuns(for: automationID, at: timestamp)
        try await persistAndPublish()
    }

    private func requireStarted() throws {
        guard started else { throw AutomationError.notStarted }
    }

    private func requireAcceptingOperations() throws {
        guard !terminating else {
            throw AutomationError.notStarted
        }
    }

    private func persistAndPublish() async throws {
        let attemptedSnapshot = currentSnapshot
        do {
            try await repository.saveAutomationSnapshot(attemptedSnapshot)
            lastPersistedSnapshot = attemptedSnapshot
            await publishSnapshotChange()
        } catch {
            currentSnapshot = lastPersistedSnapshot
            await publishSnapshotChange()
            throw error
        }
    }

    private func publishSnapshotChange() async {
        await snapshotChangeHandler?()
    }

    private func sortAutomations() {
        currentSnapshot.automations.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.rawValue.uuidString > rhs.id.rawValue.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func trimRuns(for automationID: AutomationID) {
        let matching = currentSnapshot.runs
            .filter { $0.automationID == automationID }
            .sorted { lhs, rhs in
                if lhs.queuedAt == rhs.queuedAt {
                    return lhs.id.rawValue.uuidString > rhs.id.rawValue.uuidString
                }
                return lhs.queuedAt > rhs.queuedAt
            }
        let retainedIDs = Set(matching.prefix(5).map(\.id))
        currentSnapshot.runs.removeAll {
            $0.automationID == automationID
                && $0.status.isTerminal
                && !retainedIDs.contains($0.id)
        }
    }

    private func duration(from start: Date?, to end: Date) -> TimeInterval? {
        start.map { max(0, end.timeIntervalSince($0)) }
    }

    private func effectiveDuration(
        for runID: AutomationRunID,
        fallbackStart: Date?,
        end: Date
    ) -> TimeInterval? {
        guard let start = runStartInstants.removeValue(forKey: runID) else {
            return duration(from: fallbackStart, to: end)
        }
        let components = start.duration(to: SuspendingClock().now).components
        return max(
            0,
            Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }

    private func validate(trigger: AutomationTrigger, now: Date) throws {
        switch trigger {
        case .manual, .external:
            return
        case .once(let date):
            guard date > now else { throw AutomationError.invalidTrigger }
        case .daily(let hour, let minute):
            guard (0..<24).contains(hour), (0..<60).contains(minute) else {
                throw AutomationError.invalidTrigger
            }
        case .weekly(let weekdays, let hour, let minute):
            guard !weekdays.isEmpty,
                  weekdays.allSatisfy({ (1...7).contains($0) }),
                  (0..<24).contains(hour),
                  (0..<60).contains(minute)
            else {
                throw AutomationError.invalidTrigger
            }
        case .interval(let interval):
            guard interval.duration >= 60, interval.duration <= 30 * 86_400 else {
                throw AutomationError.invalidTrigger
            }
        case .cron(let expression):
            guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AutomationError.invalidTrigger
            }
            try AutomationScheduleEvaluator.validate(trigger)
        }
    }

    private func intervalAnchor(
        for trigger: AutomationTrigger,
        at timestamp: Date
    ) -> Date? {
        guard case .interval = trigger else { return nil }
        return timestamp
    }

    private static func promptForAgent(_ prompt: String) -> String {
        """
        \(prompt)

        Breath automation constraints:
        - The Workspace is live and read-only.
        - Write only inside the temporary runtime directory.
        - Do not request interactive approval.
        - Return one complete final response.
        """
    }

    private static func truncatedOutput(
        _ output: String,
        limit: Int = 256 * 1_024
    ) -> (value: String, wasTruncated: Bool) {
        let data = Data(output.utf8)
        guard data.count > limit else { return (output, false) }
        let marker = "\n\n… Breath truncated this output …\n\n"
        let markerSize = marker.utf8.count
        let available = max(0, limit - markerSize)
        let prefixSize = available / 2
        let suffixSize = available - prefixSize
        let prefix = String(decoding: data.prefix(prefixSize), as: UTF8.self)
        let suffix = String(decoding: data.suffix(suffixSize), as: UTF8.self)
        return (prefix + marker + suffix, true)
    }

    private static func sanitizedError(_ error: Error) -> String {
        guard let runnerError = error as? AutomationRunnerError else {
            return "Agent 运行失败。"
        }
        return String(
            (runnerError.errorDescription ?? "Agent 运行失败。").prefix(512)
        )
    }

    private static func makeShortcode() -> String {
        UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(12)
            .description
    }

    private func makeUniqueShortcode() -> String {
        let existing = Set(
            currentSnapshot.automations.compactMap(\.externalShortcode)
        )
        var shortcode = Self.makeShortcode()
        while existing.contains(shortcode) {
            shortcode = Self.makeShortcode()
        }
        return shortcode
    }
}

private final class AutomationMutationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if isHeld {
                    waiters.append(continuation)
                    return false
                }
                isHeld = true
                return true
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func release() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if waiters.isEmpty {
                isHeld = false
                return nil
            }
            return waiters.removeFirst()
        }
        waiter?.resume()
    }
}

private final class AutomationRunStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if isOpen {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func open() {
        let continuations = lock.withLock {
            guard !isOpen else { return [CheckedContinuation<Void, Never>]() }
            isOpen = true
            let continuations = waiters
            waiters.removeAll()
            return continuations
        }
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private extension AutomationTrigger {
    var participatesInScheduling: Bool {
        switch self {
        case .manual, .external:
            false
        case .once, .daily, .weekly, .interval, .cron:
            true
        }
    }
}
