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

public enum SkillUninstallScope: String, Codable, Hashable, Sendable {
    case agent
    case sharedLibrary
}

public struct SkillAffectedAgent: Codable, Hashable, Sendable {
    public let agent: AgentKind
    public let displayName: String

    public init(agent: AgentKind, displayName: String) {
        self.agent = agent
        self.displayName = displayName
    }
}

public struct SkillUninstallPreviewItem: Identifiable, Hashable, Sendable {
    public var id: String { directory.standardizedFileURL.path }
    public let skillID: String
    public let skillName: String
    public let affectedAgentEntries: [SkillAffectedAgent]
    public let scope: SkillUninstallScope
    public let directory: URL
    public let resolvedDirectory: URL
    public let action: SkillUninstallAction
    let expectedDigest: String
    let sharedRegistrySkillIdentifier: String?
    let linkedDirectoriesToRemove: [URL]

    public var affectedAgents: [AgentKind] { affectedAgentEntries.map(\.agent) }
    public var affectedAgentDisplayNames: [String] {
        affectedAgentEntries.map(\.displayName)
    }
    public var agentDisplayName: String { affectedAgentDisplayNames.joined(separator: ", ") }

    init(
        skillID: String,
        skillName: String,
        affectedAgentEntries: [SkillAffectedAgent],
        scope: SkillUninstallScope,
        directory: URL,
        resolvedDirectory: URL,
        action: SkillUninstallAction,
        expectedDigest: String,
        sharedRegistrySkillIdentifier: String? = nil,
        linkedDirectoriesToRemove: [URL] = []
    ) {
        self.skillID = skillID
        self.skillName = skillName
        self.affectedAgentEntries = affectedAgentEntries
        self.scope = scope
        self.directory = directory
        self.resolvedDirectory = resolvedDirectory
        self.action = action
        self.expectedDigest = expectedDigest
        self.sharedRegistrySkillIdentifier = sharedRegistrySkillIdentifier
        self.linkedDirectoriesToRemove = linkedDirectoriesToRemove
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
    public var id: String { directory.standardizedFileURL.path }
    public let skillName: String
    public let affectedAgentEntries: [SkillAffectedAgent]
    public let scope: SkillUninstallScope
    public let directory: URL
    public let status: SkillOperationStatus
    public let message: String
    public let diagnostic: String?

    public var affectedAgents: [AgentKind] { affectedAgentEntries.map(\.agent) }
    public var affectedAgentDisplayNames: [String] {
        affectedAgentEntries.map(\.displayName)
    }
    public var agentDisplayName: String { affectedAgentDisplayNames.joined(separator: ", ") }

    public init(
        skillName: String,
        affectedAgentEntries: [SkillAffectedAgent],
        scope: SkillUninstallScope,
        directory: URL,
        status: SkillOperationStatus,
        message: String,
        diagnostic: String? = nil
    ) {
        self.skillName = skillName
        self.affectedAgentEntries = affectedAgentEntries
        self.scope = scope
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
