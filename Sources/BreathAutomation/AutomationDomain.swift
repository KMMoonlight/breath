import BreathCore
import Foundation

public struct AutomationID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var id: AutomationID { self }
}

public struct AutomationRunID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var id: AutomationRunID { self }
}

public enum AutomationIntervalUnit: String, CaseIterable, Codable, Sendable {
    case minutes
    case hours
    case days
}

public struct AutomationInterval: Equatable, Codable, Sendable {
    public let value: Int
    public let unit: AutomationIntervalUnit

    public init(value: Int, unit: AutomationIntervalUnit) {
        self.value = value
        self.unit = unit
    }

    public var duration: TimeInterval {
        let multiplier: TimeInterval
        switch unit {
        case .minutes:
            multiplier = 60
        case .hours:
            multiplier = 3_600
        case .days:
            multiplier = 86_400
        }
        return TimeInterval(value) * multiplier
    }
}

public enum AutomationTrigger: Equatable, Codable, Sendable {
    case manual
    case once(Date)
    case daily(hour: Int, minute: Int)
    case weekly(weekdays: [Int], hour: Int, minute: Int)
    case interval(AutomationInterval)
    case cron(String)
    case external
}

public enum AutomationTriggerSource: String, Equatable, Codable, Sendable {
    case manual
    case scheduled
    case external
}

public enum AutomationScheduleReconciliationReason: Sendable {
    case timer
    case resumed
}

public enum AutomationRunStatus: String, CaseIterable, Equatable, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case timedOut
    case canceled
    case interrupted
    case skipped
    case missed

    public var isTerminal: Bool {
        switch self {
        case .queued, .running:
            false
        case .succeeded, .failed, .timedOut, .canceled, .interrupted, .skipped, .missed:
            true
        }
    }

    public var contributesToUnreadCount: Bool {
        switch self {
        case .succeeded, .failed, .timedOut, .interrupted:
            true
        case .queued, .running, .canceled, .skipped, .missed:
            false
        }
    }
}

public struct AutomationMissedOccurrences: Equatable, Codable, Sendable {
    public let count: Int
    public let firstScheduledAt: Date
    public let lastScheduledAt: Date

    public init(count: Int, firstScheduledAt: Date, lastScheduledAt: Date) {
        self.count = count
        self.firstScheduledAt = firstScheduledAt
        self.lastScheduledAt = lastScheduledAt
    }
}

public struct Automation: Equatable, Codable, Sendable, Identifiable {
    public let id: AutomationID
    public var name: String
    public var workspaceID: WorkspaceID?
    public var workspaceDisplayName: String
    public var workspacePath: String
    public var prompt: String
    public var agent: AgentKind
    public var trigger: AutomationTrigger
    public var maximumDurationMinutes: Int
    public var isEnabled: Bool
    public var dependencyPauseReason: String?
    public var requiresExplicitReenable: Bool
    public var externalShortcode: String?
    public var intervalAnchor: Date?
    public var lastScheduleEvaluationAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: AutomationID,
        name: String,
        workspaceID: WorkspaceID?,
        workspaceDisplayName: String,
        workspacePath: String,
        prompt: String,
        agent: AgentKind,
        trigger: AutomationTrigger,
        maximumDurationMinutes: Int,
        isEnabled: Bool,
        dependencyPauseReason: String? = nil,
        requiresExplicitReenable: Bool = false,
        externalShortcode: String? = nil,
        intervalAnchor: Date? = nil,
        lastScheduleEvaluationAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.workspaceID = workspaceID
        self.workspaceDisplayName = workspaceDisplayName
        self.workspacePath = workspacePath
        self.prompt = prompt
        self.agent = agent
        self.trigger = trigger
        self.maximumDurationMinutes = maximumDurationMinutes
        self.isEnabled = isEnabled
        self.dependencyPauseReason = dependencyPauseReason
        self.requiresExplicitReenable = requiresExplicitReenable
        self.externalShortcode = externalShortcode
        self.intervalAnchor = intervalAnchor
        self.lastScheduleEvaluationAt = lastScheduleEvaluationAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var canRun: Bool {
        dependencyPauseReason == nil && !requiresExplicitReenable
    }
}

public struct AutomationRun: Equatable, Codable, Sendable, Identifiable {
    public let id: AutomationRunID
    public let automationID: AutomationID
    public var status: AutomationRunStatus
    public let triggerSource: AutomationTriggerSource
    public var scheduledAt: Date?
    public let missedOccurrences: AutomationMissedOccurrences?
    public let queuedAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var effectiveDuration: TimeInterval?
    public let agent: AgentKind
    public var model: String?
    public var startingGitCommit: String?
    public let workspaceMayChangeDuringRun: Bool
    public var finalOutput: String?
    public var outputWasTruncated: Bool
    public var errorSummary: String?
    public var isViewed: Bool

    public init(
        id: AutomationRunID,
        automationID: AutomationID,
        status: AutomationRunStatus,
        triggerSource: AutomationTriggerSource,
        scheduledAt: Date? = nil,
        missedOccurrences: AutomationMissedOccurrences? = nil,
        queuedAt: Date,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        effectiveDuration: TimeInterval? = nil,
        agent: AgentKind,
        model: String? = nil,
        startingGitCommit: String? = nil,
        workspaceMayChangeDuringRun: Bool = true,
        finalOutput: String? = nil,
        outputWasTruncated: Bool = false,
        errorSummary: String? = nil,
        isViewed: Bool = true
    ) {
        self.id = id
        self.automationID = automationID
        self.status = status
        self.triggerSource = triggerSource
        self.scheduledAt = scheduledAt
        self.missedOccurrences = missedOccurrences
        self.queuedAt = queuedAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.effectiveDuration = effectiveDuration
        self.agent = agent
        self.model = model
        self.startingGitCommit = startingGitCommit
        self.workspaceMayChangeDuringRun = workspaceMayChangeDuringRun
        self.finalOutput = finalOutput
        self.outputWasTruncated = outputWasTruncated
        self.errorSummary = errorSummary
        self.isViewed = isViewed
    }
}

