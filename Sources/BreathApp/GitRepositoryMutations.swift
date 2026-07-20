import Darwin
import Foundation

struct GitAuthentication: Sendable {
    var username: String
    var secret: String
    var allowHostKeyConfirmation = false
}

enum GitCommitSelection: Sendable {
    case staged
    case changelist([GitChangelistEntry])
}

struct GitCommitRequest: Sendable {
    var selection: GitCommitSelection
    var message: String
    var amend = false
    var skipHooks = false
    var sign = false
    var preCommitCommands: [String] = []
    var fixupTarget: String?
}

struct GitCommitOutcome: Equatable, Sendable {
    let objectID: String
    let warnings: [String]
}

struct GitPushPlan: Equatable, Sendable {
    let rootURL: URL
    let remote: String
    let localReference: String
    let remoteReference: String
    let baseReference: String?
    let outgoingCommits: [GitCommitSummary]
    let includeTags: Bool
    let forceWithLease: Bool
}

enum GitPullStrategy: String, CaseIterable, Codable, Sendable {
    case merge
    case rebase
}

enum GitResetMode: String, CaseIterable, Codable, Sendable {
    case soft
    case mixed
    case hard
    case keep
}

enum GitHistoryEditAction: String, Codable, Sendable {
    case pick
    case reword
    case edit
    case squash
    case fixup
    case drop
}

struct GitHistoryEditStep: Codable, Identifiable, Sendable {
    var id: String { objectID }

    var action: GitHistoryEditAction
    let objectID: String
    var subject: String
}

enum GitMutationError: LocalizedError, Equatable {
    case protectedBranch(String)
    case publishedHistory(String)
    case plainForcePushForbidden
    case invalidSelection(String)
    case partialSuccess(String)

    var errorDescription: String? {
        switch self {
        case .protectedBranch(let branch):
            "The branch \(branch) is protected by Breath."
        case .publishedHistory(let branch):
            "The branch \(branch) contains published history that Breath will not rewrite."
        case .plainForcePushForbidden:
            "Breath never performs an unleased force push."
        case .invalidSelection(let message), .partialSuccess(let message):
            message
        }
    }
}

extension GitWorkbenchService {
    static func initializeRepository(
        at directoryURL: URL,
        gitExecutableURL: URL,
        initialBranch: String = "main"
    ) async throws -> GitCommandResult {
        let runner = GitCommandRunner(executableURL: gitExecutableURL)
        let info = try await GitExecutableInspectionCache.shared.inspect(
            gitExecutableURL
        )
        let result: GitCommandResult
        if info.supportsInitialBranchOption {
            result = try await runner.run(
                arguments: [
                    "-C",
                    directoryURL.path,
                    "init",
                    "-b",
                    initialBranch,
                ]
            )
        } else {
            let initialized = try await runner.run(
                arguments: ["-C", directoryURL.path, "init"]
            )
            guard initialized.exitCode == 0 else {
                throw GitCommandError.failed(
                    command: initialized.displayCommand,
                    exitCode: initialized.exitCode,
                    output: initialized.combinedOutput
                )
            }
            result = try await runner.run(
                arguments: [
                    "-C",
                    directoryURL.path,
                    "symbolic-ref",
                    "HEAD",
                    "refs/heads/\(initialBranch)",
                ]
            )
        }
        guard result.exitCode == 0 else {
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        return result
    }

    static func cloneRepository(
        remoteURL: String,
        destinationURL: URL,
        gitExecutableURL: URL
    ) async throws -> GitCommandResult {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: destinationURL.path)
            guard contents.isEmpty else {
                throw GitMutationError.invalidSelection(
                    "Clone destination must be a new or empty directory."
                )
            }
        }
        let result = try await GitCommandRunner(executableURL: gitExecutableURL).run(
            arguments: ["clone", "--progress", remoteURL, destinationURL.path]
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

    func stage(rootURL: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["add", "--"] + paths
        )
    }

