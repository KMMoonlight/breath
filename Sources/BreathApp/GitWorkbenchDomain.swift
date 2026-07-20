import Foundation

struct GitExecutableInfo: Equatable, Sendable {
    static let minimumCoreVersion = GitSemanticVersion(2, 11, 0)

    let executableURL: URL
    let version: String
    let semanticVersion: GitSemanticVersion

    var supportsCoreWorkbench: Bool {
        semanticVersion >= Self.minimumCoreVersion
    }

    var supportsSwitchAndRestore: Bool {
        semanticVersion >= GitSemanticVersion(2, 23, 0)
    }

    var supportsInitialBranchOption: Bool {
        semanticVersion >= GitSemanticVersion(2, 28, 0)
    }
}

struct GitSemanticVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ value: String) {
        let numericPrefix = value.prefix {
            $0.isNumber || $0 == "."
        }
        let components = numericPrefix.split(separator: ".").compactMap {
            Int($0)
        }
        guard components.count >= 2 else { return nil }
        self.init(
            components[0],
            components[1],
            components.count > 2 ? components[2] : 0
        )
    }

    var displayValue: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: GitSemanticVersion, rhs: GitSemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch)
            < (rhs.major, rhs.minor, rhs.patch)
    }
}

enum GitExecutableError: LocalizedError, Equatable {
    case unsupportedVersion(actual: String, minimum: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let actual, let minimum):
            "Git \(actual) is too old; Git \(minimum) or newer is required."
        }
    }
}

enum GitExecutableInspector {
    static func inspect(_ executableURL: URL) async throws -> GitExecutableInfo {
        let result = try await GitCommandRunner(executableURL: executableURL).run(
            arguments: ["--version"]
        )
        guard result.exitCode == 0 else {
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        let output = result.standardOutput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let prefix = "git version "
        guard output.lowercased().hasPrefix(prefix) else {
            throw GitCommandError.invalidOutput(
                "The selected executable did not identify itself as Git."
            )
        }
        let version = String(output.dropFirst(prefix.count))
        guard let semanticVersion = GitSemanticVersion(version) else {
            throw GitCommandError.invalidOutput(
                "Git reported an unrecognized version: \(version)"
            )
        }
        return GitExecutableInfo(
            executableURL: executableURL.standardizedFileURL,
            version: version,
            semanticVersion: semanticVersion
        )
    }
}

actor GitExecutableInspectionCache {
    static let shared = GitExecutableInspectionCache()

    private var values: [String: GitExecutableInfo] = [:]

    func inspect(_ executableURL: URL) async throws -> GitExecutableInfo {
        let key = executableURL.standardizedFileURL.path
        if let value = values[key] {
            return value
        }
        let value = try await GitExecutableInspector.inspect(executableURL)
        values[key] = value
        return value
    }
}

struct GitRootID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum GitWorkspaceEmptyState: String, Equatable, Codable, Sendable {
    case notRepository
}

struct GitWorkspaceSnapshot: Equatable, Sendable {
    let workspaceURL: URL
    let roots: [GitRootSnapshot]
    let externalRootCandidates: [URL]
    let emptyState: GitWorkspaceEmptyState?

    init(
        workspaceURL: URL,
        roots: [GitRootSnapshot],
        externalRootCandidates: [URL] = []
    ) {
        self.workspaceURL = workspaceURL
        self.roots = roots
        self.externalRootCandidates = externalRootCandidates
        emptyState = roots.isEmpty ? .notRepository : nil
    }
}

struct GitRootSnapshot: Equatable, Identifiable, Sendable {
    let id: GitRootID
    let rootURL: URL
    let branch: GitBranchSummary
    let changes: [GitLocalChange]
    let isOutsideWorkspace: Bool
    let isSubmoduleRoot: Bool

    init(
        id: GitRootID,
        rootURL: URL,
        branch: GitBranchSummary,
        changes: [GitLocalChange],
        isOutsideWorkspace: Bool = false,
        isSubmoduleRoot: Bool = false
    ) {
        self.id = id
        self.rootURL = rootURL
        self.branch = branch
        self.changes = changes
        self.isOutsideWorkspace = isOutsideWorkspace
        self.isSubmoduleRoot = isSubmoduleRoot
    }
}

struct GitBranchSummary: Equatable, Sendable {
    let name: String
    let upstream: String?
    let aheadCount: Int
    let behindCount: Int
    let headOID: String?
}

enum GitChangeState: String, Equatable, Codable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case untracked
    case conflicted
    case typeChanged
}

struct GitLocalChange: Equatable, Identifiable, Sendable {
    var id: String {
        "\(rootID?.rawValue ?? "")\u{0}\(path)\u{0}\(originalPath ?? "")"
    }

    let rootID: GitRootID?
    let path: String
    let originalPath: String?
    let index: GitChangeState?
    let workingTree: GitChangeState?
    let isSubmodule: Bool

