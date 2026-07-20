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
        await acquire(agent)
        do {
            let result = try await operation()
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

        let token = UUID().uuidString
        let stage = parent.appendingPathComponent(".breath-stage-\(token)", isDirectory: true)
        let backup = parent.appendingPathComponent(".breath-backup-\(token)", isDirectory: true)
        var movedExisting = false
        do {
            try fileManager.copyItem(at: item.candidate.directory, to: stage)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: destination, to: backup)
                movedExisting = true
            }
            try fileManager.moveItem(at: stage, to: destination)

            if let recordRepository,
               item.candidate.remoteProvenance != nil || item.removesExistingProvenance
            {
                let timestamp = now()
                do {
                    if let provenance = item.candidate.remoteProvenance {
                        try await recordRepository.saveSkillInstallationRecord(
                            SkillInstallationRecord(
                                agent: item.targetID.agent,
                                installationDirectory: destination,
                                skillName: item.candidate.name,
                                source: provenance.source,
                                repository: provenance.repository,
                                sourceRelativePath: provenance.sourceRelativePath,
                                reference: provenance.reference,
                                resolvedCommit: provenance.resolvedCommit,
                                installedContentDigest: item.candidate.contentDigest,
                                installedAt: timestamp,
                                updatedAt: timestamp
                            )
                        )
                    } else {
                        try await recordRepository.removeSkillInstallationRecord(
                            installationDirectory: destination
                        )
                    }
                } catch {
                    try? fileManager.removeItem(at: destination)
                    if movedExisting {
                        try? fileManager.moveItem(at: backup, to: destination)
                    }
                    throw SkillInstallationError.recordPersistenceFailed
                }
            }
            if movedExisting { try? fileManager.removeItem(at: backup) }
        } catch {
            try? fileManager.removeItem(at: stage)
            if movedExisting, !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
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
            try fileManager.removeItem(at: item.directory)
        case .moveToTrash:
            try await trash.moveToTrash(item.directory)
        }
        try? await recordRepository?.removeSkillInstallationRecord(
            installationDirectory: item.directory
        )
    }
}

enum SkillInstallationError: Error {
    case stalePreview
    case recordPersistenceFailed
}
