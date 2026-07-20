import BreathCore
import Foundation

public enum SkillCandidateWarningKind: String, Codable, Hashable, Sendable {
    case nonstandardName
    case directoryNameMismatch
}

public struct SkillCandidateWarning: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(kind.rawValue):\(message)" }
    public let kind: SkillCandidateWarningKind
    public let message: String

    public init(kind: SkillCandidateWarningKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct SkillRemoteProvenance: Codable, Hashable, Sendable {
    public let source: SkillSourceKind
    public let repository: String
    public let sourceRelativePath: String
    public let reference: SkillSourceReference
    public let resolvedCommit: String

    public init(
        source: SkillSourceKind,
        repository: String,
        sourceRelativePath: String,
        reference: SkillSourceReference,
        resolvedCommit: String
    ) {
        self.source = source
        self.repository = repository
        self.sourceRelativePath = sourceRelativePath
        self.reference = reference
        self.resolvedCommit = resolvedCommit
    }
}

public struct SkillCandidate: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let manifest: String
    public let contentDigest: String
    public let files: [SkillFileEntry]
    public let warnings: [SkillCandidateWarning]
    public let source: SkillSourceKind
    public let sourceLabel: String
    public let sourceRelativePath: String
    public let remoteProvenance: SkillRemoteProvenance?
    public let securityAudit: SkillSecurityAudit
    let directory: URL

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        manifest: String,
        contentDigest: String,
        files: [SkillFileEntry],
        warnings: [SkillCandidateWarning],
        source: SkillSourceKind,
        sourceLabel: String,
        sourceRelativePath: String,
        remoteProvenance: SkillRemoteProvenance?,
        securityAudit: SkillSecurityAudit = .unknown,
        directory: URL
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.manifest = manifest
        self.contentDigest = contentDigest
        self.files = files
        self.warnings = warnings
        self.source = source
        self.sourceLabel = sourceLabel
        self.sourceRelativePath = sourceRelativePath
        self.remoteProvenance = remoteProvenance
        self.securityAudit = securityAudit
        self.directory = directory
    }
}

public struct SkillCandidateBatch: Identifiable, Sendable {
    public let id: UUID
    public let source: SkillSourceKind
    public let sourceLabel: String
    public let candidates: [SkillCandidate]
    let workspaceDirectory: URL

    init(
        id: UUID = UUID(),
        source: SkillSourceKind,
        sourceLabel: String,
        candidates: [SkillCandidate],
        workspaceDirectory: URL
    ) {
        self.id = id
        self.source = source
        self.sourceLabel = sourceLabel
        self.candidates = candidates
        self.workspaceDirectory = workspaceDirectory
    }
}

public struct SkillInstallationTargetID: Codable, Hashable, Sendable {
    public let candidateID: UUID
    public let agent: AgentKind

    public init(candidateID: UUID, agent: AgentKind) {
        self.candidateID = candidateID
        self.agent = agent
    }
}

public enum SkillReplacementChoice: String, Codable, Hashable, Sendable {
    case skip
    case replace
}

public enum SkillInstallationAction: String, Codable, Hashable, Sendable {
    case install
    case alreadyInstalled
    case skip
    case replace
    case unavailable
}

public struct SkillFileChange: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case added
        case modified
        case removed
    }

    public var id: String { "\(kind.rawValue):\(relativePath)" }
    public let kind: Kind
    public let relativePath: String

    public init(kind: Kind, relativePath: String) {
        self.kind = kind
        self.relativePath = relativePath
    }
}

public struct SkillInstallationPreviewItem: Identifiable, Hashable, Sendable {
    public var id: SkillInstallationTargetID { targetID }
    public let targetID: SkillInstallationTargetID
    public let candidate: SkillCandidate
    public let agentDisplayName: String
    public let targetDirectory: URL
    public let existingDirectory: URL?
    public let existingDescription: String?
    public let action: SkillInstallationAction
    public let changes: [SkillFileChange]
    public let reason: String?
    let expectedExistingDigest: String?
    let removesExistingProvenance: Bool

    init(
        targetID: SkillInstallationTargetID,
        candidate: SkillCandidate,
        agentDisplayName: String,
        targetDirectory: URL,
        existingDirectory: URL?,
        existingDescription: String?,
        action: SkillInstallationAction,
        changes: [SkillFileChange],
        reason: String?,
        expectedExistingDigest: String?,
        removesExistingProvenance: Bool
    ) {
        self.targetID = targetID
        self.candidate = candidate
        self.agentDisplayName = agentDisplayName
        self.targetDirectory = targetDirectory
        self.existingDirectory = existingDirectory
        self.existingDescription = existingDescription
        self.action = action
        self.changes = changes
        self.reason = reason
        self.expectedExistingDigest = expectedExistingDigest
        self.removesExistingProvenance = removesExistingProvenance
    }
}

public struct SkillInstallationPreview: Sendable {
    public let batchID: UUID
    public let sourceLabel: String
    public let items: [SkillInstallationPreviewItem]
    public let createdAt: Date
    let workspaceDirectory: URL

    init(
        batchID: UUID,
        sourceLabel: String,
        items: [SkillInstallationPreviewItem],
        createdAt: Date,
        workspaceDirectory: URL
    ) {
        self.batchID = batchID
        self.sourceLabel = sourceLabel
        self.items = items
        self.createdAt = createdAt
        self.workspaceDirectory = workspaceDirectory
    }
}

public enum SkillOperationStatus: String, Codable, Hashable, Sendable {
    case succeeded
    case alreadyInstalled
    case skipped
    case failed
}

public struct SkillOperationResultItem: Identifiable, Hashable, Sendable {
    public var id: SkillInstallationTargetID { targetID }
    public let targetID: SkillInstallationTargetID
    public let skillName: String
    public let agentDisplayName: String
    public let directory: URL
    public let status: SkillOperationStatus
    public let message: String
    public let diagnostic: String?

    public init(
        targetID: SkillInstallationTargetID,
        skillName: String,
        agentDisplayName: String,
        directory: URL,
        status: SkillOperationStatus,
        message: String,
        diagnostic: String? = nil
    ) {
        self.targetID = targetID
        self.skillName = skillName
        self.agentDisplayName = agentDisplayName
        self.directory = directory
        self.status = status
        self.message = message
        self.diagnostic = diagnostic
    }
}

public struct SkillOperationResult: Sendable {
    public let items: [SkillOperationResultItem]
    public let snapshot: GlobalSkillsSnapshot

    public init(items: [SkillOperationResultItem], snapshot: GlobalSkillsSnapshot) {
        self.items = items
        self.snapshot = snapshot
    }
}

public enum SkillSourceError: Error, Equatable, LocalizedError, Sendable {
    case unreadableArchive
    case invalidArchive
    case unsupportedArchiveFeature
    case unsafeArchivePath(String)
    case archiveLimitExceeded
    case noSkillsFound
    case invalidSkill(String)
    case unknownCandidateBatch

    public var errorDescription: String? {
        switch self {
        case .unreadableArchive: "The ZIP file could not be read."
        case .invalidArchive: "The ZIP file is damaged or invalid."
        case .unsupportedArchiveFeature: "The ZIP uses an unsupported or unsafe feature."
        case .unsafeArchivePath: "The ZIP contains an unsafe path."
        case .archiveLimitExceeded: "The ZIP exceeds the safe import limits."
        case .noSkillsFound: "No valid Skills were found in this source."
        case .invalidSkill(let reason): reason
        case .unknownCandidateBatch: "The installation source is no longer available."
        }
    }
}
