import BreathCore
import Combine
import Foundation
import Testing
@testable import BreathApp

@Suite("Git workbench use cases", .serialized)
struct GitWorkbenchServiceTests {
    @Test("opening a workspace exposes its real root branch and changes")
    func opensRepository() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("tracked.txt", "before\n")
        try repository.run(["add", "tracked.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("tracked.txt", "after\n")
        try repository.write("untracked.txt", "new\n")

        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let workspace = try await service.loadWorkspace()

        #expect(workspace.roots.count == 1)
        #expect(workspace.roots[0].rootURL.standardizedFileURL == repository.url.standardizedFileURL)
        #expect(workspace.roots[0].branch.name == "main")
        #expect(
            workspace.roots[0].changes.map(\.path).sorted()
                == ["tracked.txt", "untracked.txt"]
        )
        #expect(
            workspace.roots[0].changes.first(where: { $0.path == "tracked.txt" })?.workingTree
                == .modified
        )
        #expect(
            workspace.roots[0].changes.first(where: { $0.path == "untracked.txt" })?.workingTree
                == .untracked
        )
    }

    @Test("checkout reports overwritten files and force checkout discards them")
    func reportsAndForcesCheckoutConflicts() async throws {
        let repository = try GitWorkbenchTestRepository()
        let spacedPath = " leading and trailing.txt "
        let unicodePath = "冲突 文件.txt"
        try repository.write("notes.txt", "base\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "base"])
        try repository.run(["switch", "-c", "feature"])
        try repository.write("notes.txt", "feature\n")
        try repository.write("collision.txt", "feature file\n")
        try repository.write(spacedPath, "spaced feature file\n")
        try repository.write(unicodePath, "unicode feature file\n")
        try repository.run([
            "add", "notes.txt", "collision.txt", spacedPath, unicodePath,
        ])
        try repository.run(["commit", "-m", "feature"])
        try repository.run(["switch", "main"])
        try repository.write("notes.txt", "local\n")
        try repository.write("collision.txt", "untracked local file\n")
        try repository.write(spacedPath, "spaced untracked local file\n")
        try repository.write(unicodePath, "unicode untracked local file\n")
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )
        let target = GitCheckoutTarget.reference("feature")
        var conflictingPaths: [String] = []

        do {
            try await service.checkout(rootURL: repository.url, target: target)
            Issue.record("Checkout should report the overwritten local file")
        } catch let conflict as GitCheckoutConflictError {
            #expect(Set(conflict.paths) == [
                "notes.txt", "collision.txt", spacedPath, unicodePath,
            ])
            conflictingPaths = conflict.paths
        }

        try await service.checkout(
            rootURL: repository.url,
            target: target,
            discardChanges: true,
            conflictingPaths: conflictingPaths
        )

        #expect(try repository.output(["branch", "--show-current"]) == "feature")
        #expect(try repository.output(["show", "HEAD:notes.txt"]) == "feature")
        #expect(try repository.read("notes.txt") == "feature\n")
        #expect(try repository.read("collision.txt") == "feature file\n")
        #expect(try repository.read(spacedPath) == "spaced feature file\n")
        #expect(try repository.read(unicodePath) == "unicode feature file\n")
    }

    @Test("Smart Checkout restores tracked, staged, and untracked changes")
    func smartCheckoutRestoresLocalChanges() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "base\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "base"])
        try repository.run(["switch", "-c", "feature"])
        try repository.write("feature.txt", "feature\n")
        try repository.run(["add", "feature.txt"])
        try repository.run(["commit", "-m", "feature"])
        try repository.run(["switch", "main"])
        try repository.write("prior.txt", "prior stash\n")
        try repository.run([
            "stash", "push", "--include-untracked", "-m", "prior",
        ])
        try repository.write("notes.txt", "local\n")
        try repository.run(["add", "notes.txt"])
        try repository.write("scratch.txt", "untracked\n")
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        try await service.smartCheckout(
            rootURL: repository.url,
            target: .reference("feature")
        )

        #expect(try repository.output(["branch", "--show-current"]) == "feature")
        #expect(try repository.read("notes.txt") == "local\n")
        #expect(try repository.read("scratch.txt") == "untracked\n")
        #expect(try repository.output(["diff", "--cached", "--name-only"]) == "notes.txt")
        let remainingStashes = try repository.output(["stash", "list"])
        #expect(remainingStashes.contains("prior"))
        #expect(!remainingStashes.contains("Breath Smart Checkout"))
    }

    @Test("Smart Checkout keeps its stash when restoring creates conflicts")
    func smartCheckoutKeepsConflictingStash() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "base\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "base"])
        try repository.run(["switch", "-c", "feature"])
        try repository.write("notes.txt", "feature\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "feature"])
        try repository.run(["switch", "main"])
        try repository.write("notes.txt", "local\n")
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        await #expect(throws: GitCommandError.self) {
            try await service.smartCheckout(
                rootURL: repository.url,
                target: .reference("feature")
            )
        }

        #expect(try repository.output(["branch", "--show-current"]) == "feature")
        #expect(try repository.output(["status", "--porcelain"]).contains("UU notes.txt"))
        #expect(
            try repository.output(["stash", "list"])
                .contains("Breath Smart Checkout")
        )
    }

    @Test("branch references omit the remote default-branch alias")
    func omitsRemoteHEADAlias() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("tracked.txt", "initial\n")
        try repository.run(["add", "tracked.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.run(["remote", "add", "origin", repository.url.path])
        try repository.run(["fetch", "origin"])
        try repository.run(["remote", "set-head", "origin", "--auto"])
        try repository.run(["remote", "add", "archive", repository.url.path])
        try repository.run(["remote", "add", "team", repository.url.path])
        try repository.run([
            "remote", "add", "team/origin", repository.url.path,
        ])
        try repository.run([
            "update-ref",
            "refs/remotes/archive/HEAD",
            "HEAD",
        ])
        try repository.run([
            "update-ref",
            "refs/remotes/team/origin/feature/deep",
            "HEAD",
        ])
        try repository.run([
            "update-ref",
            "refs/remotes/team/origin/HEAD",
            "HEAD",
        ])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let references = try await service.references(rootURL: repository.url)
        let remoteNames = try await service.remotes(rootURL: repository.url)
            .map(\.name)

        #expect(references.contains { $0.fullName == "refs/heads/main" })
        #expect(references.contains { $0.fullName == "refs/remotes/origin/main" })
        #expect(references.contains { $0.fullName == "refs/remotes/archive/HEAD" })
        #expect(
            references.contains {
                $0.fullName == "refs/remotes/team/origin/feature/deep"
            }
        )
        #expect(
            references.contains {
                $0.fullName == "refs/remotes/team/origin/HEAD"
            }
        )
        #expect(!references.contains { $0.fullName == "refs/remotes/origin/HEAD" })
        #expect(
            references.first { $0.fullName == "refs/remotes/origin/main" }?
                .remoteBranchIdentity(configuredRemoteNames: remoteNames)?
                .checkoutLocalBranchName == "main"
        )
        #expect(
            references.first { $0.fullName == "refs/remotes/archive/HEAD" }?
                .remoteBranchIdentity(configuredRemoteNames: remoteNames)?
                .checkoutLocalBranchName == "archive-HEAD"
        )
        #expect(
            references.first {
                $0.fullName == "refs/remotes/team/origin/feature/deep"
            }?.remoteBranchIdentity(configuredRemoteNames: remoteNames)
                == GitRemoteBranchIdentity(
                    fullName: "refs/remotes/team/origin/feature/deep",
                    remoteName: "team/origin",
                    branchName: "feature/deep"
                )
        )
        #expect(
            references.first {
                $0.fullName == "refs/remotes/team/origin/HEAD"
            }?.remoteBranchIdentity(configuredRemoteNames: remoteNames)?
                .checkoutLocalBranchName == "team-origin-HEAD"
        )
    }

    @Test("opening a directory without Git returns an actionable empty workspace")
    func opensEmptyWorkspace() async throws {
        let directory = try TemporaryDirectory()
        let service = GitWorkbenchService(
            workspaceURL: directory.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let workspace = try await service.loadWorkspace()

        #expect(workspace.roots.isEmpty)
        #expect(workspace.emptyState == .notRepository)
    }

    @Test("initialization and clone reject implicit or destructive destinations")
    func initializesAndClonesSafely() async throws {
        let empty = try TemporaryDirectory()
        _ = try await GitWorkbenchService.initializeRepository(
            at: empty.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )
        #expect(
            FileManager.default.fileExists(
                atPath: empty.url.appendingPathComponent(".git").path
            )
        )

        let source = try GitWorkbenchTestRepository()
        try source.write("README.md", "source\n")
        try source.run(["add", "README.md"])
        try source.run(["commit", "-m", "initial"])
        let cloneParent = try TemporaryDirectory()
        let cloneURL = cloneParent.url.appendingPathComponent(
            "clone",
            isDirectory: true
        )
        _ = try await GitWorkbenchService.cloneRepository(
            remoteURL: source.url.path,
            destinationURL: cloneURL,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )
        #expect(
            try String(
                contentsOf: cloneURL.appendingPathComponent("README.md"),
                encoding: .utf8
            ) == "source\n"
        )

        let nonEmptyURL = cloneParent.url.appendingPathComponent(
            "non-empty",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: nonEmptyURL,
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(
            to: nonEmptyURL.appendingPathComponent("keep.txt")
        )
        await #expect(throws: GitMutationError.self) {
            _ = try await GitWorkbenchService.cloneRepository(
                remoteURL: source.url.path,
                destinationURL: nonEmptyURL,
                gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
            )
        }
        #expect(
            try String(
                contentsOf: nonEmptyURL.appendingPathComponent("keep.txt"),
                encoding: .utf8
            ) == "keep"
        )
    }

    @Test("nested repositories and submodules remain distinct roots")
    func discoversNestedRootsAndSubmodules() async throws {
        let child = try GitWorkbenchTestRepository()
        try child.write("child.txt", "child\n")
        try child.run(["add", "child.txt"])
        try child.run(["commit", "-m", "child"])
        let parent = try GitWorkbenchTestRepository()
        try parent.write("parent.txt", "parent\n")
        try parent.run(["add", "parent.txt"])
        try parent.run(["commit", "-m", "parent"])
        try parent.run([
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            child.url.path,
            "modules/child",
        ])
        try parent.run(["commit", "-am", "add submodule"])
        try parent.run(["config", "protocol.file.allow", "always"])
        try parent.run(["submodule", "deinit", "-f", "modules/child"])
        let service = GitWorkbenchService(
            workspaceURL: parent.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        #expect(
            try await service.submodules(rootURL: parent.url)
                .first?.isInitialized == false
        )
        try await service.updateSubmodules(
            rootURL: parent.url,
            initialize: true
        )
        try await service.synchronizeSubmoduleURLs(rootURL: parent.url)
        let workspace = try await service.loadWorkspace()

        #expect(workspace.roots.count == 2)
        #expect(workspace.roots.filter(\.isSubmoduleRoot).count == 1)
        #expect(
            workspace.roots.first(where: \.isSubmoduleRoot)?
                .rootURL.lastPathComponent == "child"
        )
        #expect(
            try await service.submodules(rootURL: parent.url)
                .first?.isInitialized == true
        )
    }

    @Test("external filesystem changes are debounced into repository refresh signals")
    func watchesExternalRepositoryChanges() async throws {
        let repository = try GitWorkbenchTestRepository()
        let probe = ChangeProbe()
        let watcher = GitRepositoryWatcher(urls: [repository.url]) {
            Task {
                await probe.signal()
            }
        }
        #expect(watcher.watchedPaths == Set([repository.url.path]))

        try repository.write("external.txt", "one\n")
        try repository.write("external.txt", "two\n")
        for _ in 0..<30 {
            if await probe.count > 0 {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(await probe.count > 0)
    }

    @Test("Git executable inspection reports the installed version")
    func inspectsGitExecutable() async throws {
        let result = try await GitExecutableInspector.inspect(
            URL(fileURLWithPath: "/usr/bin/git")
        )

        #expect(result.executableURL.path == "/usr/bin/git")
        #expect(!result.version.isEmpty)
    }

    @Test("an invalid configured Git executable does not silently fall back")
    @MainActor
    func preservesInvalidConfiguredGitExecutable() async throws {
        let defaults = try #require(
            UserDefaults(suiteName: "GitExecutablePreferences.\(UUID())")
        )
        let store = GitPreferencesStore(
            defaults: defaults,
            key: "preferences"
        )
        var preferences = store.preferences
        preferences.gitExecutablePath = "/definitely/missing/git"
        store.preferences = preferences

        #expect(
            store.resolvedGitExecutableURL.path == "/definitely/missing/git"
        )
        await #expect(throws: (any Error).self) {
            _ = try await GitExecutableInspector.inspect(
                store.resolvedGitExecutableURL
            )
        }
    }

    @Test("Git capability inspection rejects impostors and reports old versions")
    func reportsGitCapabilities() async throws {
        await #expect(throws: GitCommandError.self) {
            _ = try await GitExecutableInspector.inspect(
                URL(fileURLWithPath: "/bin/echo")
            )
        }

        let directory = try TemporaryDirectory()
        let executable = directory.url.appendingPathComponent("old-git.sh")
        try Data(
            "#!/bin/sh\nprintf 'git version 2.10.9\\n'\n".utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        let info = try await GitExecutableInspector.inspect(executable)
        #expect(info.version == "2.10.9")
        #expect(!info.supportsCoreWorkbench)
        #expect(!info.supportsSwitchAndRestore)
        #expect(!info.supportsInitialBranchOption)

        let service = GitWorkbenchService(
            workspaceURL: directory.url,
            gitExecutableURL: executable
        )
        await #expect(throws: GitExecutableError.self) {
            _ = try await service.loadWorkspace()
        }
    }

    @Test("a Changelist commit preserves unrelated staged changes")
    func commitsChangelistWithoutDisturbingIndex() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("selected.txt", "before\n")
        try repository.write("staged.txt", "before\n")
        try repository.run(["add", "selected.txt", "staged.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("selected.txt", "selected\n")
        try repository.write("staged.txt", "staged\n")
        try repository.run(["add", "staged.txt"])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let outcome = try await service.commit(
            rootURL: repository.url,
            request: GitCommitRequest(
                selection: .changelist([
                    GitChangelistEntry(
                        rootPath: repository.url.path,
                        path: "selected.txt"
                    ),
                ]),
                message: "selected change"
            )
        )

        #expect(!outcome.objectID.isEmpty)
        #expect(try repository.output(["show", "HEAD:selected.txt"]) == "selected")
        #expect(try repository.output(["show", "HEAD:staged.txt"]) == "before")
        #expect(try repository.output(["diff", "--cached", "--", "staged.txt"]).contains("+staged"))
        #expect(try repository.output(["status", "--short"]).contains("M  staged.txt"))
        let status = try repository.output(["status", "--short"])
        #expect(!status.contains("selected.txt"))
    }

    @Test("a line-level Changelist commit consumes only the selected patch")
    func commitsSelectedLinesOnly() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "one\ntwo\nthree\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("notes.txt", "ONE\ntwo\nTHREE\n")
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )
        let diff = try await service.diff(
            rootURL: repository.url,
            source: .workingTree,
            path: "notes.txt"
        )
        let file = try #require(GitPatchDocument(patch: diff.patch).files.first)
        let hunk = try #require(file.hunks.first)
        let selectedLines = Set(
            hunk.lines.filter {
                ($0.kind == .deletion && $0.content == "one")
                    || ($0.kind == .addition && $0.content == "ONE")
            }.map(\.id)
        )
        let patch = hunk.patch(
            fileHeader: file.header,
            selectedLineIDs: selectedLines
        )

        _ = try await service.commit(
            rootURL: repository.url,
            request: GitCommitRequest(
                selection: .changelist([
                    GitChangelistEntry(
                        rootPath: repository.url.path,
                        path: "notes.txt",
                        patch: patch
                    ),
                ]),
                message: "selected line"
            )
        )

        let workingDiff = try repository.output(["diff", "--", "notes.txt"])
        #expect(try repository.output(["show", "HEAD:notes.txt"]) == "ONE\ntwo\nthree")
        #expect(workingDiff.contains("+THREE"))
        #expect(!workingDiff.contains("+ONE"))
    }

    @Test("line-level staging updates and reverses the real Git Index")
    func stagesSelectedLinesOnly() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "one\ntwo\nthree\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("notes.txt", "ONE\ntwo\nTHREE\n")
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )
        let diff = try await service.diff(
            rootURL: repository.url,
            source: .workingTree,
            path: "notes.txt"
        )
        let file = try #require(GitPatchDocument(patch: diff.patch).files.first)
        let hunk = try #require(file.hunks.first)
        let lineIDs = Set(
            hunk.lines.filter {
                ($0.kind == .deletion && $0.content == "one")
                    || ($0.kind == .addition && $0.content == "ONE")
            }.map(\.id)
        )
        let patch = hunk.patch(
            fileHeader: file.header,
            selectedLineIDs: lineIDs
        )

        try await service.applyPatch(
            rootURL: repository.url,
            patch: patch,
            cached: true
        )
        #expect(try repository.output(["show", ":notes.txt"]) == "ONE\ntwo\nthree")
        #expect(try repository.output(["diff", "--", "notes.txt"]).contains("+THREE"))

        try await service.applyPatch(
            rootURL: repository.url,
            patch: patch,
            cached: true,
            reverse: true
        )
        #expect(try repository.output(["show", ":notes.txt"]) == "one\ntwo\nthree")
    }

    @Test("bulk staging moves every scoped working-tree change into and out of the index")
    @MainActor
    func stagesAndUnstagesAllChanges() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("tracked.txt", "before\n")
        try repository.run(["add", "tracked.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("tracked.txt", "after\n")
        try repository.write("untracked.txt", "new\n")

        let storage = try TemporaryDirectory()
        let registry = GitOperationRegistry(
            store: GitConsoleStore(
                fileURL: storage.url.appendingPathComponent("console.json")
            )
        )
        let defaults = try #require(
            UserDefaults(suiteName: "GitWorkbenchServiceTests.\(UUID())")
        )
        let model = GitWorkspaceViewModel(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: repository.url.path,
                displayName: "Bulk Stage"
            ),
            operationRegistry: registry,
            preferencesStore: GitPreferencesStore(
                defaults: defaults,
                key: "preferences"
            ),
            metadataStore: GitWorkspaceMetadataStore(baseURL: storage.url)
        )
        await model.load()

        #expect(model.hasUnstagedChanges)
        model.stageAll()
        for _ in 0..<100 {
            if registry.records.count == 1,
               registry.runningCount == 0,
               model.hasStagedChanges
            {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(
            try repository.output(["diff", "--cached", "--name-only"])
                .split(separator: "\n")
                .map(String.init)
                .sorted() == ["tracked.txt", "untracked.txt"]
        )

        #expect(model.hasStagedChanges)
        model.unstageAll()
        for _ in 0..<100 {
            if registry.records.count == 2,
               registry.runningCount == 0,
               !model.hasStagedChanges
            {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(try repository.output(["diff", "--cached", "--name-only"]).isEmpty)
        #expect(try repository.output(["status", "--short"]).contains("tracked.txt"))
        #expect(try repository.output(["status", "--short"]).contains("untracked.txt"))
    }

    @Test("refreshing an unchanged staged selection keeps its Diff visible")
    @MainActor
    func keepsSelectedStagedDiffVisibleAcrossRefresh() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("tracked.txt", "before\n")
        try repository.run(["add", "tracked.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("tracked.txt", "after\n")
        try repository.run(["add", "tracked.txt"])

        let storage = try TemporaryDirectory()
        let defaults = try #require(
            UserDefaults(suiteName: "GitWorkbenchServiceTests.\(UUID())")
        )
        let model = GitWorkspaceViewModel(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: repository.url.path,
                displayName: "Stable Staged Diff"
            ),
            operationRegistry: GitOperationRegistry(
                store: GitConsoleStore(
                    fileURL: storage.url.appendingPathComponent("console.json")
                )
            ),
            preferencesStore: GitPreferencesStore(
                defaults: defaults,
                key: "preferences"
            ),
            metadataStore: GitWorkspaceMetadataStore(baseURL: storage.url)
        )
        await model.load()
        model.metadata.workflow = .staging
        let change = try #require(model.snapshot.roots.first?.changes.first)
        await model.selectChange(change, source: .staged)
        #expect(model.selectedDiff?.patch.contains("+after") == true)

        var clearedSelectedDiff = false
        let observation = model.$selectedDiff
            .dropFirst()
            .sink { diff in
                if diff == nil {
                    clearedSelectedDiff = true
                }
            }

        for _ in 0..<3 {
            await model.refresh()
        }

        withExtendedLifetime(observation) {}
        #expect(
            !clearedSelectedDiff,
            "an unchanged background refresh must not replace the visible Diff with a loading state"
        )
        #expect(model.selectedDiff?.patch.contains("+after") == true)
    }

    @Test("Diff can expand unchanged context and degrades oversized text files")
    func controlsDiffContextAndLargeFiles() async throws {
        let repository = try GitWorkbenchTestRepository()
        let original = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try repository.write("notes.txt", original)
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "initial"])
        let changed = original.replacingOccurrences(of: "line 15", with: "changed 15")
        try repository.write("notes.txt", changed)
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let folded = try await service.diff(
            rootURL: repository.url,
            source: .workingTree,
            path: "notes.txt",
            foldUnchanged: true
        )
        let expanded = try await service.diff(
            rootURL: repository.url,
            source: .workingTree,
            path: "notes.txt",
            foldUnchanged: false
        )
        #expect(!folded.patch.contains(" line 1\n"))
        #expect(expanded.patch.contains(" line 1\n"))
        #expect(expanded.patch.contains(" line 30\n"))

        try repository.write(
            "large.txt",
            String(repeating: "0123456789abcdef\n", count: 140_000)
        )
        let large = try await service.diff(
            rootURL: repository.url,
            source: .workingTree,
            path: "large.txt"
        )
        #expect(large.isTooLarge)
        #expect(large.patch.isEmpty)
        #expect(large.byteCount > 2_000_000)
    }

    @Test("parsed Diff hunk and line identities remain stable across refreshes")
    func keepsPatchSelectionStable() {
        let patch = """
        diff --git a/notes.txt b/notes.txt
        index 5626abf..f719efd 100644
        --- a/notes.txt
        +++ b/notes.txt
        @@ -1 +1 @@
        -one
        +two
        """

        let first = GitPatchDocument(patch: patch)
        let second = GitPatchDocument(patch: patch)

        #expect(first.files.first?.hunks.first?.id == second.files.first?.hunks.first?.id)
        #expect(
            first.files.first?.hunks.first?.lines.map(\.id)
                == second.files.first?.hunks.first?.lines.map(\.id)
        )
    }

    @Test("Diff document resolves commit file paths to scroll targets")
    func resolvesCommitFileScrollTargets() throws {
        let patch = """
        diff --git a/old-name.txt b/new-name.txt
        similarity index 100%
        rename from old-name.txt
        rename to new-name.txt
        --- a/old-name.txt
        +++ b/new-name.txt
        @@ -1 +1 @@
        -old
        +new
        diff --git a/deleted.txt b/deleted.txt
        deleted file mode 100644
        --- a/deleted.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -deleted
        """
        let document = GitPatchDocument(patch: patch)
        let renamed = try #require(document.files.first)
        let deleted = try #require(document.files.last)

        #expect(document.fileID(matching: "new-name.txt") == renamed.id)
        #expect(document.fileID(matching: "old-name.txt") == renamed.id)
        #expect(document.fileID(matching: "deleted.txt") == deleted.id)
        #expect(document.fileID(matching: "missing.txt") == nil)
    }

    @Test("Diff parsing abandons work cancelled by a newer selection")
    func cancelsObsoleteDiffParsing() async {
        let patch = """
        diff --git a/notes.txt b/notes.txt
        --- a/notes.txt
        +++ b/notes.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let task = Task.detached {
            try? await Task.sleep(for: .seconds(1))
            return GitPatchDocument(patch: patch)
        }

        task.cancel()
        let document = await task.value

        #expect(document.files.isEmpty)
    }

    @Test("side-by-side Diff pairs replacement lines without an empty half-width block")
    func alignsSideBySideReplacementRows() throws {
        let patch = """
        diff --git a/notes.txt b/notes.txt
        --- a/notes.txt
        +++ b/notes.txt
        @@ -1,4 +1,5 @@
         before
        -old one
        -old two
        +new one
        +new two
        +new three
         after
        """
        let hunk = try #require(
            GitPatchDocument(patch: patch).files.first?.hunks.first
        )

        let rows = GitSideBySideLayout.rows(for: hunk.lines)

        #expect(rows.count == 5)
        #expect(rows[0].oldLine?.kind == .context)
        #expect(rows[0].newLine?.kind == .context)
        #expect(rows[1].oldLine?.content == "old one")
        #expect(rows[1].newLine?.content == "new one")
        #expect(rows[2].oldLine?.content == "old two")
        #expect(rows[2].newLine?.content == "new two")
        #expect(rows[3].oldLine == nil)
        #expect(rows[3].newLine?.content == "new three")
        #expect(rows[4].oldLine?.kind == .context)
        #expect(rows[4].newLine?.kind == .context)
    }

    @Test("partial Changelist selections require confirmation when remapping is ambiguous")
    func detectsAmbiguousPatchRemapping() {
        let selected = """
        diff --git a/notes.txt b/notes.txt
        --- a/notes.txt
        +++ b/notes.txt
        @@ -1 +1 @@
        -one
        +ONE
        """
        let uniqueCurrent = selected + "\n+THREE\n"
        let ambiguousCurrent = selected + "\n-one\n+ONE\n"

        #expect(
            !GitPatchRemapper.requiresConfirmation(
                selectedPatch: selected,
                currentPatch: uniqueCurrent
            )
        )
        #expect(
            GitPatchRemapper.requiresConfirmation(
                selectedPatch: selected,
                currentPatch: ambiguousCurrent
            )
        )
    }

    @Test("the log returns real topology and commit details")
    func readsLogAndDetails() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "one\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "first"])
        try repository.write("notes.txt", "two\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "second"])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let page = try await service.log(rootURL: repository.url, limit: 10)
        let details = try await service.commitDetails(
            rootURL: repository.url,
            objectID: page.commits[0].objectID
        )

        #expect(page.commits.map(\.subject) == ["second", "first"])
        #expect(page.commits[0].parentIDs == [page.commits[1].objectID])
        #expect(details.files == [
            GitCommitFile(
                status: .modified,
                path: "notes.txt",
                originalPath: nil
            ),
        ])
    }

    @Test("commit details preserve unusual filenames and rename paths")
    func readsCommitDetailsWithUnusualFilenames() async throws {
        let repository = try GitWorkbenchTestRepository()
        let originalPath = "old\tname.txt"
        let renamedPath = "new\nname.txt"
        try repository.write(originalPath, "one\n")
        try repository.run(["add", "--", originalPath])
        try repository.run(["commit", "-m", "add unusual filename"])
        try repository.run(["mv", "--", originalPath, renamedPath])
        try repository.run(["commit", "-m", "rename unusual filename"])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let page = try await service.log(rootURL: repository.url, limit: 1)
        let details = try await service.commitDetails(
            rootURL: repository.url,
            objectID: page.commits[0].objectID
        )

        #expect(details.files == [
            GitCommitFile(
                status: .renamed,
                path: renamedPath,
                originalPath: originalPath
            ),
        ])
    }

    @Test("file history follows renames and blame reports line ownership")
    func readsFileHistoryAndBlame() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("old-name.txt", "first\nshared\n")
        try repository.run(["add", "old-name.txt"])
        try repository.run(["commit", "-m", "create old name"])
        try repository.run(["mv", "old-name.txt", "new-name.txt"])
        try repository.run(["commit", "-m", "rename file"])
        try repository.write("new-name.txt", "changed\nshared\n")
        try repository.run(["add", "new-name.txt"])
        try repository.run(["commit", "-m", "change first line"])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let history = try await service.fileHistory(
            rootURL: repository.url,
            path: "new-name.txt"
        )
        let blame = try await service.blame(
            rootURL: repository.url,
            path: "new-name.txt"
        )

        #expect(
            history.commits.map(\.subject)
                == ["change first line", "rename file", "create old name"]
        )
        #expect(blame.count == 2)
        #expect(blame[0].summary == "change first line")
        #expect(blame[1].summary == "create old name")
    }

    @Test("commit assistance reads the configured template and recent messages")
    func readsCommitAssistance() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("template.txt", "Summary\n\nDetails\n")
        try repository.run(["config", "commit.template", "template.txt"])
        try repository.write("notes.txt", "one\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "first message"])
        try repository.write("notes.txt", "two\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "second message"])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let template = try await service.commitTemplate(rootURL: repository.url)
        let messages = try await service.recentCommitMessages(
            rootURL: repository.url,
            limit: 5
        )

        #expect(template == "Summary\n\nDetails\n")
        #expect(messages.prefix(2) == ["second message", "first message"])
    }

    @Test("an outside parent root requires explicit authorization")
    func authorizesOutsideParentRoot() async throws {
        let parent = try GitWorkbenchTestRepository()
        let workspaceURL = parent.url.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let metadataDirectory = try TemporaryDirectory()
        let service = GitWorkbenchService(
            workspaceURL: workspaceURL,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git"),
            metadataStore: GitWorkspaceMetadataStore(baseURL: metadataDirectory.url)
        )

        let before = try await service.loadWorkspace()
        try await service.authorizeExternalRoot(parent.url)
        let after = try await service.loadWorkspace()

        #expect(before.roots.isEmpty)
        #expect(before.externalRootCandidates == [parent.url.standardizedFileURL])
        #expect(after.roots.map(\.rootURL) == [parent.url.standardizedFileURL])
        #expect(after.roots[0].isOutsideWorkspace)
    }

    @Test("safety snapshots restore working files without blocking Git")
    func restoresSafetySnapshot() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("draft.txt", "committed\n")
        try repository.run(["add", "draft.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("draft.txt", "important local work\n")
        let cache = try TemporaryDirectory()
        let store = GitSafetySnapshotStore(
            baseURL: cache.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let snapshot = try #require(await store.create(
            rootURL: repository.url,
            action: "reset",
            retentionWorkingDays: 5
        ))
        try repository.write("draft.txt", "lost\n")
        let comparison = try await store.comparisonDiff(
            snapshot,
            rootURL: repository.url,
            path: "draft.txt"
        )
        let comparisonDocument = GitPatchDocument(
            patch: comparison.patch
        )
        let file = try #require(comparisonDocument.files.first)
        let hunk = try #require(file.hunks.first)
        try await store.restoreFragment(
            patch: hunk.patch(fileHeader: file.header),
            rootURL: repository.url
        )

        #expect(
            try String(
                contentsOf: repository.url.appendingPathComponent("draft.txt"),
                encoding: .utf8
            ) == "important local work\n"
        )

        try repository.write("draft.txt", "lost again\n")
        try await store.restore(
            snapshot,
            rootURL: repository.url
        )

        #expect(
            try String(
                contentsOf: repository.url.appendingPathComponent("draft.txt"),
                encoding: .utf8
            ) == "important local work\n"
        )

        _ = await store.create(
            rootURL: repository.url,
            action: "disabled",
            retentionWorkingDays: 0
        )
        #expect(await store.list(rootURL: repository.url).isEmpty)
    }

    @Test("safety snapshot restore rejects paths outside the repository")
    func rejectsUnsafeSafetySnapshotPaths() async throws {
        let directory = try TemporaryDirectory()
        let rootURL = directory.url.appendingPathComponent(
            "repository",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let outsideURL = directory.url.appendingPathComponent("outside.txt")
        try Data("keep\n".utf8).write(to: outsideURL)
        let snapshotID = UUID()
        let snapshot = GitSafetySnapshot(
            id: snapshotID,
            rootPath: rootURL.standardizedFileURL.path,
            action: "tampered",
            createdAt: Date(),
            directoryName: snapshotID.uuidString,
            files: [
                GitSafetySnapshotFile(
                    path: "../outside.txt",
                    copyFileName: nil,
                    wasAbsent: true
                ),
            ],
            stagedPatchFileName: nil,
            workingPatchFileName: nil
        )
        let store = GitSafetySnapshotStore(baseURL: directory.url)

        await #expect(throws: GitMutationError.self) {
            try await store.restore(
                snapshot,
                rootURL: rootURL,
                restoreIndex: false
            )
        }
        #expect(
            try String(contentsOf: outsideURL, encoding: .utf8) == "keep\n"
        )
    }

    @Test("shelf storage rejects paths outside its workspace directory")
    func rejectsUnsafeShelfStoragePaths() async throws {
        let directory = try TemporaryDirectory()
        let workspaceURL = directory.url.appendingPathComponent(
            "workspace",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        let outsideURL = directory.url.appendingPathComponent("outside.patch")
        try Data("private\n".utf8).write(to: outsideURL)
        let store = GitWorkspaceMetadataStore(baseURL: directory.url)
        let shelf = GitShelf(
            name: "tampered",
            rootPath: workspaceURL.path,
            patchFileName: "../outside.patch"
        )

        await #expect(throws: GitMutationError.self) {
            _ = try await store.shelfPatch(
                workspaceURL: workspaceURL,
                shelf: shelf
            )
        }
        try await store.deleteShelf(
            workspaceURL: workspaceURL,
            shelf: shelf
        )
        #expect(
            try String(contentsOf: outsideURL, encoding: .utf8) == "private\n"
        )
    }

    @Test("conflict result validation rejects blocks without rejecting divider text")
    func validatesConflictResultBlocks() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "base\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "base"])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        try await service.saveConflictResult(
            rootURL: repository.url,
            path: "notes.txt",
            contents: "heading\n=======\nbody\n"
        )
        await #expect(throws: GitMutationError.self) {
            try await service.saveConflictResult(
                rootURL: repository.url,
                path: "notes.txt",
                contents: """
                <<<<<<< HEAD
                ours
                =======
                theirs
                >>>>>>> feature
                """
            )
        }
    }

    @Test("console redaction removes credentials and tokens")
    func redactsConsoleSecrets() {
        let redacted = GitSecretRedactor.redact(
            """
            https://alice:secret@example.com https://ghp_single_token@example.com
            token=abc123 Authorization: Bearer xyz
            """
        )

        #expect(!redacted.contains("alice"))
        #expect(!redacted.contains("secret"))
        #expect(!redacted.contains("ghp_single_token"))
        #expect(!redacted.contains("abc123"))
        #expect(!redacted.contains("xyz"))
        #expect(redacted.contains("•••"))
    }

    @Test("command output keeps stderr separate from machine-readable stdout")
    func separatesCommandOutputStreams() async throws {
        let result = try await GitCommandRunner(
            executableURL: URL(fileURLWithPath: "/bin/sh")
        ).run(
            arguments: [
                "-c",
                "printf 'machine-output'; printf 'warning-output' >&2",
            ]
        )

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "machine-output")
        #expect(result.standardError == "warning-output")
        #expect(result.combinedOutput.contains("machine-output"))
        #expect(result.combinedOutput.contains("warning-output"))
    }

    @Test("Askpass credentials stay process-local and are redacted from console history")
    @MainActor
    func keepsAskpassCredentialsProcessLocal() async throws {
        let directory = try TemporaryDirectory()
        let executable = directory.url.appendingPathComponent("fake-git.sh")
        let script = """
        #!/bin/sh
        username=$("$GIT_ASKPASS" "Username for remote")
        password=$("$GIT_ASKPASS" "Password for remote")
        host=$("$SSH_ASKPASS" "The authenticity of host cannot be established. Continue connecting?")
        printf 'username=%s password=%s host=%s\\n' "$username" "$password" "$host"
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        let service = GitWorkbenchService(
            workspaceURL: directory.url,
            gitExecutableURL: executable
        )
        let store = GitConsoleStore(
            fileURL: directory.url.appendingPathComponent("console.json")
        )
        let registry = GitOperationRegistry(store: store)
        let rootURL = directory.url

        let result = try await registry.run(
            workspaceURL: rootURL,
            rootURL: rootURL,
            title: "Fetch",
            isMutation: true
        ) {
            try await service.fetch(
                rootURL: rootURL,
                authentication: GitAuthentication(
                    username: "alice",
                    secret: "token-secret",
                    allowHostKeyConfirmation: true
                )
            )
        }

        #expect(result.standardOutput.contains("username=alice"))
        #expect(result.standardOutput.contains("password=token-secret"))
        #expect(result.standardOutput.contains("host=yes"))
        let record = try #require(registry.records.first)
        #expect(!record.output.contains("token-secret"))
        #expect(record.output.contains("password=•••"))
        let persisted = await store.load()
        #expect(!persisted[0].output.contains("token-secret"))
    }

    @Test("operation console captures the exact Git command output and exit code")
    @MainActor
    func capturesOperationCommandAndOutput() async throws {
        let directory = try TemporaryDirectory()
        let registry = GitOperationRegistry(
            store: GitConsoleStore(
                fileURL: directory.url.appendingPathComponent("console.json")
            )
        )
        let runner = GitCommandRunner(
            executableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        _ = try await registry.run(
            workspaceURL: directory.url,
            rootURL: directory.url,
            title: "Inspect Git",
            isMutation: false
        ) {
            try await runner.run(arguments: ["--version"])
        }

        let record = try #require(registry.records.first)
        #expect(record.command == "/usr/bin/git --version")
        #expect(record.output.contains("git version"))
        #expect(record.exitCode == 0)
        #expect(record.status == .succeeded)
    }

    @Test("console persistence is redacted and trimmed to its retention bounds")
    @MainActor
    func persistsTrimmedRedactedConsole() async throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("console.json")
        let store = GitConsoleStore(fileURL: fileURL)
        let originalPreferences = GitPreferencesStore.shared.preferences
        defer {
            GitPreferencesStore.shared.preferences = originalPreferences
        }
        var enabledPreferences = originalPreferences
        enabledPreferences.persistConsole = true
        GitPreferencesStore.shared.preferences = enabledPreferences
        let registry = GitOperationRegistry(store: store)
        let runner = GitCommandRunner(
            executableURL: URL(fileURLWithPath: "/bin/echo")
        )

        _ = try await registry.run(
            workspaceURL: directory.url,
            rootURL: directory.url,
            title: "Secret",
            isMutation: false
        ) {
            try await runner.run(arguments: ["token=secret-value"])
        }
        let reloaded = GitOperationRegistry(store: store)
        await reloaded.loadPersistedIfNeeded()
        #expect(!reloaded.records[0].output.contains("secret-value"))

        let now = Date()
        await store.save([
            GitOperationRecord(
                id: GitOperationID(),
                workspacePath: directory.url.path,
                rootPath: directory.url.path,
                title: "Interrupted",
                command: nil,
                startedAt: now,
                endedAt: nil,
                status: .running,
                exitCode: nil,
                output: "",
                isMutation: true
            ),
        ])
        let interrupted = GitOperationRegistry(store: store)
        await interrupted.loadPersistedIfNeeded()
        #expect(interrupted.records[0].status == .failed)
        #expect(interrupted.records[0].endedAt != nil)
        #expect(interrupted.records[0].output.contains("previously exited"))

        let records = (0..<510).map { index in
            GitOperationRecord(
                id: GitOperationID(),
                workspacePath: directory.url.path,
                rootPath: directory.url.path,
                title: "\(index)",
                command: nil,
                startedAt: now.addingTimeInterval(
                    index == 509 ? -8 * 24 * 60 * 60 : -Double(index)
                ),
                endedAt: now,
                status: .succeeded,
                exitCode: 0,
                output: "",
                isMutation: false
            )
        }
        await store.save(records)
        let trimmed = GitOperationRegistry(store: store)
        await trimmed.loadPersistedIfNeeded()
        #expect(trimmed.records.count == 500)
        #expect(trimmed.records.allSatisfy {
            $0.startedAt >= now.addingTimeInterval(-7 * 24 * 60 * 60)
        })
    }

    @Test("workspace layout selection filters and scroll anchors survive restart")
    @MainActor
    func persistsWorkspaceNavigationState() async throws {
        let workspace = try TemporaryDirectory()
        let storage = try TemporaryDirectory()
        let store = GitWorkspaceMetadataStore(baseURL: storage.url)
        var metadata = GitWorkspaceMetadata()
        metadata.layout.leftWidth = 333
        metadata.layout.centerWidth = 555
        metadata.layout.consoleHeight = 222
        metadata.layout.isConsoleVisible = true
        metadata.localFilter = "Sources"
        metadata.logFilter = "author:Breath"
        metadata.localScrollAnchor = "working:/root\u{0}file.swift\u{0}"
        metadata.logScrollAnchor = "/root\u{0}deadbeef"

        try await store.save(metadata, workspaceURL: workspace.url)
        let restored = await store.load(workspaceURL: workspace.url)

        #expect(restored.layout == metadata.layout)
        #expect(restored.localFilter == metadata.localFilter)
        #expect(restored.logFilter == metadata.logFilter)
        #expect(restored.localScrollAnchor == metadata.localScrollAnchor)
        #expect(restored.logScrollAnchor == metadata.logScrollAnchor)

        let suiteName = "GitDiffLayoutPreferences.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = GitPreferencesStore(
            defaults: defaults,
            key: "preferences"
        )
        preferences.setDiffLayout(.unified)
        let restoredPreferences = GitPreferencesStore(
            defaults: defaults,
            key: "preferences"
        )
        #expect(restoredPreferences.preferences.diff.layout == .unified)
        preferences.setDiffLayout(.sideBySide)
        #expect(preferences.preferences.diff.layout == .sideBySide)
    }

    @Test("successful workspace checks stream their output into the operation console")
    @MainActor
    func capturesSuccessfulWorkspaceCheckOutput() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "one\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("notes.txt", "two\n")
        try repository.run(["add", "notes.txt"])
        let storage = try TemporaryDirectory()
        let registry = GitOperationRegistry(
            store: GitConsoleStore(
                fileURL: storage.url.appendingPathComponent("console.json")
            )
        )
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        _ = try await registry.run(
            workspaceURL: repository.url,
            rootURL: repository.url,
            title: "Commit",
            isMutation: true
        ) {
            try await service.commit(
                rootURL: repository.url,
                request: GitCommitRequest(
                    selection: .staged,
                    message: "checked",
                    preCommitCommands: ["printf 'workspace-check-ok\\n'"]
                )
            )
        }

        let record = try #require(registry.records.first)
        #expect(record.output.contains("workspace-check-ok"))
        #expect(record.output.contains("printf 'workspace-check-ok"))
    }

    @Test("write operations serialize per root and run concurrently across roots")
    @MainActor
    func serializesWritesPerRoot() async throws {
        let directory = try TemporaryDirectory()
        let registry = GitOperationRegistry(
            store: GitConsoleStore(
                fileURL: directory.url.appendingPathComponent("console.json")
            )
        )
        let workspaceURL = directory.url
        let sameRootProbe = ConcurrentOperationProbe()

        async let first: Void = registry.run(
            workspaceURL: workspaceURL,
            rootURL: workspaceURL,
            title: "First",
            isMutation: true
        ) {
            await sameRootProbe.execute()
        }
        async let second: Void = registry.run(
            workspaceURL: workspaceURL,
            rootURL: workspaceURL,
            title: "Second",
            isMutation: true
        ) {
            await sameRootProbe.execute()
        }
        _ = try await (first, second)
        #expect(await sameRootProbe.maximumConcurrent == 1)

        let otherRoot = workspaceURL.appendingPathComponent(
            "other",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: otherRoot,
            withIntermediateDirectories: true
        )
        let differentRootProbe = ConcurrentOperationProbe()
        async let third: Void = registry.run(
            workspaceURL: workspaceURL,
            rootURL: workspaceURL,
            title: "Third",
            isMutation: true
        ) {
            await differentRootProbe.execute()
        }
        async let fourth: Void = registry.run(
            workspaceURL: workspaceURL,
            rootURL: otherRoot,
            title: "Fourth",
            isMutation: true
        ) {
            await differentRootProbe.execute()
        }
        _ = try await (third, fourth)
        #expect(await differentRootProbe.maximumConcurrent == 2)
    }

    @Test("termination cancels Breath read-only commands and waits for mutations")
    @MainActor
    func coordinatesTermination() async throws {
        let directory = try TemporaryDirectory()
        let registry = GitOperationRegistry(
            store: GitConsoleStore(
                fileURL: directory.url.appendingPathComponent("console.json")
            )
        )
        let slowRunner = GitCommandRunner(
            executableURL: URL(fileURLWithPath: "/bin/sh")
        )
        let readTask = Task {
            try await registry.run(
                workspaceURL: directory.url,
                rootURL: directory.url,
                title: "Read",
                isMutation: false
            ) {
                try await slowRunner.run(arguments: ["-c", "sleep 5"])
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        await registry.cancelReadOnlyOperations()
        await #expect(throws: CancellationError.self) {
            _ = try await readTask.value
        }
        #expect(registry.records.first?.status == .cancelled)

        let probe = CompletionProbe()
        let mutationTask = Task {
            try await registry.run(
                workspaceURL: directory.url,
                rootURL: directory.url,
                title: "Write",
                isMutation: true
            ) {
                try await Task.sleep(for: .milliseconds(150))
                await probe.complete()
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        await registry.clear()
        #expect(
            registry.records.contains {
                $0.title == "Write" && $0.status == .running
            }
        )
        await registry.prepareForTermination()
        _ = try await mutationTask.value
        #expect(await probe.isComplete)
    }

    @Test("a first push is reviewable and protected branches reject force-with-lease")
    func reviewsFirstPushAndProtectsBranch() async throws {
        let repository = try GitWorkbenchTestRepository()
        let remote = try TemporaryDirectory()
        try repository.run(["init", "--bare", remote.url.path])
        try repository.write("notes.txt", "one\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.run(["remote", "add", "origin", remote.url.path])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let plan = try await service.makePushPlan(
            rootURL: repository.url,
            remote: "origin",
            localReference: "main",
            remoteReference: "main",
            includeTags: false,
            forceWithLease: false
        )
        #expect(plan.baseReference == nil)
        #expect(plan.outgoingCommits.map(\.subject) == ["initial"])
        _ = try await service.push(plan: plan, protectedPatterns: ["main"])
        try repository.run(["fetch", "origin"])
        try repository.run(["switch", "-c", "remote-delete"])
        try repository.write("remote.txt", "delete me\n")
        try repository.run(["add", "remote.txt"])
        try repository.run(["commit", "-m", "remote branch"])
        try repository.run(["push", "-u", "origin", "remote-delete"])
        try await service.deleteRemoteBranch(
            rootURL: repository.url,
            remote: "origin",
            branch: "remote-delete"
        )
        #expect(
            try repository.output([
                "ls-remote",
                "--heads",
                "origin",
                "remote-delete",
            ]).isEmpty
        )
        try repository.run(["switch", "main"])

        let forcePlan = try await service.makePushPlan(
            rootURL: repository.url,
            remote: "origin",
            localReference: "main",
            remoteReference: "main",
            includeTags: false,
            forceWithLease: true
        )
        await #expect(throws: GitMutationError.protectedBranch("main")) {
            _ = try await service.makePushPlan(
                rootURL: repository.url,
                remote: "origin",
                localReference: "main",
                remoteReference: "main",
                includeTags: false,
                forceWithLease: true,
                protectedPatterns: ["main"]
            )
        }
        await #expect(throws: GitMutationError.protectedBranch("main")) {
            _ = try await service.push(
                plan: forcePlan,
                protectedPatterns: ["main"]
            )
        }
    }

    @Test("current staged changes can be fixup-squashed into an unpublished commit")
    func fixupsCurrentChangesIntoSelectedCommit() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "one\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "initial"])
        let target = try repository.output(["rev-parse", "HEAD"])
        try repository.write("notes.txt", "two\n")
        try repository.run(["add", "notes.txt"])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let outcome = try await service.fixupCurrentChanges(
            rootURL: repository.url,
            targetObjectID: target,
            request: GitCommitRequest(
                selection: .staged,
                message: ""
            ),
            protectedPatterns: []
        )

        #expect(try repository.output(["rev-list", "--count", "HEAD"]) == "1")
        #expect(try repository.output(["show", "HEAD:notes.txt"]) == "two")
        #expect(try repository.output(["log", "-1", "--format=%s"]) == "initial")
        let finalHead = try repository.output(["rev-parse", "HEAD"])
        #expect(outcome.objectID == finalHead)
    }

    @Test("interactive rebase applies controlled reword fixup and drop steps")
    func rewritesLocalHistoryInteractively() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "base\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "base"])
        let base = try repository.output(["rev-parse", "HEAD"])
        var commits: [(String, String)] = []
        for subject in ["one", "two", "three"] {
            try repository.write("notes.txt", "\(subject)\n")
            try repository.run(["add", "notes.txt"])
            try repository.run(["commit", "-m", subject])
            commits.append((
                try repository.output(["rev-parse", "HEAD"]),
                subject
            ))
        }
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        try await service.interactiveRebase(
            rootURL: repository.url,
            onto: base,
            steps: [
                GitHistoryEditStep(
                    action: .reword,
                    objectID: commits[0].0,
                    subject: "ONE"
                ),
                GitHistoryEditStep(
                    action: .fixup,
                    objectID: commits[1].0,
                    subject: commits[1].1
                ),
                GitHistoryEditStep(
                    action: .drop,
                    objectID: commits[2].0,
                    subject: commits[2].1
                ),
            ],
            protectedPatterns: []
        )

        #expect(
            try repository.output(["log", "--format=%s"])
                .components(separatedBy: "\n") == ["ONE", "base"]
        )
        #expect(try repository.output(["show", "HEAD:notes.txt"]) == "two")
    }

    @Test("standard stashes interoperate with Git while shelves stay workspace-local")
    func keepsStashesAndShelvesDistinct() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "one\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.write("notes.txt", "two\n")
        let metadataDirectory = try TemporaryDirectory()
        let store = GitWorkspaceMetadataStore(baseURL: metadataDirectory.url)
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git"),
            metadataStore: store
        )

        try await service.createStash(
            rootURL: repository.url,
            message: "from Breath",
            includeUntracked: false,
            keepIndex: false
        )
        let stashes = try await service.stashes(rootURL: repository.url)
        #expect(stashes.first?.subject.contains("from Breath") == true)
        #expect(try repository.output(["stash", "list"]).contains("from Breath"))

        try repository.write("notes.txt", "three\n")
        let patch = try await service.diff(
            rootURL: repository.url,
            source: .workingTree
        ).patch
        let shelf = try await store.createShelf(
            workspaceURL: repository.url,
            rootURL: repository.url,
            name: "local shelf",
            patch: patch
        )
        #expect(try repository.output(["stash", "list"]).components(separatedBy: "\n").count == 1)
        #expect(try await store.shelfPatch(workspaceURL: repository.url, shelf: shelf) == patch)
    }

    @Test("commit history pages and filters without blocking repository state")
    func pagesAndFiltersHistory() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "0\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "seed"])
        for index in 1...35 {
            try repository.write("notes.txt", "\(index)\n")
            try repository.run(["add", "notes.txt"])
            try repository.run(["commit", "-m", index == 23 ? "needle commit" : "commit \(index)"])
        }
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let firstPage = try await service.log(
            rootURL: repository.url,
            limit: 20
        )
        let secondPage = try await service.log(
            rootURL: repository.url,
            skip: 20,
            limit: 20
        )
        let filtered = try await service.log(
            rootURL: repository.url,
            limit: 20,
            query: "needle"
        )

        #expect(firstPage.commits.count == 20)
        #expect(firstPage.hasMore)
        #expect(secondPage.commits.count == 16)
        #expect(!secondPage.hasMore)
        #expect(filtered.commits.map(\.subject) == ["needle commit"])
    }

    @Test("multi-root commit preserves successful roots when another root fails")
    @MainActor
    func commitsMultipleRootsWithPartialSuccess() async throws {
        let workspaceDirectory = try TemporaryDirectory()
        let goodURL = workspaceDirectory.url.appendingPathComponent(
            "good",
            isDirectory: true
        )
        let badURL = workspaceDirectory.url.appendingPathComponent(
            "bad",
            isDirectory: true
        )
        let good = try GitWorkbenchTestRepository(at: goodURL)
        let bad = try GitWorkbenchTestRepository(at: badURL)
        for repository in [good, bad] {
            try repository.write("notes.txt", "one\n")
            try repository.run(["add", "notes.txt"])
            try repository.run(["commit", "-m", "initial"])
            try repository.write("notes.txt", "two\n")
            try repository.run(["add", "notes.txt"])
        }
        let storage = try TemporaryDirectory()
        let registry = GitOperationRegistry(
            store: GitConsoleStore(
                fileURL: storage.url.appendingPathComponent("console.json")
            )
        )
        let defaults = try #require(
            UserDefaults(suiteName: "GitWorkbenchServiceTests.\(UUID())")
        )
        let preferences = GitPreferencesStore(
            defaults: defaults,
            key: "preferences"
        )
        let model = GitWorkspaceViewModel(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: workspaceDirectory.url.path,
                displayName: "Multi Root"
            ),
            operationRegistry: registry,
            preferencesStore: preferences,
            metadataStore: GitWorkspaceMetadataStore(baseURL: storage.url)
        )
        await model.load()
        model.selectRoot(nil)
        model.setWorkflow(.staging)
        model.currentCommitDraft = "multi-root"
        model.metadata.preCommitCommands = [
            #"test "$(basename "$PWD")" != "bad""#,
        ]

        model.commit()
        for _ in 0..<100 {
            if registry.records.count == 2, registry.runningCount == 0 {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(try good.output(["log", "-1", "--format=%s"]) == "multi-root")
        #expect(try bad.output(["log", "-1", "--format=%s"]) == "initial")
        #expect(try good.output(["show", "HEAD:notes.txt"]) == "two")
        #expect(try bad.output(["diff", "--cached"]).contains("+two"))
        #expect(model.errorMessage?.contains("bad") == true)
    }

    @Test("multi-root checkout offers Smart resolution for conflicting roots")
    @MainActor
    func synchronizedCheckoutResolvesOnlyConflictingRoots() async throws {
        let workspaceDirectory = try TemporaryDirectory()
        let clean = try GitWorkbenchTestRepository(
            at: workspaceDirectory.url.appendingPathComponent(
                "clean",
                isDirectory: true
            )
        )
        let conflicted = try GitWorkbenchTestRepository(
            at: workspaceDirectory.url.appendingPathComponent(
                "conflicted",
                isDirectory: true
            )
        )
        for repository in [clean, conflicted] {
            try repository.write("notes.txt", "one\nmiddle\nlast\n")
            try repository.run(["add", "notes.txt"])
            try repository.run(["commit", "-m", "initial"])
            try repository.run(["switch", "-c", "feature"])
            try repository.write("notes.txt", "feature\nmiddle\nlast\n")
            try repository.run(["add", "notes.txt"])
            try repository.run(["commit", "-m", "feature"])
            try repository.run(["switch", "main"])
        }
        try conflicted.write("notes.txt", "one\nmiddle\nlocal\n")

        let storage = try TemporaryDirectory()
        let registry = GitOperationRegistry(
            store: GitConsoleStore(
                fileURL: storage.url.appendingPathComponent("console.json")
            )
        )
        let defaults = try #require(
            UserDefaults(suiteName: "GitWorkbenchServiceTests.\(UUID())")
        )
        let model = GitWorkspaceViewModel(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: workspaceDirectory.url.path,
                displayName: "Multi Root Checkout"
            ),
            operationRegistry: registry,
            preferencesStore: GitPreferencesStore(
                defaults: defaults,
                key: "preferences"
            ),
            metadataStore: GitWorkspaceMetadataStore(baseURL: storage.url)
        )
        await model.load()
        model.selectRoot(nil)
        model.metadata.synchronizeMultiRootOperations = true

        model.synchronizeCheckout(reference: "feature")
        for _ in 0..<100 {
            if registry.runningCount == 0, model.checkoutConflict != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let request = try #require(model.checkoutConflict)
        #expect(request.synchronizesRoots)
        #expect(request.rootConflicts.map(\.root.rootURL.lastPathComponent) == [
            "conflicted",
        ])
        #expect(request.rootConflicts.first?.paths == ["notes.txt"])
        #expect(try clean.output(["branch", "--show-current"]) == "feature")
        #expect(try conflicted.output(["branch", "--show-current"]) == "main")

        model.resolveCheckoutConflict(request, using: .smart)
        for _ in 0..<100 {
            if registry.records.count >= 3,
               registry.runningCount == 0,
               try conflicted.output(["branch", "--show-current"]) == "feature"
            {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(model.checkoutConflict == nil)
        #expect(try clean.output(["branch", "--show-current"]) == "feature")
        #expect(try conflicted.output(["branch", "--show-current"]) == "feature")
        #expect(try conflicted.read("notes.txt") == "feature\nmiddle\nlocal\n")
    }

    @Test("successful Commit and Push opens push review without an error alert")
    @MainActor
    func successfulCommitAndPushDoesNotTreatGitOutputAsFailure() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "seed\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "seed"])
        try repository.write("notes.txt", "ready\n")
        try repository.run(["add", "notes.txt"])
        let storage = try TemporaryDirectory()
        let registry = GitOperationRegistry(
            store: GitConsoleStore(
                fileURL: storage.url.appendingPathComponent("console.json")
            )
        )
        let defaults = try #require(
            UserDefaults(suiteName: "GitWorkbenchServiceTests.\(UUID())")
        )
        let model = GitWorkspaceViewModel(
            workspace: Workspace(
                id: WorkspaceID(rawValue: UUID()),
                path: repository.url.path,
                displayName: "Commit and Push"
            ),
            operationRegistry: registry,
            preferencesStore: GitPreferencesStore(
                defaults: defaults,
                key: "preferences"
            ),
            metadataStore: GitWorkspaceMetadataStore(baseURL: storage.url)
        )
        await model.load()
        model.setWorkflow(.staging)
        model.currentCommitDraft = "ready to push"

        model.commit(pushAfter: true)
        for _ in 0..<100 {
            if model.shouldPresentPushReview || model.errorMessage != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(model.errorMessage == nil)
        #expect(model.shouldPresentPushReview)
        #expect(registry.records.first?.output.contains("ready to push") == true)
        #expect(
            try repository.output(["log", "-1", "--format=%s"])
                == "ready to push"
        )
    }

    @Test("merge conflicts are rediscovered and cannot continue with conflict markers")
    func resolvesMergeConflict() async throws {
        let repository = try GitWorkbenchTestRepository()
        try repository.write("notes.txt", "shared\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "initial"])
        try repository.run(["switch", "-c", "feature"])
        try repository.write("notes.txt", "feature\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "feature"])
        try repository.run(["switch", "main"])
        try repository.write("notes.txt", "main\n")
        try repository.run(["add", "notes.txt"])
        try repository.run(["commit", "-m", "main"])
        try repository.runExpectingFailure(["merge", "feature"])
        let service = GitWorkbenchService(
            workspaceURL: repository.url,
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        )

        let operation = try #require(
            try await service.sequencedOperation(rootURL: repository.url)
        )
        let conflict = try await service.conflictFile(
            rootURL: repository.url,
            path: "notes.txt"
        )

        #expect(operation.kind == .merge)
        #expect(operation.conflictedPaths == ["notes.txt"])
        #expect(!operation.canContinue)
        await #expect(throws: GitMutationError.self) {
            try await service.saveConflictResult(
                rootURL: repository.url,
                path: "notes.txt",
                contents: conflict.result
            )
        }
        try await service.saveConflictResult(
            rootURL: repository.url,
            path: "notes.txt",
            contents: conflict.ours
        )
        #expect(
            try await service.sequencedOperation(rootURL: repository.url)?
                .canContinue == true
        )
        try await service.abortSequence(rootURL: repository.url, kind: .merge)
        #expect(try await service.sequencedOperation(rootURL: repository.url) == nil)
    }
}

