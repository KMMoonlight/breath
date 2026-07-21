import BreathAgents
import BreathCore
import Foundation
import Yams

public enum SkillSourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case zip
    case github
    case skillsSh
    case unknown
}

public enum SkillSourceReferenceKind: String, Codable, Hashable, Sendable {
    case defaultBranch
    case branch
    case tag
    case commit
}

public struct SkillSourceReference: Codable, Hashable, Sendable {
    public let kind: SkillSourceReferenceKind
    public let value: String

    public init(kind: SkillSourceReferenceKind, value: String) {
        self.kind = kind
        self.value = value
    }

    public var followsUpdates: Bool {
        kind == .defaultBranch || kind == .branch
    }
}

public struct SkillInstallationRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String { installationDirectory.path }
    public let agent: AgentKind
    public let installationDirectory: URL
    public let skillName: String
    public let origin: SkillInstallationOrigin
    public let installedContentDigest: String
    public let installedAt: Date
    public let updatedAt: Date

    public var source: SkillSourceKind { origin.source }
    public var repository: String? { origin.remoteProvenance?.repository }
    public var sourceRelativePath: String? { origin.remoteProvenance?.sourceRelativePath }
    public var reference: SkillSourceReference? { origin.remoteProvenance?.reference }
    public var resolvedCommit: String? { origin.remoteProvenance?.resolvedCommit }

    public init(
        agent: AgentKind,
        installationDirectory: URL,
        skillName: String,
        origin: SkillInstallationOrigin,
        installedContentDigest: String,
        installedAt: Date,
        updatedAt: Date
    ) {
        self.agent = agent
        self.installationDirectory = installationDirectory
        self.skillName = skillName
        self.origin = origin
        self.installedContentDigest = installedContentDigest
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

public protocol SkillInstallationRecordRepository: Sendable {
    func loadSkillInstallationRecords() async throws -> [SkillInstallationRecord]
    func saveSkillInstallationRecord(_ record: SkillInstallationRecord) async throws
    func removeSkillInstallationRecord(installationDirectory: URL) async throws
}

public enum SkillUpdateState: String, Codable, Hashable, Sendable {
    case unavailable
    case checking
    case current
    case updateAvailable
    case locallyModified
    case pinned
    case failed
}

public enum SkillFileKind: String, Codable, Hashable, Sendable {
    case file
    case symbolicLink
}

public struct SkillFileEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let size: Int64
    public let kind: SkillFileKind

    public init(relativePath: String, size: Int64, kind: SkillFileKind) {
        self.relativePath = relativePath
        self.size = size
        self.kind = kind
    }
}

public struct InstalledSkillCopy: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(agent.rawValue):\(directory.path)" }
    public let agent: AgentKind
    public let agentDisplayName: String
    public let directory: URL
    public let resolvedDirectory: URL
    public let isSymbolicLink: Bool
    public let source: SkillSourceKind
    public let repository: String?
    public let sourceRelativePath: String?
    public let reference: SkillSourceReference?
    public let resolvedCommit: String?
    public let updateState: SkillUpdateState
    public let isLocallyModified: Bool

    public init(
        agent: AgentKind,
        agentDisplayName: String,
        directory: URL,
        resolvedDirectory: URL,
        isSymbolicLink: Bool,
        source: SkillSourceKind = .unknown,
        repository: String? = nil,
        sourceRelativePath: String? = nil,
        reference: SkillSourceReference? = nil,
        resolvedCommit: String? = nil,
        updateState: SkillUpdateState = .unavailable,
        isLocallyModified: Bool = false
    ) {
        self.agent = agent
        self.agentDisplayName = agentDisplayName
        self.directory = directory
        self.resolvedDirectory = resolvedDirectory
        self.isSymbolicLink = isSymbolicLink
        self.source = source
        self.repository = repository
        self.sourceRelativePath = sourceRelativePath
        self.reference = reference
        self.resolvedCommit = resolvedCommit
        self.updateState = updateState
        self.isLocallyModified = isLocallyModified
    }
}

public struct GlobalSkill: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let manifest: String
    public let contentDigest: String
    public let files: [SkillFileEntry]
    public let copies: [InstalledSkillCopy]

    public init(
        name: String,
        description: String,
        manifest: String,
        contentDigest: String,
        files: [SkillFileEntry],
        copies: [InstalledSkillCopy]
    ) {
        id = "\(name):\(contentDigest)"
        self.name = name
        self.description = description
        self.manifest = manifest
        self.contentDigest = contentDigest
        self.files = files
        self.copies = copies
    }

    public var sourceKinds: Set<SkillSourceKind> {
        Set(copies.map(\.source))
    }
}

public struct UnrecognizedSkillItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(agent.rawValue):\(path.path)" }
    public let agent: AgentKind
    public let agentDisplayName: String
    public let path: URL
    public let reason: String

    public init(
        agent: AgentKind,
        agentDisplayName: String,
        path: URL,
        reason: String
    ) {
        self.agent = agent
        self.agentDisplayName = agentDisplayName
        self.path = path
        self.reason = reason
    }
}

public enum SkillInstallationTargetAvailability: Codable, Hashable, Sendable {
    case available
    case unavailable(reason: String)

    public var isSelectable: Bool {
        if case .available = self { return true }
        return false
    }
}

public struct SkillInstallationTarget: Codable, Hashable, Identifiable, Sendable {
    public var id: AgentKind { agent }
    public let agent: AgentKind
    public let displayName: String
    public let directory: URL?
    public let availability: SkillInstallationTargetAvailability
    public let activationHint: String

    public init(
        agent: AgentKind,
        displayName: String,
        directory: URL?,
        availability: SkillInstallationTargetAvailability,
        activationHint: String
    ) {
        self.agent = agent
        self.displayName = displayName
        self.directory = directory
        self.availability = availability
        self.activationHint = activationHint
    }
}

public struct GlobalSkillsSnapshot: Codable, Equatable, Sendable {
    public let skills: [GlobalSkill]
    public let unrecognizedItems: [UnrecognizedSkillItem]
    public let targets: [SkillInstallationTarget]
    public let scannedAt: Date

    public init(
        skills: [GlobalSkill],
        unrecognizedItems: [UnrecognizedSkillItem],
        targets: [SkillInstallationTarget],
        scannedAt: Date
    ) {
        self.skills = skills
        self.unrecognizedItems = unrecognizedItems
        self.targets = targets
        self.scannedAt = scannedAt
    }

    public static let empty = GlobalSkillsSnapshot(
        skills: [],
        unrecognizedItems: [],
        targets: [],
        scannedAt: .distantPast
    )
}