public struct AutomationSnapshot: Equatable, Codable, Sendable {
    public var automations: [Automation]
    public var runs: [AutomationRun]
    public var concurrencyLimit: Int

    public init(
        automations: [Automation],
        runs: [AutomationRun],
        concurrencyLimit: Int
    ) {
        self.automations = automations
        self.runs = runs
        self.concurrencyLimit = concurrencyLimit
    }

    public static let empty = AutomationSnapshot(
        automations: [],
        runs: [],
        concurrencyLimit: 2
    )

    public var unreadCount: Int {
        runs.count {
            $0.status.contributesToUnreadCount && !$0.isViewed
        }
    }

    public func runs(for automationID: AutomationID) -> [AutomationRun] {
        runs
            .filter { $0.automationID == automationID }
            .sorted { lhs, rhs in
                if lhs.queuedAt == rhs.queuedAt {
                    return lhs.id.rawValue.uuidString > rhs.id.rawValue.uuidString
                }
                return lhs.queuedAt > rhs.queuedAt
            }
    }
}

public struct AutomationDraft: Equatable, Sendable {
    public let name: String
    public let workspaceID: WorkspaceID
    public let prompt: String
    public let agent: AgentKind
    public let trigger: AutomationTrigger
    public let maximumDurationMinutes: Int

    public init(
        name: String,
        workspaceID: WorkspaceID,
        prompt: String,
        agent: AgentKind,
        trigger: AutomationTrigger,
        maximumDurationMinutes: Int = 60
    ) {
        self.name = name
        self.workspaceID = workspaceID
        self.prompt = prompt
        self.agent = agent
        self.trigger = trigger
        self.maximumDurationMinutes = maximumDurationMinutes
    }
}

public enum AutomationAgentAvailability: Equatable, Sendable {
    case available(executablePath: String, currentVersion: String?)
    case unavailable(reason: String, isInstalled: Bool, currentVersion: String?)

    public var isAvailable: Bool {
        executablePath != nil
    }

    public var isInstalled: Bool {
        switch self {
        case .available:
            true
        case .unavailable(_, let isInstalled, _):
            isInstalled
        }
    }

    public var currentVersion: String? {
        switch self {
        case .available(_, let currentVersion),
             .unavailable(_, _, let currentVersion):
            currentVersion
        }
    }

    public var executablePath: String? {
        guard case .available(let executablePath, _) = self else { return nil }
        return executablePath
    }

    public var unavailableReason: String? {
        guard case .unavailable(let reason, _, _) = self else { return nil }
        return reason
    }
}

public struct AutomationAgentResult: Equatable, Sendable {
    public let finalOutput: String
    public let model: String?

    public init(finalOutput: String, model: String? = nil) {
        self.finalOutput = finalOutput
        self.model = model
    }
}

public struct AutomationRunRequest: Equatable, Sendable {
    public let runID: AutomationRunID
    public let automationID: AutomationID
    public let agent: AgentKind
    public let executablePath: String
    public let workspacePath: String
    public let prompt: String
    public let maximumDurationMinutes: Int

    public init(
        runID: AutomationRunID,
        automationID: AutomationID,
        agent: AgentKind,
        executablePath: String,
        workspacePath: String,
        prompt: String,
        maximumDurationMinutes: Int
    ) {
        self.runID = runID
        self.automationID = automationID
        self.agent = agent
        self.executablePath = executablePath
        self.workspacePath = workspacePath
        self.prompt = prompt
        self.maximumDurationMinutes = maximumDurationMinutes
    }
}

public protocol AutomationRepository: Sendable {
    func loadAutomationSnapshot() async throws -> AutomationSnapshot
    func saveAutomationSnapshot(_ snapshot: AutomationSnapshot) async throws
}

public protocol AutomationRunning: Sendable {
    func prepareForStartup() async throws
    func run(_ request: AutomationRunRequest) async throws -> AutomationAgentResult
}

public extension AutomationRunning {
    func prepareForStartup() async throws {}
}

public enum AutomationError: Error, Equatable, Sendable {
    case notStarted
    case automationNotFound(AutomationID)
    case workspaceNotFound(WorkspaceID)
    case invalidName
    case invalidPrompt
    case invalidMaximumDuration
    case agentUnavailable(String)
    case dependencyPaused(String)
    case disabled
    case invalidTrigger
    case invalidShortcode
    case alreadyInFlight
    case runNotFound(AutomationRunID)
    case invalidConcurrencyLimit
}

extension AutomationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notStarted:
            "自动化服务尚未启动。"
        case .automationNotFound:
            "找不到自动化。"
        case .workspaceNotFound:
            "找不到自动化绑定的工作区。"
        case .invalidName:
            "请输入自动化名称。"
        case .invalidPrompt:
            "请输入 Prompt。"
        case .invalidMaximumDuration:
            "最大运行时长必须是正整数分钟。"
        case .agentUnavailable(let reason), .dependencyPaused(let reason):
            reason
        case .disabled:
            "该自动化已禁用。"
        case .invalidTrigger:
            "触发规则无效。"
        case .invalidShortcode:
            "自动化短码无效或已失效。"
        case .alreadyInFlight:
            "该自动化已经在排队或运行。"
        case .runNotFound:
            "找不到自动化运行记录。"
        case .invalidConcurrencyLimit:
            "并发运行数量必须介于 1 和 4 之间。"
        }
    }
}