    func unstage(rootURL: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let info = try await gitExecutableInfo()
        if info.supportsSwitchAndRestore {
            _ = try await requiredGit(
                rootURL: rootURL,
                arguments: ["restore", "--staged", "--"] + paths
            )
            return
        }
        let headExists = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "rev-parse",
                "--verify",
                "HEAD",
            ]
        ).exitCode == 0
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: (
                headExists
                    ? ["reset", "HEAD", "--"]
                    : ["rm", "--cached", "--ignore-unmatch", "--"]
            ) + paths
        )
    }

    func restoreWorkingTree(rootURL: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let info = try await gitExecutableInfo()
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: (
                info.supportsSwitchAndRestore
                    ? ["restore", "--worktree", "--"]
                    : ["checkout", "--"]
            ) + paths
        )
    }

    func applyPatch(
        rootURL: URL,
        patch: String,
        cached: Bool,
        reverse: Bool = false,
        threeWay: Bool = false
    ) async throws {
        var arguments = ["apply", "--recount"]
        if cached { arguments.append("--cached") }
        if reverse { arguments.append("--reverse") }
        if threeWay { arguments.append("--3way") }
        let result = try await runner.run(
            arguments: ["-C", rootURL.path] + arguments,
            standardInput: Data(patch.utf8)
        )
        guard result.exitCode == 0 else {
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
    }

    func commit(rootURL: URL, request: GitCommitRequest) async throws -> GitCommitOutcome {
        guard request.fixupTarget != nil
            || !request.message.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw GitMutationError.invalidSelection("Commit message cannot be empty.")
        }
        try await runPreCommitCommands(
            rootURL: rootURL,
            commands: request.preCommitCommands
        )
        switch request.selection {
        case .staged:
            let result = try await runCommitCommand(
                rootURL: rootURL,
                request: request,
                environment: nil
            )
            return GitCommitOutcome(
                objectID: try await headObjectID(rootURL: rootURL),
                warnings: result.combinedOutput.isEmpty ? [] : [result.combinedOutput]
            )
        case .changelist(let entries):
            return try await commitChangelist(
                rootURL: rootURL,
                request: request,
                entries: entries
            )
        }
    }

    func createBranch(
        rootURL: URL,
        name: String,
        startPoint: String? = nil,
        checkout: Bool = false
    ) async throws {
        let supportsSwitch = try await gitExecutableInfo()
            .supportsSwitchAndRestore
        var arguments = checkout
            ? (supportsSwitch ? ["switch", "-c", name] : ["checkout", "-b", name])
            : ["branch", name]
        if let startPoint, !startPoint.isEmpty {
            arguments.append(startPoint)
        }
        _ = try await requiredGit(rootURL: rootURL, arguments: arguments)
    }

    func checkout(rootURL: URL, reference: String) async throws {
        let supportsSwitch = try await gitExecutableInfo()
            .supportsSwitchAndRestore
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: [supportsSwitch ? "switch" : "checkout", reference]
        )
    }

    func checkoutRemote(
        rootURL: URL,
        remoteBranch: String,
        localName: String
    ) async throws {
        let supportsSwitch = try await gitExecutableInfo()
            .supportsSwitchAndRestore
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: supportsSwitch
                ? ["switch", "--track", "-c", localName, remoteBranch]
                : ["checkout", "--track", "-b", localName, remoteBranch]
        )
    }

    func renameBranch(rootURL: URL, oldName: String, newName: String) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["branch", "-m", oldName, newName]
        )
    }

    func deleteBranch(
        rootURL: URL,
        name: String,
        force: Bool = false,
        protectedPatterns: [String]
    ) async throws {
        try ensureBranchIsMutable(name, protectedPatterns: protectedPatterns)
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["branch", force ? "-D" : "-d", name]
        )
    }

    func setUpstream(
        rootURL: URL,
        branch: String,
        upstream: String?
    ) async throws {
        let arguments = if let upstream {
            ["branch", "--set-upstream-to=\(upstream)", branch]
        } else {
            ["branch", "--unset-upstream", branch]
        }
        _ = try await requiredGit(rootURL: rootURL, arguments: arguments)
    }

    func setRemote(
        rootURL: URL,
        name: String,
        fetchURL: String,
        existing: Bool
    ) async throws {
        let arguments = existing
            ? ["remote", "set-url", name, fetchURL]
            : ["remote", "add", name, fetchURL]
        _ = try await requiredGit(rootURL: rootURL, arguments: arguments)
    }

    func removeRemote(rootURL: URL, name: String) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["remote", "remove", name]
        )
    }

    func deleteRemoteBranch(
        rootURL: URL,
        remote: String,
        branch: String,
        authentication: GitAuthentication? = nil
    ) async throws {
        _ = try await authenticatedGit(
            rootURL: rootURL,
            arguments: [
                "push",
                "--progress",
                remote,
                "--delete",
                branch,
            ],
            authentication: authentication
        )
    }

    func fetch(
        rootURL: URL,
        remote: String? = nil,
        authentication: GitAuthentication? = nil
    ) async throws -> GitCommandResult {
        var arguments = ["fetch", "--prune", "--progress"]
        if let remote {
            arguments.append(remote)
        } else {
            arguments.append("--all")
        }
        return try await authenticatedGit(
            rootURL: rootURL,
            arguments: arguments,
            authentication: authentication
        )
    }

    func pull(
        rootURL: URL,
        remote: String? = nil,
        branch: String? = nil,
        strategy: GitPullStrategy,
        authentication: GitAuthentication? = nil
    ) async throws -> GitCommandResult {
        var arguments = [
            "pull",
            "--progress",
            strategy == .rebase ? "--rebase" : "--no-rebase",
        ]
        if let remote { arguments.append(remote) }
        if let branch { arguments.append(branch) }
        return try await authenticatedGit(
            rootURL: rootURL,
            arguments: arguments,
            authentication: authentication
        )
    }

    func makePushPlan(
        rootURL: URL,
        remote: String,
        localReference: String,
        remoteReference: String,
        includeTags: Bool,
        forceWithLease: Bool,
        protectedPatterns: [String] = []
    ) async throws -> GitPushPlan {
        if forceWithLease {
            try ensureBranchIsMutable(
                remoteReference,
                protectedPatterns: protectedPatterns
            )
        }
        let reachable = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "merge-base",
                "--is-ancestor",
                localReference,
                "HEAD",
            ]
        )
        guard reachable.exitCode == 0 else {
            throw GitMutationError.invalidSelection(
                "The selected push cutoff is not reachable from the current branch."
            )
        }
        let remoteTrackingReference = "\(remote)/\(remoteReference)"
        let remoteReferenceExists = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "rev-parse",
                "--verify",
                "--quiet",
                remoteTrackingReference,
            ]
        ).exitCode == 0
        let page = try await log(
            rootURL: rootURL,
            limit: 1_000,
            revision: remoteReferenceExists
                ? "\(remoteTrackingReference)..\(localReference)"
                : localReference
        )
        return GitPushPlan(
            rootURL: rootURL,
            remote: remote,
            localReference: localReference,
            remoteReference: remoteReference,
            baseReference: remoteReferenceExists ? remoteTrackingReference : nil,
            outgoingCommits: page.commits,
            includeTags: includeTags,
            forceWithLease: forceWithLease
        )
    }

    func push(
        plan: GitPushPlan,
        protectedPatterns: [String],
        authentication: GitAuthentication? = nil
    ) async throws -> GitCommandResult {
        if plan.forceWithLease {
            try ensureBranchIsMutable(
                plan.remoteReference,
                protectedPatterns: protectedPatterns
            )
        }
        var arguments = [
            "push",
            "--progress",
            plan.remote,
            "\(plan.localReference):\(plan.remoteReference)",
        ]
        if plan.includeTags { arguments.append("--follow-tags") }
        if plan.forceWithLease { arguments.append("--force-with-lease") }
        guard !arguments.contains("--force") else {
            throw GitMutationError.plainForcePushForbidden
        }
        return try await authenticatedGit(
            rootURL: plan.rootURL,
            arguments: arguments,
            authentication: authentication
        )
    }

    func merge(rootURL: URL, reference: String) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["merge", "--no-edit", reference]
        )
    }

    func rebase(rootURL: URL, onto reference: String) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["rebase", reference]
        )
    }

    func interactiveRebase(
        rootURL: URL,
        onto reference: String,
        steps: [GitHistoryEditStep],
        protectedPatterns: [String]
    ) async throws {
        let branch = try await loadRootSnapshot(rootURL).branch.name
        try ensureBranchIsMutable(branch, protectedPatterns: protectedPatterns)
        if try await currentHeadIsPublished(rootURL: rootURL) {
            throw GitMutationError.publishedHistory(branch)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-rebase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let todoURL = directory.appendingPathComponent("todo")
        let editorURL = directory.appendingPathComponent("sequence-editor.sh")
        let commitEditorURL = directory.appendingPathComponent("commit-editor.sh")
        let rewordDirectory = directory.appendingPathComponent(
            "reword",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rewordDirectory,
            withIntermediateDirectories: true
        )
        let todo = steps.map {
            "\($0.action.rawValue) \($0.objectID) \($0.subject)"
        }.joined(separator: "\n") + "\n"
        try Data(todo.utf8).write(to: todoURL)
        let script = "#!/bin/sh\ncp \"$BREATH_REBASE_TODO\" \"$1\"\n"
        try Data(script.utf8).write(to: editorURL)
        let rewordMessages = steps.filter { $0.action == .reword }
        for (index, step) in rewordMessages.enumerated() {
            try Data((step.subject + "\n").utf8).write(
                to: rewordDirectory.appendingPathComponent("\(index)")
            )
        }
        let commitEditorScript = """
        #!/bin/sh
        index_file="$BREATH_REWORD_DIR/index"
        index=0
        if [ -f "$index_file" ]; then index=$(cat "$index_file"); fi
        message_file="$BREATH_REWORD_DIR/$index"
        if [ -f "$message_file" ]; then
          cp "$message_file" "$1"
          expr "$index" + 1 > "$index_file"
        fi
        """
        try Data(commitEditorScript.utf8).write(to: commitEditorURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: editorURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: commitEditorURL.path
        )
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_SEQUENCE_EDITOR"] = editorURL.path
        environment["GIT_EDITOR"] = commitEditorURL.path
        environment["BREATH_REBASE_TODO"] = todoURL.path
        environment["BREATH_REWORD_DIR"] = rewordDirectory.path
        let result = try await runner.run(
            arguments: ["-C", rootURL.path, "rebase", "-i", reference],
            environment: environment
        )
        guard result.exitCode == 0 else {
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
    }

    func fixupCurrentChanges(
        rootURL: URL,
        targetObjectID: String,
        request: GitCommitRequest,
        protectedPatterns: [String]
    ) async throws -> GitCommitOutcome {
        let branch = try await loadRootSnapshot(rootURL).branch.name
        try ensureBranchIsMutable(branch, protectedPatterns: protectedPatterns)
        let reachable = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "merge-base",
                "--is-ancestor",
                targetObjectID,
                "HEAD",
            ]
        )
        guard reachable.exitCode == 0 else {
            throw GitMutationError.invalidSelection(
                "The selected Fixup target is not reachable from the current branch."
            )
        }
        if try await commitIsPublished(
            rootURL: rootURL,
            objectID: targetObjectID
        ) {
            throw GitMutationError.publishedHistory(branch)
        }

        var fixupRequest = request
        fixupRequest.amend = false
        fixupRequest.fixupTarget = targetObjectID
        let commitOutcome = try await commit(
            rootURL: rootURL,
            request: fixupRequest
        )
        let parent = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "rev-parse",
                "--verify",
                "\(targetObjectID)^",
            ]
        )
        var arguments = [
            "-C",
            rootURL.path,
            "rebase",
            "-i",
            "--autosquash",
        ]
        if parent.exitCode == 0 {
            arguments.append(
                parent.standardOutput.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        } else {
            arguments.append("--root")
        }
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_SEQUENCE_EDITOR"] = "/usr/bin/true"
        environment["GIT_EDITOR"] = "/usr/bin/true"
        let rebase = try await runner.run(
            arguments: arguments,
            environment: environment
        )
        try requireSuccess(rebase)
        return GitCommitOutcome(
            objectID: try await headObjectID(rootURL: rootURL),
            warnings: commitOutcome.warnings
        )
    }

    func cherryPick(rootURL: URL, objectIDs: [String]) async throws {
        guard !objectIDs.isEmpty else { return }
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["cherry-pick"] + objectIDs
        )
    }

    func revert(rootURL: URL, objectIDs: [String]) async throws {
        guard !objectIDs.isEmpty else { return }
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["revert", "--no-edit"] + objectIDs
        )
    }

    func reset(
        rootURL: URL,
        objectID: String,
        mode: GitResetMode,
        protectedPatterns: [String]
    ) async throws {
        let branch = try await loadRootSnapshot(rootURL).branch.name
        try ensureBranchIsMutable(branch, protectedPatterns: protectedPatterns)
        let currentHead = try await headObjectID(rootURL: rootURL)
        if objectID != currentHead,
           try await currentHeadIsPublished(rootURL: rootURL)
        {
            throw GitMutationError.publishedHistory(branch)
        }
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["reset", "--\(mode.rawValue)", objectID]
        )
    }

    func undoLastCommit(
        rootURL: URL,
        keepIndex: Bool,
        protectedPatterns: [String]
    ) async throws {
        let branch = try await loadRootSnapshot(rootURL).branch.name
        try ensureBranchIsMutable(branch, protectedPatterns: protectedPatterns)
        if try await currentHeadIsPublished(rootURL: rootURL) {
            throw GitMutationError.publishedHistory(branch)
        }
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: [
                "reset",
                keepIndex ? "--soft" : "--mixed",
                "HEAD^",
            ]
        )
    }

    func continueSequence(rootURL: URL, kind: GitSequencedOperationKind) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: sequenceArguments(kind: kind, action: "--continue")
        )
    }

    func skipSequence(rootURL: URL, kind: GitSequencedOperationKind) async throws {
        guard kind != .merge else {
            throw GitMutationError.invalidSelection("Merge does not support Skip.")
        }
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: sequenceArguments(kind: kind, action: "--skip")
        )
    }

    func abortSequence(rootURL: URL, kind: GitSequencedOperationKind) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: sequenceArguments(kind: kind, action: "--abort")
        )
    }

    func markResolved(rootURL: URL, paths: [String]) async throws {
        try await stage(rootURL: rootURL, paths: paths)
    }

    func saveConflictResult(
        rootURL: URL,
        path: String,
        contents: String
    ) async throws {
        guard GitConflictDocument(contents: contents).blocks.isEmpty else {
            throw GitMutationError.invalidSelection(
                "Resolve every conflict block before marking the file resolved."
            )
        }
        let url = rootURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url, options: .atomic)
        try await markResolved(rootURL: rootURL, paths: [path])
    }

    func createTag(
        rootURL: URL,
        name: String,
        objectID: String = "HEAD",
        message: String? = nil,
        sign: Bool = false
    ) async throws {
        var arguments = ["tag"]
        if sign {
            arguments += [
                "-s",
                name,
                "-m",
                message ?? name,
                objectID,
            ]
        } else if let message {
            arguments += ["-a", name, "-m", message, objectID]
        } else {
            arguments += [name, objectID]
        }
        _ = try await requiredGit(rootURL: rootURL, arguments: arguments)
    }

    func deleteTag(rootURL: URL, name: String) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["tag", "-d", name]
        )
    }

    func createStash(
        rootURL: URL,
        message: String,
        includeUntracked: Bool,
        keepIndex: Bool
    ) async throws {
        var arguments = ["stash", "push", "-m", message]
        if includeUntracked { arguments.append("--include-untracked") }
        if keepIndex { arguments.append("--keep-index") }
        _ = try await requiredGit(rootURL: rootURL, arguments: arguments)
    }

    func applyStash(rootURL: URL, reference: String, pop: Bool) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["stash", pop ? "pop" : "apply", reference]
        )
    }

    func dropStash(rootURL: URL, reference: String) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["stash", "drop", reference]
        )
    }

    func updateSubmodules(rootURL: URL, initialize: Bool) async throws {
        var arguments = ["submodule", "update", "--recursive"]
        if initialize { arguments.append("--init") }
        _ = try await requiredGit(rootURL: rootURL, arguments: arguments)
    }

    func synchronizeSubmoduleURLs(rootURL: URL) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["submodule", "sync", "--recursive"]
        )
    }

    func fetchLFS(rootURL: URL, pull: Bool) async throws {
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: ["lfs", pull ? "pull" : "fetch"]
        )
    }

    private func commitChangelist(
        rootURL: URL,
        request: GitCommitRequest,
        entries: [GitChangelistEntry]
    ) async throws -> GitCommitOutcome {
        let rootEntries = entries.filter {
            URL(fileURLWithPath: $0.rootPath).standardizedFileURL
                == rootURL.standardizedFileURL
        }
        guard !rootEntries.isEmpty,
              !rootEntries.contains(where: \.needsConfirmation)
        else {
            throw GitMutationError.invalidSelection(
                "The Changelist is empty or contains changes that require confirmation."
            )
        }
        let originalStaged = try await requiredGit(
            rootURL: rootURL,
            arguments: ["diff", "--cached", "--binary"]
        ).standardOutput
        let temporaryIndexURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryIndexURL) }
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_INDEX_FILE"] = temporaryIndexURL.path

        let headExists = try await runner.run(
            arguments: ["-C", rootURL.path, "rev-parse", "--verify", "HEAD"]
        ).exitCode == 0
        let readTree = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "read-tree",
                headExists ? "HEAD" : "--empty",
            ],
            environment: environment
        )
        try requireSuccess(readTree)

        for entry in rootEntries {
            if let patch = entry.patch {
                let apply = try await runner.run(
                    arguments: [
                        "-C",
                        rootURL.path,
                        "apply",
                        "--cached",
                        "--recount",
                    ],
                    environment: environment,
                    standardInput: Data(patch.utf8)
                )
                try requireSuccess(apply)
            } else {
                let add = try await runner.run(
                    arguments: [
                        "-C",
                        rootURL.path,
                        "add",
                        "--",
                        entry.path,
                    ],
                    environment: environment
                )
                try requireSuccess(add)
            }
        }

        _ = try await runCommitCommand(
            rootURL: rootURL,
            request: request,
            environment: environment
        )
        let objectID = try await headObjectID(rootURL: rootURL)
        var warnings: [String] = []

        let resetIndex = try await runner.run(
            arguments: ["-C", rootURL.path, "read-tree", "HEAD"]
        )
        if resetIndex.exitCode != 0 {
            warnings.append(
                "Commit succeeded, but Breath could not align the real Index with the new HEAD: "
                    + resetIndex.combinedOutput
            )
        } else if !originalStaged.isEmpty {
            let restore = try await runner.run(
                arguments: [
                    "-C",
                    rootURL.path,
                    "apply",
                    "--cached",
                    "--3way",
                ],
                standardInput: Data(originalStaged.utf8)
            )
            if restore.exitCode != 0 {
                warnings.append(
                    "Commit succeeded, but some previously staged changes need review: "
                        + restore.combinedOutput
                )
            }
        }
        return GitCommitOutcome(objectID: objectID, warnings: warnings)
    }

    private func runCommitCommand(
        rootURL: URL,
        request: GitCommitRequest,
        environment: [String: String]?
    ) async throws -> GitCommandResult {
        var arguments = ["commit"]
        if let fixupTarget = request.fixupTarget {
            arguments.append("--fixup=\(fixupTarget)")
        } else {
            arguments += ["-m", request.message]
        }
        if request.amend { arguments.append("--amend") }
        if request.skipHooks { arguments.append("--no-verify") }
        if request.sign { arguments.append("-S") }
        let result = try await runner.run(
            arguments: ["-C", rootURL.path] + arguments,
            environment: environment
        )
        try requireSuccess(result)
        return result
    }

    private func runPreCommitCommands(
        rootURL: URL,
        commands: [String]
    ) async throws {
        for command in commands where !command.isEmpty {
            if let outputRecorder = GitOperationContext.outputRecorder {
                await outputRecorder("$ \(command)\n")
            }
            let result = try await ShellCommandRunner.run(
                command,
                workingDirectory: rootURL
            )
            guard result.exitCode == 0 else {
                throw GitCommandError.failed(
                    command: command,
                    exitCode: result.exitCode,
                    output: result.output
                )
            }
        }
    }

    private func headObjectID(rootURL: URL) async throws -> String {
        try await requiredGit(
            rootURL: rootURL,
            arguments: ["rev-parse", "HEAD"]
        ).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentHeadIsPublished(rootURL: URL) async throws -> Bool {
        let upstream = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "rev-parse",
                "--verify",
                "--quiet",
                "@{upstream}",
            ]
        )
        guard upstream.exitCode == 0 else { return false }
        return try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "merge-base",
                "--is-ancestor",
                "HEAD",
                "@{upstream}",
            ]
        ).exitCode == 0
    }

    private func commitIsPublished(
        rootURL: URL,
        objectID: String
    ) async throws -> Bool {
        let result = try await runner.run(
            arguments: [
                "-C",
                rootURL.path,
                "for-each-ref",
                "--format=%(refname)",
                "--contains=\(objectID)",
                "refs/remotes",
            ]
        )
        try requireSuccess(result)
        return !result.standardOutput.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private func authenticatedGit(
        rootURL: URL,
        arguments: [String],
        authentication: GitAuthentication?
    ) async throws -> GitCommandResult {
        var environment = ProcessInfo.processInfo.environment
        var askpassDirectory: URL?
        if let authentication {
            if let statusRecorder = GitOperationContext.statusRecorder {
                await statusRecorder(
                    authentication.allowHostKeyConfirmation
                        ? .waitingForConfirmation
                        : .waitingForAuthentication
                )
            }
            let prepared = try GitAskpass.prepare(authentication)
            askpassDirectory = prepared.directory
            environment.merge(prepared.environment) { _, new in new }
        }
        defer {
            if let askpassDirectory {
                try? FileManager.default.removeItem(at: askpassDirectory)
            }
        }
        let result = try await runner.run(
            arguments: ["-C", rootURL.path] + arguments,
            environment: environment
        )
        try requireSuccess(result)
        return result
    }

    private func ensureBranchIsMutable(
        _ branch: String,
        protectedPatterns: [String]
    ) throws {
        if protectedPatterns.contains(where: { GitBranchPattern($0).matches(branch) }) {
            throw GitMutationError.protectedBranch(branch)
        }
    }

    private func sequenceArguments(
        kind: GitSequencedOperationKind,
        action: String
    ) -> [String] {
        switch kind {
        case .merge: ["merge", action]
        case .rebase: ["rebase", action]
        case .cherryPick: ["cherry-pick", action]
        case .revert: ["revert", action]
        }
    }

    private func requireSuccess(_ result: GitCommandResult) throws {
        guard result.exitCode == 0 else {
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
    }

    private func gitExecutableInfo() async throws -> GitExecutableInfo {
        let info = try await GitExecutableInspectionCache.shared.inspect(
            gitExecutableURL
        )
        guard info.supportsCoreWorkbench else {
            throw GitExecutableError.unsupportedVersion(
                actual: info.version,
                minimum: GitExecutableInfo.minimumCoreVersion.displayValue
            )
        }
        return info
    }
}

private struct GitBranchPattern {
    let expression: NSRegularExpression?

    init(_ glob: String) {
        let escaped = NSRegularExpression.escapedPattern(for: glob)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        expression = try? NSRegularExpression(pattern: "^\(escaped)$")
    }

    func matches(_ branch: String) -> Bool {
        expression?.firstMatch(
            in: branch,
            range: NSRange(branch.startIndex..., in: branch)
        ) != nil
    }
}

private enum GitAskpass {
    struct Prepared {
        let directory: URL
        let environment: [String: String]
    }

    static func prepare(_ authentication: GitAuthentication) throws -> Prepared {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-askpass-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("askpass.sh")
        let script = """
        #!/bin/sh
        case "$1" in
          *authenticity*|*continue\\ connecting*)
            if [ "$BREATH_GIT_CONFIRM_HOST" = "yes" ]; then
              printf '%s' "yes"
            else
              printf '%s' "no"
            fi
            ;;
          *sername*|*login*) printf '%s' "$BREATH_GIT_USERNAME" ;;
          *) printf '%s' "$BREATH_GIT_SECRET" ;;
        esac
        """
        try Data(script.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )
        return Prepared(
            directory: directory,
            environment: [
                "GIT_ASKPASS": scriptURL.path,
                "SSH_ASKPASS": scriptURL.path,
                "SSH_ASKPASS_REQUIRE": "force",
                "GIT_TERMINAL_PROMPT": "0",
                "BREATH_GIT_USERNAME": authentication.username,
                "BREATH_GIT_SECRET": authentication.secret,
                "BREATH_GIT_CONFIRM_HOST": authentication.allowHostKeyConfirmation
                    ? "yes"
                    : "no",
                "DISPLAY": ProcessInfo.processInfo.environment["DISPLAY"] ?? ":0",
            ]
        )
    }
}

private enum ShellCommandRunner {
    struct Result {
        let exitCode: Int32
        let output: String
    }

    static func run(_ command: String, workingDirectory: URL) async throws -> Result {
        let outputRecorder = GitOperationContext.outputRecorder
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            let termination = GitProcessTermination()
            process.terminationHandler = { process in
                termination.finish(process.terminationStatus)
            }
            try process.run()
            var output = Data()
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                output.append(chunk)
                if let outputRecorder {
                    await outputRecorder(
                        String(decoding: chunk, as: UTF8.self)
                    )
                }
            }
            let exitCode = await termination.wait()
            return Result(
                exitCode: exitCode,
                output: String(decoding: output, as: UTF8.self)
            )
        }.value
    }
}
