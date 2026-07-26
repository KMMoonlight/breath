import Foundation

enum GitReferenceKind: String, Equatable, Codable, Sendable {
    case localBranch
    case remoteBranch
    case tag
}

struct GitRemoteBranchIdentity: Equatable, Sendable {
    let fullName: String
    let remoteName: String
    let branchName: String

    var checkoutLocalBranchName: String {
        let leafName = branchName.split(separator: "/").last
            .map(String.init) ?? branchName
        let localRemoteName = remoteName.replacingOccurrences(
            of: "/",
            with: "-"
        )
        return leafName == "HEAD" ? "\(localRemoteName)-HEAD" : leafName
    }
}

struct GitReference: Equatable, Identifiable, Sendable {
    var id: String { fullName }

    func remoteBranchIdentity(
        configuredRemoteNames: [String]
    ) -> GitRemoteBranchIdentity? {
        let prefix = "refs/remotes/"
        guard kind == .remoteBranch, fullName.hasPrefix(prefix) else {
            return nil
        }
        let scopedName = String(fullName.dropFirst(prefix.count))
        guard let remoteName = configuredRemoteNames
            .filter({ !$0.isEmpty && scopedName.hasPrefix("\($0)/") })
            .max(by: { $0.count < $1.count })
        else {
            return nil
        }
        let branchName = String(scopedName.dropFirst(remoteName.count + 1))
        guard !branchName.isEmpty else { return nil }
        return GitRemoteBranchIdentity(
            fullName: fullName,
            remoteName: remoteName,
            branchName: branchName
        )
    }

    let fullName: String
    let shortName: String
    let kind: GitReferenceKind
    let objectID: String
    let upstream: String?
    let upstreamTrack: String?
    let isCurrent: Bool
    let subject: String
}

struct GitRemote: Equatable, Identifiable, Sendable {
    var id: String { name }

    let name: String
    let fetchURL: String?
    let pushURL: String?
}

struct GitCommitSummary: Equatable, Identifiable, Sendable {
    var id: String { "\(rootID.rawValue)\u{0}\(objectID)" }

    let objectID: String
    let parentIDs: [String]
    let authorName: String
    let authorEmail: String
    let authoredAt: Date?
    let decorations: [String]
    let subject: String
    let body: String
    let rootID: GitRootID
}

struct GitCommitPage: Equatable, Sendable {
    let commits: [GitCommitSummary]
    let hasMore: Bool
}

struct GitCommitFile: Equatable, Identifiable, Sendable {
    var id: String { "\(status.rawValue):\(path):\(originalPath ?? "")" }

    let status: GitChangeState
    let path: String
    let originalPath: String?
}

struct GitCommitDetails: Equatable, Sendable {
    let commit: GitCommitSummary
    let files: [GitCommitFile]
}

enum GitDiffSource: Equatable, Sendable {
    case workingTree
    case staged
    case commit(String)
    case between(String, String)
    case stash(String)
}

struct GitFileDiff: Equatable, Sendable {
    let rootID: GitRootID
    let path: String?
    let source: GitDiffSource
    let patch: String
    let isBinary: Bool
    let isTooLarge: Bool
    let byteCount: Int

    init(
        rootID: GitRootID,
        path: String?,
        source: GitDiffSource,
        patch: String,
        isBinary: Bool,
        isTooLarge: Bool = false,
        byteCount: Int
    ) {
        self.rootID = rootID
        self.path = path
        self.source = source
        self.patch = patch
        self.isBinary = isBinary
        self.isTooLarge = isTooLarge
        self.byteCount = byteCount
    }
}

struct GitBlameLine: Equatable, Identifiable, Sendable {
    var id: Int { lineNumber }

    let lineNumber: Int
    let objectID: String
    let author: String
    let authoredAt: Date?
    let summary: String
    let text: String
}

enum GitSequencedOperationKind: String, Equatable, Codable, Sendable {
    case merge
    case rebase
    case cherryPick
    case revert
}

struct GitSequencedOperation: Equatable, Sendable {
    let kind: GitSequencedOperationKind
    let conflictedPaths: [String]
    let canContinue: Bool
    let canSkip: Bool
    let canAbort: Bool
}

