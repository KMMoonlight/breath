import BreathCore
import CryptoKit
import Foundation

struct SkillFileContents {
    let relativePath: String
    let data: Data
    let kind: SkillFileKind
}

enum SkillContentReader {
    static func collectFiles(
        in root: URL,
        fileManager: FileManager
    ) throws -> [SkillFileContents] {
        let canonicalRoot = URL(
            fileURLWithPath: (root.path as NSString).resolvingSymlinksInPath,
            isDirectory: true
        )
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw SkillReadingError.unreadableDirectory
        }
        var result: [SkillFileContents] = []
        while let item = enumerator.nextObject() as? URL {
            let relativePath = relativePath(from: canonicalRoot, to: item)
            if ignoredPathComponents.contains(where: {
                relativePath.split(separator: "/").contains(Substring($0))
            }) {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let values = try item.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true {
                let destination = try fileManager.destinationOfSymbolicLink(atPath: item.path)
                result.append(SkillFileContents(
                    relativePath: relativePath,
                    data: Data(destination.utf8),
                    kind: .symbolicLink
                ))
            } else if values.isRegularFile == true {
                result.append(SkillFileContents(
                    relativePath: relativePath,
                    data: try Data(contentsOf: item, options: [.mappedIfSafe]),
                    kind: .file
                ))
            }
        }
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    static func digest(_ files: [SkillFileContents]) -> String {
        var hasher = SHA256()
        for file in files {
            hasher.update(data: Data(file.relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(file.kind.rawValue.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: file.data)
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func digestDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws -> String {
        let isLink = (try? directory.resourceValues(
            forKeys: [.isSymbolicLinkKey]
        ).isSymbolicLink) == true
        let root = isLink ? directory.resolvingSymlinksInPath() : directory
        return digest(try collectFiles(in: root, fileManager: fileManager))
    }

    static func relativePath(from root: URL, to item: URL) -> String {
        let rootComponents = root.pathComponents.filter { $0 != "/" }
        let itemComponents = item.pathComponents.filter { $0 != "/" }
        if itemComponents.count >= rootComponents.count {
            for start in 0...(itemComponents.count - rootComponents.count) {
                let end = start + rootComponents.count
                if Array(itemComponents[start..<end]) == rootComponents {
                    return itemComponents[end...].joined(separator: "/")
                }
            }
        }
        return item.lastPathComponent
    }

    private static let ignoredPathComponents: Set<String> = [
        ".DS_Store", ".git", ".svn",
    ]
}

actor SkillWriteCoordinator {
    private var lockedAgents: Set<AgentKind> = []
    private var waiters: [AgentKind: [CheckedContinuation<Void, Never>]] = [:]

    func withLock<T: Sendable>(
        for agent: AgentKind,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await withLocks(for: [agent], operation: operation)
    }

    func withLocks<T: Sendable>(
        for agents: [AgentKind],
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let orderedAgents = Array(Set(agents)).sorted { $0.rawValue < $1.rawValue }
        return try await withLocks(
            for: orderedAgents[...],
            operation: operation
        )
    }

    private func withLocks<T: Sendable>(
        for agents: ArraySlice<AgentKind>,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        guard let agent = agents.first else {
            return try await operation()
        }
        await acquire(agent)
        do {
            let result = try await withLocks(
                for: agents.dropFirst(),
                operation: operation
            )
            release(agent)
            return result
        } catch {
            release(agent)
            throw error
        }
    }

    private func acquire(_ agent: AgentKind) async {
        guard lockedAgents.contains(agent) else {
            lockedAgents.insert(agent)
            return
        }
        await withCheckedContinuation { continuation in
            waiters[agent, default: []].append(continuation)
        }
    }

    private func release(_ agent: AgentKind) {
        if var queued = waiters[agent], !queued.isEmpty {
            let next = queued.removeFirst()
            waiters[agent] = queued.isEmpty ? nil : queued
            next.resume()
        } else {
            lockedAgents.remove(agent)
        }
    }
}

struct SkillInstallationCommitter: @unchecked Sendable {
    let fileManager: FileManager
    let recordRepository: (any SkillInstallationRecordRepository)?
    let now: @Sendable () -> Date

    func commit(_ item: SkillInstallationPreviewItem) async throws {
        let destination = item.existingDirectory ?? item.targetDirectory
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if let expected = item.expectedExistingDigest {
            guard fileManager.fileExists(atPath: destination.path),
                  try SkillContentReader.digestDirectory(
                      destination,
                      fileManager: fileManager
                  ) == expected
            else {
                throw SkillInstallationError.stalePreview
            }
        } else if fileManager.fileExists(atPath: destination.path) {
            throw SkillInstallationError.stalePreview
        }
        guard try sameNameSkillPaths(
            in: parent,
            skillName: item.candidate.name
        ) == item.expectedSameNamePaths else {
            throw SkillInstallationError.stalePreview
        }

        let existingRecord: SkillInstallationRecord?
        if let recordRepository {
            do {
                existingRecord = try await recordRepository.loadSkillInstallationRecords()
                    .first {
                        $0.installationDirectory.standardizedFileURL
                            == destination.standardizedFileURL
                    }
            } catch {
                throw SkillInstallationError.recordPersistenceFailed
            }
        } else {
            existingRecord = nil
        }

        let token = UUID().uuidString
        let stage = parent.appendingPathComponent(".breath-stage-\(token)", isDirectory: true)
        let backup = parent.appendingPathComponent(".breath-backup-\(token)", isDirectory: true)
        var movedExisting = false
        do {
            try fileManager.copyItem(at: item.candidate.directory, to: stage)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: stage,
                    backupItemName: backup.lastPathComponent,
                    options: []
                )
                movedExisting = true
            } else {
                try fileManager.moveItem(at: stage, to: destination)
            }

            if let recordRepository {
                let timestamp = now()
                let installedAt = item.existingDirectory == nil
                    ? timestamp
                    : existingRecord?.installedAt ?? timestamp
                do {
                    if let installationOrigin = item.candidate.installationOrigin {
                        try await recordRepository.saveSkillInstallationRecord(
                            SkillInstallationRecord(
                                agent: item.targetID.agent,
                                installationDirectory: destination,
                                skillName: item.candidate.name,
                                origin: installationOrigin,
                                installedContentDigest: item.candidate
                                    .installationRecordContentDigest
                                    ?? item.candidate.contentDigest,
                                installedAt: installedAt,
                                updatedAt: timestamp
                            )
                        )
                    } else if let provenance = item.candidate.remoteProvenance {
                        try await recordRepository.saveSkillInstallationRecord(
                            SkillInstallationRecord(
                                agent: item.targetID.agent,
                                installationDirectory: destination,
                                skillName: item.candidate.name,
                                origin: .remote(provenance),
                                installedContentDigest: item.candidate.contentDigest,
                                installedAt: installedAt,
                                updatedAt: timestamp
                            )
                        )
                    } else if item.candidate.source == .zip {
                        try await recordRepository.saveSkillInstallationRecord(
                            SkillInstallationRecord(
                                agent: item.targetID.agent,
                                installationDirectory: destination,
                                skillName: item.candidate.name,
                                origin: .zip,
                                installedContentDigest: item.candidate.contentDigest,
                                installedAt: installedAt,
                                updatedAt: timestamp
                            )
                        )
                    } else {
                        try await recordRepository.removeSkillInstallationRecord(
                            installationDirectory: destination
                        )
                    }
                } catch {
                    if movedExisting,
                       fileManager.fileExists(atPath: backup.path)
                    {
                        _ = try? fileManager.replaceItemAt(
                            destination,
                            withItemAt: backup,
                            backupItemName: nil,
                            options: []
                        )
                    } else {
                        try? fileManager.removeItem(at: destination)
                    }
                    throw SkillInstallationError.recordPersistenceFailed
                }
            }
            if movedExisting { try? fileManager.removeItem(at: backup) }
        } catch {
            try? fileManager.removeItem(at: stage)
            if movedExisting,
               fileManager.fileExists(atPath: backup.path)
            {
                if fileManager.fileExists(atPath: destination.path) {
                    _ = try? fileManager.replaceItemAt(
                        destination,
                        withItemAt: backup,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try? fileManager.moveItem(at: backup, to: destination)
                }
            }
            throw error
        }
    }

    private func sameNameSkillPaths(
        in root: URL,
        skillName: String
    ) throws -> Set<String> {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var matches: Set<String> = []
        for child in children {
            let resolved = child.resolvingSymlinksInPath()
            guard let manifest = try? String(
                contentsOf: resolved.appendingPathComponent("SKILL.md"),
                encoding: .utf8
            ), let metadata = try? SkillManifestParser.parse(manifest),
                  metadata.name == skillName
            else { continue }
            matches.insert(child.standardizedFileURL.path)
        }
        return matches
    }
}

struct SkillUninstallCommitter: @unchecked Sendable {
    let fileManager: FileManager
    let recordRepository: (any SkillInstallationRecordRepository)?
    let trash: any SkillTrashing

    func commit(_ item: SkillUninstallPreviewItem) async throws {
        guard fileManager.fileExists(atPath: item.directory.path),
              try SkillContentReader.digestDirectory(
                  item.directory,
                  fileManager: fileManager
              ) == item.expectedDigest
        else {
            throw SkillInstallationError.stalePreview
        }
        let isLink = (try item.directory.resourceValues(
            forKeys: [.isSymbolicLinkKey]
        ).isSymbolicLink) == true
        guard (item.action == .removeSymbolicLink) == isLink else {
            throw SkillInstallationError.stalePreview
        }
        switch item.action {
        case .removeSymbolicLink:
            let dependentLinks = try validatedLinks(
                at: item.linkedDirectoriesToRemove,
                resolvingTo: item.resolvedDirectory
            )
            let primaryLink = try validatedLinks(
                at: [item.directory],
                resolvingTo: item.resolvedDirectory
            )
            try await removeLinksWithRollback(
                dependentLinks + primaryLink,
                operation: {}
            )
        case .moveToTrash:
            try await moveSharedTargetToTrash(item)
        }
        do {
            try removeSharedRegistryEntry(for: item)
        } catch {
            throw SkillInstallationError.sharedRegistryPersistenceFailed
        }
        do {
            for directory in [item.directory] + item.linkedDirectoriesToRemove {
                try await recordRepository?.removeSkillInstallationRecord(
                    installationDirectory: directory
                )
            }
        } catch {
            throw SkillInstallationError.recordPersistenceFailed
        }
    }

    private func moveSharedTargetToTrash(
        _ item: SkillUninstallPreviewItem
    ) async throws {
        let links = try validatedLinks(
            at: item.linkedDirectoriesToRemove,
            resolvingTo: item.resolvedDirectory
        )
        try await removeLinksWithRollback(links) {
            try await trash.moveToTrash(item.directory)
        }
    }

    private struct ValidatedSymbolicLink {
        let url: URL
        let destination: String
    }

    private func validatedLinks(
        at directories: [URL],
        resolvingTo target: URL
    ) throws -> [ValidatedSymbolicLink] {
        try directories.map { linkedDirectory in
            let linkedValues = try linkedDirectory.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            )
            guard linkedValues.isSymbolicLink == true,
                  linkedDirectory.resolvingSymlinksInPath().standardizedFileURL
                    == target.standardizedFileURL
            else {
                throw SkillInstallationError.stalePreview
            }
            return ValidatedSymbolicLink(
                url: linkedDirectory,
                destination: try fileManager.destinationOfSymbolicLink(
                    atPath: linkedDirectory.path
                )
            )
        }
    }

    private func removeLinksWithRollback(
        _ links: [ValidatedSymbolicLink],
        operation: () async throws -> Void
    ) async throws {
        var removedLinks: [ValidatedSymbolicLink] = []
        do {
            for link in links {
                try fileManager.removeItem(at: link.url)
                removedLinks.append(link)
            }
            try await operation()
        } catch {
            for link in removedLinks.reversed() {
                try? fileManager.createSymbolicLink(
                    atPath: link.url.path,
                    withDestinationPath: link.destination
                )
            }
            throw error
        }
    }

    private func removeSharedRegistryEntry(
        for item: SkillUninstallPreviewItem
    ) throws {
        guard item.scope == .sharedLibrary,
              let skillIdentifier = item.sharedRegistrySkillIdentifier
        else {
            return
        }
        let skillsRoot = item.directory.deletingLastPathComponent()
        let sharedContainer = skillsRoot.deletingLastPathComponent()
        guard skillsRoot.lastPathComponent == "skills",
              sharedContainer.lastPathComponent == ".agents"
        else {
            throw SkillInstallationError.stalePreview
        }
        let lockURL = sharedContainer.appendingPathComponent(".skill-lock.json")
        guard fileManager.fileExists(atPath: lockURL.path) else { return }
        let data = try Data(contentsOf: lockURL)
        guard var lock = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var skills = lock["skills"] as? [String: Any]
        else {
            throw SkillInstallationError.sharedRegistryPersistenceFailed
        }
        guard skills.removeValue(forKey: skillIdentifier) != nil else { return }
        lock["skills"] = skills
        let updated = try JSONSerialization.data(
            withJSONObject: lock,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try updated.write(to: lockURL, options: .atomic)
    }
}

enum SkillInstallationError: Error {
    case stalePreview
    case recordPersistenceFailed
    case sharedRegistryPersistenceFailed
}
