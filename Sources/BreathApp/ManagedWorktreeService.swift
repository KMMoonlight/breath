import BreathCore
import Foundation

private actor ManagedWorktreeOperationGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

enum ManagedWorktreeServiceError: LocalizedError, Equatable {
    case invalidBranchName(String)
    case invalidStartBranch(String)
    case sessionBranchAlreadyExists(String)
    case unsupportedRepository(String)
    case managedPathAlreadyExists(String)
    case unsafeManagedPath(String)
    case unsafeSessionWorkingDirectory(String)
    case repositoryIdentityMismatch(expected: String, actual: String)
    case checkoutCommitMismatch(expected: String, actual: String)
    case gitFailed(exitCode: Int32, output: String)
    case incompleteCheckout(String)
    case worktreeContainsChanges
    case worktreeContainsUnprotectedCommits
    case worktreeLocked(String?)
    case creationRollbackFailed(
        path: String,
        creationError: String,
        cleanupError: String
    )

    var errorDescription: String? {
        switch self {
        case .invalidBranchName(let branchName):
            return "“\(branchName)”不是有效的 Git 分支名称。"
        case .invalidStartBranch(let reference):
            return "“\(reference)”不是可用的 Worktree 起始分支。"
        case .sessionBranchAlreadyExists(let branchName):
            return "Worktree 会话分支已经存在：\(branchName)"
        case .unsupportedRepository(let reason):
            return reason
        case .managedPathAlreadyExists(let path):
            return "Worktree 托管目录已经存在：\(path)"
        case .unsafeManagedPath(let path):
            return "拒绝操作不属于 Breath 的 Worktree 路径：\(path)"
        case .unsafeSessionWorkingDirectory(let path):
            return "会话工作目录包含符号链接或逃出了托管工作树根目录：\(path)"
        case .repositoryIdentityMismatch(let expected, let actual):
            return """
            Worktree 所属 Git 仓库与记录不一致。
            记录：\(expected)
            实际：\(actual)
            """
        case .checkoutCommitMismatch(let expected, let actual):
            return """
            Worktree 检出的提交与创建基线不一致。
            预期：\(expected)
            实际：\(actual)
            """
        case .gitFailed(let exitCode, let output):
            let detail = output.isEmpty ? "Git 没有返回详细信息。" : output
            return "Git 操作失败（退出码 \(exitCode)）：\(detail)"
        case .incompleteCheckout(let path):
            return "Git 已创建 Worktree，但工作目录不完整：\(path)"
        case .worktreeContainsChanges:
            return "Worktree 中仍有未提交修改，请先提交或移走这些修改。"
        case .worktreeContainsUnprotectedCommits:
            return "Worktree 中存在未被本地分支或标签保护的提交，无法安全删除。"
        case .worktreeLocked(let reason):
            if let reason, !reason.isEmpty {
                return "Worktree 已锁定：\(reason)"
            }
            return "Worktree 已锁定，无法删除。"
        case .creationRollbackFailed(
            let path,
            let creationError,
            let cleanupError
        ):
            return """
            Worktree 创建失败，且自动清理未完成：\(path)
            创建错误：\(creationError)
            清理错误：\(cleanupError)
            """
        }
    }
}

struct ManagedWorktreeService: ManagedWorktreeManaging, Sendable {
    private struct RepositoryContext: Sendable {
        let repositoryRoot: URL
        let gitCommonDirectory: URL
        let workspaceRelativePath: String
    }

    private enum WorktreeLock {
        case unlocked
        case locked(String?)
    }

    private struct GitWorktreeListEntry: Sendable {
        let path: String
        let isLocked: Bool
        let lockReason: String?
    }

    private let managedRootURL: URL
    private let disabledHooksURL: URL
    private let runner: GitCommandRunner
    private let operationGate: ManagedWorktreeOperationGate

    init(
        managedRootURL: URL,
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) {
        let root = managedRootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        self.managedRootURL = root
        disabledHooksURL = root.appendingPathComponent(
            ".disabled-hooks",
            isDirectory: true
        )
        runner = GitCommandRunner(executableURL: gitExecutableURL)
        operationGate = ManagedWorktreeOperationGate()
    }

