import BreathCore
import Foundation

protocol ManagedWorktreeDirectoryTrashing: Sendable {
    func moveToTrash(_ url: URL) async throws
}

private struct MacOSManagedWorktreeDirectoryTrash:
    ManagedWorktreeDirectoryTrashing,
    Sendable
{
    func moveToTrash(_ url: URL) async throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(
            at: url,
            resultingItemURL: &resultingURL
        )
    }
}

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

enum ManagedWorktreeInventoryState: Equatable, Sendable {
    case tracked
    case unavailable
    case branchOnly
    case directoryOnly
    case orphanedCheckout
}

struct ManagedWorktreeInventorySnapshot: Equatable, Sendable {
    let items: [ManagedWorktreeInventoryItem]
    let warnings: [String]
}

struct ManagedWorktreeInventoryItem: Equatable, Identifiable, Sendable {
    let repositoryName: String
    let repositoryPath: String
    let gitCommonDirectory: String?
    let branchName: String?
    let branchCommit: String?
    let directoryPath: String?
    let state: ManagedWorktreeInventoryState

    var id: String {
        [
            repositoryPath,
            branchName ?? "",
            directoryPath ?? "",
        ].joined(separator: "\0")
    }
}

enum ManagedWorktreeServiceError: LocalizedError, Equatable {
    case invalidBranchName(String)
    case invalidStartBranch(String)
    case sessionBranchAlreadyExists(String)
    case unsupportedRepository(String)
    case inventoryDeletionNotAllowed(String)
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
    case mergeTargetMustBeLocal(String)
    case mergeTargetMatchesSource(String)
    case mergeTargetContainsChanges(String)
    case mergeTargetLocked(branch: String, reason: String?)
    case mergeFailed(branch: String, output: String)
    case mergeAbortFailed(branch: String, output: String)
    case mergeCleanupFailed(path: String, output: String)
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
        case .inventoryDeletionNotAllowed(let reason):
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
        case .mergeTargetMustBeLocal(let branch):
            return "合并目标必须是本地分支：\(branch)"
        case .mergeTargetMatchesSource(let branch):
            return "不能将 Worktree 分支合并到自身：\(branch)"
        case .mergeTargetContainsChanges(let branch):
            return "目标分支 \(branch) 的检出目录存在未提交修改，请先处理后再合并。"
        case .mergeTargetLocked(let branch, let reason):
            if let reason, !reason.isEmpty {
                return "目标分支 \(branch) 的 Worktree 已锁定：\(reason)"
            }
            return "目标分支 \(branch) 的 Worktree 已锁定，无法合并。"
        case .mergeFailed(let branch, let output):
            let detail = output.isEmpty ? "Git 没有返回详细信息。" : output
            return "合并到 \(branch) 失败，已自动中止合并：\(detail)"
        case .mergeAbortFailed(let branch, let output):
            let detail = output.isEmpty ? "Git 没有返回详细信息。" : output
            return "合并到 \(branch) 失败，且无法自动中止合并：\(detail)"
        case .mergeCleanupFailed(let path, let output):
            let detail = output.isEmpty ? "Git 没有返回详细信息。" : output
            return "分支已经合并，但临时 Worktree 清理失败：\(path)\n\(detail)"
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
    private struct InventoryRepository: Codable, Sendable {
        let gitCommonDirectory: String
        let repositoryPath: String
        let displayName: String
    }

    private struct RepositoryContext: Sendable {
        let repositoryRoot: URL
        let gitCommonDirectory: URL
        let workspaceRelativePath: String
    }

    private struct RepositoryLocations: Sendable {
        let repositoryRoot: URL
        let gitCommonDirectory: URL
    }

    private struct InventoryBranch: Sendable {
        let name: String
        let commit: String
    }

    private enum WorktreeLock {
        case unlocked
        case locked(String?)
    }

    private struct GitWorktreeListEntry: Sendable {
        let path: String
        let branchReference: String?
        let isLocked: Bool
        let lockReason: String?
    }

    private let managedRootURL: URL
    private let disabledHooksURL: URL
    private let inventoryRepositoriesURL: URL
    private let runner: GitCommandRunner
    private let operationGate: ManagedWorktreeOperationGate
    private let directoryTrash: any ManagedWorktreeDirectoryTrashing

