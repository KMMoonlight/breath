import BreathCore
import Foundation

public protocol SkillTrashing: Sendable {
    func moveToTrash(_ url: URL) async throws
}

public struct MacOSSkillTrash: SkillTrashing, Sendable {
    public init() {}

    public func moveToTrash(_ url: URL) async throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
}

public enum SkillUninstallAction: String, Codable, Hashable, Sendable {
    case moveToTrash
    case removeSymbolicLink
}

public struct SkillUninstallPreviewItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(agent.rawValue):\(directory.path)" }
    public let skillID: String
    public let skillName: String
    public let agent: AgentKind
    public let agentDisplayName: String
    public let directory: URL
    public let resolvedDirectory: URL
    public let action: SkillUninstallAction
    let expectedDigest: String

    init(
        skillID: String,
        skillName: String,
        agent: AgentKind,
        agentDisplayName: String,
        directory: URL,
        resolvedDirectory: URL,
        action: SkillUninstallAction,
        expectedDigest: String
    ) {
        self.skillID = skillID
        self.skillName = skillName
        self.agent = agent
        self.agentDisplayName = agentDisplayName
        self.directory = directory
        self.resolvedDirectory = resolvedDirectory
        self.action = action
        self.expectedDigest = expectedDigest
    }
}

public struct SkillUninstallPreview: Sendable {
    public let items: [SkillUninstallPreviewItem]
    public let createdAt: Date

    public init(items: [SkillUninstallPreviewItem], createdAt: Date) {
        self.items = items
        self.createdAt = createdAt
    }
}

public struct SkillUninstallResultItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(agent.rawValue):\(directory.path)" }
    public let skillName: String
    public let agent: AgentKind
    public let agentDisplayName: String
    public let directory: URL
    public let status: SkillOperationStatus
    public let message: String
    public let diagnostic: String?

    public init(
        skillName: String,
        agent: AgentKind,
        agentDisplayName: String,
        directory: URL,
        status: SkillOperationStatus,
        message: String,
        diagnostic: String? = nil
    ) {
        self.skillName = skillName
        self.agent = agent
        self.agentDisplayName = agentDisplayName
        self.directory = directory
        self.status = status
        self.message = message
        self.diagnostic = diagnostic
    }
}

public struct SkillUninstallResult: Sendable {
    public let items: [SkillUninstallResultItem]
    public let snapshot: GlobalSkillsSnapshot

    public init(items: [SkillUninstallResultItem], snapshot: GlobalSkillsSnapshot) {
        self.items = items
        self.snapshot = snapshot
    }
}