    init(
        rootID: GitRootID? = nil,
        path: String,
        originalPath: String?,
        index: GitChangeState?,
        workingTree: GitChangeState?,
        isSubmodule: Bool
    ) {
        self.rootID = rootID
        self.path = path
        self.originalPath = originalPath
        self.index = index
        self.workingTree = workingTree
        self.isSubmodule = isSubmodule
    }

    func rooted(at rootID: GitRootID) -> GitLocalChange {
        GitLocalChange(
            rootID: rootID,
            path: path,
            originalPath: originalPath,
            index: index,
            workingTree: workingTree,
            isSubmodule: isSubmodule
        )
    }
}

final class GitWorkbenchService: @unchecked Sendable {
    let workspaceURL: URL
    let gitExecutableURL: URL

    let runner: GitCommandRunner
    let metadataStore: GitWorkspaceMetadataStore

    init(
        workspaceURL: URL,
        gitExecutableURL: URL,
        metadataStore: GitWorkspaceMetadataStore = GitWorkspaceMetadataStore()
    ) {
        self.workspaceURL = workspaceURL.standardizedFileURL
        self.gitExecutableURL = gitExecutableURL.standardizedFileURL
        self.metadataStore = metadataStore
        runner = GitCommandRunner(executableURL: gitExecutableURL)
    }

    func loadWorkspace() async throws -> GitWorkspaceSnapshot {
        let executableInfo = try await GitExecutableInspectionCache.shared
            .inspect(gitExecutableURL)
        guard executableInfo.supportsCoreWorkbench else {
            throw GitExecutableError.unsupportedVersion(
                actual: executableInfo.version,
                minimum: GitExecutableInfo.minimumCoreVersion.displayValue
            )
        }
        let metadata = await metadataStore.load(workspaceURL: workspaceURL)
        let discovery = try await discoverRoots(
            authorizedExternalRootPaths: metadata.authorizedExternalRootPaths
        )
        var roots: [GitRootSnapshot] = []
        for rootURL in discovery.authorizedRoots {
            roots.append(try await loadRootSnapshot(rootURL))
        }
        roots.sort {
            $0.rootURL.path.localizedStandardCompare($1.rootURL.path) == .orderedAscending
        }
        return GitWorkspaceSnapshot(
            workspaceURL: workspaceURL,
            roots: roots,
            externalRootCandidates: discovery.externalCandidates
        )
    }

    func authorizeExternalRoot(_ rootURL: URL) async throws {
        var metadata = await metadataStore.load(workspaceURL: workspaceURL)
        metadata.authorizedExternalRootPaths.insert(rootURL.standardizedFileURL.path)
        try await metadataStore.save(metadata, workspaceURL: workspaceURL)
    }

    func revokeExternalRootAuthorization(_ rootURL: URL) async throws {
        var metadata = await metadataStore.load(workspaceURL: workspaceURL)
        metadata.authorizedExternalRootPaths.remove(rootURL.standardizedFileURL.path)
        try await metadataStore.save(metadata, workspaceURL: workspaceURL)
    }

    func loadRootSnapshot(_ rootURL: URL) async throws -> GitRootSnapshot {
        let statusResult = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "status",
                "--porcelain=v2",
                "--branch",
                "-z",
                "--untracked-files=all",
            ]
        )
        guard statusResult.exitCode == 0 else {
            throw GitCommandError.failed(
                command: statusResult.displayCommand,
                exitCode: statusResult.exitCode,
                output: statusResult.combinedOutput
            )
        }
        let parsed = GitPorcelainV2WorkspaceParser().parse(statusResult.standardOutputData)
        let rootID = GitRootID(rawValue: rootURL.path)
        var gitPathIsDirectory: ObjCBool = false
        let gitPathExists = FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent(".git").path,
            isDirectory: &gitPathIsDirectory
        )
        return GitRootSnapshot(
            id: rootID,
            rootURL: rootURL,
            branch: parsed.branch,
            changes: parsed.changes.map { $0.rooted(at: rootID) },
            isOutsideWorkspace: !rootURL.isDescendant(of: workspaceURL),
            isSubmoduleRoot: gitPathExists && !gitPathIsDirectory.boolValue
        )
    }

    private func discoverRoots(
        authorizedExternalRootPaths: Set<String>
    ) async throws -> (authorizedRoots: [URL], externalCandidates: [URL]) {
        var candidates = Set(
            GitRootFileDiscovery.candidateRoots(inside: workspaceURL)
                .map { $0.standardizedFileURL }
        )
        let containingResult = try await runner.run(
            arguments: [
                "-C",
                workspaceURL.path,
                "rev-parse",
                "--show-toplevel",
            ]
        )
        if containingResult.exitCode == 0 {
            let rootPath = containingResult.standardOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !rootPath.isEmpty {
                candidates.insert(
                    URL(fileURLWithPath: rootPath, isDirectory: true)
                        .standardizedFileURL
                )
            }
        }

        var authorized: [URL] = []
        var external: [URL] = []
        for candidate in candidates {
            if candidate.isDescendant(of: workspaceURL)
                || authorizedExternalRootPaths.contains(candidate.path)
            {
                authorized.append(candidate)
            } else {
                external.append(candidate)
            }
        }
        return (
            authorized.sorted { $0.path < $1.path },
            external.sorted { $0.path < $1.path }
        )
    }
}

