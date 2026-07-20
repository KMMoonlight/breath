import BreathCore
import Foundation

public struct SkillUpdateTarget: Identifiable, Hashable, Sendable {
    public var id: AgentKind { agent }
    public let agent: AgentKind
    public let agentDisplayName: String
    public let directory: URL
    public let isLocallyModified: Bool
    public let isSymbolicLink: Bool
    public let isSelectedByDefault: Bool

    public init(
        agent: AgentKind,
        agentDisplayName: String,
        directory: URL,
        isLocallyModified: Bool,
        isSymbolicLink: Bool,
        isSelectedByDefault: Bool
    ) {
        self.agent = agent
        self.agentDisplayName = agentDisplayName
        self.directory = directory
        self.isLocallyModified = isLocallyModified
        self.isSymbolicLink = isSymbolicLink
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public struct SkillAvailableUpdate: Identifiable, Sendable {
    public let id: String
    public let skillName: String
    public let source: SkillSourceKind
    public let repository: String
    public let sourceRelativePath: String
    public let oldCommits: [String]
    public let newCommit: String
    public let candidate: SkillCandidate
    public let targets: [SkillUpdateTarget]
    let workspaceDirectory: URL

    init(
        skillName: String,
        source: SkillSourceKind,
        repository: String,
        sourceRelativePath: String,
        oldCommits: [String],
        newCommit: String,
        candidate: SkillCandidate,
        targets: [SkillUpdateTarget],
        workspaceDirectory: URL
    ) {
        id = "\(source.rawValue):\(repository):\(sourceRelativePath):\(skillName)"
        self.skillName = skillName
        self.source = source
        self.repository = repository
        self.sourceRelativePath = sourceRelativePath
        self.oldCommits = oldCommits
        self.newCommit = newCommit
        self.candidate = candidate
        self.targets = targets
        self.workspaceDirectory = workspaceDirectory
    }
}

public struct SkillUpdateCheckFailure: Identifiable, Hashable, Sendable {
    public var id: String { "\(repository):\(sourceRelativePath):\(skillName)" }
    public let skillName: String
    public let repository: String
    public let sourceRelativePath: String
    public let message: String

    public init(
        skillName: String,
        repository: String,
        sourceRelativePath: String,
        message: String
    ) {
        self.skillName = skillName
        self.repository = repository
        self.sourceRelativePath = sourceRelativePath
        self.message = message
    }
}

public struct SkillUpdateCheckResult: Sendable {
    public let updates: [SkillAvailableUpdate]
    public let failures: [SkillUpdateCheckFailure]
    public let checkedAt: Date
    public let usedSessionCache: Bool

    public init(
        updates: [SkillAvailableUpdate],
        failures: [SkillUpdateCheckFailure],
        checkedAt: Date,
        usedSessionCache: Bool
    ) {
        self.updates = updates
        self.failures = failures
        self.checkedAt = checkedAt
        self.usedSessionCache = usedSessionCache
    }
}