    init(
        managedRootURL: URL,
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        directoryTrash: any ManagedWorktreeDirectoryTrashing =
            MacOSManagedWorktreeDirectoryTrash()
    ) {
        let root = managedRootURL.standardizedFileURL
        self.managedRootURL = root
        disabledHooksURL = root.appendingPathComponent(
            ".disabled-hooks",
            isDirectory: true
        )
        inventoryRepositoriesURL = root.appendingPathComponent(
            ".repositories.json"
        )
        runner = GitCommandRunner(executableURL: gitExecutableURL)
        operationGate = ManagedWorktreeOperationGate()
        self.directoryTrash = directoryTrash
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

    func inventory(
        workspaces: [Workspace],
        knownWorktrees: [ManagedWorktree]
    ) async -> ManagedWorktreeInventorySnapshot {
        await operationGate.acquire()
        let snapshot = await inventoryWithoutAcquiringGate(
            workspaces: workspaces,
            knownWorktrees: knownWorktrees
        )
        await operationGate.release()
        return snapshot
    }

    func preserveInventoryRepository(
        for workspace: Workspace,
        knownWorktrees: [ManagedWorktree]
    ) async throws -> Bool {
        await operationGate.acquire()
        do {
            let didPreserve =
                try await preserveInventoryRepositoryWithoutAcquiringGate(
                    for: workspace,
                    knownWorktrees: knownWorktrees
                )
            await operationGate.release()
            return didPreserve
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func preserveInventoryRepositoryWithoutAcquiringGate(
        for workspace: Workspace,
        knownWorktrees: [ManagedWorktree]
    ) async throws -> Bool {
        let result = try await runner.run(arguments: [
            "-C", workspace.path,
            "rev-parse", "--is-inside-work-tree",
        ])
        if result.exitCode == 0,
           result.standardOutput.trimmingCharacters(
               in: .whitespacesAndNewlines
           ) == "true"
        {
            try recordInventoryRepository(
                try await inventoryRepository(for: workspace)
            )
            return true
        }

        let workspaceWorktrees = knownWorktrees.filter {
            $0.workspaceID == workspace.id
        }
        var preservedGitDirectories: Set<String> = []
        var didPreserveRepository = false
        for worktree in workspaceWorktrees {
            let gitDirectoryPath = standardizedPath(
                worktree.gitCommonDirectory
            )
            guard preservedGitDirectories.insert(gitDirectoryPath).inserted
            else {
                continue
            }
            guard FileManager.default.fileExists(atPath: gitDirectoryPath)
            else {
                throw unavailableInventoryRepositoryError(for: workspace)
            }
            let validation = try await runner.run(arguments: [
                "--git-dir=\(gitDirectoryPath)",
                "rev-parse", "--git-common-dir",
            ])
            guard validation.exitCode == 0 else {
                throw unavailableInventoryRepositoryError(for: workspace)
            }
            try recordInventoryRepository(
                InventoryRepository(
                    gitCommonDirectory: gitDirectoryPath,
                    repositoryPath: workspace.path,
                    displayName: workspace.displayName
                )
            )
            didPreserveRepository = true
        }
        guard didPreserveRepository || workspaceWorktrees.isEmpty else {
            throw unavailableInventoryRepositoryError(for: workspace)
        }
        return didPreserveRepository
    }

    func deleteInventoryBranch(
        _ item: ManagedWorktreeInventoryItem
    ) async throws {
        await operationGate.acquire()
        do {
            try await deleteInventoryBranchWithoutAcquiringGate(item)
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func deleteInventoryBranchWithoutAcquiringGate(
        _ item: ManagedWorktreeInventoryItem
    ) async throws {
        guard item.state == .branchOnly,
              item.directoryPath == nil,
              let branchName = item.branchName,
              managedWorkSessionID(for: branchName) != nil,
              let branchCommit = item.branchCommit,
              let gitCommonDirectory = item.gitCommonDirectory
        else {
            throw ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "只能从 Worktree 库存中删除没有检出目录的 Breath 会话分支。"
            )
        }
        let gitDirectoryPath = standardizedPath(gitCommonDirectory)
        guard FileManager.default.fileExists(atPath: gitDirectoryPath) else {
            throw ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "Worktree 所属 Git 仓库不可用，无法删除分支。"
            )
        }
        let branchReference = "refs/heads/\(branchName)"
        let entries = parseWorktreeList(
            try await checkedOutput([
                "--git-dir=\(gitDirectoryPath)",
                "worktree", "list", "--porcelain",
            ])
        )
        guard !entries.contains(where: {
            $0.branchReference == branchReference
        }) else {
            throw ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "该分支已被 Git Worktree 检出，请刷新库存后重试。"
            )
        }
        _ = try await checkedResult([
            "--git-dir=\(gitDirectoryPath)",
            "update-ref", "-d", branchReference, branchCommit,
        ])
    }

    func deleteInventoryDirectory(
        _ item: ManagedWorktreeInventoryItem
    ) async throws {
        await operationGate.acquire()
        do {
            try await deleteInventoryDirectoryWithoutAcquiringGate(item)
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func deleteInventoryDirectoryWithoutAcquiringGate(
        _ item: ManagedWorktreeInventoryItem
    ) async throws {
        guard item.state == .orphanedCheckout
                || item.state == .directoryOnly,
              let directoryPath = item.directoryPath
        else {
            throw ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "只能删除库存中的目录残留或未关联会话目录。"
            )
        }
        let rootURL = URL(
            fileURLWithPath: directoryPath,
            isDirectory: true
        ).standardizedFileURL
        guard let owners = managedPathOwners(for: rootURL),
              isManagedPath(
                  rootURL,
                  workspaceID: owners.workspaceID,
                  workSessionID: owners.workSessionID
              )
        else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(rootURL.path)
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "Worktree 目录已经不存在，请刷新库存。"
            )
        }
        if item.state == .directoryOnly {
            let gitProbe = try await runner.run(arguments: [
                "-C", rootURL.path,
                "rev-parse", "--is-inside-work-tree",
            ])
            guard gitProbe.exitCode != 0
                    || gitProbe.standardOutput.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) != "true"
            else {
                throw ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                    "该目录仍是有效的 Git Worktree，请刷新库存后重试。"
                )
            }
            try await directoryTrash.moveToTrash(rootURL)
            try removeEmptyManagedAncestors(startingAt: rootURL)
            return
        }
        guard let storedGitCommonDirectory = item.gitCommonDirectory else {
            throw ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "无法确认 Worktree 所属 Git 仓库，请刷新库存。"
            )
        }
        let gitDirectoryPath = standardizedPath(storedGitCommonDirectory)
        let actualGitDirectoryPath = try await gitCommonDirectory(
            for: rootURL
        )
        guard actualGitDirectoryPath == gitDirectoryPath else {
            throw ManagedWorktreeServiceError.repositoryIdentityMismatch(
                expected: gitDirectoryPath,
                actual: actualGitDirectoryPath
            )
        }
        let entries = parseWorktreeList(
            try await checkedOutput([
                "--git-dir=\(gitDirectoryPath)",
                "worktree", "list", "--porcelain",
            ])
        )
        guard let entry = worktreeEntry(at: rootURL, in: entries) else {
            throw ManagedWorktreeServiceError.inventoryDeletionNotAllowed(
                "该目录已不再是登记的 Git Worktree，请刷新库存。"
            )
        }
        guard !entry.isLocked else {
            throw ManagedWorktreeServiceError.worktreeLocked(entry.lockReason)
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
            "--git-dir=\(gitDirectoryPath)",
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
        _ = try await checkedResult([
            "--git-dir=\(gitDirectoryPath)",
            "worktree", "remove", rootURL.path,
        ])
        try removeEmptyManagedAncestors(startingAt: rootURL)
    }

    private func unavailableInventoryRepositoryError(
        for workspace: Workspace
    ) -> ManagedWorktreeServiceError {
        .unsupportedRepository(
            "无法补录 \(workspace.displayName) 的 Worktree 仓库索引："
                + "已知 Git common directory 不可用。"
        )
    }

    private func inventoryWithoutAcquiringGate(
        workspaces: [Workspace],
        knownWorktrees: [ManagedWorktree]
    ) async -> ManagedWorktreeInventorySnapshot {
        var items: [ManagedWorktreeInventoryItem] = []
        var warnings: [String] = []
        var representedDirectoryPaths: Set<String> = []
        var representedKnownWorktreeIDs: Set<WorkSessionID> = []
        var repositories: [String: InventoryRepository] = [:]

        do {
            for repository in try loadInventoryRepositories() {
                repositories[
                    standardizedPath(repository.gitCommonDirectory)
                ] = repository
            }
        } catch {
            warnings.append(
                "无法读取 Worktree 仓库记录：\(inventoryErrorSummary(error))"
            )
        }
        for workspace in workspaces {
            do {
                let repository = try await inventoryRepository(for: workspace)
                repositories[
                    standardizedPath(repository.gitCommonDirectory)
                ] = repository
            } catch {
                warnings.append(
                    "无法读取 \(workspace.displayName) 的 Git 仓库："
                        + inventoryErrorSummary(error)
                )
            }
        }
        for worktree in knownWorktrees {
            let gitDirectoryPath = standardizedPath(
                worktree.gitCommonDirectory
            )
            guard repositories[gitDirectoryPath] == nil else {
                continue
            }
            let workspace = workspaces.first {
                $0.id == worktree.workspaceID
            }
            repositories[gitDirectoryPath] = InventoryRepository(
                gitCommonDirectory: worktree.gitCommonDirectory,
                repositoryPath: workspace?.path ?? worktree.rootPath,
                displayName: workspace?.displayName ?? ""
            )
        }

        for (gitDirectoryPath, repository) in repositories.sorted(by: {
            $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }) {
            let branches: [InventoryBranch]
            let worktreeEntries: [GitWorktreeListEntry]
            do {
                branches = try await checkedOutput([
                    "--git-dir=\(gitDirectoryPath)",
                    "for-each-ref",
                    "--sort=refname",
                    "--format=%(refname:short)%00%(objectname)",
                    "refs/heads/breath/",
                ])
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    let fields = line.split(
                        separator: "\0",
                        omittingEmptySubsequences: false
                    )
                    .map(String.init)
                    guard fields.count == 2,
                          managedWorkSessionID(for: fields[0]) != nil
                    else {
                        return nil
                    }
                    return InventoryBranch(
                        name: fields[0],
                        commit: fields[1]
                    )
                }
                worktreeEntries = parseWorktreeList(
                    try await checkedOutput([
                        "--git-dir=\(gitDirectoryPath)",
                        "worktree", "list", "--porcelain",
                    ])
                )
            } catch {
                let name = repository.displayName.isEmpty
                    ? repository.repositoryPath
                    : repository.displayName
                warnings.append(
                    "无法扫描 \(name) 的 Worktree："
                        + inventoryErrorSummary(error)
                )
                continue
            }

            var representedBranchNames: Set<String> = []
            let repositoryWorktrees = knownWorktrees.filter {
                standardizedPath($0.gitCommonDirectory) == gitDirectoryPath
            }
            for knownWorktree in repositoryWorktrees {
                guard let entry = worktreeEntries.first(where: {
                    standardizedPath($0.path)
                        == standardizedPath(knownWorktree.rootPath)
                        && isInsideManagedRoot(
                            URL(
                                fileURLWithPath: $0.path,
                                isDirectory: true
                            )
                        )
                        && FileManager.default.fileExists(atPath: $0.path)
                }) else {
                    continue
                }
                let path = standardizedPath(entry.path)
                representedDirectoryPaths.insert(path)
                representedKnownWorktreeIDs.insert(
                    knownWorktree.workSessionID
                )
                representedBranchNames.insert(knownWorktree.branchName)
                let validation = await inventoryState(
                    for: knownWorktree,
                    registeredDirectoryPath: entry.path
                )
                if let warning = validation.warning {
                    warnings.append(warning)
                }
                items.append(
                    ManagedWorktreeInventoryItem(
                        repositoryName: repository.displayName,
                        repositoryPath: repository.repositoryPath,
                        gitCommonDirectory: gitDirectoryPath,
                        branchName: knownWorktree.branchName,
                        branchCommit: branches.first {
                            $0.name == knownWorktree.branchName
                        }?.commit,
                        directoryPath: knownWorktree.rootPath,
                        state: validation.state
                    )
                )
            }

            for branch in branches
                where representedBranchNames.insert(branch.name).inserted
            {
                let branchName = branch.name
                let branchReference = "refs/heads/\(branchName)"
                let entry = worktreeEntries.first {
                    $0.branchReference == branchReference
                        && isInsideManagedRoot(
                            URL(
                                fileURLWithPath: $0.path,
                                isDirectory: true
                            )
                        )
                }
                let existingDirectoryPath = entry.flatMap { entry in
                    FileManager.default.fileExists(atPath: entry.path)
                        ? entry.path
                        : nil
                }
                if let existingDirectoryPath {
                    let path = standardizedPath(existingDirectoryPath)
                    guard representedDirectoryPaths.insert(path).inserted else {
                        continue
                    }
                }
                let knownWorktree = existingDirectoryPath == nil
                    ? repositoryWorktrees.first {
                        $0.branchName == branchName
                    }
                    : nil
                let state: ManagedWorktreeInventoryState
                if let knownWorktree {
                    representedKnownWorktreeIDs.insert(
                        knownWorktree.workSessionID
                    )
                    state = .unavailable
                } else if existingDirectoryPath == nil {
                    state = .branchOnly
                } else {
                    state = .orphanedCheckout
                }
                let directoryPath = existingDirectoryPath.map { path in
                    knownWorktree?.rootPath ?? path
                }
                items.append(
                    ManagedWorktreeInventoryItem(
                        repositoryName: repository.displayName,
                        repositoryPath: repository.repositoryPath,
                        gitCommonDirectory: gitDirectoryPath,
                        branchName: branchName,
                        branchCommit: branch.commit,
                        directoryPath: directoryPath,
                        state: state
                    )
                )
            }

            for entry in worktreeEntries {
                let directoryURL = URL(
                    fileURLWithPath: entry.path,
                    isDirectory: true
                )
                guard isInsideManagedRoot(directoryURL),
                      FileManager.default.fileExists(atPath: entry.path)
                else {
                    continue
                }
                let branchName = entry.branchReference.flatMap {
                    reference -> String? in
                    let prefix = "refs/heads/"
                    guard reference.hasPrefix(prefix) else { return nil }
                    return String(reference.dropFirst(prefix.count))
                }
                guard branchName.map({
                    !representedBranchNames.contains($0)
                }) ?? true else {
                    continue
                }
                let path = standardizedPath(entry.path)
                guard representedDirectoryPaths.insert(path).inserted else {
                    continue
                }
                let knownWorktree = knownWorktrees.first {
                    standardizedPath($0.gitCommonDirectory)
                        == gitDirectoryPath
                        && standardizedPath($0.rootPath) == path
                }
                if let knownWorktree {
                    representedKnownWorktreeIDs.insert(
                        knownWorktree.workSessionID
                    )
                }
                let state: ManagedWorktreeInventoryState
                if let knownWorktree {
                    let validation = await inventoryState(
                        for: knownWorktree,
                        registeredDirectoryPath: entry.path
                    )
                    state = validation.state
                    if let warning = validation.warning {
                        warnings.append(warning)
                    }
                } else {
                    state = .orphanedCheckout
                }
                items.append(
                    ManagedWorktreeInventoryItem(
                        repositoryName: repository.displayName,
                        repositoryPath: repository.repositoryPath,
                        gitCommonDirectory: gitDirectoryPath,
                        branchName: branchName,
                        branchCommit: branchName.flatMap { name in
                            branches.first { $0.name == name }?.commit
                        },
                        directoryPath: knownWorktree?.rootPath ?? entry.path,
                        state: state
                    )
                )
            }
        }

        do {
            for directoryURL in try managedCheckoutDirectories() {
                let path = standardizedPath(directoryURL.path)
                guard representedDirectoryPaths.insert(path).inserted else {
                    continue
                }
                let knownWorktree = knownWorktrees.first {
                    standardizedPath($0.rootPath) == path
                }
                if let knownWorktree {
                    representedKnownWorktreeIDs.insert(
                        knownWorktree.workSessionID
                    )
                }
                let workspace = workspaceOwningManagedDirectory(
                    directoryURL,
                    workspaces: workspaces
                )
                items.append(
                    ManagedWorktreeInventoryItem(
                        repositoryName: workspace?.displayName ?? "",
                        repositoryPath: workspace?.path ?? "",
                        gitCommonDirectory: knownWorktree?
                            .gitCommonDirectory,
                        branchName: knownWorktree?.branchName,
                        branchCommit: nil,
                        directoryPath: knownWorktree?.rootPath
                            ?? directoryURL.path,
                        state: knownWorktree == nil
                            ? .directoryOnly
                            : .unavailable
                    )
                )
            }
        } catch {
            warnings.append(
                "无法扫描 Worktree 托管目录："
                    + inventoryErrorSummary(error)
            )
        }

        for worktree in knownWorktrees
            where !representedKnownWorktreeIDs.contains(
                worktree.workSessionID
            )
        {
            let workspace = workspaces.first {
                $0.id == worktree.workspaceID
            }
            items.append(
                ManagedWorktreeInventoryItem(
                    repositoryName: workspace?.displayName ?? "",
                    repositoryPath: workspace?.path ?? "",
                    gitCommonDirectory: worktree.gitCommonDirectory,
                    branchName: worktree.branchName,
                    branchCommit: nil,
                    directoryPath: FileManager.default.fileExists(
                        atPath: worktree.rootPath
                    ) ? worktree.rootPath : nil,
                    state: .unavailable
                )
            )
        }

        return ManagedWorktreeInventorySnapshot(
            items: items.sorted(by: inventorySort),
            warnings: warnings
        )
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
            try recordInventoryRepository(
                context,
                displayName: workspace.displayName
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

    func merge(
        _ worktree: ManagedWorktree,
        into targetBranch: ManagedWorktreeStartBranch
    ) async throws {
        await operationGate.acquire()
        do {
            try await mergeWithoutAcquiringGate(
                worktree,
                into: targetBranch
            )
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func mergeWithoutAcquiringGate(
        _ worktree: ManagedWorktree,
        into targetBranch: ManagedWorktreeStartBranch
    ) async throws {
        guard targetBranch.kind == .localBranch,
              targetBranch.reference == "refs/heads/\(targetBranch.name)"
        else {
            throw ManagedWorktreeServiceError.mergeTargetMustBeLocal(
                targetBranch.name
            )
        }
        guard targetBranch.name != worktree.branchName else {
            throw ManagedWorktreeServiceError.mergeTargetMatchesSource(
                targetBranch.name
            )
        }
        try await validateBranchName(targetBranch.name)
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
        try await validateRepositoryIdentity(worktree, rootURL: rootURL)
        try validateSessionWorkingDirectory(worktree)

        let sourceStatus = try await checkedOutput([
            "-C", rootURL.path,
            "status", "--porcelain=v1", "-z",
            "--untracked-files=all",
        ])
        guard sourceStatus.isEmpty else {
            throw ManagedWorktreeServiceError.worktreeContainsChanges
        }
        let sourceReference = "refs/heads/\(worktree.branchName)"
        let sourceCommit = try await checkedOutput([
            "-C", rootURL.path,
            "rev-parse", "--verify", "HEAD^{commit}",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        let branchCommit = try await checkedOutput([
            "--git-dir=\(worktree.gitCommonDirectory)",
            "rev-parse", "--verify", "\(sourceReference)^{commit}",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sourceCommit == branchCommit else {
            throw ManagedWorktreeServiceError.checkoutCommitMismatch(
                expected: branchCommit,
                actual: sourceCommit
            )
        }
        try await validateStartBranchReference(
            targetBranch.reference,
            gitCommonDirectory: worktree.gitCommonDirectory
        )

        let entries = parseWorktreeList(
            try await checkedOutput([
                "--git-dir=\(worktree.gitCommonDirectory)",
                "worktree", "list", "--porcelain",
            ])
        )
        if let targetEntry = entries.first(where: {
            $0.branchReference == targetBranch.reference
        }) {
            if targetEntry.isLocked {
                throw ManagedWorktreeServiceError.mergeTargetLocked(
                    branch: targetBranch.name,
                    reason: targetEntry.lockReason
                )
            }
            try await merge(
                sourceReference: sourceReference,
                into: targetBranch,
                checkoutURL: URL(
                    fileURLWithPath: targetEntry.path,
                    isDirectory: true
                ).standardizedFileURL
            )
            return
        }

        try await mergeUsingTemporaryWorktree(
            sourceReference: sourceReference,
            targetBranch: targetBranch,
            gitCommonDirectory: worktree.gitCommonDirectory
        )
    }

    private func mergeUsingTemporaryWorktree(
        sourceReference: String,
        targetBranch: ManagedWorktreeStartBranch,
        gitCommonDirectory: String
    ) async throws {
        let temporaryParent = managedRootURL.appendingPathComponent(
            ".merge",
            isDirectory: true
        ).standardizedFileURL
        let temporaryURL = temporaryParent.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        ).standardizedFileURL
        guard temporaryURL.deletingLastPathComponent() == temporaryParent,
              !isSymbolicLink(managedRootURL),
              !isSymbolicLink(temporaryParent),
              !FileManager.default.fileExists(atPath: temporaryURL.path)
        else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(
                temporaryURL.path
            )
        }
        try FileManager.default.createDirectory(
            at: temporaryParent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let addResult = try await runner.run(arguments: [
            "--git-dir=\(gitCommonDirectory)",
            "worktree", "add", "--quiet",
            temporaryURL.path,
            targetBranch.name,
        ])
        guard addResult.exitCode == 0 else {
            try? removeEmptyMergeDirectory(temporaryParent)
            throw gitFailure(addResult)
        }

        do {
            try await merge(
                sourceReference: sourceReference,
                into: targetBranch,
                checkoutURL: temporaryURL
            )
        } catch {
            let cleanupResult = try await runner.run(arguments: [
                "--git-dir=\(gitCommonDirectory)",
                "worktree", "remove", "--force",
                temporaryURL.path,
            ])
            try? removeEmptyMergeDirectory(temporaryParent)
            guard cleanupResult.exitCode == 0 else {
                throw ManagedWorktreeServiceError.mergeAbortFailed(
                    branch: targetBranch.name,
                    output: [
                        error.localizedDescription,
                        cleanupResult.combinedOutput,
                    ].filter { !$0.isEmpty }.joined(separator: "\n")
                )
            }
            throw error
        }

        let cleanupResult = try await runner.run(arguments: [
            "--git-dir=\(gitCommonDirectory)",
            "worktree", "remove", temporaryURL.path,
        ])
        try? removeEmptyMergeDirectory(temporaryParent)
        guard cleanupResult.exitCode == 0 else {
            throw ManagedWorktreeServiceError.mergeCleanupFailed(
                path: temporaryURL.path,
                output: cleanupResult.combinedOutput
            )
        }
    }

    private func merge(
        sourceReference: String,
        into targetBranch: ManagedWorktreeStartBranch,
        checkoutURL: URL
    ) async throws {
        let status = try await checkedOutput([
            "-C", checkoutURL.path,
            "status", "--porcelain=v1", "-z",
            "--untracked-files=all",
        ])
        guard status.isEmpty else {
            throw ManagedWorktreeServiceError.mergeTargetContainsChanges(
                targetBranch.name
            )
        }
        let checkedOutReference = try await checkedOutput([
            "-C", checkoutURL.path,
            "symbolic-ref", "--quiet", "HEAD",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard checkedOutReference == targetBranch.reference else {
            throw ManagedWorktreeServiceError.mergeTargetMustBeLocal(
                targetBranch.name
            )
        }
        let mergeResult = try await runner.run(arguments: [
            "-C", checkoutURL.path,
            "merge", "--no-edit", sourceReference,
        ])
        guard mergeResult.exitCode == 0 else {
            let mergeHead = try await runner.run(arguments: [
                "-C", checkoutURL.path,
                "rev-parse", "--verify", "--quiet", "MERGE_HEAD",
            ])
            if mergeHead.exitCode == 0 {
                let abortResult = try await runner.run(arguments: [
                    "-C", checkoutURL.path,
                    "merge", "--abort",
                ])
                guard abortResult.exitCode == 0 else {
                    throw ManagedWorktreeServiceError.mergeAbortFailed(
                        branch: targetBranch.name,
                        output: [
                            mergeResult.combinedOutput,
                            abortResult.combinedOutput,
                        ].filter { !$0.isEmpty }.joined(separator: "\n")
                    )
                }
            }
            throw ManagedWorktreeServiceError.mergeFailed(
                branch: targetBranch.name,
                output: mergeResult.combinedOutput
            )
        }
    }

    private func removeEmptyMergeDirectory(_ directory: URL) throws {
        guard directory.deletingLastPathComponent().standardizedFileURL
                == managedRootURL.standardizedFileURL,
              directory.lastPathComponent == ".merge",
              !isSymbolicLink(directory)
        else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(
                directory.path
            )
        }
        guard FileManager.default.fileExists(atPath: directory.path),
              try FileManager.default.contentsOfDirectory(
                  atPath: directory.path
              ).isEmpty
        else {
            return
        }
        try FileManager.default.removeItem(at: directory)
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

    private func inventoryRepository(
        for workspace: Workspace
    ) async throws -> InventoryRepository {
        let workspaceURL = URL(
            fileURLWithPath: workspace.path,
            isDirectory: true
        ).standardizedFileURL
        let locations = try await repositoryLocations(
            for: workspaceURL
        )
        return InventoryRepository(
            gitCommonDirectory: locations.gitCommonDirectory.path,
            repositoryPath: locations.repositoryRoot.path,
            displayName: workspace.displayName
        )
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

        let locations = try await repositoryLocations(
            for: workspaceURL
        )
        let relativePath = try relativePath(
            from: locations.repositoryRoot,
            to: workspaceURL
        )
        return RepositoryContext(
            repositoryRoot: locations.repositoryRoot,
            gitCommonDirectory: locations.gitCommonDirectory,
            workspaceRelativePath: relativePath
        )
    }

    private func repositoryLocations(
        for workspaceURL: URL
    ) async throws -> RepositoryLocations {
        let rootPath = try await checkedOutput([
            "-C", workspaceURL.path,
            "rev-parse", "--show-toplevel",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
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
        return RepositoryLocations(
            repositoryRoot: URL(
                fileURLWithPath: rootPath,
                isDirectory: true
            ).standardizedFileURL,
            gitCommonDirectory: gitCommonDirectory
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

    private func validateStartBranchReference(
        _ reference: String,
        gitCommonDirectory: String
    ) async throws {
        guard reference.hasPrefix("refs/heads/"),
              await commandSucceeds([
                  "check-ref-format", reference,
              ])
        else {
            throw ManagedWorktreeServiceError.invalidStartBranch(reference)
        }
        let result = try await runner.run(arguments: [
            "--git-dir=\(gitCommonDirectory)",
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
        var branchReference: String?
        var isLocked = false
        var lockReason: String?

        func appendCurrentEntry() {
            guard let path else { return }
            entries.append(
                GitWorktreeListEntry(
                    path: path,
                    branchReference: branchReference,
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
                branchReference = nil
                isLocked = false
                lockReason = nil
            } else if line.hasPrefix("branch ") {
                branchReference = String(line.dropFirst("branch ".count))
            } else if line == "locked" {
                isLocked = true
                lockReason = nil
            } else if line.hasPrefix("locked ") {
                isLocked = true
                lockReason = String(line.dropFirst("locked ".count))
            } else if line.isEmpty {
                appendCurrentEntry()
                path = nil
                branchReference = nil
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
        let expectedPath = standardizedPath(rootURL.path)
        return entries.first { entry in
            standardizedPath(entry.path) == expectedPath
        }
    }

    private func isInsideManagedRoot(_ url: URL) -> Bool {
        let rootPath = standardizedPath(managedRootURL.path)
        let candidatePath = standardizedPath(url.path)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
    }

    private func managedPathOwners(
        for url: URL
    ) -> (
        workspaceID: WorkspaceID,
        workSessionID: WorkSessionID
    )? {
        let rootComponents = managedRootURL.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count == rootComponents.count + 2,
              Array(components.prefix(rootComponents.count)) == rootComponents,
              let workspaceValue = UUID(
                  uuidString: components[rootComponents.count]
              ),
              let sessionValue = UUID(
                  uuidString: components[rootComponents.count + 1]
              )
        else {
            return nil
        }
        return (
            WorkspaceID(rawValue: workspaceValue),
            WorkSessionID(rawValue: sessionValue)
        )
    }

    private func managedWorkSessionID(
        for branchName: String
    ) -> WorkSessionID? {
        let prefix = "breath/"
        guard branchName.hasPrefix(prefix),
              let value = UUID(
                  uuidString: String(branchName.dropFirst(prefix.count))
              )
        else {
            return nil
        }
        let workSessionID = WorkSessionID(rawValue: value)
        guard branchName == ManagedWorktree.sessionBranchName(
            for: workSessionID
        ) else {
            return nil
        }
        return workSessionID
    }

    private func recordInventoryRepository(
        _ context: RepositoryContext,
        displayName: String
    ) throws {
        try recordInventoryRepository(
            InventoryRepository(
                gitCommonDirectory: context.gitCommonDirectory.path,
                repositoryPath: context.repositoryRoot.path,
                displayName: displayName
            )
        )
    }

    private func recordInventoryRepository(
        _ repository: InventoryRepository
    ) throws {
        var repositories: [String: InventoryRepository] = [:]
        for repository in try loadInventoryRepositories() {
            repositories[
                standardizedPath(repository.gitCommonDirectory)
            ] = repository
        }
        repositories[
            standardizedPath(repository.gitCommonDirectory)
        ] = repository
        try saveInventoryRepositories(Array(repositories.values))
    }

    private func loadInventoryRepositories() throws
        -> [InventoryRepository]
    {
        try validateInventoryStoragePath()
        guard FileManager.default.fileExists(
            atPath: inventoryRepositoriesURL.path
        ) else {
            return []
        }
        return try JSONDecoder().decode(
            [InventoryRepository].self,
            from: Data(contentsOf: inventoryRepositoriesURL)
        )
    }

    private func saveInventoryRepositories(
        _ repositories: [InventoryRepository]
    ) throws {
        guard !repositories.isEmpty else { return }
        try validateInventoryStoragePath()
        try FileManager.default.createDirectory(
            at: managedRootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let repositories = repositories.sorted {
            standardizedPath($0.gitCommonDirectory)
                .localizedStandardCompare(
                    standardizedPath($1.gitCommonDirectory)
                ) == .orderedAscending
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(repositories).write(
            to: inventoryRepositoriesURL,
            options: .atomic
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: inventoryRepositoriesURL.path
        )
    }

    private func validateInventoryStoragePath() throws {
        guard !isSymbolicLink(managedRootURL),
              !isSymbolicLink(inventoryRepositoriesURL)
        else {
            throw ManagedWorktreeServiceError.unsafeManagedPath(
                managedRootURL.path
            )
        }
    }

    private func managedCheckoutDirectories() throws -> [URL] {
        try validateInventoryStoragePath()
        guard FileManager.default.fileExists(atPath: managedRootURL.path) else {
            return []
        }
        let workspaceDirectories = try FileManager.default
            .contentsOfDirectory(
                at: managedRootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        var checkoutDirectories: [URL] = []
        for workspaceDirectory in workspaceDirectories {
            let values = try workspaceDirectory.resourceValues(
                forKeys: [.isDirectoryKey]
            )
            guard values.isDirectory == true else { continue }
            let children = try FileManager.default.contentsOfDirectory(
                at: workspaceDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in children {
                let childValues = try child.resourceValues(
                    forKeys: [.isDirectoryKey]
                )
                if childValues.isDirectory == true {
                    checkoutDirectories.append(child.standardizedFileURL)
                }
            }
        }
        return checkoutDirectories
    }

    private func workspaceOwningManagedDirectory(
        _ directoryURL: URL,
        workspaces: [Workspace]
    ) -> Workspace? {
        let workspaceDirectoryName = directoryURL
            .deletingLastPathComponent()
            .lastPathComponent
        return workspaces.first {
            $0.id.rawValue.uuidString.caseInsensitiveCompare(
                workspaceDirectoryName
            ) == .orderedSame
        }
    }

    private func inventorySort(
        _ left: ManagedWorktreeInventoryItem,
        _ right: ManagedWorktreeInventoryItem
    ) -> Bool {
        if left.repositoryName != right.repositoryName {
            return left.repositoryName.localizedStandardCompare(
                right.repositoryName
            ) == .orderedAscending
        }
        let leftBranch = left.branchName ?? ""
        let rightBranch = right.branchName ?? ""
        if leftBranch != rightBranch {
            return leftBranch.localizedStandardCompare(rightBranch)
                == .orderedAscending
        }
        return (left.directoryPath ?? "").localizedStandardCompare(
            right.directoryPath ?? ""
        ) == .orderedAscending
    }

    private func inventoryState(
        for worktree: ManagedWorktree,
        registeredDirectoryPath: String
    ) async -> (
        state: ManagedWorktreeInventoryState,
        warning: String?
    ) {
        guard worktree.state == .available else {
            return (.unavailable, nil)
        }
        guard standardizedPath(worktree.rootPath)
                == standardizedPath(registeredDirectoryPath)
        else {
            return (
                .unavailable,
                "无法验证 \(worktree.branchName) 的 Worktree："
                    + "Git 登记路径与会话记录不一致。"
            )
        }
        let rootURL = URL(
            fileURLWithPath: registeredDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        guard isManagedPath(
            rootURL,
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID
        ) else {
            return (
                .unavailable,
                "无法验证 \(worktree.branchName) 的 Worktree："
                    + "托管路径与会话所有权不一致。"
            )
        }
        do {
            try validateSessionWorkingDirectory(worktree)
            try await validateRepositoryIdentity(
                worktree,
                rootURL: rootURL
            )
            return (.tracked, nil)
        } catch {
            return (
                .unavailable,
                "无法验证 \(worktree.branchName) 的 Worktree："
                    + inventoryErrorSummary(error)
            )
        }
    }

    private func inventoryErrorSummary(_ error: Error) -> String {
        if let worktreeError = error as? ManagedWorktreeServiceError,
           case .gitFailed(let exitCode, _) = worktreeError
        {
            return "Git 退出码 \(exitCode)。"
        }
        return error.localizedDescription
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
        let actualPath = try await gitCommonDirectory(for: rootURL)
        let expectedPath = standardizedPath(worktree.gitCommonDirectory)
        guard actualPath == expectedPath else {
            throw ManagedWorktreeServiceError.repositoryIdentityMismatch(
                expected: expectedPath,
                actual: actualPath
            )
        }
    }

    private func gitCommonDirectory(
        for rootURL: URL
    ) async throws -> String {
        let commonPath = try await checkedOutput([
            "-C", rootURL.path,
            "rev-parse", "--git-common-dir",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        if commonPath.hasPrefix("/") {
            return standardizedPath(commonPath)
        }
        return URL(
            fileURLWithPath: commonPath,
            relativeTo: rootURL
        )
        .resolvingSymlinksInPath()
        .standardizedFileURL.path
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