private enum GitRootFileDiscovery {
    static func candidateRoots(inside workspaceURL: URL) -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let directGitPath = workspaceURL.appendingPathComponent(".git").path
        var roots: [URL] = fileManager.fileExists(
            atPath: directGitPath,
            isDirectory: &isDirectory
        ) ? [workspaceURL] : []

        guard let enumerator = fileManager.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return roots
        }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" {
                roots.append(url.deletingLastPathComponent())
                enumerator.skipDescendants()
                continue
            }
            if [".build", ".swiftpm", "node_modules"].contains(name),
               (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            {
                enumerator.skipDescendants()
            }
        }
        return Array(Set(roots.map(\.standardizedFileURL)))
    }
}

private extension URL {
    func isDescendant(of ancestor: URL) -> Bool {
        let path = standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        return path == ancestorPath || path.hasPrefix(ancestorPath + "/")
    }
}

private struct GitPorcelainV2WorkspaceParser {
    func parse(_ data: Data) -> (branch: GitBranchSummary, changes: [GitLocalChange]) {
        let records = String(decoding: data, as: UTF8.self)
            .split(separator: "\0", omittingEmptySubsequences: true)
            .flatMap { record in
                record.split(separator: "\n", omittingEmptySubsequences: true)
            }
            .map(String.init)
        var branchName = "HEAD"
        var upstream: String?
        var aheadCount = 0
        var behindCount = 0
        var headOID: String?
        var changes: [GitLocalChange] = []
        var index = 0

        while index < records.count {
            let record = records[index]
            if record.hasPrefix("# branch.head ") {
                branchName = String(record.dropFirst("# branch.head ".count))
            } else if record.hasPrefix("# branch.upstream ") {
                upstream = String(record.dropFirst("# branch.upstream ".count))
            } else if record.hasPrefix("# branch.oid ") {
                let value = String(record.dropFirst("# branch.oid ".count))
                headOID = value == "(initial)" ? nil : value
            } else if record.hasPrefix("# branch.ab ") {
                let components = record.split(separator: " ")
                if components.count >= 4 {
                    aheadCount = Int(components[2].dropFirst()) ?? 0
                    behindCount = Int(components[3].dropFirst()) ?? 0
                }
            } else if record.hasPrefix("? ") {
                changes.append(
                    GitLocalChange(
                        path: String(record.dropFirst(2)),
                        originalPath: nil,
                        index: nil,
                        workingTree: .untracked,
                        isSubmodule: false
                    )
                )
            } else if record.hasPrefix("u ") {
                if let parsed = parseTracked(record, conflicted: true) {
                    changes.append(parsed)
                }
            } else if record.hasPrefix("1 ") || record.hasPrefix("2 ") {
                var originalPath: String?
                if record.hasPrefix("2 "), index + 1 < records.count {
                    originalPath = records[index + 1]
                    index += 1
                }
                if let parsed = parseTracked(
                    record,
                    originalPath: originalPath,
                    conflicted: false
                ) {
                    changes.append(parsed)
                }
            }
            index += 1
        }

        return (
            GitBranchSummary(
                name: branchName,
                upstream: upstream,
                aheadCount: aheadCount,
                behindCount: behindCount,
                headOID: headOID
            ),
            changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        )
    }

    private func parseTracked(
        _ record: String,
        originalPath: String? = nil,
        conflicted: Bool
    ) -> GitLocalChange? {
        let fields = record.split(
            separator: " ",
            maxSplits: conflicted ? 10 : 8,
            omittingEmptySubsequences: true
        )
        guard fields.count >= (conflicted ? 11 : 9) else { return nil }
        let xy = fields[1]
        guard xy.count == 2 else { return nil }
        let path = String(fields[conflicted ? 10 : 8])
        let submodule = fields[2]
        return GitLocalChange(
            path: path,
            originalPath: originalPath,
            index: conflicted ? .conflicted : state(for: xy.first),
            workingTree: conflicted ? .conflicted : state(for: xy.last),
            isSubmodule: submodule.first == "S"
        )
    }

    private func state(for character: Character?) -> GitChangeState? {
        switch character {
        case "A": .added
        case "M": .modified
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        case "T": .typeChanged
        case "U": .conflicted
        default: nil
        }
    }
}