struct GitStashEntry: Equatable, Identifiable, Sendable {
    var id: String { reference }

    let reference: String
    let objectID: String
    let createdAt: Date?
    let subject: String
}

struct GitSubmoduleState: Equatable, Identifiable, Sendable {
    var id: String { path }

    let path: String
    let objectID: String
    let description: String
    let isInitialized: Bool
    let hasRecordedChanges: Bool
}

struct GitLFSCapability: Equatable, Sendable {
    let isInstalled: Bool
    let version: String?
}

struct GitLFSLock: Equatable, Identifiable, Sendable {
    let id: String
    let path: String
    let owner: String
    let lockedAt: Date?
}

struct GitLFSFileInfo: Equatable, Sendable {
    let path: String
    let isManaged: Bool
    let isPointer: Bool
    let objectID: String?
    let declaredSize: Int?
}

struct GitConflictFile: Equatable, Sendable {
    let path: String
    let base: String
    let ours: String
    let theirs: String
    let result: String
}

extension GitWorkbenchService {
    func commitTemplate(rootURL: URL) async throws -> String? {
        let result = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "config",
                "--path",
                "--get",
                "commit.template",
            ]
        )
        guard result.exitCode == 0 else {
            if result.exitCode == 1 { return nil }
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        let configuredPath = result.standardOutput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !configuredPath.isEmpty else { return nil }
        let resolvedURL = (configuredPath as NSString).isAbsolutePath
            ? URL(fileURLWithPath: configuredPath)
            : rootURL.appendingPathComponent(configuredPath)
        return try String(contentsOf: resolvedURL, encoding: .utf8)
    }

    func recentCommitMessages(
        rootURL: URL,
        limit: Int = 20
    ) async throws -> [String] {
        let result = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "log",
                "-\(max(1, limit))",
                "--format=%B%x00",
            ]
        )
        guard result.exitCode == 0 else {
            if try await repositoryHasAnyCommit(rootURL: rootURL) == false {
                return []
            }
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        var seen: Set<String> = []
        return result.standardOutput
            .split(separator: "\0")
            .map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { message in
                !message.isEmpty && seen.insert(message).inserted
            }
    }

    func references(rootURL: URL) async throws -> [GitReference] {
        let result = try await requiredGit(
            rootURL: rootURL,
            arguments: [
                "for-each-ref",
                "--sort=refname",
                "--format=%(refname)%00%(refname:short)%00%(objectname)%00%(upstream:short)%00%(upstream:track)%00%(HEAD)%00%(subject)%00%(symref)",
                "refs/heads",
                "refs/remotes",
                "refs/tags",
            ]
        )
        return result.standardOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let fields = line.split(
                    separator: "\0",
                    omittingEmptySubsequences: false
                ).map(String.init)
                guard fields.count >= 8 else { return nil }
                let kind: GitReferenceKind
                if fields[0].hasPrefix("refs/heads/") {
                    kind = .localBranch
                } else if fields[0].hasPrefix("refs/remotes/") {
                    kind = .remoteBranch
                } else {
                    kind = .tag
                }
                guard kind != .remoteBranch || fields[7].isEmpty else {
                    return nil
                }
                return GitReference(
                    fullName: fields[0],
                    shortName: fields[1],
                    kind: kind,
                    objectID: fields[2],
                    upstream: fields[3].nilIfEmpty,
                    upstreamTrack: fields[4].nilIfEmpty,
                    isCurrent: fields[5].trimmingCharacters(in: .whitespaces) == "*",
                    subject: fields[6]
                )
            }
    }

    func remotes(rootURL: URL) async throws -> [GitRemote] {
        let result = try await requiredGit(
            rootURL: rootURL,
            arguments: ["remote", "-v"]
        )
        var values: [String: (fetch: String?, push: String?)] = [:]
        for line in result.standardOutput.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 3 else { continue }
            let name = String(fields[0])
            let url = String(fields[1])
            var pair = values[name] ?? (nil, nil)
            if fields[2].contains("fetch") {
                pair.fetch = url
            } else if fields[2].contains("push") {
                pair.push = url
            }
            values[name] = pair
        }
        return values.keys.sorted().map { name in
            GitRemote(
                name: name,
                fetchURL: values[name]?.fetch,
                pushURL: values[name]?.push
            )
        }
    }

    func log(
        rootURL: URL,
        skip: Int = 0,
        limit: Int = 200,
        revision: String = "--all",
        path: String? = nil,
        query: String? = nil
    ) async throws -> GitCommitPage {
        let filter = GitLogQuery(query)
        let resolvedRevision = filter.revision ?? revision
        var arguments = [
            "log",
            "--topo-order",
            "--date=iso-strict",
            "--skip=\(max(0, skip))",
            "--max-count=\(max(1, limit + 1))",
            "--format=%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%D%x1f%s%x1f%b",
            resolvedRevision,
        ]
        if let author = filter.author {
            arguments.insert("--author=\(author)", at: arguments.count - 1)
        }
        if let since = filter.since {
            arguments.insert("--since=\(since)", at: arguments.count - 1)
        }
        if let until = filter.until {
            arguments.insert("--until=\(until)", at: arguments.count - 1)
        }
        if let text = filter.text.nilIfEmpty {
            arguments.insert("--regexp-ignore-case", at: arguments.count - 1)
            arguments.insert("--grep=\(text)", at: arguments.count - 1)
        }
        if let resolvedPath = path ?? filter.path {
            arguments += ["--", resolvedPath]
        }
        let result = try await runner.run(
            arguments: ["-C", rootURL.path] + arguments
        )
        guard result.exitCode == 0 else {
            if try await repositoryHasAnyCommit(rootURL: rootURL) == false {
                return GitCommitPage(commits: [], hasMore: false)
            }
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        var commits = GitLogParser(rootID: GitRootID(rawValue: rootURL.path))
            .parse(result.standardOutput)
        let hasMore = commits.count > limit
        if hasMore {
            commits.removeLast(commits.count - limit)
        }
        return GitCommitPage(commits: commits, hasMore: hasMore)
    }

    private func repositoryHasAnyCommit(rootURL: URL) async throws -> Bool {
        let result = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "rev-list",
                "--all",
                "--max-count=1",
            ]
        )
        guard result.exitCode == 0 else {
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        return !result.standardOutput.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    func commitDetails(rootURL: URL, objectID: String) async throws -> GitCommitDetails {
        let page = try await log(
            rootURL: rootURL,
            limit: 1,
            revision: objectID
        )
        guard let commit = page.commits.first else {
            throw GitCommandError.invalidOutput("Commit \(objectID) was not found.")
        }
        let filesResult = try await requiredGit(
            rootURL: rootURL,
            arguments: [
                "diff-tree",
                "--root",
                "--no-commit-id",
                "--name-status",
                "-r",
                "-M",
                "-z",
                objectID,
            ]
        )
        let files = GitCommitFileParser.parse(filesResult.standardOutput)
        return GitCommitDetails(commit: commit, files: files)
    }

    func diff(
        rootURL: URL,
        source: GitDiffSource,
        path: String? = nil,
        ignoreWhitespace: Bool = false,
        foldUnchanged: Bool = true
    ) async throws -> GitFileDiff {
        let maximumTextDiffBytes = 2 * 1_024 * 1_024
        if let path {
            let byteCount = await diffFileByteCount(
                rootURL: rootURL,
                source: source,
                path: path
            )
            let isBinary = await diffFileIsBinary(
                rootURL: rootURL,
                source: source,
                path: path
            )
            if isBinary || (byteCount ?? 0) > maximumTextDiffBytes {
                return GitFileDiff(
                    rootID: GitRootID(rawValue: rootURL.path),
                    path: path,
                    source: source,
                    patch: "",
                    isBinary: isBinary,
                    isTooLarge: !isBinary,
                    byteCount: byteCount ?? 0
                )
            }
        }
        var arguments: [String]
        switch source {
        case .workingTree:
            if let path,
               try await isUntracked(rootURL: rootURL, path: path)
            {
                arguments = [
                    "diff",
                    "--no-index",
                    "--no-ext-diff",
                    "--binary",
                ]
                if ignoreWhitespace {
                    arguments.append("--ignore-all-space")
                }
                if !foldUnchanged {
                    arguments.append("--unified=1000000")
                }
                arguments += ["--", "/dev/null", path]
                let result = try await runner.run(
                    arguments: ["-C", rootURL.path] + arguments
                )
                guard result.exitCode == 0 || result.exitCode == 1 else {
                    throw GitCommandError.failed(
                        command: result.displayCommand,
                        exitCode: result.exitCode,
                        output: result.combinedOutput
                    )
                }
                return GitFileDiff(
                    rootID: GitRootID(rawValue: rootURL.path),
                    path: path,
                    source: source,
                    patch: result.standardOutput,
                    isBinary: result.standardOutput.contains("GIT binary patch")
                        || result.standardOutput.contains("Binary files "),
                    byteCount: result.standardOutputData.count
                )
            }
            arguments = ["diff", "--no-ext-diff", "--binary"]
        case .staged:
            arguments = ["diff", "--cached", "--no-ext-diff", "--binary"]
        case .commit(let objectID):
            arguments = [
                "show",
                "--format=",
                "--no-ext-diff",
                "--binary",
                objectID,
            ]
        case .between(let left, let right):
            arguments = [
                "diff",
                "--no-ext-diff",
                "--binary",
                left,
                right,
            ]
        case .stash(let reference):
            arguments = [
                "stash",
                "show",
                "--patch",
                "--include-untracked",
                reference,
            ]
        }
        if ignoreWhitespace {
            arguments.insert("--ignore-all-space", at: 1)
        }
        if !foldUnchanged {
            arguments.insert("--unified=1000000", at: 1)
        }
        if let path {
            arguments += ["--", path]
        }
        let result = try await requiredGit(rootURL: rootURL, arguments: arguments)
        let patch = result.standardOutput
        return GitFileDiff(
            rootID: GitRootID(rawValue: rootURL.path),
            path: path,
            source: source,
            patch: patch,
            isBinary: patch.contains("GIT binary patch")
                || patch.contains("Binary files "),
            byteCount: result.standardOutputData.count
        )
    }

    private func isUntracked(rootURL: URL, path: String) async throws -> Bool {
        let result = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "ls-files",
                "--error-unmatch",
                "--",
                path,
            ]
        )
        return result.exitCode != 0
    }

    private func diffFileByteCount(
        rootURL: URL,
        source: GitDiffSource,
        path: String
    ) async -> Int? {
        if source == .workingTree {
            let fileURL = rootURL.appendingPathComponent(path)
            if let attributes = try? FileManager.default.attributesOfItem(
                atPath: fileURL.path
            ), let size = attributes[.size] as? NSNumber {
                return size.intValue
            }
        }
        let revision = switch source {
        case .workingTree: "HEAD:\(path)"
        case .staged: ":\(path)"
        case .commit(let objectID): "\(objectID):\(path)"
        case .between(_, let right): "\(right):\(path)"
        case .stash(let reference): "\(reference):\(path)"
        }
        let result = try? await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "cat-file",
                "-s",
                revision,
            ]
        )
        guard result?.exitCode == 0 else { return nil }
        return Int(
            result?.standardOutput.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
        )
    }

    private func diffFileIsBinary(
        rootURL: URL,
        source: GitDiffSource,
        path: String
    ) async -> Bool {
        if source == .workingTree {
            let fileURL = rootURL.appendingPathComponent(path)
            if let handle = try? FileHandle(forReadingFrom: fileURL) {
                defer { try? handle.close() }
                if let data = try? handle.read(upToCount: 8_192),
                   data.contains(0)
                {
                    return true
                }
            }
        }
        var arguments: [String]
        switch source {
        case .workingTree:
            arguments = ["diff", "--numstat"]
        case .staged:
            arguments = ["diff", "--cached", "--numstat"]
        case .commit(let objectID):
            arguments = ["show", "--format=", "--numstat", objectID]
        case .between(let left, let right):
            arguments = ["diff", "--numstat", left, right]
        case .stash(let reference):
            arguments = ["stash", "show", "--numstat", reference]
        }
        arguments += ["--", path]
        guard let result = try? await runner.run(
            arguments: ["-C", rootURL.path] + arguments
        ), result.exitCode == 0
        else {
            return false
        }
        return result.standardOutput
            .split(separator: "\n")
            .contains { $0.hasPrefix("-\t-\t") }
    }

    func fileHistory(rootURL: URL, path: String, limit: Int = 200) async throws
        -> GitCommitPage
    {
        var arguments = [
            "log",
            "--follow",
            "--topo-order",
            "--date=iso-strict",
            "--max-count=\(max(1, limit + 1))",
            "--format=%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%D%x1f%s%x1f%b",
            "--",
            path,
        ]
        let result = try await requiredGit(rootURL: rootURL, arguments: arguments)
        var commits = GitLogParser(rootID: GitRootID(rawValue: rootURL.path))
            .parse(result.standardOutput)
        let hasMore = commits.count > limit
        if hasMore {
            commits = Array(commits.prefix(limit))
        }
        arguments.removeAll()
        return GitCommitPage(commits: commits, hasMore: hasMore)
    }

    func blame(rootURL: URL, path: String) async throws -> [GitBlameLine] {
        let result = try await requiredGit(
            rootURL: rootURL,
            arguments: ["blame", "--line-porcelain", "--", path]
        )
        return GitBlameParser().parse(result.standardOutput)
    }

    func sequencedOperation(rootURL: URL) async throws -> GitSequencedOperation? {
        let gitDirectory = try await requiredGit(
            rootURL: rootURL,
            arguments: ["rev-parse", "--git-dir"]
        ).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = URL(
            fileURLWithPath: gitDirectory,
            relativeTo: rootURL
        ).standardizedFileURL
        let fileManager = FileManager.default
        let kind: GitSequencedOperationKind?
        if fileManager.fileExists(atPath: directory.appendingPathComponent("MERGE_HEAD").path) {
            kind = .merge
        } else if fileManager.fileExists(
            atPath: directory.appendingPathComponent("rebase-merge").path
        ) || fileManager.fileExists(
            atPath: directory.appendingPathComponent("rebase-apply").path
        ) {
            kind = .rebase
        } else if fileManager.fileExists(
            atPath: directory.appendingPathComponent("CHERRY_PICK_HEAD").path
        ) {
            kind = .cherryPick
        } else if fileManager.fileExists(
            atPath: directory.appendingPathComponent("REVERT_HEAD").path
        ) {
            kind = .revert
        } else {
            kind = nil
        }
        guard let kind else { return nil }
        let snapshot = try await loadRootSnapshot(rootURL)
        let conflicts = snapshot.changes
            .filter { $0.index == .conflicted || $0.workingTree == .conflicted }
            .map(\.path)
        return GitSequencedOperation(
            kind: kind,
            conflictedPaths: conflicts,
            canContinue: conflicts.isEmpty,
            canSkip: kind != .merge,
            canAbort: true
        )
    }

    func conflictFile(rootURL: URL, path: String) async throws -> GitConflictFile {
        async let base = optionalGitBlob(rootURL: rootURL, revision: ":1:\(path)")
        async let ours = optionalGitBlob(rootURL: rootURL, revision: ":2:\(path)")
        async let theirs = optionalGitBlob(rootURL: rootURL, revision: ":3:\(path)")
        let result = (try? String(
            contentsOf: rootURL.appendingPathComponent(path),
            encoding: .utf8
        )) ?? ""
        let resolvedBase = try await base
        let resolvedOurs = try await ours
        let resolvedTheirs = try await theirs
        return GitConflictFile(
            path: path,
            base: resolvedBase,
            ours: resolvedOurs,
            theirs: resolvedTheirs,
            result: result
        )
    }

    func stashes(rootURL: URL) async throws -> [GitStashEntry] {
        let result = try await requiredGit(
            rootURL: rootURL,
            arguments: [
                "stash",
                "list",
                "--date=iso-strict",
                "--format=%gd%x00%H%x00%aI%x00%gs",
            ]
        )
        return result.standardOutput.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
            guard fields.count >= 4 else { return nil }
            return GitStashEntry(
                reference: String(fields[0]),
                objectID: String(fields[1]),
                createdAt: ISO8601DateFormatter().date(from: String(fields[2])),
                subject: String(fields[3])
            )
        }
    }

    func submodules(rootURL: URL) async throws -> [GitSubmoduleState] {
        let result = try await runner.run(
            arguments: ["-C", rootURL.path, "submodule", "status", "--recursive"]
        )
        guard result.exitCode == 0 else { return [] }
        return result.standardOutput.split(separator: "\n").compactMap { line in
            guard let prefix = line.first else { return nil }
            let fields = line.dropFirst().split(separator: " ", maxSplits: 2)
            guard fields.count >= 2 else { return nil }
            return GitSubmoduleState(
                path: String(fields[1]),
                objectID: String(fields[0]),
                description: fields.count > 2 ? String(fields[2]) : "",
                isInitialized: prefix != "-",
                hasRecordedChanges: prefix == "+"
            )
        }
    }

    func lfsCapability(rootURL: URL) async throws -> GitLFSCapability {
        let result = try await runner.run(
            arguments: ["-C", rootURL.path, "lfs", "version"]
        )
        guard result.exitCode == 0 else {
            return GitLFSCapability(isInstalled: false, version: nil)
        }
        return GitLFSCapability(
            isInstalled: true,
            version: result.standardOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func lfsFileInfo(
        rootURL: URL,
        path: String
    ) async throws -> GitLFSFileInfo {
        let attribute = try await requiredGit(
            rootURL: rootURL,
            arguments: ["check-attr", "filter", "--", path]
        ).standardOutput
        let isManaged = attribute
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .hasSuffix(": lfs")
        guard isManaged else {
            return GitLFSFileInfo(
                path: path,
                isManaged: false,
                isPointer: false,
                objectID: nil,
                declaredSize: nil
            )
        }
        let data = try Data(
            contentsOf: rootURL.appendingPathComponent(path),
            options: [.mappedIfSafe]
        )
        let contents = String(decoding: data.prefix(4_096), as: UTF8.self)
        let isPointer = contents.hasPrefix(
            "version https://git-lfs.github.com/spec/v1"
        )
        let objectID = contents
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("oid sha256:") })
            .map { String($0.dropFirst("oid sha256:".count)) }
        let size = contents
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("size ") })
            .flatMap { Int($0.dropFirst("size ".count)) }
        return GitLFSFileInfo(
            path: path,
            isManaged: true,
            isPointer: isPointer,
            objectID: objectID,
            declaredSize: size
        )
    }

    func lfsLocks(rootURL: URL) async throws -> [GitLFSLock] {
        let result = try await requiredGit(
            rootURL: rootURL,
            arguments: ["lfs", "locks", "--json"]
        )
        struct Response: Decodable {
            struct Lock: Decodable {
                struct Owner: Decodable { let name: String }
                let id: String
                let path: String
                let owner: Owner?
                let lockedAt: String?

                enum CodingKeys: String, CodingKey {
                    case id, path, owner
                    case lockedAt = "locked_at"
                }
            }
            let locks: [Lock]
        }
        let response = try JSONDecoder().decode(
            Response.self,
            from: result.standardOutputData
        )
        return response.locks.map {
            GitLFSLock(
                id: $0.id,
                path: $0.path,
                owner: $0.owner?.name ?? "",
                lockedAt: $0.lockedAt.flatMap(ISO8601DateFormatter().date)
            )
        }
    }

    func requiredGit(rootURL: URL, arguments: [String]) async throws -> GitCommandResult {
        let result = try await runner.run(
            arguments: ["-C", rootURL.path] + arguments
        )
        guard result.exitCode == 0 else {
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        return result
    }

    private func optionalGitBlob(rootURL: URL, revision: String) async throws -> String {
        let result = try await runner.run(
            arguments: ["-C", rootURL.path, "show", revision]
        )
        return result.exitCode == 0 ? result.standardOutput : ""
    }
}

