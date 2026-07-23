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
    case unsupportedRepository(String)
    case managedPathAlreadyExists(String)
    case unsafeManagedPath(String)
    case gitFailed(exitCode: Int32, output: String)
    case incompleteCheckout(String)
    case worktreeContainsChanges
    case worktreeContainsUnprotectedCommits
    case worktreeLocked(String?)

    var errorDescription: String? {
        switch self {
        case .invalidBranchName(let branchName):
            return "“\(branchName)”不是有效的 Git 分支名称。"
        case .unsupportedRepository(let reason):
            return reason
        case .managedPathAlreadyExists(let path):
            return "Worktree 托管目录已经存在：\(path)"
        case .unsafeManagedPath(let path):
            return "拒绝操作不属于 Breath 的 Worktree 路径：\(path)"
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

    func create(
        workspace: Workspace,
        workSessionID: WorkSessionID,
        branchName: String
    ) async throws -> ManagedWorktree {
        await operationGate.acquire()
        do {
            let worktree = try await createWithoutAcquiringGate(
                workspace: workspace,
                workSessionID: workSessionID,
                branchName: branchName
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
        branchName: String
    ) async throws -> ManagedWorktree {
        let normalizedBranchName = branchName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        try await validateBranchName(normalizedBranchName)
        let context = try await repositoryContext(for: workspace)
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
        try prepareManagedDirectories(
            for: rootURL,
            checkoutHooksURL: checkoutHooksURL
        )
        defer {
            try? FileManager.default.removeItem(at: checkoutHooksURL)
        }
        let branchReference = "refs/heads/\(normalizedBranchName)"
        let branchExists = await commandSucceeds([
            "-C", context.repositoryRoot.path,
            "show-ref", "--verify", "--quiet", branchReference,
        ])
        let baselineReference = branchExists
            ? "\(branchReference)^{commit}"
            : "HEAD^{commit}"
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
        arguments.append(contentsOf: ["worktree", "add"])
        if branchExists {
            arguments.append(contentsOf: [rootURL.path, normalizedBranchName])
        } else {
            arguments.append(contentsOf: [
                "--no-track",
                "-b", normalizedBranchName,
                rootURL.path,
                baselineCommit,
            ])
        }

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_LFS_SKIP_SMUDGE"] = "1"
        do {
            _ = try await checkedResult(
                arguments,
                environment: environment
            )
        } catch {
            try? removeEmptyManagedAncestors(startingAt: rootURL)
            throw error
        }

        let worktree = ManagedWorktree(
            workspaceID: workspace.id,
            workSessionID: workSessionID,
            rootPath: rootURL.path,
            gitCommonDirectory: context.gitCommonDirectory.path,
            baselineCommit: baselineCommit,
            workspaceRelativePath: context.workspaceRelativePath,
            branchName: normalizedBranchName
        )
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: worktree.workingDirectory,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            try? await removeCreatedWorktree(worktree)
            throw ManagedWorktreeServiceError.incompleteCheckout(
                worktree.workingDirectory
            )
        }
        return worktree
    }

    func isAvailable(_ worktree: ManagedWorktree) async -> Bool {
        guard isManagedPath(
            URL(fileURLWithPath: worktree.rootPath, isDirectory: true),
            workspaceID: worktree.workspaceID,
            workSessionID: worktree.workSessionID
        ),
              FileManager.default.fileExists(atPath: worktree.workingDirectory),
              FileManager.default.fileExists(atPath: worktree.gitCommonDirectory)
        else {
            return false
        }
        guard let result = try? await runner.run(arguments: [
            "--git-dir=\(worktree.gitCommonDirectory)",
            "worktree", "list", "--porcelain",
        ]), result.exitCode == 0 else {
            return false
        }
        let expectedPath = URL(
            fileURLWithPath: worktree.rootPath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL.path
        return result.standardOutput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                let prefix = "worktree "
                guard line.hasPrefix(prefix) else { return nil }
                return String(line.dropFirst(prefix.count))
            }
            .contains { path in
                URL(fileURLWithPath: path, isDirectory: true)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
                    .path == expectedPath
            }
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
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        _ = try await checkedResult([
            "--git-dir=\(worktree.gitCommonDirectory)",
            "worktree", "remove", rootURL.path,
        ])
        try removeEmptyManagedAncestors(startingAt: rootURL)
    }

    private func worktreeLock(
        _ worktree: ManagedWorktree,
        rootURL: URL
    ) async throws -> WorktreeLock {
        let output = try await checkedOutput([
            "--git-dir=\(worktree.gitCommonDirectory)",
            "worktree", "list", "--porcelain",
        ])
        let expectedPath = rootURL.resolvingSymlinksInPath()
            .standardizedFileURL.path
        var isTarget = false
        for line in output.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            if line.hasPrefix("worktree ") {
                let path = String(line.dropFirst("worktree ".count))
                isTarget = URL(fileURLWithPath: path, isDirectory: true)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL.path == expectedPath
            } else if isTarget, line == "locked" {
                return .locked(nil)
            } else if isTarget, line.hasPrefix("locked ") {
                return .locked(String(line.dropFirst("locked ".count)))
            } else if line.isEmpty {
                isTarget = false
            }
        }
        return .unlocked
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
        try FileManager.default.createDirectory(
            at: worktreeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
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