private actor ConcurrentOperationProbe {
    private var concurrent = 0
    private(set) var maximumConcurrent = 0

    func execute() async {
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        try? await Task.sleep(for: .milliseconds(100))
        concurrent -= 1
    }
}

private actor CompletionProbe {
    private(set) var isComplete = false

    func complete() {
        isComplete = true
    }
}

private actor ChangeProbe {
    private(set) var count = 0

    func signal() {
        count += 1
    }
}

private struct GitWorkbenchTestRepository {
    let url: URL

    init() throws {
        try self.init(
            at: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    }

    init(at url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try run(["init", "-b", "main"])
        try run(["config", "user.name", "Breath Tests"])
        try run(["config", "user.email", "breath@example.com"])
    }

    func write(_ path: String, _ contents: String) throws {
        try Data(contents.utf8).write(to: url.appendingPathComponent(path))
    }

    func read(_ path: String) throws -> String {
        String(
            decoding: try Data(contentsOf: url.appendingPathComponent(path)),
            as: UTF8.self
        )
    }

    func run(_ arguments: [String]) throws {
        _ = try output(arguments)
    }

    func runExpectingFailure(_ arguments: [String]) throws {
        do {
            _ = try output(arguments)
            throw GitWorkbenchTestError.commandUnexpectedlySucceeded
        } catch GitWorkbenchTestError.commandFailed {
            return
        }
    }

    func output(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path] + arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitWorkbenchTestError.commandFailed(
                String(decoding: data, as: UTF8.self)
            )
        }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private enum GitWorkbenchTestError: Error {
    case commandFailed(String)
    case commandUnexpectedlySucceeded
}