private struct GitLogQuery {
    var author: String?
    var since: String?
    var until: String?
    var path: String?
    var revision: String?
    var root: String?
    var text = ""

    init(_ query: String?) {
        for token in (query ?? "").split(whereSeparator: \.isWhitespace) {
            let value = String(token)
            if value.hasPrefix("author:") {
                author = String(value.dropFirst("author:".count))
            } else if value.hasPrefix("since:") {
                since = String(value.dropFirst("since:".count))
            } else if value.hasPrefix("until:") {
                until = String(value.dropFirst("until:".count))
            } else if value.hasPrefix("path:") {
                path = String(value.dropFirst("path:".count))
            } else if value.hasPrefix("branch:") {
                revision = String(value.dropFirst("branch:".count))
            } else if value.hasPrefix("tag:") {
                revision = String(value.dropFirst("tag:".count))
            } else if value.hasPrefix("hash:") {
                revision = String(value.dropFirst("hash:".count))
            } else if value.hasPrefix("root:") {
                root = String(value.dropFirst("root:".count))
            } else if value.count >= 7,
                      value.allSatisfy(\.isHexDigit)
            {
                revision = value
            } else {
                if !text.isEmpty { text += " " }
                text += value
            }
        }
    }
}

private struct GitLogParser {
    let rootID: GitRootID