    func startBranches(
        for workspace: Workspace
    ) async throws -> [ManagedWorktreeStartBranch] {
        let context = try await repositoryContext(for: workspace)
        let output = try await checkedOutput([
            "-C", context.repositoryRoot.path,
            "for-each-ref",
            "--sort=refname",
            "--format=%(refname)%00%(refname:short)%00%(HEAD)%00%(symref)",
            "refs/heads",
            "refs/remotes",
        ])
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> ManagedWorktreeStartBranch? in
                let fields = line.split(
                    separator: "\0",
                    omittingEmptySubsequences: false
                ).map(String.init)
                guard fields.count >= 4 else {
                    return nil
                }
                let symbolicTarget = fields[3]
                guard symbolicTarget.isEmpty else {
                    return nil
                }
                let fullReference = fields[0]
                let shortName = fields[1]
                let headMarker = fields[2]
                let kind: ManagedWorktreeStartBranchKind
                if fullReference.hasPrefix("refs/heads/") {
                    kind = .localBranch
                } else if fullReference.hasPrefix("refs/remotes/") {
                    kind = .remoteBranch
                } else {
                    return nil
                }
                return ManagedWorktreeStartBranch(
                    reference: fullReference,
                    name: shortName,
                    kind: kind,
                    isCurrent: headMarker
                        .trimmingCharacters(in: .whitespaces) == "*"
                )
            }
            .sorted { left, right in
                if left.isCurrent != right.isCurrent {
                    return left.isCurrent
                }
                if left.kind != right.kind {
                    return left.kind == .localBranch
                }
                return left.name.localizedStandardCompare(right.name)
                    == .orderedAscending
            }
    }

    func create(
        workspace: Workspace,
        workSessionID: WorkSessionID,
        branchName: String,
        startBranch: ManagedWorktreeStartBranch?
    ) async throws -> ManagedWorktree {
        await operationGate.acquire()
        do {
            let worktree = try await createWithoutAcquiringGate(
                workspace: workspace,
                workSessionID: workSessionID,
                branchName: branchName,
                startBranch: startBranch
            )
            await operationGate.release()
            return worktree
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func createWithoutAcquiringGate(
        workspace: Workspace,
        workSessionID: WorkSessionID,
        branchName: String,
        startBranch: ManagedWorktreeStartBranch? = nil
    ) async throws -> ManagedWorktree {
        let normalizedBranchName = branchName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        try await validateBranchName(normalizedBranchName)
        let context = try await repositoryContext(for: workspace)
        if let startBranch {
            try await validateStartBranchReference(
                startBranch.reference,
                repositoryRoot: context.repositoryRoot
            )
        }
        let rootURL = managedRootURL
            .appendingPathComponent(workspace.id.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent(workSessionID.rawValue.uuidString, isDirectory: true)
            .standardizedFileURL
        guard isManagedPath(
            rootURL,
            workspaceID: workspace.id,
            workSessionID: workSessionID
        ) else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(rootURL.path)
        }
        guard !FileManager.default.fileExists(atPath: rootURL.path) else {
            throw ManagedWorktreeServiceError.managedPathAlreadyExists(rootURL.path)
        }

        let checkoutHooksURL = disabledHooksURL.appendingPathComponent(
            workSessionID.rawValue.uuidString,
            isDirectory: true
        )
        let branchReference = "refs/heads/\(normalizedBranchName)"
        let branchExists = try await localBranchExists(
            branchReference,
            repositoryRoot: context.repositoryRoot
        )
        if startBranch != nil, branchExists {
            throw ManagedWorktreeServiceError.sessionBranchAlreadyExists(
                normalizedBranchName
            )
        }
        let baselineReference = startBranch.map {
            "\($0.reference)^{commit}"
        } ?? (branchExists ? "\(branchReference)^{commit}" : "HEAD^{commit}")
        let baselineCommit = try await checkedOutput([
            "-C", context.repositoryRoot.path,
            "rev-parse", "--verify", baselineReference,
        ]).trimmingCharacters(in: .whitespacesAndNewlines)

        var arguments = [
            "-C", context.repositoryRoot.path,
            "-c", "core.hooksPath=\(checkoutHooksURL.path)",
            "-c", "submodule.recurse=false",
        ]
        arguments.append(contentsOf: try await filterOverrides(
            repositoryRoot: context.repositoryRoot
        ))
        arguments.append(
            contentsOf: [
                "worktree", "add", rootURL.path, normalizedBranchName,
            ]
        )

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_LFS_SKIP_SMUDGE"] = "1"
        let provisionalWorktree = ManagedWorktree(
            workspaceID: workspace.id,
            workSessionID: workSessionID,
            rootPath: rootURL.path,
            gitCommonDirectory: context.gitCommonDirectory.path,
            baselineCommit: baselineCommit,
            workspaceRelativePath: context.workspaceRelativePath,
            branchName: normalizedBranchName,
            createdBranch: false
        )
        do {
            try prepareManagedDirectories(
                for: rootURL,
                checkoutHooksURL: checkoutHooksURL
            )
        } catch let preparationError {
            do {
                try removeEmptyManagedAncestors(startingAt: rootURL)
            } catch let cleanupError {
                throw ManagedWorktreeServiceError.creationRollbackFailed(
                    path: rootURL.path,
                    creationError: preparationError.localizedDescription,
                    cleanupError: cleanupError.localizedDescription
                )
            }
            throw preparationError
        }

        var createdBranch = false
        if !branchExists {
            do {
                _ = try await checkedResult([
                    "-C", context.repositoryRoot.path,
                    "update-ref",
                    branchReference,
                    baselineCommit,
                    String(repeating: "0", count: baselineCommit.count),
                ])
                createdBranch = true
            } catch let creationError {
                try await throwAfterRollingBackCreation(
                    provisionalWorktree,
                    checkoutHooksURL: checkoutHooksURL,
                    creationError: creationError
                )
            }
        }
        let worktree = ManagedWorktree(
            workspaceID: provisionalWorktree.workspaceID,
            workSessionID: provisionalWorktree.workSessionID,
            rootPath: provisionalWorktree.rootPath,
            gitCommonDirectory: provisionalWorktree.gitCommonDirectory,
            baselineCommit: provisionalWorktree.baselineCommit,
            workspaceRelativePath: provisionalWorktree.workspaceRelativePath,
            branchName: provisionalWorktree.branchName,
            createdBranch: createdBranch
        )

        do {
            _ = try await checkedResult(
                arguments,
                environment: environment
            )
        } catch let creationError {
            try await throwAfterRollingBackCreation(
                worktree,
                checkoutHooksURL: checkoutHooksURL,
                creationError: creationError
            )
        }

        do {
            let checkoutCommit = try await checkedOutput([
                "-C", worktree.rootPath,
                "rev-parse", "--verify", "HEAD^{commit}",
            ]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard checkoutCommit == worktree.baselineCommit else {
                throw ManagedWorktreeServiceError.checkoutCommitMismatch(
                    expected: worktree.baselineCommit,
                    actual: checkoutCommit
                )
            }
            try validateSessionWorkingDirectory(worktree)
        } catch let creationError {
            try await throwAfterRollingBackCreation(
                worktree,
                checkoutHooksURL: checkoutHooksURL,
                creationError: creationError
            )
        }
        do {
            try FileManager.default.removeItem(at: checkoutHooksURL)
        } catch let creationError {
            try await throwAfterRollingBackCreation(
                worktree,
                checkoutHooksURL: checkoutHooksURL,
                creationError: creationError
            )
        }
        return worktree
    }

    func isAvailable(_ worktree: ManagedWorktree) async -> Bool {
        let rootURL = URL(
            fileURLWithPath: worktree.rootPath,
            isDirectory: true
        ).standardizedFileURL
        guard isManagedPath(
            rootURL,
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID
        ),
              FileManager.default.fileExists(atPath: worktree.gitCommonDirectory)
        else {
            return false
        }
        do {
            try validateSessionWorkingDirectory(worktree)
            try await validateRepositoryIdentity(
                worktree,
                rootURL: rootURL
            )
        } catch {
            return false
        }
        guard let result = try? await runner.run(arguments: [
            "--git-dir=\(worktree.gitCommonDirectory)",
            "worktree", "list", "--porcelain",
        ]), result.exitCode == 0 else {
            return false
        }
        return worktreeEntry(
            at: rootURL,
            in: parseWorktreeList(result.standardOutput)
        ) != nil
    }

    func remove(_ worktree: ManagedWorktree) async throws {
        await operationGate.acquire()
        do {
            try await validateRemovalWithoutAcquiringGate(worktree)
            try await removeCreatedWorktree(worktree)
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    func rollbackCreation(_ worktree: ManagedWorktree) async throws {
        await operationGate.acquire()
        do {
            try await validateRemovalWithoutAcquiringGate(worktree)
            try await removeCreatedWorktree(worktree)
            try await removeCreatedBranch(worktree)
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    func validateRemoval(_ worktree: ManagedWorktree) async throws {
        await operationGate.acquire()
        do {
            try await validateRemovalWithoutAcquiringGate(worktree)
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func validateRemovalWithoutAcquiringGate(
        _ worktree: ManagedWorktree
    ) async throws {
        let rootURL = URL(
            fileURLWithPath: worktree.rootPath,
            isDirectory: true
        ).standardizedFileURL
        guard isManagedPath(
            rootURL,
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID
        ) else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(rootURL.path)
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        try await validateRepositoryIdentity(worktree, rootURL: rootURL)
        try validateSessionWorkingDirectory(worktree)
        if case .locked(let reason) = try await worktreeLock(
            worktree,
            rootURL: rootURL
        ) {
            throw ManagedWorktreeServiceError.worktreeLocked(reason)
        }
        let status = try await checkedOutput([
            "-C", rootURL.path,
            "status", "--porcelain=v1", "-z",
            "--untracked-files=all",
        ])
        guard status.isEmpty else {
            throw ManagedWorktreeServiceError.worktreeContainsChanges
        }
        let headCommit = try await checkedOutput([
            "-C", rootURL.path,
            "rev-parse", "--verify", "HEAD^{commit}",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let protectingReferences = try await checkedOutput([
            "--git-dir=\(worktree.gitCommonDirectory)",
            "for-each-ref",
            "--format=%(refname)",
            "--contains=\(headCommit)",
            "refs/heads",
            "refs/tags",
        ])
        guard !protectingReferences
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        else {
            throw ManagedWorktreeServiceError.worktreeContainsUnprotectedCommits
        }
    }

    private func repositoryContext(
        for workspace: Workspace
    ) async throws -> RepositoryContext {
        let workspaceURL = URL(
            fileURLWithPath: workspace.path,
            isDirectory: true
        )
        .standardizedFileURL
        let insideResult = try await runner.run(arguments: [
            "-C", workspaceURL.path,
            "rev-parse", "--is-inside-work-tree",
        ])
        guard insideResult.exitCode == 0,
              insideResult.standardOutput.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ) == "true"
        else {
            throw ManagedWorktreeServiceError.unsupportedRepository(
                "所选工作区不在 Git 工作树中。"
            )
        }
        let bare = try await checkedOutput([
            "-C", workspaceURL.path,
            "rev-parse", "--is-bare-repository",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard bare == "false" else {
            throw ManagedWorktreeServiceError.unsupportedRepository(
                "暂不支持 bare Git 仓库。"
            )
        }
        guard await commandSucceeds([
            "-C", workspaceURL.path,
            "rev-parse", "--verify", "HEAD^{commit}",
        ]) else {
            throw ManagedWorktreeServiceError.unsupportedRepository(
                "Git 仓库还没有可检出的提交。"
            )
        }
        let symbolicHead = try await runner.run(arguments: [
            "-C", workspaceURL.path,
            "symbolic-ref", "--quiet", "HEAD",
        ])
        switch symbolicHead.exitCode {
        case 0:
            break
        case 1:
            throw ManagedWorktreeServiceError.unsupportedRepository(
                "当前 Git 仓库处于 detached HEAD 状态，请先检出一个分支。"
            )
        default:
            throw gitFailure(symbolicHead)
        }
        if await configIsTrue(
            key: "core.sparseCheckout",
            repositoryURL: workspaceURL
        ) {
            throw ManagedWorktreeServiceError.unsupportedRepository(
                "暂不支持启用了 sparse checkout 的仓库。"
            )
        }

        let rootPath = try await checkedOutput([
            "-C", workspaceURL.path,
            "rev-parse", "--show-toplevel",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let repositoryRoot = URL(
            fileURLWithPath: rootPath,
            isDirectory: true
        ).standardizedFileURL
        let commonPath = try await checkedOutput([
            "-C", workspaceURL.path,
            "rev-parse", "--git-common-dir",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let gitCommonDirectory: URL
        if commonPath.hasPrefix("/") {
            gitCommonDirectory = URL(
                fileURLWithPath: commonPath,
                isDirectory: true
            ).standardizedFileURL
        } else {
            gitCommonDirectory = URL(
                fileURLWithPath: commonPath,
                relativeTo: workspaceURL
            ).standardizedFileURL
        }
        let relativePath = try relativePath(
            from: repositoryRoot,
            to: workspaceURL
        )
        return RepositoryContext(
            repositoryRoot: repositoryRoot,
            gitCommonDirectory: gitCommonDirectory,
            workspaceRelativePath: relativePath
        )
    }

    private func validateBranchName(_ branchName: String) async throws {
        guard !branchName.isEmpty,
              await commandSucceeds([
                  "check-ref-format", "--branch", branchName,
              ])
        else {
            throw ManagedWorktreeServiceError.invalidBranchName(branchName)
        }
    }

    private func validateStartBranchReference(
        _ reference: String,
        repositoryRoot: URL
    ) async throws {
        guard reference.hasPrefix("refs/heads/")
                || reference.hasPrefix("refs/remotes/"),
              await commandSucceeds([
                  "check-ref-format", reference,
              ])
        else {
            throw ManagedWorktreeServiceError.invalidStartBranch(reference)
        }
        let result = try await runner.run(arguments: [
            "-C", repositoryRoot.path,
            "show-ref", "--verify", "--quiet", reference,
        ])
        switch result.exitCode {
        case 0:
            return
        case 1:
            throw ManagedWorktreeServiceError.invalidStartBranch(reference)
        default:
            throw gitFailure(result)
        }
    }

    private func localBranchExists(
        _ branchReference: String,
        repositoryRoot: URL
    ) async throws -> Bool {
        let result = try await runner.run(arguments: [
            "-C", repositoryRoot.path,
            "show-ref", "--verify", "--quiet", branchReference,
        ])
        switch result.exitCode {
        case 0:
            return true
        case 1:
            return false
        default:
            throw gitFailure(result)
        }
    }

    private func filterOverrides(
        repositoryRoot: URL
    ) async throws -> [String] {
        let result = try await runner.run(arguments: [
            "-C", repositoryRoot.path,
            "config", "--get-regexp",
            #"^filter\..*\.(smudge|process|required)$"#,
        ])
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw gitFailure(result)
        }
        let names = Set(result.standardOutput.split(separator: "\n").compactMap {
            line -> String? in
            guard let key = line.split(
                maxSplits: 1,
                whereSeparator: \.isWhitespace
            ).first else {
                return nil
            }
            let value = String(key)
            guard value.hasPrefix("filter.") else { return nil }
            for suffix in [".smudge", ".process", ".required"]
                where value.hasSuffix(suffix)
            {
                return String(
                    value.dropFirst("filter.".count).dropLast(suffix.count)
                )
            }
            return nil
        })
        return names.sorted().flatMap { name in
            [
                "-c", "filter.\(name).smudge=cat",
                "-c", "filter.\(name).process=",
                "-c", "filter.\(name).required=false",
            ]
        }
    }

    private func removeCreatedWorktree(
        _ worktree: ManagedWorktree
    ) async throws {
        let rootURL = URL(
            fileURLWithPath: worktree.rootPath,
            isDirectory: true
        ).standardizedFileURL
        guard isManagedPath(
            rootURL,
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID
        ) else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(rootURL.path)
        }
        let rootExists = FileManager.default.fileExists(atPath: rootURL.path)
        guard rootExists else {
            try removeEmptyManagedAncestors(startingAt: rootURL)
            return
        }
        try await validateRepositoryIdentity(worktree, rootURL: rootURL)
        let result = try await runner.run(arguments: [
            "--git-dir=\(worktree.gitCommonDirectory)",
            "worktree", "remove", rootURL.path,
        ])
        if result.exitCode != 0 {
            let isRegistered = try await isWorktreeRegistered(
                worktree,
                rootURL: rootURL
            )
            guard !rootExists, !isRegistered else {
                throw gitFailure(result)
            }
        }
        try removeEmptyManagedAncestors(startingAt: rootURL)
    }

    private func rollbackIncompleteCreation(
        _ worktree: ManagedWorktree
    ) async throws {
        let rootURL = URL(
            fileURLWithPath: worktree.rootPath,
            isDirectory: true
        ).standardizedFileURL
        guard isManagedPath(
            rootURL,
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID
        ) else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(rootURL.path)
        }

        let result = try await runner.run(arguments: [
            "--git-dir=\(worktree.gitCommonDirectory)",
            "worktree", "remove", "--force", rootURL.path,
        ])
        if result.exitCode != 0,
           try await isWorktreeRegistered(worktree, rootURL: rootURL)
        {
            throw gitFailure(result)
        }
        if FileManager.default.fileExists(atPath: rootURL.path) {
            guard isManagedPath(
                rootURL,
                workspaceID: worktree.workspaceID,
                workSessionID: worktree.workSessionID
            ) else {
                throw ManagedWorktreeServiceError.unsafeManagedPath(
                    rootURL.path
                )
            }
            try FileManager.default.removeItem(at: rootURL)
        }
        try removeEmptyManagedAncestors(startingAt: rootURL)
        try await removeCreatedBranch(worktree)
    }

    private func removeCreatedBranch(
        _ worktree: ManagedWorktree
    ) async throws {
        guard worktree.createdBranch == true,
              FileManager.default.fileExists(
                  atPath: worktree.gitCommonDirectory
              )
        else {
            return
        }
        _ = try await checkedResult([
            "--git-dir=\(worktree.gitCommonDirectory)",
            "update-ref",
            "-d",
            "refs/heads/\(worktree.branchName)",
            worktree.baselineCommit,
        ])
    }

    private func throwAfterRollingBackCreation(
        _ worktree: ManagedWorktree,
        checkoutHooksURL: URL,
        creationError: any Error
    ) async throws -> Never {
        var cleanupErrors: [String] = []
        do {
            try await rollbackIncompleteCreation(worktree)
        } catch {
            cleanupErrors.append(error.localizedDescription)
        }
        if FileManager.default.fileExists(atPath: checkoutHooksURL.path) {
            do {
                try FileManager.default.removeItem(at: checkoutHooksURL)
            } catch {
                cleanupErrors.append(error.localizedDescription)
            }
        }
        do {
            try removeEmptyManagedAncestors(
                startingAt: URL(
                    fileURLWithPath: worktree.rootPath,
                    isDirectory: true
                )
            )
        } catch {
            cleanupErrors.append(error.localizedDescription)
        }

        guard !cleanupErrors.isEmpty else {
            throw creationError
        }
        throw ManagedWorktreeServiceError.creationRollbackFailed(
            path: worktree.rootPath,
            creationError: creationError.localizedDescription,
            cleanupError: cleanupErrors.joined(separator: "\n")
        )
    }

    private func isWorktreeRegistered(
        _ worktree: ManagedWorktree,
        rootURL: URL
    ) async throws -> Bool {
        let output = try await checkedOutput([
            "--git-dir=\(worktree.gitCommonDirectory)",
            "worktree", "list", "--porcelain",
        ])
        return worktreeEntry(
            at: rootURL,
            in: parseWorktreeList(output)
        ) != nil
    }

    private func worktreeLock(
        _ worktree: ManagedWorktree,
        rootURL: URL
    ) async throws -> WorktreeLock {
        let output = try await checkedOutput([
            "--git-dir=\(worktree.gitCommonDirectory)",
            "worktree", "list", "--porcelain",
        ])
        guard let entry = worktreeEntry(
            at: rootURL,
            in: parseWorktreeList(output)
        ) else {
            return .unlocked
        }
        if entry.isLocked {
            return .locked(entry.lockReason)
        }
        return .unlocked
    }

    private func parseWorktreeList(
        _ output: String
    ) -> [GitWorktreeListEntry] {
        var entries: [GitWorktreeListEntry] = []
        var path: String?
        var isLocked = false
        var lockReason: String?

        func appendCurrentEntry() {
            guard let path else { return }
            entries.append(
                GitWorktreeListEntry(
                    path: path,
                    isLocked: isLocked,
                    lockReason: lockReason
                )
            )
        }

        for line in output.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            if line.hasPrefix("worktree ") {
                appendCurrentEntry()
                path = String(line.dropFirst("worktree ".count))
                isLocked = false
                lockReason = nil
            } else if line == "locked" {
                isLocked = true
                lockReason = nil
            } else if line.hasPrefix("locked ") {
                isLocked = true
                lockReason = String(line.dropFirst("locked ".count))
            } else if line.isEmpty {
                appendCurrentEntry()
                path = nil
                isLocked = false
                lockReason = nil
            }
        }
        appendCurrentEntry()
        return entries
    }

    private func worktreeEntry(
        at rootURL: URL,
        in entries: [GitWorktreeListEntry]
    ) -> GitWorktreeListEntry? {
        let expectedPath = rootURL.resolvingSymlinksInPath()
            .standardizedFileURL.path
        return entries.first { entry in
            URL(fileURLWithPath: entry.path, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL.path == expectedPath
        }
    }

    private func validateSessionWorkingDirectory(
        _ worktree: ManagedWorktree
    ) throws {
        let rootURL = URL(
            fileURLWithPath: worktree.rootPath,
            isDirectory: true
        ).standardizedFileURL
        guard !worktree.workspaceRelativePath.hasPrefix("/") else {
            throw ManagedWorktreeServiceError.unsafeSessionWorkingDirectory(
                worktree.workingDirectory
            )
        }
        var workspaceURL = rootURL
        let components = worktree.workspaceRelativePath.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        for component in components {
            guard component != ".", component != ".." else {
                throw ManagedWorktreeServiceError.unsafeSessionWorkingDirectory(
                    worktree.workingDirectory
                )
            }
            workspaceURL.appendPathComponent(String(component))
            if isSymbolicLink(workspaceURL) {
                throw ManagedWorktreeServiceError.unsafeSessionWorkingDirectory(
                    workspaceURL.path
                )
            }
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: workspaceURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ManagedWorktreeServiceError.incompleteCheckout(
                workspaceURL.path
            )
        }
        let resolvedRoot = rootURL.resolvingSymlinksInPath()
            .standardizedFileURL.path
        let resolvedWorkspace = workspaceURL.resolvingSymlinksInPath()
            .standardizedFileURL.path
        let rootPrefix = resolvedRoot.hasSuffix("/")
            ? resolvedRoot
            : resolvedRoot + "/"
        guard resolvedWorkspace == resolvedRoot
                || resolvedWorkspace.hasPrefix(rootPrefix)
        else {
            throw ManagedWorktreeServiceError.unsafeSessionWorkingDirectory(
                workspaceURL.path
            )
        }
    }

    private func validateRepositoryIdentity(
        _ worktree: ManagedWorktree,
        rootURL: URL
    ) async throws {
        let commonPath = try await checkedOutput([
            "-C", rootURL.path,
            "rev-parse", "--git-common-dir",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let actualDirectory: URL
        if commonPath.hasPrefix("/") {
            actualDirectory = URL(
                fileURLWithPath: commonPath,
                isDirectory: true
            )
        } else {
            actualDirectory = URL(
                fileURLWithPath: commonPath,
                relativeTo: rootURL
            )
        }
        let actualPath = actualDirectory.resolvingSymlinksInPath()
            .standardizedFileURL.path
        let expectedPath = URL(
            fileURLWithPath: worktree.gitCommonDirectory,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL.path
        guard actualPath == expectedPath else {
            throw ManagedWorktreeServiceError.repositoryIdentityMismatch(
                expected: expectedPath,
                actual: actualPath
            )
        }
    }

    private func prepareManagedDirectories(
        for worktreeURL: URL,
        checkoutHooksURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: managedRootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var root = managedRootURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? root.setResourceValues(resourceValues)
        guard !isSymbolicLink(disabledHooksURL),
              !FileManager.default.fileExists(atPath: checkoutHooksURL.path)
        else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(
                checkoutHooksURL.path
            )
        }
        try FileManager.default.createDirectory(
            at: disabledHooksURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: worktreeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: checkoutHooksURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard !isSymbolicLink(checkoutHooksURL),
              try FileManager.default.contentsOfDirectory(
                  atPath: checkoutHooksURL.path
              ).isEmpty
        else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(
                checkoutHooksURL.path
            )
        }
    }

    private func removeEmptyManagedAncestors(
        startingAt worktreeURL: URL
    ) throws {
        let workspaceRoot = worktreeURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: worktreeURL.path),
           (try FileManager.default.contentsOfDirectory(
               atPath: worktreeURL.path
           )).isEmpty
        {
            try FileManager.default.removeItem(at: worktreeURL)
        }
        if FileManager.default.fileExists(atPath: workspaceRoot.path),
           (try FileManager.default.contentsOfDirectory(
               atPath: workspaceRoot.path
           )).isEmpty
        {
            try FileManager.default.removeItem(at: workspaceRoot)
        }
    }

    private func isManagedPath(
        _ url: URL,
        workspaceID: WorkspaceID,
        workSessionID: WorkSessionID
    ) -> Bool {
        let rootComponents = managedRootURL.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count == rootComponents.count + 2,
              Array(components.prefix(rootComponents.count)) == rootComponents
        else {
            return false
        }
        guard components[rootComponents.count]
            == workspaceID.rawValue.uuidString,
            components[rootComponents.count + 1]
                == workSessionID.rawValue.uuidString
        else {
            return false
        }
        let workspaceRoot = url.deletingLastPathComponent()
        return ![
            managedRootURL,
            workspaceRoot,
            url,
        ].contains(where: isSymbolicLink)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private func relativePath(from root: URL, to child: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        if rootPath == childPath { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard childPath.hasPrefix(prefix) else {
            throw ManagedWorktreeServiceError.unsupportedRepository(
                "无法确定工作区在 Git 仓库中的相对路径。"
            )
        }
        return String(childPath.dropFirst(prefix.count))
    }

    private func configIsTrue(
        key: String,
        repositoryURL: URL
    ) async -> Bool {
        guard let result = try? await runner.run(arguments: [
            "-C", repositoryURL.path,
            "config", "--bool", key,
        ]), result.exitCode == 0 else {
            return false
        }
        return result.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    private func commandSucceeds(_ arguments: [String]) async -> Bool {
        guard let result = try? await runner.run(arguments: arguments) else {
            return false
        }
        return result.exitCode == 0
    }

    private func checkedOutput(
        _ arguments: [String]
    ) async throws -> String {
        try await checkedResult(arguments).standardOutput
    }

    private func checkedResult(
        _ arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> GitCommandResult {
        let result = try await runner.run(
            arguments: arguments,
            environment: environment
        )
        guard result.exitCode == 0 else { throw gitFailure(result) }
        return result
    }

    private func gitFailure(
        _ result: GitCommandResult
    ) -> ManagedWorktreeServiceError {
        .gitFailed(
            exitCode: result.exitCode,
            output: GitSecretRedactor.redact(result.combinedOutput)
        )
    }
}