public actor GlobalSkillsService {
    private let homeDirectory: URL
    private let agentAdapters: [AgentAdapterDescriptor]
    private let environment: [String: String]
    private var targetAvailability: [AgentKind: SkillInstallationTargetAvailability]
    private let recordRepository: (any SkillInstallationRecordRepository)?
    private let githubProvider: any GitHubSkillProviding
    private let skillsShProvider: any SkillsShProviding
    private let trash: any SkillTrashing
    private let writeCoordinator = SkillWriteCoordinator()
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private var updateStates: [String: SkillUpdateState] = [:]
    private var cachedUpdateResult: SkillUpdateCheckResult?
    private var snapshotContinuations: [
        UUID: AsyncStream<GlobalSkillsSnapshot>.Continuation
    ] = [:]

    public init(
        homeDirectory: URL,
        agentAdapters: [AgentAdapterDescriptor] = AgentAdapterRegistry.builtIn.adapters,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        targetAvailability: [AgentKind: SkillInstallationTargetAvailability] = [:],
        recordRepository: (any SkillInstallationRecordRepository)? = nil,
        githubProvider: any GitHubSkillProviding = GitHubHTTPSkillProvider(),
        skillsShProvider: any SkillsShProviding = SkillsShHTTPProvider(),
        trash: any SkillTrashing = MacOSSkillTrash(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.homeDirectory = homeDirectory
        self.agentAdapters = agentAdapters
        self.environment = environment
        self.targetAvailability = targetAvailability
        self.recordRepository = recordRepository
        self.githubProvider = githubProvider
        self.skillsShProvider = skillsShProvider
        self.trash = trash
        self.fileManager = fileManager
        self.now = now
    }

    public func scan() async -> GlobalSkillsSnapshot {
        var parsed: [ParsedInstalledSkill] = []
        var unrecognized: [UnrecognizedSkillItem] = []
        var targets: [SkillInstallationTarget] = []
        let records = (try? await recordRepository?.loadSkillInstallationRecords()) ?? []
        let recordsByPath = Dictionary(
            records.map { ($0.installationDirectory.standardizedFileURL.path, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var matchedRecordPaths: Set<String> = []
        var reconcilableAgents: Set<AgentKind> = []

        for adapter in agentAdapters {
            guard let capability = adapter.globalSkills else { continue }
            guard let root = capability.reliablyResolveDirectory(
                homeDirectory: homeDirectory,
                environment: environment
            ) else {
                targets.append(SkillInstallationTarget(
                    agent: adapter.kind,
                    displayName: adapter.displayName,
                    directory: nil,
                    availability: .unavailable(
                        reason: "The configured Skills root is not an absolute path."
                    ),
                    activationHint: capability.activationHint
                ))
                continue
            }
            reconcilableAgents.insert(adapter.kind)
            targets.append(SkillInstallationTarget(
                agent: adapter.kind,
                displayName: adapter.displayName,
                directory: root,
                availability: targetAvailability[adapter.kind] ?? .available,
                activationHint: capability.activationHint
            ))

            guard fileManager.fileExists(atPath: root.path) else { continue }
            do {
                let children = try fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                ).map {
                    root.appendingPathComponent($0.lastPathComponent, isDirectory: true)
                }.sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                for child in children {
                    do {
                        let installed = try parseInstalledSkill(
                            at: child,
                            adapter: adapter,
                            record: recordsByPath[child.standardizedFileURL.path]
                        )
                        parsed.append(installed)
                        if installed.matchesInstallationRecord {
                            matchedRecordPaths.insert(child.standardizedFileURL.path)
                        }
                    } catch {
                        unrecognized.append(UnrecognizedSkillItem(
                            agent: adapter.kind,
                            agentDisplayName: adapter.displayName,
                            path: child,
                            reason: Self.userFacingReason(for: error)
                        ))
                    }
                }
            } catch {
                unrecognized.append(UnrecognizedSkillItem(
                    agent: adapter.kind,
                    agentDisplayName: adapter.displayName,
                    path: root,
                    reason: "The Agent Skills directory could not be read."
                ))
            }
        }

        if let recordRepository {
            for record in records where reconcilableAgents.contains(record.agent)
                && !matchedRecordPaths.contains(
                    record.installationDirectory.standardizedFileURL.path
                )
            {
                try? await recordRepository.removeSkillInstallationRecord(
                    installationDirectory: record.installationDirectory
                )
            }
        }

        let grouped = Dictionary(grouping: parsed) { "\($0.name):\($0.contentDigest)" }
        let skills = grouped.values.compactMap { entries -> GlobalSkill? in
            guard let first = entries.first else { return nil }
            return GlobalSkill(
                name: first.name,
                description: first.description,
                manifest: first.manifest,
                contentDigest: first.contentDigest,
                files: first.files,
                copies: entries.map(\.copy).sorted {
                    $0.agentDisplayName.localizedStandardCompare($1.agentDisplayName) == .orderedAscending
                }
            )
        }.sorted {
            if $0.name == $1.name {
                return $0.description.localizedStandardCompare($1.description) == .orderedAscending
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        return GlobalSkillsSnapshot(
            skills: skills,
            unrecognizedItems: unrecognized.sorted { $0.path.path < $1.path.path },
            targets: targets,
            scannedAt: now()
        )
    }

    public func updateTargetAvailability(
        _ availability: [AgentKind: SkillInstallationTargetAvailability]
    ) async {
        guard targetAvailability != availability else { return }
        targetAvailability = availability
        let snapshot = await scan()
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }

    public nonisolated func snapshots(
        debouncedBy interval: Duration = .milliseconds(250)
    ) -> AsyncStream<GlobalSkillsSnapshot> {
        AsyncStream { continuation in
            let identifier = UUID()
            let task = Task {
                await self.addSnapshotContinuation(continuation, id: identifier)
                var monitor = await SkillDirectoryEventMonitor(
                    directories: self.directoriesToMonitor()
                )
                var previous = await self.scan()
                continuation.yield(previous)
                while !Task.isCancelled {
                    var events = monitor.events.makeAsyncIterator()
                    guard await events.next() != nil, !Task.isCancelled else {
                        monitor.cancel()
                        break
                    }
                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        monitor.cancel()
                        break
                    }
                    let next = await self.scan()
                    let replacementMonitor = await SkillDirectoryEventMonitor(
                        directories: self.directoriesToMonitor()
                    )
                    monitor.cancel()
                    monitor = replacementMonitor
                    if !Self.hasSameContents(previous, next) {
                        continuation.yield(next)
                        previous = next
                    }
                }
                monitor.cancel()
                await self.removeSnapshotContinuation(id: identifier)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.removeSnapshotContinuation(id: identifier) }
            }
        }
    }

    private func addSnapshotContinuation(
        _ continuation: AsyncStream<GlobalSkillsSnapshot>.Continuation,
        id: UUID
    ) {
        snapshotContinuations[id] = continuation
    }

    private func removeSnapshotContinuation(id: UUID) {
        snapshotContinuations.removeValue(forKey: id)
    }

    private func directoriesToMonitor() -> [URL] {
        var directories: [URL] = []
        for adapter in agentAdapters {
            guard let root = adapter.globalSkills?.reliablyResolveDirectory(
                homeDirectory: homeDirectory,
                environment: environment
            ) else { continue }
            var existing = root
            while !fileManager.fileExists(atPath: existing.path),
                  existing.path != "/"
            {
                existing.deleteLastPathComponent()
            }
            directories.append(existing)
            guard existing.standardizedFileURL == root.standardizedFileURL,
                  let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles],
                    errorHandler: { _, _ in false }
                  )
            else { continue }
            while let item = enumerator.nextObject() as? URL {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    directories.append(item)
                }
            }
        }
        return directories
    }

    private static func hasSameContents(
        _ lhs: GlobalSkillsSnapshot,
        _ rhs: GlobalSkillsSnapshot
    ) -> Bool {
        lhs.skills == rhs.skills
            && lhs.unrecognizedItems == rhs.unrecognizedItems
            && lhs.targets == rhs.targets
    }

    private func parseInstalledSkill(
        at presentedURL: URL,
        adapter: AgentAdapterDescriptor,
        record: SkillInstallationRecord?
    ) throws -> ParsedInstalledSkill {
        let values = try presentedURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        let isSymbolicLink = values.isSymbolicLink == true
        let resolvedURL = isSymbolicLink
            ? presentedURL.resolvingSymlinksInPath()
            : presentedURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw SkillReadingError.notDirectory
        }

        let manifestURL = resolvedURL.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SkillReadingError.missingManifest
        }
        let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        guard let manifest = String(data: manifestData, encoding: .utf8) else {
            throw SkillReadingError.invalidManifestEncoding
        }
        let metadata = try SkillManifestParser.parse(manifest)
        let fileContents = try SkillContentReader.collectFiles(
            in: resolvedURL,
            fileManager: fileManager
        )
        let digest = SkillContentReader.digest(fileContents)
        let files = fileContents.map {
            SkillFileEntry(
                relativePath: $0.relativePath,
                size: Int64($0.data.count),
                kind: $0.kind
            )
        }
        let matchingRecord = record.flatMap {
            $0.agent == adapter.kind && $0.skillName == metadata.name ? $0 : nil
        }
        let isLocallyModified = matchingRecord.map {
            guard case .remote = $0.origin else { return false }
            return $0.installedContentDigest != digest
        } ?? false
        let recordedUpdateState = updateStates[presentedURL.standardizedFileURL.path]
        return ParsedInstalledSkill(
            name: metadata.name,
            description: metadata.description,
            manifest: manifest,
            contentDigest: digest,
            files: files,
            copy: InstalledSkillCopy(
                agent: adapter.kind,
                agentDisplayName: adapter.displayName,
                directory: presentedURL,
                resolvedDirectory: resolvedURL,
                isSymbolicLink: isSymbolicLink,
                source: matchingRecord?.source ?? .unknown,
                repository: matchingRecord?.repository,
                sourceRelativePath: matchingRecord?.sourceRelativePath,
                reference: matchingRecord?.reference,
                resolvedCommit: matchingRecord?.resolvedCommit,
                updateState: recordedUpdateState ?? matchingRecord.map {
                    guard case .remote(let provenance) = $0.origin else {
                        return .unavailable
                    }
                    return provenance.reference.followsUpdates
                        ? (isLocallyModified ? .locallyModified : .current)
                        : .pinned
                } ?? .unavailable,
                isLocallyModified: isLocallyModified
            ),
            matchesInstallationRecord: matchingRecord != nil
        )
    }

    public func discoverSkills(inZip archiveURL: URL) throws -> SkillCandidateBatch {
        let workspace = fileManager.temporaryDirectory.appendingPathComponent(
            "breath-skill-import-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try SecureZIPArchive.extract(
                archiveURL: archiveURL,
                to: workspace,
                fileManager: fileManager
            )
            let discovery = try discoverCandidates(
                in: workspace,
                source: .zip,
                sourceLabel: archiveURL.lastPathComponent,
                remoteProvenance: nil
            )
            guard !discovery.candidates.isEmpty || !discovery.rejections.isEmpty else {
                throw SkillSourceError.noSkillsFound
            }
            return SkillCandidateBatch(
                source: .zip,
                sourceLabel: archiveURL.lastPathComponent,
                candidates: discovery.candidates,
                rejectedCandidates: discovery.rejections,
                workspaceDirectory: workspace
            )
        } catch {
            try? fileManager.removeItem(at: workspace)
            throw error
        }
    }

    public func discoverSkills(fromGitHub input: String) async throws -> SkillCandidateBatch {
        let locator = try GitHubSkillLocator.parse(input)
        let resolved = try await githubProvider.resolve(locator)
        return try makeRemoteCandidateBatch(
            resolved: resolved,
            source: .github,
            sourceLabel: "GitHub · \(resolved.repository)",
            securityAudit: .unknown,
            preferredSkillSlug: nil
        )
    }

    public func searchSkillsSh(
        query: String,
        limit: Int = 50
    ) async throws -> [SkillsShSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let results = try await skillsShProvider.search(query: trimmed, limit: limit)
        let provider = skillsShProvider
        return await withTaskGroup(
            of: (Int, SkillsShSearchResult).self,
            returning: [SkillsShSearchResult].self
        ) { group in
            for (index, result) in results.enumerated() {
                group.addTask {
                    let audit = (try? await provider.audit(skillID: result.id)) ?? .unknown
                    return (index, result.withSecurityAudit(audit))
                }
            }
            var audited: [(Int, SkillsShSearchResult)] = []
            for await item in group { audited.append(item) }
            return audited.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    public func discoverSkill(
        fromSkillsSh result: SkillsShSearchResult
    ) async throws -> SkillCandidateBatch {
        guard result.sourceType.lowercased() == "github",
              result.source.split(separator: "/").count == 2
        else {
            throw OnlineSkillSourceError.unsupportedCatalogSource
        }
        let resolved = try await githubProvider.resolve(
            GitHubSkillLocator(repository: result.source)
        )
        return try makeRemoteCandidateBatch(
            resolved: resolved,
            source: .skillsSh,
            sourceLabel: "skills.sh · \(result.name)",
            securityAudit: result.securityAudit,
            preferredSkillSlug: result.slug,
            catalogSkillID: result.id
        )
    }

    public func beginUpdateCheckSession() {
        if let cachedUpdateResult {
            for update in cachedUpdateResult.updates {
                try? fileManager.removeItem(at: update.workspaceDirectory)
            }
        }
        cachedUpdateResult = nil
    }

    public func checkForUpdates(force: Bool = false) async -> SkillUpdateCheckResult {
        if !force, let cachedUpdateResult {
            return SkillUpdateCheckResult(
                updates: cachedUpdateResult.updates,
                failures: cachedUpdateResult.failures,
                checkedAt: cachedUpdateResult.checkedAt,
                usedSessionCache: true
            )
        }
        if force, let cachedUpdateResult {
            for update in cachedUpdateResult.updates {
                try? fileManager.removeItem(at: update.workspaceDirectory)
            }
        }
        guard let recordRepository else {
            let result = SkillUpdateCheckResult(
                updates: [],
                failures: [],
                checkedAt: now(),
                usedSessionCache: false
            )
            cachedUpdateResult = result
            return result
        }

        let records: [SkillInstallationRecord]
        do {
            records = try await recordRepository.loadSkillInstallationRecords()
        } catch {
            let result = SkillUpdateCheckResult(
                updates: [],
                failures: [SkillUpdateCheckFailure(
                    skillName: "Skills",
                    repository: "",
                    sourceRelativePath: "",
                    message: "Saved Skill sources could not be read."
                )],
                checkedAt: now(),
                usedSessionCache: false
            )
            cachedUpdateResult = result
            return result
        }

        let localSnapshot = await scan()
        let keyedRecords = records.compactMap { record -> SkillUpdateRecord? in
            guard case .remote(let provenance) = record.origin else { return nil }
            return SkillUpdateRecord(
                key: SkillUpdateGroupKey(
                    skillName: record.skillName,
                    source: provenance.source.sourceKind,
                    repository: provenance.repository,
                    sourceRelativePath: provenance.sourceRelativePath,
                    reference: provenance.reference,
                    catalogSkillID: provenance.catalogSkillID
                ),
                record: record,
                resolvedCommit: provenance.resolvedCommit
            )
        }
        let groups = Dictionary(grouping: keyedRecords, by: \.key)
        var updates: [SkillAvailableUpdate] = []
        var failures: [SkillUpdateCheckFailure] = []
        for (key, keyedGroup) in groups.sorted(by: { $0.key.sortKey < $1.key.sortKey }) {
            let groupRecords = keyedGroup.map(\.record)
            guard key.reference.followsUpdates else {
                for record in groupRecords {
                    updateStates[record.installationDirectory.standardizedFileURL.path] = .pinned
                }
                continue
            }
            do {
                let resolved = try await githubProvider.resolve(GitHubSkillLocator(
                    repository: key.repository,
                    subdirectory: key.sourceRelativePath.isEmpty ? nil : key.sourceRelativePath,
                    reference: key.reference
                ))
                let securityAudit: SkillSecurityAudit
                if key.source == .skillsSh, let catalogSkillID = key.catalogSkillID {
                    securityAudit = (try? await skillsShProvider.audit(
                        skillID: catalogSkillID
                    )) ?? .unknown
                } else {
                    securityAudit = .unknown
                }
                let batch = try makeRemoteCandidateBatch(
                    resolved: resolved,
                    source: key.source,
                    sourceLabel: "Update · \(key.repository)",
                    securityAudit: securityAudit,
                    preferredSkillSlug: nil
                )
                guard let candidate = batch.candidates.first(where: {
                    $0.name == key.skillName
                }) else {
                    try? fileManager.removeItem(at: batch.workspaceDirectory)
                    throw SkillSourceError.noSkillsFound
                }

                var targets: [SkillUpdateTarget] = []
                for record in groupRecords {
                    let recordPath = record.installationDirectory.standardizedFileURL.path
                    if candidate.contentDigest == record.installedContentDigest {
                        updateStates[recordPath] = key.reference.followsUpdates
                            ? .current
                            : .pinned
                        continue
                    }
                    guard let copy = localSnapshot.skills.lazy.flatMap(\.copies).first(where: {
                        $0.directory.standardizedFileURL.path == recordPath
                            && $0.agent == record.agent
                    }) else {
                        continue
                    }
                    updateStates[recordPath] = .updateAvailable
                    targets.append(SkillUpdateTarget(
                        agent: record.agent,
                        agentDisplayName: copy.agentDisplayName,
                        directory: copy.directory,
                        isLocallyModified: copy.isLocallyModified,
                        isSymbolicLink: copy.isSymbolicLink,
                        isSelectedByDefault: !copy.isLocallyModified
                    ))
                }
                if targets.isEmpty {
                    try? fileManager.removeItem(at: batch.workspaceDirectory)
                    continue
                }
                updates.append(SkillAvailableUpdate(
                    skillName: key.skillName,
                    source: key.source,
                    repository: key.repository,
                    sourceRelativePath: key.sourceRelativePath,
                    oldCommits: Array(Set(keyedGroup.map(\.resolvedCommit))).sorted(),
                    newCommit: resolved.resolvedCommit,
                    candidate: candidate,
                    targets: targets.sorted { $0.agentDisplayName < $1.agentDisplayName },
                    workspaceDirectory: batch.workspaceDirectory
                ))
            } catch {
                for record in groupRecords {
                    updateStates[record.installationDirectory.standardizedFileURL.path] = .failed
                }
                failures.append(SkillUpdateCheckFailure(
                    skillName: key.skillName,
                    repository: key.repository,
                    sourceRelativePath: key.sourceRelativePath,
                    message: error.localizedDescription
                ))
            }
        }
        let result = SkillUpdateCheckResult(
            updates: updates,
            failures: failures,
            checkedAt: now(),
            usedSessionCache: false
        )
        cachedUpdateResult = result
        return result
    }

    public func previewUpdate(
        _ update: SkillAvailableUpdate,
        targetAgents: Set<AgentKind>? = nil
    ) async -> SkillInstallationPreview {
        let selectedAgents = targetAgents ?? Set(
            update.targets.filter(\.isSelectedByDefault).map(\.agent)
        )
        let batch = SkillCandidateBatch(
            source: update.source,
            sourceLabel: "Update · \(update.repository)",
            candidates: [update.candidate],
            workspaceDirectory: update.workspaceDirectory
        )
        let choices = Dictionary(uniqueKeysWithValues: selectedAgents.map {
            (
                SkillInstallationTargetID(
                    candidateID: update.candidate.id,
                    agent: $0
                ),
                SkillReplacementChoice.replace
            )
        })
        return await previewInstallation(
            batch: batch,
            candidateIDs: [update.candidate.id],
            targetAgents: selectedAgents,
            replacementChoices: choices
        )
    }

    public func previewUninstall(
        skillID: String,
        targetAgents: Set<AgentKind>
    ) async -> SkillUninstallPreview {
        let snapshot = await scan()
        guard let skill = snapshot.skills.first(where: { $0.id == skillID }) else {
            return SkillUninstallPreview(items: [], createdAt: now())
        }
        let items = skill.copies.filter {
            targetAgents.contains($0.agent)
        }.map { copy in
            SkillUninstallPreviewItem(
                skillID: skill.id,
                skillName: skill.name,
                agent: copy.agent,
                agentDisplayName: copy.agentDisplayName,
                directory: copy.directory,
                resolvedDirectory: copy.resolvedDirectory,
                action: copy.isSymbolicLink ? .removeSymbolicLink : .moveToTrash,
                expectedDigest: skill.contentDigest
            )
        }.sorted { $0.agentDisplayName < $1.agentDisplayName }
        return SkillUninstallPreview(items: items, createdAt: now())
    }

    public func uninstall(_ preview: SkillUninstallPreview) async -> SkillUninstallResult {
        let committer = SkillUninstallCommitter(
            fileManager: fileManager,
            recordRepository: recordRepository,
            trash: trash
        )
        let coordinator = writeCoordinator
        var indexedResults: [(Int, SkillUninstallResultItem)] = []
        await withTaskGroup(of: (Int, SkillUninstallResultItem).self) { group in
            for (index, item) in preview.items.enumerated() {
                group.addTask {
                    let result: SkillUninstallResultItem
                    do {
                        try await coordinator.withLock(for: item.agent) {
                            try await committer.commit(item)
                        }
                        result = SkillUninstallResultItem(
                            skillName: item.skillName,
                            agent: item.agent,
                            agentDisplayName: item.agentDisplayName,
                            directory: item.directory,
                            status: .succeeded,
                            message: item.action == .removeSymbolicLink
                                ? "The selected symbolic link was removed; its shared target was kept."
                                : "The selected Skill was moved to Trash."
                        )
                    } catch {
                        result = SkillUninstallResultItem(
                            skillName: item.skillName,
                            agent: item.agent,
                            agentDisplayName: item.agentDisplayName,
                            directory: item.directory,
                            status: .failed,
                            message: Self.uninstallFailureMessage(error),
                            diagnostic: Self.sanitizedDiagnostic(error)
                        )
                    }
                    return (index, result)
                }
            }
            for await result in group { indexedResults.append(result) }
        }
        for item in preview.items {
            updateStates.removeValue(forKey: item.directory.standardizedFileURL.path)
        }
        let snapshot = await scan()
        return SkillUninstallResult(
            items: indexedResults.sorted { $0.0 < $1.0 }.map(\.1),
            snapshot: snapshot
        )
    }

    public func cancel(_ batch: SkillCandidateBatch) {
        try? fileManager.removeItem(at: batch.workspaceDirectory)
    }

    public func previewInstallation(
        batch: SkillCandidateBatch,
        candidateIDs: Set<UUID>,
        targetAgents: Set<AgentKind>,
        replacementChoices: [SkillInstallationTargetID: SkillReplacementChoice] = [:]
    ) async -> SkillInstallationPreview {
        let snapshot = await scan()
        let selectedCandidates = batch.candidates.filter { candidateIDs.contains($0.id) }
        var items: [SkillInstallationPreviewItem] = []
        for candidate in selectedCandidates {
            for agent in targetAgents.sorted(by: { $0.rawValue < $1.rawValue }) {
                let targetID = SkillInstallationTargetID(
                    candidateID: candidate.id,
                    agent: agent
                )
                guard let adapter = agentAdapters.first(where: { $0.kind == agent }),
                      let capability = adapter.globalSkills
                else {
                    items.append(unavailablePreviewItem(
                        targetID: targetID,
                        candidate: candidate,
                        agentDisplayName: agent.rawValue,
                        reason: "This Agent does not declare a global Skills directory."
                    ))
                    continue
                }
                guard let root = capability.reliablyResolveDirectory(
                    homeDirectory: homeDirectory,
                    environment: environment
                ) else {
                    items.append(unavailablePreviewItem(
                        targetID: targetID,
                        candidate: candidate,
                        agentDisplayName: adapter.displayName,
                        reason: "The configured Skills root is not an absolute path."
                    ))
                    continue
                }
                let target = root.appendingPathComponent(candidate.name, isDirectory: true)
                let availability = targetAvailability[agent] ?? .available
                guard availability.isSelectable else {
                    let reason: String
                    if case .unavailable(let unavailableReason) = availability {
                        reason = unavailableReason
                    } else {
                        reason = "This Agent is not available."
                    }
                    items.append(unavailablePreviewItem(
                        targetID: targetID,
                        candidate: candidate,
                        agentDisplayName: adapter.displayName,
                        targetDirectory: target,
                        reason: reason
                    ))
                    continue
                }

                let matchingSkills = snapshot.skills.filter { skill in
                    skill.name == candidate.name
                        && skill.copies.contains(where: { $0.agent == agent })
                }
                let existing = matchingSkills.compactMap { skill -> (GlobalSkill, InstalledSkillCopy)? in
                    guard let copy = skill.copies.first(where: { $0.agent == agent }) else {
                        return nil
                    }
                    return (skill, copy)
                }
                if existing.count > 1 {
                    items.append(unavailablePreviewItem(
                        targetID: targetID,
                        candidate: candidate,
                        agentDisplayName: adapter.displayName,
                        targetDirectory: target,
                        reason: "The Agent contains more than one existing Skill with this name."
                    ))
                    continue
                }
                if let (existingSkill, existingCopy) = existing.first {
                    let action: SkillInstallationAction
                    if existingSkill.contentDigest == candidate.contentDigest {
                        action = .alreadyInstalled
                    } else if replacementChoices[targetID] == .replace {
                        action = .replace
                    } else {
                        action = .skip
                    }
                    items.append(SkillInstallationPreviewItem(
                        targetID: targetID,
                        candidate: candidate,
                        agentDisplayName: adapter.displayName,
                        targetDirectory: existingCopy.directory,
                        existingDirectory: existingCopy.directory,
                        existingDescription: existingSkill.description,
                        action: action,
                        changes: Self.fileChanges(
                            existing: existingSkill.files,
                            candidate: candidate.files,
                            contentsDiffer: existingSkill.contentDigest != candidate.contentDigest
                        ),
                        reason: action == .skip
                            ? "An existing same-name Skill will be kept unless replacement is selected."
                            : nil,
                        expectedExistingDigest: existingSkill.contentDigest,
                        removesExistingProvenance: existingCopy.source == .github
                            || existingCopy.source == .skillsSh
                    ))
                } else {
                    items.append(SkillInstallationPreviewItem(
                        targetID: targetID,
                        candidate: candidate,
                        agentDisplayName: adapter.displayName,
                        targetDirectory: target,
                        existingDirectory: nil,
                        existingDescription: nil,
                        action: .install,
                        changes: candidate.files.map {
                            SkillFileChange(kind: .added, relativePath: $0.relativePath)
                        },
                        reason: nil,
                        expectedExistingDigest: nil,
                        removesExistingProvenance: false
                    ))
                }
            }
        }
        return SkillInstallationPreview(
            batchID: batch.id,
            sourceLabel: batch.sourceLabel,
            items: items,
            createdAt: now(),
            workspaceDirectory: batch.workspaceDirectory
        )
    }

    public func install(
        _ preview: SkillInstallationPreview,
        confirmedRiskCandidateIDs: Set<UUID> = []
    ) async -> SkillOperationResult {
        let committer = SkillInstallationCommitter(
            fileManager: fileManager,
            recordRepository: recordRepository,
            now: now
        )
        let coordinator = writeCoordinator
        var indexedResults: [(Int, SkillOperationResultItem)] = []
        await withTaskGroup(of: (Int, SkillOperationResultItem).self) { group in
            for (index, item) in preview.items.enumerated() {
                let targetIsCurrentlyAvailable = targetAvailability[item.targetID.agent]?
                    .isSelectable ?? true
                group.addTask {
                    let result: SkillOperationResultItem
                    guard targetIsCurrentlyAvailable else {
                        return (
                            index,
                            Self.resultItem(
                                for: item,
                                status: .failed,
                                message: "The Skill installation target is unavailable."
                            )
                        )
                    }
                    switch item.action {
                    case .alreadyInstalled:
                        result = Self.resultItem(
                            for: item,
                            status: .alreadyInstalled,
                            message: "The same Skill content is already installed."
                        )
                    case .skip:
                        result = Self.resultItem(
                            for: item,
                            status: .skipped,
                            message: "The existing same-name Skill was kept."
                        )
                    case .unavailable:
                        result = Self.resultItem(
                            for: item,
                            status: .failed,
                            message: item.reason ?? "The Skill installation target is unavailable."
                        )
                    case .install, .replace:
                        if item.candidate.securityAudit.riskLevel.requiresExtraConfirmation,
                           !confirmedRiskCandidateIDs.contains(item.candidate.id)
                        {
                            result = Self.resultItem(
                                for: item,
                                status: .failed,
                                message: "Confirm the high-risk security audit before installing this Skill."
                            )
                        } else {
                            do {
                                try await coordinator.withLock(for: item.targetID.agent) {
                                    try await committer.commit(item)
                                }
                                result = Self.resultItem(
                                    for: item,
                                    status: .succeeded,
                                    message: "Installed. Start a new Agent session if the Skill is not visible yet."
                                )
                            } catch {
                                result = Self.resultItem(
                                    for: item,
                                    status: .failed,
                                    message: Self.installationFailureMessage(error),
                                    diagnostic: Self.sanitizedDiagnostic(error)
                                )
                            }
                        }
                    }
                    return (index, result)
                }
            }
            for await result in group { indexedResults.append(result) }
        }
        try? fileManager.removeItem(at: preview.workspaceDirectory)
        let snapshot = await scan()
        return SkillOperationResult(
            items: indexedResults.sorted { $0.0 < $1.0 }.map(\.1),
            snapshot: snapshot
        )
    }

    private func discoverCandidates(
        in sourceRoot: URL,
        source: SkillSourceKind,
        sourceLabel: String,
        remoteProvenance: SkillRemoteProvenance?,
        securityAudit: SkillSecurityAudit = .unknown
    ) throws -> SkillCandidateDiscovery {
        var roots: [URL] = []
        if fileManager.fileExists(
            atPath: sourceRoot.appendingPathComponent("SKILL.md").path
        ) {
            roots = [sourceRoot]
        } else {
            roots = try boundedCandidateRoots(in: sourceRoot)
        }
        guard roots.count <= 256 else {
            throw SkillSourceError.archiveLimitExceeded
        }
        var candidates: [SkillCandidate] = []
        var rejections: [RejectedSkillCandidate] = []
        for root in roots.sorted(by: { $0.path < $1.path }) {
            let relativePath = SkillContentReader.relativePath(from: sourceRoot, to: root)
            do {
                candidates.append(try makeCandidate(
                    root: root,
                    sourceRoot: sourceRoot,
                    source: source,
                    sourceLabel: sourceLabel,
                    remoteProvenance: remoteProvenance,
                    securityAudit: securityAudit
                ))
            } catch {
                rejections.append(RejectedSkillCandidate(
                    sourceRelativePath: relativePath,
                    message: Self.candidateRejectionMessage(error)
                ))
            }
        }
        return SkillCandidateDiscovery(
            candidates: candidates,
            rejections: rejections
        )
    }

    private func makeCandidate(
        root: URL,
        sourceRoot: URL,
        source: SkillSourceKind,
        sourceLabel: String,
        remoteProvenance: SkillRemoteProvenance?,
        securityAudit: SkillSecurityAudit
    ) throws -> SkillCandidate {
        let manifestURL = root.appendingPathComponent("SKILL.md")
        guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw SkillSourceError.invalidSkill("SKILL.md is missing or is not valid UTF-8.")
        }
        let metadata: SkillManifestMetadata
        do {
            metadata = try SkillManifestParser.parse(manifest)
        } catch {
            throw SkillSourceError.invalidSkill(Self.userFacingReason(for: error))
        }
        guard Self.isSafeSkillName(metadata.name) else {
            throw SkillSourceError.invalidSkill("The Skill name cannot be used as one directory component.")
        }
        let contents = try SkillContentReader.collectFiles(
            in: root,
            fileManager: fileManager
        )
        let relativePath = SkillContentReader.relativePath(from: sourceRoot, to: root)
        var warnings: [SkillCandidateWarning] = []
        if metadata.name.range(
            of: "^[a-z0-9]+(?:-[a-z0-9]+)*$",
            options: .regularExpression
        ) == nil {
            warnings.append(SkillCandidateWarning(
                kind: .nonstandardName,
                message: "The Skill name does not use the recommended lowercase hyphen format."
            ))
        }
        if root.lastPathComponent != metadata.name {
            warnings.append(SkillCandidateWarning(
                kind: .directoryNameMismatch,
                message: "The source directory name differs from the Skill name."
            ))
        }
        let provenance = remoteProvenance.map {
            let sourcePath = [$0.sourceRelativePath, relativePath]
                .filter { !$0.isEmpty && $0 != "." }
                .joined(separator: "/")
            return SkillRemoteProvenance(
                source: $0.source,
                repository: $0.repository,
                sourceRelativePath: sourcePath,
                reference: $0.reference,
                resolvedCommit: $0.resolvedCommit,
                catalogSkillID: $0.catalogSkillID
            )
        }
        return SkillCandidate(
            name: metadata.name,
            description: metadata.description,
            declarations: metadata.declarations,
            manifest: manifest,
            contentDigest: SkillContentReader.digest(contents),
            files: contents.map {
                SkillFileEntry(
                    relativePath: $0.relativePath,
                    size: Int64($0.data.count),
                    kind: $0.kind
                )
            },
            warnings: warnings,
            source: source,
            sourceLabel: sourceLabel,
            sourceRelativePath: relativePath,
            remoteProvenance: provenance,
            securityAudit: securityAudit,
            directory: root
        )
    }

    private func makeRemoteCandidateBatch(
        resolved: GitHubResolvedSkillArchive,
        source: SkillSourceKind,
        sourceLabel: String,
        securityAudit: SkillSecurityAudit,
        preferredSkillSlug: String?,
        catalogSkillID: String? = nil
    ) throws -> SkillCandidateBatch {
        let workspace = fileManager.temporaryDirectory.appendingPathComponent(
            "breath-skill-remote-\(UUID().uuidString)",
            isDirectory: true
        )
        let archiveURL = workspace.appendingPathComponent("source.zip")
        let extracted = workspace.appendingPathComponent("contents", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: workspace,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try resolved.archiveData.write(to: archiveURL, options: [.atomic])
            try SecureZIPArchive.extract(
                archiveURL: archiveURL,
                to: extracted,
                fileManager: fileManager
            )
            try? fileManager.removeItem(at: archiveURL)
            let topLevel = try fileManager.contentsOfDirectory(
                at: extracted,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let repositoryRoot: URL
            if topLevel.count == 1,
               (try? topLevel[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            {
                repositoryRoot = topLevel[0]
            } else {
                repositoryRoot = extracted
            }
            let sourceRoot: URL
            if let subdirectory = resolved.subdirectory, !subdirectory.isEmpty {
                guard Self.isSafeRelativeSourcePath(subdirectory) else {
                    throw SkillSourceError.unsafeArchivePath(subdirectory)
                }
                sourceRoot = repositoryRoot.appendingPathComponent(subdirectory, isDirectory: true)
                guard fileManager.fileExists(atPath: sourceRoot.path) else {
                    throw SkillSourceError.noSkillsFound
                }
            } else {
                sourceRoot = repositoryRoot
            }
            guard let remoteSource = SkillRemoteSourceKind(source) else {
                throw SkillSourceError.noSkillsFound
            }
            let provenance = SkillRemoteProvenance(
                source: remoteSource,
                repository: resolved.repository,
                sourceRelativePath: resolved.subdirectory ?? "",
                reference: resolved.reference,
                resolvedCommit: resolved.resolvedCommit,
                catalogSkillID: catalogSkillID
            )
            var discovery = try discoverCandidates(
                in: sourceRoot,
                source: source,
                sourceLabel: sourceLabel,
                remoteProvenance: provenance,
                securityAudit: securityAudit
            )
            if let preferredSkillSlug {
                let normalizedSlug = preferredSkillSlug.lowercased()
                let preferred = discovery.candidates.filter {
                    $0.name.lowercased() == normalizedSlug
                        || $0.sourceRelativePath.split(separator: "/").last?
                            .lowercased() == normalizedSlug
                }
                let rejected = discovery.rejections.filter {
                    $0.sourceRelativePath.split(separator: "/").last?
                        .lowercased() == normalizedSlug
                }
                guard !preferred.isEmpty || !rejected.isEmpty else {
                    throw SkillSourceError.noSkillsFound
                }
                discovery = SkillCandidateDiscovery(
                    candidates: preferred,
                    rejections: rejected
                )
            }
            guard !discovery.candidates.isEmpty || !discovery.rejections.isEmpty else {
                throw SkillSourceError.noSkillsFound
            }
            return SkillCandidateBatch(
                source: source,
                sourceLabel: sourceLabel,
                candidates: discovery.candidates,
                rejectedCandidates: discovery.rejections,
                workspaceDirectory: workspace
            )
        } catch {
            try? fileManager.removeItem(at: workspace)
            throw error
        }
    }

    private func boundedSkillRoots(in sourceRoot: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in false }
        ) else {
            return []
        }
        let excluded = Set([".git", "node_modules", ".build", "build", "dist", "DerivedData"])
        var roots: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            let depth = item.pathComponents.count - sourceRoot.pathComponents.count
            if depth > 8 || excluded.contains(item.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            if fileManager.fileExists(atPath: item.appendingPathComponent("SKILL.md").path) {
                roots.append(item)
                enumerator.skipDescendants()
            }
            if roots.count > 256 {
                throw SkillSourceError.archiveLimitExceeded
            }
        }
        return roots
    }

    private func boundedCandidateRoots(in sourceRoot: URL) throws -> [URL] {
        let manifestRoots = try boundedSkillRoots(in: sourceRoot)
        let excludedPeers = Set([
            ".git", ".github", ".build", "build", "dist", "DerivedData",
            "node_modules", "docs", "scripts", "src", "tests", "assets", "references",
        ])
        var rootsByPath = Dictionary(
            manifestRoots.map { ($0.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let collectionParents = Set(manifestRoots.map { $0.deletingLastPathComponent() })
        for parent in collectionParents {
            let peers = try fileManager.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for peer in peers where !excludedPeers.contains(peer.lastPathComponent) {
                guard (try? peer.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { continue }
                rootsByPath[peer.standardizedFileURL.path] = peer
            }
        }
        if rootsByPath.isEmpty {
            let children = try fileManager.contentsOfDirectory(
                at: sourceRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter {
                !excludedPeers.contains($0.lastPathComponent)
                    && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            if children.isEmpty {
                rootsByPath[sourceRoot.standardizedFileURL.path] = sourceRoot
            } else {
                for child in children {
                    rootsByPath[child.standardizedFileURL.path] = child
                }
            }
        }
        guard rootsByPath.count <= 256 else {
            throw SkillSourceError.archiveLimitExceeded
        }
        return Array(rootsByPath.values)
    }

    private func unavailablePreviewItem(
        targetID: SkillInstallationTargetID,
        candidate: SkillCandidate,
        agentDisplayName: String,
        targetDirectory: URL = URL(fileURLWithPath: "/"),
        reason: String
    ) -> SkillInstallationPreviewItem {
        SkillInstallationPreviewItem(
            targetID: targetID,
            candidate: candidate,
            agentDisplayName: agentDisplayName,
            targetDirectory: targetDirectory,
            existingDirectory: nil,
            existingDescription: nil,
            action: .unavailable,
            changes: [],
            reason: reason,
            expectedExistingDigest: nil,
            removesExistingProvenance: false
        )
    }

    private static func resultItem(
        for item: SkillInstallationPreviewItem,
        status: SkillOperationStatus,
        message: String,
        diagnostic: String? = nil
    ) -> SkillOperationResultItem {
        SkillOperationResultItem(
            targetID: item.targetID,
            skillName: item.candidate.name,
            agentDisplayName: item.agentDisplayName,
            directory: item.targetDirectory,
            status: status,
            message: message,
            diagnostic: diagnostic
        )
    }

    private static func fileChanges(
        existing: [SkillFileEntry],
        candidate: [SkillFileEntry],
        contentsDiffer: Bool
    ) -> [SkillFileChange] {
        let existingByPath = Dictionary(uniqueKeysWithValues: existing.map { ($0.relativePath, $0) })
        let candidateByPath = Dictionary(uniqueKeysWithValues: candidate.map { ($0.relativePath, $0) })
        var changes: [SkillFileChange] = []
        for path in candidateByPath.keys.sorted() {
            if let old = existingByPath[path] {
                if contentsDiffer && (old.size != candidateByPath[path]?.size || old.kind != candidateByPath[path]?.kind) {
                    changes.append(SkillFileChange(kind: .modified, relativePath: path))
                }
            } else {
                changes.append(SkillFileChange(kind: .added, relativePath: path))
            }
        }
        for path in existingByPath.keys where candidateByPath[path] == nil {
            changes.append(SkillFileChange(kind: .removed, relativePath: path))
        }
        if contentsDiffer && changes.isEmpty {
            changes = candidate.map {
                SkillFileChange(kind: .modified, relativePath: $0.relativePath)
            }
        }
        return changes.sorted { $0.relativePath < $1.relativePath }
    }

    private static func isSafeSkillName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
            && !name.unicodeScalars.contains(where: { $0.value == 0 })
            && name.utf8.count <= 128
    }

    private static func isSafeRelativeSourcePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.contains("\\")
            && path.split(separator: "/").allSatisfy { $0 != "." && $0 != ".." }
    }

    private static func installationFailureMessage(_ error: Error) -> String {
        switch error {
        case SkillInstallationError.stalePreview:
            "The target changed after preview. Refresh and review it again."
        case SkillInstallationError.recordPersistenceFailed:
            "The source record could not be saved, so the previous directory was restored."
        default:
            "The Skill could not be installed at this target."
        }
    }

    private static func uninstallFailureMessage(_ error: Error) -> String {
        if case SkillInstallationError.recordPersistenceFailed = error {
            return "The Skill was removed, but its source record could not be cleaned up. Refresh to retry reconciliation."
        }
        return installationFailureMessage(error)
    }

    private static func candidateRejectionMessage(_ error: Error) -> String {
        if let sourceError = error as? SkillSourceError,
           let description = sourceError.errorDescription
        {
            return description
        }
        return userFacingReason(for: error)
    }

    private static func sanitizedDiagnostic(_ error: Error) -> String {
        String(describing: type(of: error))
    }

    private static func userFacingReason(for error: Error) -> String {
        switch error {
        case SkillReadingError.notDirectory:
            "The item is not a readable Skill directory."
        case SkillReadingError.missingManifest:
            "SKILL.md is missing."
        case SkillReadingError.invalidManifestEncoding:
            "SKILL.md is not valid UTF-8."
        case SkillReadingError.missingName:
            "SKILL.md is missing a name."
        case SkillReadingError.missingDescription:
            "SKILL.md is missing a description."
        case SkillReadingError.invalidFrontmatter:
            "SKILL.md frontmatter could not be parsed."
        default:
            "The Skill could not be read."
        }
    }

}

private struct ParsedInstalledSkill {
    let name: String
    let description: String
    let manifest: String
    let contentDigest: String
    let files: [SkillFileEntry]
    let copy: InstalledSkillCopy
    let matchesInstallationRecord: Bool
}

private struct SkillCandidateDiscovery {
    let candidates: [SkillCandidate]
    let rejections: [RejectedSkillCandidate]
}

struct SkillManifestMetadata {
    let name: String
    let description: String
    let declarations: SkillManifestDeclarations
}

enum SkillReadingError: Error {
    case notDirectory
    case missingManifest
    case invalidManifestEncoding
    case invalidFrontmatter
    case missingName
    case missingDescription
    case unreadableDirectory
}

private struct SkillUpdateGroupKey: Hashable {
    let skillName: String
    let source: SkillSourceKind
    let repository: String
    let sourceRelativePath: String
    let reference: SkillSourceReference
    let catalogSkillID: String?

    var sortKey: String {
        "\(repository):\(sourceRelativePath):\(skillName):\(reference.value):\(catalogSkillID ?? "")"
    }
}

private struct SkillUpdateRecord {
    let key: SkillUpdateGroupKey
    let record: SkillInstallationRecord
    let resolvedCommit: String
}

enum SkillManifestParser {
    static func parse(_ manifest: String) throws -> SkillManifestMetadata {
        let lines = manifest.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              })
        else {
            throw SkillReadingError.invalidFrontmatter
        }

        let frontmatter = lines[1..<closingIndex].joined(separator: "\n")
        let values: [String: Any]
        do {
            guard let loaded = try Yams.load(yaml: frontmatter) as? [String: Any] else {
                throw SkillReadingError.invalidFrontmatter
            }
            values = loaded
        } catch is SkillReadingError {
            throw SkillReadingError.invalidFrontmatter
        } catch {
            throw SkillReadingError.invalidFrontmatter
        }

        guard let name = (values["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else {
            throw SkillReadingError.missingName
        }
        guard let description = (values["description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty
        else {
            throw SkillReadingError.missingDescription
        }
        func optionalValue(_ key: String) -> String? {
            guard let value = values[key] else { return nil }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            guard let serialized = try? Yams.dump(object: value) else { return nil }
            let trimmed = serialized.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return SkillManifestMetadata(
            name: name,
            description: description,
            declarations: SkillManifestDeclarations(
                license: optionalValue("license"),
                compatibility: optionalValue("compatibility"),
                metadata: optionalValue("metadata"),
                allowedTools: optionalValue("allowed-tools")
            )
        )
    }
}