    func parse(_ output: String) -> [GitCommitSummary] {
        output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.split(
                separator: "\u{1f}",
                maxSplits: 7,
                omittingEmptySubsequences: false
            ).map(String.init)
            guard fields.count >= 8 else { return nil }
            return GitCommitSummary(
                objectID: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                parentIDs: fields[1].split(separator: " ").map(String.init),
                authorName: fields[2],
                authorEmail: fields[3],
                authoredAt: ISO8601DateFormatter().date(from: fields[4]),
                decorations: fields[5]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                subject: fields[6],
                body: fields[7].trimmingCharacters(in: .whitespacesAndNewlines),
                rootID: rootID
            )
        }
    }
}

private enum GitCommitFileParser {
    static func parse(_ output: String) -> [GitCommitFile] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true)
        var files: [GitCommitFile] = []
        var index = 0
        while index < fields.count {
            guard let status = status(for: fields[index].first) else {
                index += 1
                continue
            }
            let pathCount = status == .renamed || status == .copied ? 2 : 1
            guard index + pathCount < fields.count else { break }
            if pathCount == 2 {
                files.append(
                    GitCommitFile(
                        status: status,
                        path: String(fields[index + 2]),
                        originalPath: String(fields[index + 1])
                    )
                )
            } else {
                files.append(
                    GitCommitFile(
                        status: status,
                        path: String(fields[index + 1]),
                        originalPath: nil
                    )
                )
            }
            index += pathCount + 1
        }
        return files
    }

    private static func status(for code: Character?) -> GitChangeState? {
        switch code {
        case "A": .added
        case "M": .modified
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        case "T": .typeChanged
        default: nil
        }
    }
}

private struct GitBlameParser {
    func parse(_ output: String) -> [GitBlameLine] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [GitBlameLine] = []
        var index = 0
        while index < lines.count {
            let header = lines[index].split(separator: " ")
            guard header.count >= 3,
                  header[0].count >= 7,
                  let lineNumber = Int(header[2])
            else {
                index += 1
                continue
            }
            let objectID = String(header[0])
            var author = ""
            var authoredAt: Date?
            var summary = ""
            var text = ""
            index += 1
            while index < lines.count {
                let line = String(lines[index])
                if line.hasPrefix("author ") {
                    author = String(line.dropFirst(7))
                } else if line.hasPrefix("author-time "),
                          let seconds = TimeInterval(line.dropFirst(12))
                {
                    authoredAt = Date(timeIntervalSince1970: seconds)
                } else if line.hasPrefix("summary ") {
                    summary = String(line.dropFirst(8))
                } else if line.hasPrefix("\t") {
                    text = String(line.dropFirst())
                    index += 1
                    break
                }
                index += 1
            }
            result.append(
                GitBlameLine(
                    lineNumber: lineNumber,
                    objectID: objectID,
                    author: author,
                    authoredAt: authoredAt,
                    summary: summary,
                    text: text
                )
            )
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
