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

public enum SkillRemoteSourceKind: String, Codable, Hashable, Sendable {
    case github
    case skillsSh

    public init?(_ source: SkillSourceKind) {
        switch source {
        case .github: self = .github
        case .skillsSh: self = .skillsSh
        case .zip, .unknown: return nil
        }
    }

    public var sourceKind: SkillSourceKind {
        switch self {
        case .github: .github
        case .skillsSh: .skillsSh
        }
    }
}

public struct SkillRemoteProvenance: Codable, Hashable, Sendable {
    public let source: SkillRemoteSourceKind
    public let repository: String
    public let sourceRelativePath: String
    public let reference: SkillSourceReference
    public let resolvedCommit: String
    public let catalogSkillID: String?

    public init(
        source: SkillRemoteSourceKind,
        repository: String,
        sourceRelativePath: String,
        reference: SkillSourceReference,
        resolvedCommit: String,
        catalogSkillID: String? = nil
    ) {
        self.source = source
        self.repository = repository
        self.sourceRelativePath = sourceRelativePath
        self.reference = reference
        self.resolvedCommit = resolvedCommit
        self.catalogSkillID = catalogSkillID
    }
}

public enum SkillSourceIdentity: Codable, Hashable, Sendable {
    case skillsSh(catalogSkillID: String)
    case github(repository: String, sourceRelativePath: String)

    public init?(
        source: SkillRemoteSourceKind,
        repository: String,
        sourceRelativePath: String,
        catalogSkillID: String?
    ) {
        switch source {
        case .skillsSh:
            guard let catalogSkillID else { return nil }
            let normalizedID = catalogSkillID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalizedID.isEmpty else { return nil }
            self = .skillsSh(catalogSkillID: normalizedID)
        case .github:
            let normalizedRepository = repository.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "/")
                )
            ).lowercased()
            guard !normalizedRepository.isEmpty else { return nil }
            let trimmedPath = sourceRelativePath.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            let normalizedPath = trimmedPath == "." ? "" : trimmedPath
            self = .github(
                repository: normalizedRepository,
                sourceRelativePath: normalizedPath
            )
        }
    }
}

public extension SkillRemoteProvenance {
    var sourceIdentity: SkillSourceIdentity? {
        SkillSourceIdentity(
            source: source,
            repository: repository,
            sourceRelativePath: sourceRelativePath,
            catalogSkillID: catalogSkillID
        )
    }
}

public enum SkillInstallationOrigin: Codable, Hashable, Sendable {
    case zip
    case remote(SkillRemoteProvenance)

    public var source: SkillSourceKind {
        switch self {
        case .zip: .zip
        case .remote(let provenance): provenance.source.sourceKind
        }
    }

    public var remoteProvenance: SkillRemoteProvenance? {
        if case .remote(let provenance) = self { return provenance }
        return nil
    }
}

public struct SkillManifestDeclarations: Codable, Hashable, Sendable {
    public let author: String?
    public let license: String?
    public let compatibility: String?
    public let metadata: String?
    public let allowedTools: String?

    public init(
        author: String? = nil,
        license: String? = nil,
        compatibility: String? = nil,
        metadata: String? = nil,
        allowedTools: String? = nil
    ) {
        self.author = author
        self.license = license
        self.compatibility = compatibility
        self.metadata = metadata
        self.allowedTools = allowedTools
    }

    public var isEmpty: Bool {
        author == nil && license == nil && compatibility == nil && metadata == nil
            && allowedTools == nil
    }
}

public struct SkillCandidate: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let declarations: SkillManifestDeclarations
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
        declarations: SkillManifestDeclarations = SkillManifestDeclarations(),
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
        self.declarations = declarations
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

public struct RejectedSkillCandidate: Identifiable, Hashable, Sendable {
    public var id: String { "\(sourceRelativePath):\(message)" }
    public let sourceRelativePath: String
    public let message: String

    public init(sourceRelativePath: String, message: String) {
        self.sourceRelativePath = sourceRelativePath
        self.message = message
    }
}

public struct SkillCandidateBatch: Identifiable, Sendable {
    public let id: UUID
    public let source: SkillSourceKind
    public let sourceLabel: String
    public let candidates: [SkillCandidate]
    public let rejectedCandidates: [RejectedSkillCandidate]
    let workspaceDirectory: URL

    init(
        id: UUID = UUID(),
        source: SkillSourceKind,
        sourceLabel: String,
        candidates: [SkillCandidate],
        rejectedCandidates: [RejectedSkillCandidate] = [],
        workspaceDirectory: URL
    ) {
        self.id = id
        self.source = source
        self.sourceLabel = sourceLabel
        self.candidates = candidates
        self.rejectedCandidates = rejectedCandidates
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

public enum ExistingSkillMatch: String, Codable, Hashable, Sendable {
    case sameSourceIdentity
    case sameName
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
    public let existingMatch: ExistingSkillMatch?
    let expectedExistingDigest: String?
    let expectedSameNamePaths: Set<String>
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
        existingMatch: ExistingSkillMatch?,
        expectedExistingDigest: String?,
        expectedSameNamePaths: Set<String>,
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
        self.existingMatch = existingMatch
        self.expectedExistingDigest = expectedExistingDigest
        self.expectedSameNamePaths = expectedSameNamePaths
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
