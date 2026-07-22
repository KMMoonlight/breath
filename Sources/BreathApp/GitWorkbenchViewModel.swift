import AppKit
import BreathCore
import Combine
import Foundation
import SwiftUI

@MainActor
final class GitWorkbenchCoordinator: ObservableObject {
    let operationRegistry: GitOperationRegistry

    private var workspaceModels: [WorkspaceID: GitWorkspaceViewModel] = [:]
    private var registryObservation: AnyCancellable?

    init(operationRegistry: GitOperationRegistry = .shared) {
        self.operationRegistry = operationRegistry
        registryObservation = operationRegistry.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var runningCount: Int { operationRegistry.runningCount }
    var failedCount: Int { operationRegistry.failedCount }

    var attentionWorkspacePath: String? {
        attentionOperation?.workspacePath
    }

    var attentionOperation: GitOperationRecord? {
        operationRegistry.records.first(where: { $0.status == .failed })
            ?? operationRegistry.records.first(where: {
                [.waiting, .running, .waitingForAuthentication, .waitingForConfirmation]
                    .contains($0.status)
            })
    }

    func model(for workspace: Workspace) -> GitWorkspaceViewModel {
        if let model = workspaceModels[workspace.id] {
            return model
        }
        let model = GitWorkspaceViewModel(
            workspace: workspace,
            operationRegistry: operationRegistry
        )
        workspaceModels[workspace.id] = model
        return model
    }

    func workspaceModel(for path: String) -> GitWorkspaceViewModel? {
        workspaceModels.values.first {
            $0.workspace.path == path
        }
    }
}

struct GitCheckoutRootConflict: Equatable, Sendable {
    let root: GitRootSnapshot
    let paths: [String]
}

struct GitCheckoutConflictRequest: Equatable, Identifiable, Sendable {
    var id: String {
        reference.id + (updatesAfterCheckout ? "\u{0}update" : "\u{0}checkout")
    }

    let reference: GitReference
    let rootConflicts: [GitCheckoutRootConflict]
    let synchronizesRoots: Bool
    let updatesAfterCheckout: Bool
    let pullStrategy: GitPullStrategy
}

private enum GitSynchronizedCheckoutOutcome: Sendable {
    case success
    case conflict(GitCheckoutRootConflict)
    case failure(String)
}

@MainActor
final class GitWorkspaceViewModel: ObservableObject {
    let workspace: Workspace

    @Published private(set) var snapshot: GitWorkspaceSnapshot
    @Published var metadata: GitWorkspaceMetadata
    @Published var selectedRootID: GitRootID?
    @Published private(set) var references: [GitReference] = []
    @Published private(set) var remotes: [GitRemote] = []
    @Published private(set) var commits: [GitCommitSummary] = []
    @Published private(set) var hasMoreCommits = false
    @Published var selectedChangeID: String?
    @Published var selectedChangeListID: String?
    @Published private(set) var selectedChangeSource: GitDiffSource?
    @Published var selectedCommitID: String?
    @Published var selectedCommitIDs: Set<String> = []
    @Published private(set) var selectedDiff: GitFileDiff?
    @Published private(set) var selectedCommitDetails: GitCommitDetails?
    @Published private(set) var sequencedOperation: GitSequencedOperation?
    @Published private(set) var stashes: [GitStashEntry] = []
    @Published private(set) var submodules: [GitSubmoduleState] = []
    @Published private(set) var lfsCapability = GitLFSCapability(
        isInstalled: false,
        version: nil
    )
    @Published private(set) var lfsLocks: [GitLFSLock] = []
    @Published private(set) var selectedLFSFileInfo: GitLFSFileInfo?
    @Published private(set) var safetySnapshots: [GitSafetySnapshot] = []
    @Published private(set) var fileHistory: [GitCommitSummary] = []
    @Published private(set) var blameLines: [GitBlameLine] = []
    @Published private(set) var commitTemplate: String?
    @Published private(set) var recentCommitMessages: [String] = []
    @Published private(set) var pushPlan: GitPushPlan?
    @Published private(set) var pushPreviewDiff: GitFileDiff?
    @Published var shouldPresentPushReview = false
    @Published var shouldFocusCommitMessage = false
    @Published var conflictFile: GitConflictFile?
    @Published var conflictRootID: GitRootID?
    @Published var conflictResult = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingSelectedDetail = false
    @Published var errorMessage: String?
    @Published var errorGuidanceKey: String?
    @Published private(set) var checkoutConflict: GitCheckoutConflictRequest?
    @Published var authenticationUsername = ""
    @Published var authenticationSecret = ""
    @Published var authenticationConfirmHostKey = false
    @Published var highlightedOperationID: GitOperationID?
    @Published var editableFileContents = ""
    @Published var editableHeadContents = ""
    @Published var editableLocalContents = ""
    @Published var editableFilePath: String?
    @Published var editableRootID: GitRootID?
    @Published var isEditingStagedFile = false

    let operationRegistry: GitOperationRegistry
    let preferencesStore: GitPreferencesStore

    private let metadataStore: GitWorkspaceMetadataStore
    private var service: GitWorkbenchService
    private var snapshotStore: GitSafetySnapshotStore
    private var refreshTask: Task<Void, Never>?
    private var autoFetchTask: Task<Void, Never>?
    private var repositoryWatcher: GitRepositoryWatcher?
    private var fileHistoryTask: Task<Void, Never>?
    private var blameTask: Task<Void, Never>?
    private var metadataSaveTask: Task<Bool, Never>?
    private var isActive = false
    private var loadedCommitCount = 200
    private var fetchingRootIDs: Set<GitRootID> = []
    private var commitSelectionOrder: [String] = []
    private var rootDataLoadGeneration = 0
    private var logLoadGeneration = 0

    init(
        workspace: Workspace,
        operationRegistry: GitOperationRegistry = .shared,
        preferencesStore: GitPreferencesStore = .shared,
        metadataStore: GitWorkspaceMetadataStore = GitWorkspaceMetadataStore()
    ) {
        self.workspace = workspace
        self.operationRegistry = operationRegistry
        self.preferencesStore = preferencesStore
        self.metadataStore = metadataStore
        let workspaceURL = URL(fileURLWithPath: workspace.path, isDirectory: true)
        snapshot = GitWorkspaceSnapshot(workspaceURL: workspaceURL, roots: [])
        metadata = GitWorkspaceMetadata()
        let executableURL = preferencesStore.resolvedGitExecutableURL
        service = GitWorkbenchService(
            workspaceURL: workspaceURL,
            gitExecutableURL: executableURL,
            metadataStore: metadataStore
        )
        snapshotStore = GitSafetySnapshotStore(
            gitExecutableURL: executableURL
        )
    }

    var workspaceURL: URL {
        URL(fileURLWithPath: workspace.path, isDirectory: true).standardizedFileURL
    }

    var selectedRoot: GitRootSnapshot? {
        if let selectedRootID {
            return snapshot.roots.first { $0.id == selectedRootID }
        }
        return snapshot.roots.count == 1 ? snapshot.roots.first : nil
    }

    var visibleChanges: [GitLocalChange] {
        let query = metadata.localFilter.trimmingCharacters(in: .whitespaces)
        let source = changesInSelectedScope
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    var hasUnstagedChanges: Bool {
        changesInSelectedScope.contains { $0.workingTree != nil }
    }

    var hasStagedChanges: Bool {
        changesInSelectedScope.contains { $0.index != nil }
    }

    private var changesInSelectedScope: [GitLocalChange] {
        selectedRoot?.changes ?? snapshot.roots.flatMap(\.changes)
    }

    var currentCommitDraft: String {
        get {
            let key = commitDraftKey
            return metadata.commitDrafts[key, default: ""]
        }
        set {
            metadata.commitDrafts[commitDraftKey] = newValue
            persistMetadata()
            objectWillChange.send()
        }
    }

    var defaultChangelist: GitChangelist? {
        guard let id = metadata.defaultChangelistID else {
            return metadata.changelists.first
        }
        return metadata.changelists.first { $0.id == id }
    }

    var consoleRecords: [GitOperationRecord] {
        operationRegistry.records(workspacePath: workspaceURL.path)
    }

    var focusedChangeForAction: GitLocalChange? {
        selectedChange
    }

    var focusedCommitForAction: GitCommitSummary? {
        guard let selectedCommitID else { return nil }
        return commits.first { $0.id == selectedCommitID }
    }

    func activate() {
        isActive = true
        refreshServiceConfigurationIfNeeded()
        if snapshot.roots.isEmpty && !isLoading {
            Task { await load() }
        }
        startRefreshLoop()
        startAutoFetchLoop()
    }

    func deactivate() {
        isActive = false
        fileHistoryTask?.cancel()
        blameTask?.cancel()
        persistMetadata()
    }

    func applyGlobalPreferencesChange(
        from previous: GitGlobalPreferences,
        to current: GitGlobalPreferences
    ) {
        if previous.autoFetchMinutes != current.autoFetchMinutes {
            startAutoFetchLoop()
        }
        if previous.gitExecutablePath != current.gitExecutablePath {
            refreshServiceConfigurationIfNeeded()
            Task { await load() }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            await operationRegistry.loadPersistedIfNeeded()
            metadata = await metadataStore.load(workspaceURL: workspaceURL)
            snapshot = try await service.loadWorkspace()
            selectedRootID = resolvedSelectedRootID()
            configureRepositoryWatcher()
            await reconcileChangelistEntries()
            await loadSelectedRootData()
            await restoreDetailSelection()
        } catch {
            present(error)
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let previousHeads = Dictionary(
                uniqueKeysWithValues: snapshot.roots.map {
                    ($0.id, $0.branch.headOID)
                }
            )
            snapshot = try await service.loadWorkspace()
            configureRepositoryWatcher()
            await reconcileChangelistEntries()
            if selectedRootID != nil,
               !snapshot.roots.contains(where: { $0.id == selectedRootID })
            {
                selectedRootID = resolvedSelectedRootID()
            }
            let headsChanged = snapshot.roots.contains {
                previousHeads[$0.id] != $0.branch.headOID
            }
            await loadSelectedRootData(reloadLog: headsChanged)
            if let selectedChange {
                await refreshSelectedChangeDetail(selectedChange)
            }
        } catch {
            present(error)
        }
    }

    func authorizeExternalRoot(_ rootURL: URL) {
        metadata.authorizedExternalRootPaths.insert(
            rootURL.standardizedFileURL.path
        )
        let saveTask = persistMetadata()
        Task {
            if await saveTask.value {
                await refresh()
            }
        }
    }

    func selectRoot(_ id: GitRootID?) {
        selectedRootID = id
        metadata.selectedRootPath = id?.rawValue
        selectedChangeID = nil
        selectedChangeListID = nil
        selectedChangeSource = nil
        selectedCommitID = nil
        selectedCommitIDs = []
        commitSelectionOrder = []
        selectedDiff = nil
        selectedCommitDetails = nil
        isLoadingSelectedDetail = false
        persistMetadata()
        Task { await loadSelectedRootData() }
    }

    func selectChange(
        _ change: GitLocalChange,
        source requestedSource: GitDiffSource? = nil
    ) async {
        guard let root = root(containing: change) else { return }
        let source = requestedSource
            ?? selectedChangeSource
            ?? (
                metadata.workflow == .staging
                    && change.index != nil
                    && change.workingTree == nil
                    ? .staged
                    : .workingTree
            )
        selectedChangeID = change.id
        selectedCommitID = nil
        selectedCommitDetails = nil
        selectedDiff = nil
        selectedLFSFileInfo = nil
        selectedChangeSource = source
        isLoadingSelectedDetail = true
        defer {
            if selectedChangeID == change.id, selectedCommitID == nil {
                isLoadingSelectedDetail = false
            }
        }
        metadata.selectedLocalPath = change.path
        metadata.lastDetailSelection = "change"
        persistMetadata()
        do {
            let detail = try await loadChangeDetail(
                change,
                root: root,
                source: source
            )
            guard selectedChangeID == change.id,
                  selectedChangeSource == source
            else {
                return
            }
            selectedDiff = detail.diff
            selectedLFSFileInfo = detail.lfsInfo
        } catch {
            guard selectedChangeID == change.id, selectedCommitID == nil else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSelectedChangeDetail(_ change: GitLocalChange) async {
        guard let root = root(containing: change) else { return }
        let source = selectedChangeSource
            ?? (
                metadata.workflow == .staging
                    && change.index != nil
                    && change.workingTree == nil
                    ? .staged
                    : .workingTree
            )
        do {
            let detail = try await loadChangeDetail(
                change,
                root: root,
                source: source
            )
            guard selectedChangeID == change.id,
                  selectedCommitID == nil,
                  selectedChangeSource == source
            else {
                return
            }
            if selectedDiff != detail.diff {
                selectedDiff = detail.diff
            }
            if selectedLFSFileInfo != detail.lfsInfo {
                selectedLFSFileInfo = detail.lfsInfo
            }
        } catch {
            guard selectedChangeID == change.id, selectedCommitID == nil else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func loadChangeDetail(
        _ change: GitLocalChange,
        root: GitRootSnapshot,
        source: GitDiffSource
    ) async throws -> (diff: GitFileDiff, lfsInfo: GitLFSFileInfo?) {
        async let loadedDiff = service.diff(
            rootURL: root.rootURL,
            source: source,
            path: change.path,
            ignoreWhitespace: preferencesStore.preferences.diff.ignoreWhitespace,
            foldUnchanged: preferencesStore.preferences.diff.foldUnchanged
        )
        async let loadedLFS = service.lfsFileInfo(
            rootURL: root.rootURL,
            path: change.path
        )
        let diff = try await loadedDiff
        let lfsInfo = try? await loadedLFS
        return (
            diff,
            lfsInfo?.isManaged == true ? lfsInfo : nil
        )
    }

    func selectCommit(_ commit: GitCommitSummary) async {
        guard let root = snapshot.roots.first(where: { $0.id == commit.rootID }) else {
            return
        }
        selectedCommitID = commit.id
        selectedCommitIDs.insert(commit.id)
        if !commitSelectionOrder.contains(commit.id) {
            commitSelectionOrder.append(commit.id)
        }
        selectedChangeID = nil
        selectedChangeListID = nil
        selectedChangeSource = nil
        selectedLFSFileInfo = nil
        selectedCommitDetails = nil
        selectedDiff = nil
        isLoadingSelectedDetail = true
        defer {
            if selectedCommitID == commit.id, selectedChangeID == nil {
                isLoadingSelectedDetail = false
            }
        }
        metadata.selectedCommitOID = commit.objectID
        metadata.lastDetailSelection = "commit"
        persistMetadata()
        do {
            async let details = service.commitDetails(
                rootURL: root.rootURL,
                objectID: commit.objectID
            )
            async let diff = service.diff(
                rootURL: root.rootURL,
                source: .commit(commit.objectID),
                ignoreWhitespace: preferencesStore.preferences.diff.ignoreWhitespace,
                foldUnchanged: preferencesStore.preferences.diff.foldUnchanged
            )
            let loadedDetails = try await details
            let loadedDiff = try await diff
            guard selectedCommitID == commit.id else { return }
            selectedCommitDetails = loadedDetails
            selectedDiff = loadedDiff
        } catch {
            guard selectedCommitID == commit.id, selectedChangeID == nil else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func reloadSelectedDetail() async {
        if let change = selectedChange {
            await selectChange(change, source: selectedChangeSource)
            return
        }
        guard let selectedCommitID,
              let commit = commits.first(where: {
                  $0.id == selectedCommitID
              })
        else {
            return
        }
        await selectCommit(commit)
    }

    func loadMoreCommits() {
        loadedCommitCount += 200
        Task { await loadLog() }
    }

    func updateCommitSelection(_ objectIDs: Set<String>) {
        let added = objectIDs.subtracting(commitSelectionOrder)
        commitSelectionOrder.removeAll { !objectIDs.contains($0) }
        commitSelectionOrder += commits
            .filter { added.contains($0.id) }
            .map(\.id)
        guard let focusedID = commitSelectionOrder.last,
              let commit = commits.first(where: {
                  $0.id == focusedID
              })
        else {
            selectedCommitID = nil
            selectedCommitDetails = nil
            selectedDiff = nil
            isLoadingSelectedDetail = false
            return
        }
        Task { await selectCommit(commit) }
    }

    func cherryPickSelectedCommits() {
        guard !commitSelectionOrder.isEmpty else { return }
        let selected = commitSelectionOrder.compactMap { id in
            commits.first(where: { $0.id == id })
        }
        guard Set(selected.map(\.rootID)).count == 1 else {
            errorGuidanceKey = "Cherry-pick 只能在同一个 Git Root 中执行。"
            errorMessage = selected.map(\.subject).joined(separator: "\n")
            return
        }
        if let rootID = selected.first?.rootID {
            selectRoot(rootID)
        }
        cherryPick(selected.map(\.objectID))
    }

    func setWorkflow(_ workflow: GitChangeWorkflow) {
        metadata.workflow = workflow
        persistMetadata()
        Task { await refresh() }
    }

    func toggleChangeInDefaultChangelist(_ change: GitLocalChange) {
        guard let root = root(containing: change),
              let listIndex = defaultChangelistIndex
        else {
            return
        }
        let existingIndex = metadata.changelists[listIndex].entries.firstIndex {
            $0.rootPath == root.rootURL.path && $0.path == change.path && $0.patch == nil
        }
        if let existingIndex {
            metadata.changelists[listIndex].entries.remove(at: existingIndex)
        } else {
            metadata.changelists[listIndex].entries.append(
                GitChangelistEntry(
                    rootPath: root.rootURL.path,
                    path: change.path
                )
            )
        }
        persistMetadata()
    }

    func addHunkToChangelist(
        file: GitPatchFile,
        hunk: GitPatchHunk,
        rootURL: URL,
        changelistID: UUID
    ) {
        guard let listIndex = metadata.changelists.firstIndex(where: {
                  $0.id == changelistID
              }),
              let path = file.newPath ?? file.oldPath
        else {
            return
        }
        let patch = hunk.patch(fileHeader: file.header)
        metadata.changelists[listIndex].entries.append(
            GitChangelistEntry(
                rootPath: rootURL.path,
                path: path,
                patch: patch,
                fingerprint: patch.gitFingerprint
            )
        )
        persistMetadata()
    }

    func addLinesToChangelist(
        file: GitPatchFile,
        hunk: GitPatchHunk,
        lineIDs: Set<UUID>,
        rootURL: URL,
        changelistID: UUID
    ) {
        guard let listIndex = metadata.changelists.firstIndex(where: {
                  $0.id == changelistID
              }),
              let path = file.newPath ?? file.oldPath,
              !lineIDs.isEmpty
        else {
            return
        }
        let patch = hunk.patch(
            fileHeader: file.header,
            selectedLineIDs: lineIDs
        )
        metadata.changelists[listIndex].entries.append(
            GitChangelistEntry(
                rootPath: rootURL.path,
                path: path,
                patch: patch,
                fingerprint: patch.gitFingerprint
            )
        )
        persistMetadata()
    }

    func createChangelist(name: String) {
        let list = GitChangelist(name: name)
        metadata.changelists.append(list)
        metadata.defaultChangelistID = list.id
        persistMetadata()
    }

    func renameChangelist(_ id: UUID, name: String) {
        guard let index = metadata.changelists.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }
        metadata.changelists[index].name = name
        persistMetadata()
    }

    func moveChange(_ change: GitLocalChange, to changelistID: UUID) {
        guard let root = root(containing: change),
              let targetIndex = metadata.changelists.firstIndex(where: {
                  $0.id == changelistID
              })
        else {
            return
        }
        for index in metadata.changelists.indices {
            metadata.changelists[index].entries.removeAll {
                $0.rootPath == root.rootURL.path
                    && $0.path == change.path
                    && $0.patch == nil
            }
        }
        metadata.changelists[targetIndex].entries.append(
            GitChangelistEntry(
                rootPath: root.rootURL.path,
                path: change.path
            )
        )
        persistMetadata()
    }

    func confirmChangelistEntry(_ entryID: UUID) {
        Task {
            for listIndex in metadata.changelists.indices {
                guard let entryIndex = metadata.changelists[listIndex].entries
                    .firstIndex(where: { $0.id == entryID })
                else {
                    continue
                }
                let entry = metadata.changelists[listIndex].entries[entryIndex]
                guard let root = snapshot.roots.first(where: {
                    $0.rootURL.path == entry.rootPath
                }), let patch = try? await service.diff(
                    rootURL: root.rootURL,
                    source: .workingTree,
                    path: entry.path
                ).patch
                else {
                    return
                }
                metadata.changelists[listIndex].entries[entryIndex]
                    .needsConfirmation = false
                metadata.changelists[listIndex].entries[entryIndex]
                    .fingerprint = patch.gitFingerprint
                persistMetadata()
                return
            }
        }
    }

    func deleteChangelist(_ id: UUID) {
        guard metadata.changelists.count > 1 else { return }
        metadata.changelists.removeAll { $0.id == id }
        if metadata.defaultChangelistID == id {
            metadata.defaultChangelistID = metadata.changelists.first?.id
        }
        persistMetadata()
    }

    func setDefaultChangelist(_ id: UUID) {
        metadata.defaultChangelistID = id
        persistMetadata()
    }

    func stage(_ change: GitLocalChange) {
        guard let root = root(containing: change) else { return }
        runMutation(title: "Stage \(change.path)", rootURL: root.rootURL) {
            try await self.service.stage(
                rootURL: root.rootURL,
                paths: [change.path]
            )
        }
    }

    func stageAll() {
        for root in selectedRootsForMutation {
            let paths = root.changes.compactMap { change in
                change.workingTree == nil ? nil : change.path
            }
            guard !paths.isEmpty else { continue }
            runMutation(
                title: "Stage All \(root.rootURL.lastPathComponent)",
                rootURL: root.rootURL
            ) {
                try await self.service.stage(
                    rootURL: root.rootURL,
                    paths: paths
                )
            }
        }
    }

    func unstage(_ change: GitLocalChange) {
        guard let root = root(containing: change) else { return }
        runMutation(title: "Unstage \(change.path)", rootURL: root.rootURL) {
            try await self.service.unstage(
                rootURL: root.rootURL,
                paths: [change.path]
            )
        }
    }

    func unstageAll() {
        for root in selectedRootsForMutation {
            let paths = root.changes.compactMap { change in
                change.index == nil ? nil : change.path
            }
            guard !paths.isEmpty else { continue }
            runMutation(
                title: "Unstage All \(root.rootURL.lastPathComponent)",
                rootURL: root.rootURL
            ) {
                try await self.service.unstage(
                    rootURL: root.rootURL,
                    paths: paths
                )
            }
        }
    }

    func stageHunk(_ hunk: GitPatchHunk, file: GitPatchFile, reverse: Bool = false) {
        guard let root = selectedDiffRoot else { return }
        let patch = hunk.patch(fileHeader: file.header)
        runMutation(
            title: reverse ? "Unstage Hunk" : "Stage Hunk",
            rootURL: root.rootURL
        ) {
            try await self.service.applyPatch(
                rootURL: root.rootURL,
                patch: patch,
                cached: true,
                reverse: reverse
            )
        }
    }

    func stageLines(
        _ lineIDs: Set<UUID>,
        hunk: GitPatchHunk,
        file: GitPatchFile,
        reverse: Bool = false
    ) {
        guard let root = selectedDiffRoot else { return }
        let patch = hunk.patch(
            fileHeader: file.header,
            selectedLineIDs: lineIDs
        )
        runMutation(
            title: reverse ? "Unstage Selected Lines" : "Stage Selected Lines",
            rootURL: root.rootURL
        ) {
            try await self.service.applyPatch(
                rootURL: root.rootURL,
                patch: patch,
                cached: true,
                reverse: reverse
            )
        }
    }

    func rollback(_ change: GitLocalChange) {
        guard let root = root(containing: change) else { return }
        withSafetySnapshot(action: "rollback \(change.path)", root: root) {
            try await self.service.restoreWorkingTree(
                rootURL: root.rootURL,
                paths: [change.path]
            )
        }
    }

    func rollbackHunk(
        _ hunk: GitPatchHunk,
        file: GitPatchFile,
        selectedLineIDs: Set<UUID>? = nil
    ) {
        guard let root = selectedDiffRoot else { return }
        let patch = hunk.patch(
            fileHeader: file.header,
            selectedLineIDs: selectedLineIDs
        )
        withSafetySnapshot(action: "rollback hunk", root: root) {
            try await self.service.applyPatch(
                rootURL: root.rootURL,
                patch: patch,
                cached: false,
                reverse: true
            )
        }
    }

    func commit(
        amend: Bool = false,
        skipHooks: Bool = false,
        sign: Bool = false,
        pushAfter: Bool = false
    ) {
        guard ensureNoSequencedOperation() else { return }
        let roots = selectedRootsForMutation
        guard !roots.isEmpty else { return }
        let selection: GitCommitSelection
        switch metadata.workflow {
        case .staging:
            selection = .staged
        case .changelists:
            selection = .changelist(defaultChangelist?.entries ?? [])
        }
        let message = currentCommitDraft
        let commands = metadata.preCommitCommands
        let workflow = metadata.workflow
        let service = service
        let registry = operationRegistry
        let workspaceURL = workspaceURL
        Task {
            var succeededRootPaths: Set<String> = []
            var failures: [String] = []
            await withTaskGroup(
                of: (String, [String]).self
            ) { group in
                for root in roots {
                    group.addTask {
                        let request = GitCommitRequest(
                            selection: selection,
                            message: message,
                            amend: amend,
                            skipHooks: skipHooks,
                            sign: sign,
                            preCommitCommands: commands
                        )
                        do {
                            let outcome = try await registry.run(
                                workspaceURL: workspaceURL,
                                rootURL: root.rootURL,
                                title: amend ? "Amend Commit" : "Commit",
                                command: "git commit",
                                isMutation: true
                            ) {
                                try await service.commit(
                                    rootURL: root.rootURL,
                                    request: request
                                )
                            }
                            return (
                                root.rootURL.path,
                                outcome.warnings.map {
                                    "\(root.rootURL.lastPathComponent): \($0)"
                                }
                            )
                        } catch {
                            return (
                                "",
                                [
                                    "\(root.rootURL.lastPathComponent): "
                                        + error.localizedDescription,
                                ]
                            )
                        }
                    }
                }
                for await result in group {
                    if !result.0.isEmpty {
                        succeededRootPaths.insert(result.0)
                    }
                    failures += result.1
                }
            }
            if !succeededRootPaths.isEmpty {
                currentCommitDraft = ""
                if workflow == .changelists,
                   let index = defaultChangelistIndex
                {
                    metadata.changelists[index].entries.removeAll {
                        succeededRootPaths.contains($0.rootPath)
                    }
                    persistMetadata()
                }
            }
            if !failures.isEmpty {
                errorMessage = failures.joined(separator: "\n\n")
            } else if pushAfter, succeededRootPaths.count == 1 {
                shouldPresentPushReview = true
            }
            await refresh()
        }
    }

    func preparePush(
        remote: String = "origin",
        includeTags: Bool = false,
        forceWithLease: Bool = false,
        upTo objectID: String? = nil
    ) async {
        guard let root = selectedRoot else {
            pushPlan = nil
            pushPreviewDiff = nil
            return
        }
        do {
            let localReference = objectID ?? root.branch.name
            let plan = try await service.makePushPlan(
                rootURL: root.rootURL,
                remote: remote,
                localReference: localReference,
                remoteReference: root.branch.name,
                includeTags: includeTags,
                forceWithLease: forceWithLease,
                protectedPatterns: metadata.protectedBranchPatterns
            )
            pushPlan = plan
            if let baseReference = plan.baseReference {
                pushPreviewDiff = try await service.diff(
                    rootURL: root.rootURL,
                    source: .between(baseReference, localReference),
                    ignoreWhitespace: preferencesStore.preferences.diff.ignoreWhitespace,
                    foldUnchanged: preferencesStore.preferences.diff.foldUnchanged
                )
            } else {
                pushPreviewDiff = try await service.diff(
                    rootURL: root.rootURL,
                    source: .commit(localReference),
                    ignoreWhitespace: preferencesStore.preferences.diff.ignoreWhitespace,
                    foldUnchanged: preferencesStore.preferences.diff.foldUnchanged
                )
            }
        } catch {
            pushPlan = nil
            pushPreviewDiff = nil
            errorMessage = error.localizedDescription
        }
    }

    func fetch(authentication: GitAuthentication? = nil) {
        for root in selectedRootsForMutation {
            guard !fetchingRootIDs.contains(root.id) else { continue }
            fetchingRootIDs.insert(root.id)
            Task {
                defer { fetchingRootIDs.remove(root.id) }
                do {
                    _ = try await operationRegistry.run(
                        workspaceURL: workspaceURL,
                        rootURL: root.rootURL,
                        title: "Fetch \(root.rootURL.lastPathComponent)",
                        isMutation: true
                    ) {
                        try await self.service.fetch(
                            rootURL: root.rootURL,
                            authentication: authentication
                        )
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                await refresh()
            }
        }
    }

    func clearAuthentication() {
        authenticationUsername = ""
        authenticationSecret = ""
        authenticationConfirmHostKey = false
    }

    func setPreferredPullStrategy(_ strategy: GitPullStrategy) {
        guard metadata.preferredPullStrategy != strategy else { return }
        metadata.preferredPullStrategy = strategy
        persistMetadata()
    }

    func pull(strategy: GitPullStrategy, authentication: GitAuthentication? = nil) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        metadata.preferredPullStrategy = strategy
        persistMetadata()
        withSafetySnapshot(action: "pull", root: root) {
            _ = try await self.service.pull(
                rootURL: root.rootURL,
                strategy: strategy,
                authentication: authentication
            )
        }
    }

    func push(
        remote: String = "origin",
        includeTags: Bool = false,
        forceWithLease: Bool = false,
        authentication: GitAuthentication? = nil,
        upTo objectID: String? = nil
    ) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        let localReference = objectID ?? root.branch.name
        runMutation(title: "Push \(root.branch.name)", rootURL: root.rootURL) {
            let preparedPlan = await MainActor.run { self.pushPlan }
            let plan = if let preparedPlan,
                          preparedPlan.remote == remote,
                          preparedPlan.localReference == localReference,
                          preparedPlan.remoteReference == root.branch.name,
                          preparedPlan.includeTags == includeTags,
                          preparedPlan.forceWithLease == forceWithLease
            {
                preparedPlan
            } else {
                try await self.service.makePushPlan(
                    rootURL: root.rootURL,
                    remote: remote,
                    localReference: localReference,
                    remoteReference: root.branch.name,
                    includeTags: includeTags,
                    forceWithLease: forceWithLease,
                    protectedPatterns: self.metadata.protectedBranchPatterns
                )
            }
            _ = try await self.service.push(
                plan: plan,
                protectedPatterns: self.metadata.protectedBranchPatterns,
                authentication: authentication
            )
        }
    }

    func pushUpTo(_ commit: GitCommitSummary, remote: String = "origin") {
        guard let root = snapshot.roots.first(where: { $0.id == commit.rootID }) else {
            return
        }
        runMutation(title: "Push up to \(String(commit.objectID.prefix(8)))", rootURL: root.rootURL) {
            let plan = try await self.service.makePushPlan(
                rootURL: root.rootURL,
                remote: remote,
                localReference: commit.objectID,
                remoteReference: root.branch.name,
                includeTags: false,
                forceWithLease: false
            )
            _ = try await self.service.push(
                plan: plan,
                protectedPatterns: self.metadata.protectedBranchPatterns
            )
        }
    }

    func interactiveRebase(
        onto reference: String,
        steps: [GitHistoryEditStep]
    ) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: "interactive rebase", root: root) {
            try await self.service.interactiveRebase(
                rootURL: root.rootURL,
                onto: reference,
                steps: steps,
                protectedPatterns: self.metadata.protectedBranchPatterns
            )
        }
    }

    func fixupCurrentChanges(into commit: GitCommitSummary) {
        guard ensureNoSequencedOperation(),
              let root = snapshot.roots.first(where: {
                  $0.id == commit.rootID
              })
        else {
            return
        }
        let selection: GitCommitSelection = switch metadata.workflow {
        case .staging:
            .staged
        case .changelists:
            .changelist(defaultChangelist?.entries ?? [])
        }
        let request = GitCommitRequest(
            selection: selection,
            message: "",
            preCommitCommands: metadata.preCommitCommands
        )
        let retention = preferencesStore.preferences.snapshotRetentionWorkingDays
        Task {
            do {
                _ = await snapshotStore.create(
                    rootURL: root.rootURL,
                    action: "fixup \(commit.objectID)",
                    retentionWorkingDays: retention
                )
                _ = try await operationRegistry.run(
                    workspaceURL: workspaceURL,
                    rootURL: root.rootURL,
                    title: "Fixup Current Changes",
                    command: "git commit --fixup",
                    isMutation: true
                ) {
                    try await self.service.fixupCurrentChanges(
                        rootURL: root.rootURL,
                        targetObjectID: commit.objectID,
                        request: request,
                        protectedPatterns: self.metadata.protectedBranchPatterns
                    )
                }
                currentCommitDraft = ""
                if metadata.workflow == .changelists,
                   let index = defaultChangelistIndex
                {
                    metadata.changelists[index].entries.removeAll {
                        $0.rootPath == root.rootURL.path
                    }
                    persistMetadata()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            await refresh()
        }
    }

    func createBranch(name: String, startPoint: String? = nil, checkout: Bool = true) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        runMutation(title: "Create Branch \(name)", rootURL: root.rootURL) {
            try await self.service.createBranch(
                rootURL: root.rootURL,
                name: name,
                startPoint: startPoint,
                checkout: checkout
            )
        }
    }

    func createTag(
        name: String,
        objectID: String = "HEAD",
        message: String? = nil,
        sign: Bool = false
    ) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Create Tag \(name)", rootURL: root.rootURL) {
            try await self.service.createTag(
                rootURL: root.rootURL,
                name: name,
                objectID: objectID,
                message: message,
                sign: sign
            )
        }
    }

    func deleteTag(_ name: String) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Delete Tag \(name)", rootURL: root.rootURL) {
            try await self.service.deleteTag(rootURL: root.rootURL, name: name)
        }
    }

    func renameBranch(oldName: String, newName: String) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Rename Branch \(oldName)", rootURL: root.rootURL) {
            try await self.service.renameBranch(
                rootURL: root.rootURL,
                oldName: oldName,
                newName: newName
            )
        }
    }

    func deleteBranch(_ name: String, force: Bool = false) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Delete Branch \(name)", rootURL: root.rootURL) {
            try await self.service.deleteBranch(
                rootURL: root.rootURL,
                name: name,
                force: force,
                protectedPatterns: self.metadata.protectedBranchPatterns
            )
        }
    }

    func setUpstream(branch: String, upstream: String?) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Set Upstream \(branch)", rootURL: root.rootURL) {
            try await self.service.setUpstream(
                rootURL: root.rootURL,
                branch: branch,
                upstream: upstream
            )
        }
    }

    func toggleFavoriteReference(_ reference: GitReference) {
        var favorites = metadata.favoriteReferenceNames ?? []
        if favorites.contains(reference.fullName) {
            favorites.remove(reference.fullName)
        } else {
            favorites.insert(reference.fullName)
        }
        metadata.favoriteReferenceNames = favorites
        persistMetadata()
    }

    func setRemote(name: String, url: String, existing: Bool) {
        guard let root = selectedRoot else { return }
        runMutation(
            title: existing ? "Edit Remote \(name)" : "Add Remote \(name)",
            rootURL: root.rootURL
        ) {
            try await self.service.setRemote(
                rootURL: root.rootURL,
                name: name,
                fetchURL: url,
                existing: existing
            )
        }
    }

    func removeRemote(_ name: String) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Remove Remote \(name)", rootURL: root.rootURL) {
            try await self.service.removeRemote(rootURL: root.rootURL, name: name)
        }
    }

    func deleteRemoteBranch(
        _ reference: GitReference,
        authentication: GitAuthentication? = nil
    ) {
        guard let remoteBranch = remoteBranchIdentity(for: reference),
              let root = selectedRoot
        else {
            return
        }
        runMutation(
            title: "Delete Remote Branch \(reference.shortName)",
            rootURL: root.rootURL
        ) {
            try await self.service.deleteRemoteBranch(
                rootURL: root.rootURL,
                remote: remoteBranch.remoteName,
                branch: remoteBranch.branchName,
                authentication: authentication
            )
        }
    }

    func checkout(reference: String) {
        if let resolvedReference = references.first(where: {
            $0.shortName == reference || $0.fullName == reference
        }) {
            checkout(reference: resolvedReference)
            return
        }
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: "checkout \(reference)", root: root) {
            try await self.service.checkout(
                rootURL: root.rootURL,
                reference: reference
            )
        }
    }

    func checkout(reference: GitReference) {
        performCheckout(reference: reference, updatesAfterCheckout: false)
    }

    func checkoutAndUpdate(reference: String, strategy: GitPullStrategy = .merge) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: "checkout and update \(reference)", root: root) {
            try await self.service.checkout(
                rootURL: root.rootURL,
                reference: reference
            )
            _ = try await self.service.pull(
                rootURL: root.rootURL,
                strategy: strategy
            )
        }
    }

    func checkoutAndUpdate(
        reference: GitReference,
        strategy: GitPullStrategy = .merge
    ) {
        performCheckout(
            reference: reference,
            updatesAfterCheckout: true,
            pullStrategy: strategy
        )
    }

    func resolveCheckoutConflict(
        _ request: GitCheckoutConflictRequest,
        using resolution: GitCheckoutResolution
    ) {
        if checkoutConflict?.id == request.id {
            checkoutConflict = nil
        }
        if request.synchronizesRoots {
            performSynchronizedCheckout(
                reference: request.reference,
                roots: request.rootConflicts.map(\.root),
                conflictingPaths: Dictionary(
                    uniqueKeysWithValues: request.rootConflicts.map {
                        ($0.root.id, $0.paths)
                    }
                ),
                resolution: resolution
            )
            return
        }
        performCheckout(
            reference: request.reference,
            updatesAfterCheckout: request.updatesAfterCheckout,
            pullStrategy: request.pullStrategy,
            conflictingPaths: request.rootConflicts.first?.paths ?? [],
            resolution: resolution
        )
    }

    func dismissCheckoutConflict() {
        checkoutConflict = nil
    }

    private func performCheckout(
        reference: GitReference,
        updatesAfterCheckout: Bool,
        pullStrategy: GitPullStrategy = .merge,
        conflictingPaths: [String] = [],
        resolution: GitCheckoutResolution? = nil
    ) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot,
              let target = checkoutTarget(for: reference)
        else {
            return
        }
        let action = updatesAfterCheckout
            ? "checkout and update \(reference.shortName)"
            : "checkout \(reference.shortName)"
        withSafetySnapshot(
            action: action,
            root: root,
            onError: resolution == nil ? { [weak self] error in
                guard let conflict = error as? GitCheckoutConflictError else {
                    return false
                }
                self?.checkoutConflict = GitCheckoutConflictRequest(
                    reference: reference,
                    rootConflicts: [
                        GitCheckoutRootConflict(
                            root: root,
                            paths: conflict.paths
                        ),
                    ],
                    synchronizesRoots: false,
                    updatesAfterCheckout: updatesAfterCheckout,
                    pullStrategy: pullStrategy
                )
                return true
            } : nil
        ) {
            try await self.service.checkout(
                rootURL: root.rootURL,
                target: target,
                resolution: resolution,
                conflictingPaths: conflictingPaths
            )
            if updatesAfterCheckout {
                _ = try await self.service.pull(
                    rootURL: root.rootURL,
                    strategy: pullStrategy
                )
            }
        }
    }

    private func checkoutTarget(
        for reference: GitReference
    ) -> GitCheckoutTarget? {
        guard reference.kind == .remoteBranch else {
            return .reference(reference.shortName)
        }
        guard let remoteBranch = remoteBranchIdentity(for: reference) else {
            return nil
        }
        return .remote(
            remoteBranch: remoteBranch.fullName,
            localName: remoteBranch.checkoutLocalBranchName
        )
    }

    func synchronizeCheckout(reference: String) {
        guard metadata.synchronizeMultiRootOperations,
              selectedRootID == nil,
              snapshot.roots.count > 1
        else {
            checkout(reference: reference)
            return
        }
        guard let branchReference = references.first(where: {
            $0.kind == .localBranch && $0.shortName == reference
        }) else {
            checkout(reference: reference)
            return
        }
        performSynchronizedCheckout(
            reference: branchReference,
            roots: snapshot.roots.filter { !$0.isSubmoduleRoot }
        )
    }

    private func performSynchronizedCheckout(
        reference: GitReference,
        roots: [GitRootSnapshot],
        conflictingPaths: [GitRootID: [String]] = [:],
        resolution: GitCheckoutResolution? = nil
    ) {
        let service = service
        let registry = operationRegistry
        let workspaceURL = workspaceURL
        let snapshotStore = snapshotStore
        let retention = preferencesStore.preferences.snapshotRetentionWorkingDays
        let title = "Checkout \(reference.shortName)"
        Task {
            var conflicts: [GitCheckoutRootConflict] = []
            var failures: [String] = []
            await withTaskGroup(
                of: GitSynchronizedCheckoutOutcome.self
            ) { group in
                for root in roots {
                    group.addTask {
                        _ = await snapshotStore.create(
                            rootURL: root.rootURL,
                            action: title,
                            retentionWorkingDays: retention
                        )
                        do {
                            try await registry.run(
                                workspaceURL: workspaceURL,
                                rootURL: root.rootURL,
                                title: title,
                                isMutation: true
                            ) {
                                let target = GitCheckoutTarget.reference(
                                    reference.shortName
                                )
                                try await service.checkout(
                                    rootURL: root.rootURL,
                                    target: target,
                                    resolution: resolution,
                                    conflictingPaths: conflictingPaths[
                                        root.id
                                    ] ?? []
                                )
                            }
                            return .success
                        } catch let conflict as GitCheckoutConflictError {
                            return .conflict(
                                GitCheckoutRootConflict(
                                    root: root,
                                    paths: conflict.paths
                                )
                            )
                        } catch {
                            return .failure(
                                root.rootURL.lastPathComponent + ": "
                                    + error.localizedDescription
                            )
                        }
                    }
                }
                for await outcome in group {
                    switch outcome {
                    case .success:
                        break
                    case .conflict(let conflict):
                        conflicts.append(conflict)
                    case .failure(let failure):
                        failures.append(failure)
                    }
                }
            }
            if !conflicts.isEmpty {
                checkoutConflict = GitCheckoutConflictRequest(
                    reference: reference,
                    rootConflicts: conflicts.sorted {
                        $0.root.rootURL.path < $1.root.rootURL.path
                    },
                    synchronizesRoots: true,
                    updatesAfterCheckout: false,
                    pullStrategy: .merge
                )
            }
            if !failures.isEmpty {
                errorMessage = failures.sorted().joined(separator: "\n")
            }
            await refresh()
        }
    }

    private func remoteBranchIdentity(
        for reference: GitReference
    ) -> GitRemoteBranchIdentity? {
        reference.remoteBranchIdentity(
            configuredRemoteNames: remotes.map(\.name)
        )
    }

    func synchronizeMerge(reference: String) {
        guard metadata.synchronizeMultiRootOperations,
              selectedRootID == nil,
              snapshot.roots.count > 1
        else {
            merge(reference: reference)
            return
        }
        synchronizeMutation(title: "Merge \(reference)") { service, root in
            try await service.merge(
                rootURL: root.rootURL,
                reference: reference
            )
        }
    }

    func synchronizeRebase(onto reference: String) {
        guard metadata.synchronizeMultiRootOperations,
              selectedRootID == nil,
              snapshot.roots.count > 1
        else {
            rebase(onto: reference)
            return
        }
        synchronizeMutation(title: "Rebase \(reference)") { service, root in
            try await service.rebase(
                rootURL: root.rootURL,
                onto: reference
            )
        }
    }

    func synchronizeReset(
        to reference: String,
        mode: GitResetMode
    ) {
        guard metadata.synchronizeMultiRootOperations,
              selectedRootID == nil,
              snapshot.roots.count > 1
        else {
            reset(to: reference, mode: mode)
            return
        }
        let protectedPatterns = metadata.protectedBranchPatterns
        synchronizeMutation(title: "Reset --\(mode.rawValue) \(reference)") {
            service,
            root in
            try await service.reset(
                rootURL: root.rootURL,
                objectID: reference,
                mode: mode,
                protectedPatterns: protectedPatterns
            )
        }
    }

    func synchronizePush(
        remote: String = "origin",
        includeTags: Bool = false
    ) {
        guard metadata.synchronizeMultiRootOperations,
              selectedRootID == nil,
              snapshot.roots.count > 1
        else {
            push(remote: remote, includeTags: includeTags)
            return
        }
        let protectedPatterns = metadata.protectedBranchPatterns
        synchronizeMutation(title: "Push \(remote)") { service, root in
            let plan = try await service.makePushPlan(
                rootURL: root.rootURL,
                remote: remote,
                localReference: root.branch.name,
                remoteReference: root.branch.name,
                includeTags: includeTags,
                forceWithLease: false,
                protectedPatterns: protectedPatterns
            )
            _ = try await service.push(
                plan: plan,
                protectedPatterns: protectedPatterns
            )
        }
    }

    func selectSubmodule(_ submodule: GitSubmoduleState) {
        guard let parentRoot = selectedRoot,
              let root = snapshot.roots.first(where: {
                  $0.rootURL.standardizedFileURL
                      == parentRoot.rootURL
                          .appendingPathComponent(submodule.path)
                          .standardizedFileURL
              })
        else {
            return
        }
        selectRoot(root.id)
    }

    func merge(reference: String) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: "merge \(reference)", root: root) {
            try await self.service.merge(
                rootURL: root.rootURL,
                reference: reference
            )
        }
    }

    func rebase(onto reference: String) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: "rebase \(reference)", root: root) {
            try await self.service.rebase(
                rootURL: root.rootURL,
                onto: reference
            )
        }
    }

    func cherryPick(_ objectIDs: [String]) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: "cherry-pick", root: root) {
            try await self.service.cherryPick(
                rootURL: root.rootURL,
                objectIDs: objectIDs
            )
        }
    }

    func cherryPick(_ commit: GitCommitSummary) {
        selectRoot(commit.rootID)
        cherryPick([commit.objectID])
    }

    func revert(_ objectIDs: [String]) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: "revert", root: root) {
            try await self.service.revert(
                rootURL: root.rootURL,
                objectIDs: objectIDs
            )
        }
    }

    func revert(_ commit: GitCommitSummary) {
        selectRoot(commit.rootID)
        revert([commit.objectID])
    }

    func applyCommitToWorkingTree(_ commit: GitCommitSummary) {
        guard ensureNoSequencedOperation(),
              let root = snapshot.roots.first(where: {
                  $0.id == commit.rootID
              })
        else {
            return
        }
        withSafetySnapshot(action: "apply commit to working tree", root: root) {
            let patch = try await self.service.diff(
                rootURL: root.rootURL,
                source: .commit(commit.objectID)
            ).patch
            try await self.service.applyPatch(
                rootURL: root.rootURL,
                patch: patch,
                cached: false,
                threeWay: true
            )
        }
    }

    func reset(to objectID: String, mode: GitResetMode) {
        guard ensureNoSequencedOperation() else { return }
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: "reset --\(mode.rawValue)", root: root) {
            try await self.service.reset(
                rootURL: root.rootURL,
                objectID: objectID,
                mode: mode,
                protectedPatterns: self.metadata.protectedBranchPatterns
            )
        }
    }

    func reset(commit: GitCommitSummary, mode: GitResetMode) {
        selectRoot(commit.rootID)
        reset(to: commit.objectID, mode: mode)
    }

    func undoLastCommit(keepIndex: Bool) {
        guard ensureNoSequencedOperation(),
              let root = selectedRoot
        else {
            return
        }
        withSafetySnapshot(action: "undo last commit", root: root) {
            try await self.service.undoLastCommit(
                rootURL: root.rootURL,
                keepIndex: keepIndex,
                protectedPatterns: self.metadata.protectedBranchPatterns
            )
        }
    }

    func continueSequence() {
        guard let root = selectedRoot, let sequencedOperation else { return }
        runMutation(title: "Continue \(sequencedOperation.kind.rawValue)", rootURL: root.rootURL) {
            try await self.service.continueSequence(
                rootURL: root.rootURL,
                kind: sequencedOperation.kind
            )
        }
    }

    func skipSequence() {
        guard let root = selectedRoot, let sequencedOperation else { return }
        runMutation(title: "Skip \(sequencedOperation.kind.rawValue)", rootURL: root.rootURL) {
            try await self.service.skipSequence(
                rootURL: root.rootURL,
                kind: sequencedOperation.kind
            )
        }
    }

    func abortSequence() {
        guard let root = selectedRoot, let sequencedOperation else { return }
        runMutation(title: "Abort \(sequencedOperation.kind.rawValue)", rootURL: root.rootURL) {
            try await self.service.abortSequence(
                rootURL: root.rootURL,
                kind: sequencedOperation.kind
            )
        }
    }

    func loadFileHistory(change: GitLocalChange) {
        guard let root = root(containing: change) else { return }
        fileHistoryTask?.cancel()
        fileHistoryTask = Task {
            do {
                let history = try await service.fileHistory(
                    rootURL: root.rootURL,
                    path: change.path
                ).commits
                guard !Task.isCancelled else { return }
                fileHistory = history
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadBlame(change: GitLocalChange) {
        guard let root = root(containing: change) else { return }
        blameTask?.cancel()
        blameTask = Task {
            do {
                let lines = try await service.blame(
                    rootURL: root.rootURL,
                    path: change.path
                )
                guard !Task.isCancelled else { return }
                blameLines = lines
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func jumpToCommit(objectID: String) {
        guard let rootID = selectedDiff?.rootID,
              let root = snapshot.roots.first(where: { $0.id == rootID })
        else {
            return
        }
        Task {
            do {
                let commit: GitCommitSummary
                if let existing = commits.first(where: {
                    $0.rootID == rootID && $0.objectID == objectID
                }) {
                    commit = existing
                } else {
                    let page = try await service.log(
                        rootURL: root.rootURL,
                        limit: 1,
                        revision: objectID
                    )
                    guard let loaded = page.commits.first else { return }
                    commit = loaded
                    commits.insert(loaded, at: 0)
                }
                await selectCommit(commit)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadConflict(path: String, rootID: GitRootID? = nil) {
        guard let root = snapshot.roots.first(where: {
            $0.id == (rootID ?? selectedRootID)
        }) else {
            return
        }
        Task {
            do {
                let file = try await service.conflictFile(
                    rootURL: root.rootURL,
                    path: path
                )
                conflictFile = file
                conflictRootID = root.id
                conflictResult = file.result
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func acceptConflictSide(ours: Bool) {
        guard let conflictFile else { return }
        conflictResult = ours ? conflictFile.ours : conflictFile.theirs
    }

    func resetConflictResultToAutomaticMerge() {
        conflictResult = conflictFile?.result ?? ""
    }

    func resolveConflictBlock(
        _ block: GitConflictBlock,
        with choice: GitConflictResolutionChoice
    ) {
        conflictResult = GitConflictDocument(contents: conflictResult)
            .resolving(block, with: choice)
    }

    func saveConflictResult() {
        guard let root = snapshot.roots.first(where: {
            $0.id == conflictRootID
        }), let conflictFile
        else {
            return
        }
        let contents = conflictResult
        runMutation(title: "Resolve \(conflictFile.path)", rootURL: root.rootURL) {
            try await self.service.saveConflictResult(
                rootURL: root.rootURL,
                path: conflictFile.path,
                contents: contents
            )
        }
    }

    func createStash(message: String, includeUntracked: Bool, keepIndex: Bool) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Create Git Stash", rootURL: root.rootURL) {
            try await self.service.createStash(
                rootURL: root.rootURL,
                message: message,
                includeUntracked: includeUntracked,
                keepIndex: keepIndex
            )
        }
    }

    func applyStash(_ stash: GitStashEntry, pop: Bool) {
        guard let root = selectedRoot else { return }
        withSafetySnapshot(action: pop ? "stash pop" : "stash apply", root: root) {
            try await self.service.applyStash(
                rootURL: root.rootURL,
                reference: stash.reference,
                pop: pop
            )
        }
    }

    func previewStash(_ stash: GitStashEntry) {
        guard let root = selectedRoot else { return }
        Task {
            do {
                selectedCommitID = nil
                selectedCommitDetails = nil
                selectedDiff = try await service.diff(
                    rootURL: root.rootURL,
                    source: .stash(stash.reference)
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dropStash(_ stash: GitStashEntry) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Drop \(stash.reference)", rootURL: root.rootURL) {
            try await self.service.dropStash(
                rootURL: root.rootURL,
                reference: stash.reference
            )
        }
    }

    func shelveCurrentChanges(name: String) {
        guard let root = selectedRoot else { return }
        Task {
            do {
                let patch: String
                switch metadata.workflow {
                case .staging:
                    patch = try await service.diff(
                        rootURL: root.rootURL,
                        source: .staged
                    ).patch
                case .changelists:
                    var patches: [String] = []
                    for entry in defaultChangelist?.entries ?? []
                    where entry.rootPath == root.rootURL.path {
                        if let entryPatch = entry.patch {
                            patches.append(entryPatch)
                        } else {
                            patches.append(
                                try await service.diff(
                                    rootURL: root.rootURL,
                                    source: .workingTree,
                                    path: entry.path
                                ).patch
                            )
                        }
                    }
                    patch = patches.joined(separator: "\n")
                }
                guard !patch.isEmpty else {
                    throw GitMutationError.invalidSelection(
                        "There are no selected changes to shelve."
                    )
                }
                _ = try await metadataStore.createShelf(
                    workspaceURL: workspaceURL,
                    rootURL: root.rootURL,
                    name: name,
                    patch: patch
                )
                metadata = await metadataStore.load(workspaceURL: workspaceURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func shelvePatch(
        name: String,
        file: GitPatchFile,
        hunk: GitPatchHunk,
        selectedLineIDs: Set<UUID>? = nil
    ) {
        guard let rootID = selectedDiff?.rootID,
              let root = snapshot.roots.first(where: { $0.id == rootID })
        else {
            return
        }
        let patch = hunk.patch(
            fileHeader: file.header,
            selectedLineIDs: selectedLineIDs
        )
        Task {
            do {
                _ = try await metadataStore.createShelf(
                    workspaceURL: workspaceURL,
                    rootURL: root.rootURL,
                    name: name,
                    patch: patch
                )
                metadata = await metadataStore.load(workspaceURL: workspaceURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func previewShelf(_ shelf: GitShelf) {
        guard let root = snapshot.roots.first(where: {
            $0.rootURL.path == shelf.rootPath
        }) else {
            return
        }
        Task {
            do {
                let patch = try await metadataStore.shelfPatch(
                    workspaceURL: workspaceURL,
                    shelf: shelf
                )
                selectedCommitID = nil
                selectedCommitDetails = nil
                selectedDiff = GitFileDiff(
                    rootID: root.id,
                    path: nil,
                    source: .stash("Shelf · \(shelf.name)"),
                    patch: patch,
                    isBinary: patch.contains("GIT binary patch")
                        || patch.contains("Binary files "),
                    byteCount: patch.utf8.count
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func applyPreviewPatch(
        file: GitPatchFile,
        hunk: GitPatchHunk,
        selectedLineIDs: Set<UUID>? = nil
    ) {
        guard let rootID = selectedDiff?.rootID,
              let root = snapshot.roots.first(where: { $0.id == rootID })
        else {
            return
        }
        let patch = hunk.patch(
            fileHeader: file.header,
            selectedLineIDs: selectedLineIDs
        )
        withSafetySnapshot(action: "apply preview patch", root: root) {
            try await self.service.applyPatch(
                rootURL: root.rootURL,
                patch: patch,
                cached: false
            )
        }
    }

    func renameShelf(_ shelf: GitShelf, name: String) {
        guard let index = metadata.shelves.firstIndex(where: {
            $0.id == shelf.id
        }) else {
            return
        }
        metadata.shelves[index].name = name
        persistMetadata()
    }

    func importShelf(from sourceURL: URL) {
        guard let root = selectedRoot else { return }
        Task {
            do {
                _ = try await metadataStore.importShelf(
                    workspaceURL: workspaceURL,
                    rootURL: root.rootURL,
                    sourceURL: sourceURL
                )
                metadata = await metadataStore.load(workspaceURL: workspaceURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func exportShelf(_ shelf: GitShelf, to destinationURL: URL) {
        Task {
            do {
                try await metadataStore.exportShelf(
                    workspaceURL: workspaceURL,
                    shelf: shelf,
                    destinationURL: destinationURL
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func applyShelf(_ shelf: GitShelf) {
        guard let root = snapshot.roots.first(where: {
            $0.rootURL.path == shelf.rootPath
        }) else {
            return
        }
        withSafetySnapshot(action: "apply shelf", root: root) {
            let patch = try await self.metadataStore.shelfPatch(
                workspaceURL: self.workspaceURL,
                shelf: shelf
            )
            try await self.service.applyPatch(
                rootURL: root.rootURL,
                patch: patch,
                cached: false,
                threeWay: true
            )
        }
    }

    func deleteShelf(_ shelf: GitShelf) {
        Task {
            do {
                try await metadataStore.deleteShelf(
                    workspaceURL: workspaceURL,
                    shelf: shelf
                )
                metadata = await metadataStore.load(workspaceURL: workspaceURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func initializeRepository() {
        Task {
            do {
                _ = try await operationRegistry.run(
                    workspaceURL: workspaceURL,
                    rootURL: workspaceURL,
                    title: "Initialize Git Repository",
                    command: "git init -b main",
                    isMutation: true
                ) {
                    try await GitWorkbenchService.initializeRepository(
                        at: self.workspaceURL,
                        gitExecutableURL: self.preferencesStore.resolvedGitExecutableURL
                    )
                }
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cloneRepository(
        remoteURL: String,
        destinationURL: URL
    ) async -> Bool {
        do {
            _ = try await operationRegistry.run(
                workspaceURL: workspaceURL,
                rootURL: destinationURL,
                title: "Clone Git Repository",
                command: "git clone",
                isMutation: true
            ) {
                try await GitWorkbenchService.cloneRepository(
                    remoteURL: remoteURL,
                    destinationURL: destinationURL,
                    gitExecutableURL: self.preferencesStore.resolvedGitExecutableURL
                )
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateSubmodules(initialize: Bool) {
        guard let root = selectedRoot else { return }
        runMutation(title: "Update Submodules", rootURL: root.rootURL) {
            try await self.service.updateSubmodules(
                rootURL: root.rootURL,
                initialize: initialize
            )
        }
    }

    func synchronizeSubmoduleURLs() {
        guard let root = selectedRoot else { return }
        runMutation(title: "Synchronize Submodule URLs", rootURL: root.rootURL) {
            try await self.service.synchronizeSubmoduleURLs(rootURL: root.rootURL)
        }
    }

    func fetchLFS(pull: Bool) {
        guard let root = selectedRoot else { return }
        runMutation(title: pull ? "Git LFS Pull" : "Git LFS Fetch", rootURL: root.rootURL) {
            try await self.service.fetchLFS(rootURL: root.rootURL, pull: pull)
        }
    }

    func openEditableFile(
        path: String,
        staged: Bool,
        rootID: GitRootID? = nil
    ) {
        guard let root = snapshot.roots.first(where: {
            $0.id == (rootID ?? selectedDiff?.rootID ?? selectedRootID)
        }) else {
            return
        }
        Task {
            do {
                editableFilePath = path
                editableRootID = root.id
                isEditingStagedFile = staged
                if staged {
                    let head = try await service.runner.run(
                        arguments: [
                            "-C",
                            root.rootURL.path,
                            "show",
                            "HEAD:\(path)",
                        ]
                    )
                    editableHeadContents = head.exitCode == 0
                        ? head.standardOutput
                        : ""
                    editableFileContents = try await service.requiredGit(
                        rootURL: root.rootURL,
                        arguments: ["show", ":\(path)"]
                    ).standardOutput
                    editableLocalContents = (
                        try? String(
                            contentsOf: root.rootURL
                                .appendingPathComponent(path),
                            encoding: .utf8
                        )
                    ) ?? ""
                } else {
                    editableHeadContents = ""
                    editableLocalContents = ""
                    editableFileContents = try String(
                        contentsOf: root.rootURL.appendingPathComponent(path),
                        encoding: .utf8
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openSelectedFileWithSystemPreview() {
        guard let diff = selectedDiff,
              let path = diff.path,
              let root = snapshot.roots.first(where: {
                  $0.id == diff.rootID
              })
        else {
            return
        }
        NSWorkspace.shared.open(root.rootURL.appendingPathComponent(path))
    }

    func saveEditableFile() {
        guard let root = snapshot.roots.first(where: {
            $0.id == editableRootID
        }), let path = editableFilePath
        else {
            return
        }
        let staged = isEditingStagedFile
        let contents = editableFileContents
        let service = service
        runMutation(
            title: staged ? "Edit Staged \(path)" : "Edit \(path)",
            rootURL: root.rootURL
        ) {
            if staged {
                try await service.replaceIndexFile(
                    rootURL: root.rootURL,
                    path: path,
                    contents: contents
                )
            } else {
                let url = root.rootURL.appendingPathComponent(path)
                try Data(contents.utf8).write(to: url, options: .atomic)
            }
        }
    }

    func restoreSnapshot(_ snapshot: GitSafetySnapshot, paths: Set<String>? = nil) {
        let rootURL = URL(fileURLWithPath: snapshot.rootPath)
        runMutation(title: "Restore Git Safety Snapshot", rootURL: rootURL) {
            try await self.snapshotStore.restore(
                snapshot,
                rootURL: rootURL,
                paths: paths
            )
        }
    }

    func previewSnapshotFile(
        _ snapshot: GitSafetySnapshot,
        path: String
    ) {
        let rootURL = URL(fileURLWithPath: snapshot.rootPath)
        Task {
            do {
                selectedCommitID = nil
                selectedCommitDetails = nil
                selectedDiff = try await snapshotStore.comparisonDiff(
                    snapshot,
                    rootURL: rootURL,
                    path: path
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveWorkspaceMetadata() {
        persistMetadata()
    }

    private func loadSelectedRootData(reloadLog: Bool = true) async {
        rootDataLoadGeneration += 1
        let generation = rootDataLoadGeneration
        if reloadLog {
            logLoadGeneration += 1
        }
        guard !snapshot.roots.isEmpty else {
            references = []
            remotes = []
            commits = []
            stashes = []
            submodules = []
            commitTemplate = nil
            recentCommitMessages = []
            sequencedOperation = nil
            return
        }
        let roots = selectedRootsForRead
        do {
            if roots.count == 1, let root = roots.first {
                async let nextReferences = service.references(rootURL: root.rootURL)
                async let nextRemotes = service.remotes(rootURL: root.rootURL)
                async let nextStashes = service.stashes(rootURL: root.rootURL)
                async let nextSubmodules = service.submodules(rootURL: root.rootURL)
                async let nextSequence = service.sequencedOperation(rootURL: root.rootURL)
                async let nextLFS = service.lfsCapability(rootURL: root.rootURL)
                async let nextTemplate = service.commitTemplate(rootURL: root.rootURL)
                async let nextMessages = service.recentCommitMessages(rootURL: root.rootURL)
                let (
                    loadedReferences,
                    loadedRemotes,
                    loadedStashes,
                    loadedSubmodules,
                    loadedSequence,
                    loadedLFS,
                    loadedTemplate,
                    loadedMessages
                ) = try await (
                    nextReferences,
                    nextRemotes,
                    nextStashes,
                    nextSubmodules,
                    nextSequence,
                    nextLFS,
                    nextTemplate,
                    nextMessages
                )
                let loadedLocks: [GitLFSLock]
                if loadedLFS.isInstalled {
                    loadedLocks = (
                        try? await service.lfsLocks(rootURL: root.rootURL)
                    ) ?? []
                } else {
                    loadedLocks = []
                }
                let loadedSnapshots = await snapshotStore.list(
                    rootURL: root.rootURL
                )
                guard generation == rootDataLoadGeneration else { return }
                references = loadedReferences
                remotes = loadedRemotes
                stashes = loadedStashes
                submodules = loadedSubmodules
                sequencedOperation = loadedSequence
                lfsCapability = loadedLFS
                commitTemplate = loadedTemplate
                recentCommitMessages = loadedMessages
                lfsLocks = loadedLocks
                safetySnapshots = loadedSnapshots
                if currentCommitDraft.isEmpty, let loadedTemplate {
                    currentCommitDraft = loadedTemplate
                }
            } else {
                var rootReferences: [[GitReference]] = []
                for root in roots {
                    rootReferences.append(
                        try await service.references(rootURL: root.rootURL)
                    )
                }
                guard generation == rootDataLoadGeneration else { return }
                let localReferences = rootReferences.flatMap {
                    $0.filter { $0.kind == .localBranch }
                }
                let counts = Dictionary(grouping: localReferences, by: \.shortName)
                references = counts.values.compactMap { values in
                    values.count == roots.count ? values.first : nil
                }.sorted { $0.shortName < $1.shortName }
                remotes = []
                stashes = []
                submodules = []
                sequencedOperation = nil
                lfsLocks = []
                commitTemplate = nil
                recentCommitMessages = []
            }
            if reloadLog {
                await loadLog()
            }
        } catch {
            guard generation == rootDataLoadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadLog() async {
        logLoadGeneration += 1
        let generation = logLoadGeneration
        do {
            var aggregated: [GitCommitSummary] = []
            var anyMore = false
            let rootFilter = metadata.logFilter
                .split(whereSeparator: \.isWhitespace)
                .first(where: { $0.hasPrefix("root:") })
                .map { String($0.dropFirst("root:".count)) }
            let roots = selectedRootsForRead.filter { root in
                guard let rootFilter, !rootFilter.isEmpty else { return true }
                return root.rootURL.lastPathComponent
                    .localizedCaseInsensitiveContains(rootFilter)
                    || root.rootURL.path.localizedCaseInsensitiveContains(
                        rootFilter
                    )
            }
            for root in roots {
                let page = try await service.log(
                    rootURL: root.rootURL,
                    limit: loadedCommitCount,
                    query: metadata.logFilter.nilIfEmpty
                )
                aggregated += page.commits
                anyMore = anyMore || page.hasMore
            }
            guard generation == logLoadGeneration else { return }
            commits = aggregated.sorted {
                ($0.authoredAt ?? .distantPast) > ($1.authoredAt ?? .distantPast)
            }
            hasMoreCommits = anyMore
        } catch {
            guard generation == logLoadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func restoreDetailSelection() async {
        if metadata.lastDetailSelection == "commit",
           let objectID = metadata.selectedCommitOID,
           let commit = commits.first(where: { $0.objectID == objectID })
        {
            await selectCommit(commit)
            return
        }
        if metadata.lastDetailSelection == "change",
           let path = metadata.selectedLocalPath,
           let change = snapshot.roots.flatMap(\.changes).first(where: {
               $0.path == path
           })
        {
            let staged = metadata.workflow == .staging
                && change.index != nil
                && change.workingTree == nil
            selectedChangeListID = (staged ? "staged:" : "working:") + change.id
            await selectChange(
                change,
                source: staged ? .staged : .workingTree
            )
        }
    }

    private func reconcileChangelistEntries() async {
        var changed = false
        for listIndex in metadata.changelists.indices {
            for entryIndex in metadata.changelists[listIndex].entries.indices {
                guard let selectedPatch = metadata.changelists[listIndex]
                    .entries[entryIndex].patch
                else {
                    continue
                }
                let entry = metadata.changelists[listIndex].entries[entryIndex]
                guard let root = snapshot.roots.first(where: {
                    $0.rootURL.path == entry.rootPath
                }) else {
                    if !entry.needsConfirmation {
                        metadata.changelists[listIndex].entries[entryIndex]
                            .needsConfirmation = true
                        changed = true
                    }
                    continue
                }
                let currentPatch = try? await service.diff(
                    rootURL: root.rootURL,
                    source: .workingTree,
                    path: entry.path
                ).patch
                if let currentPatch,
                   entry.fingerprint == currentPatch.gitFingerprint,
                   !entry.needsConfirmation
                {
                    continue
                }
                let needsConfirmation = currentPatch.map {
                    GitPatchRemapper.requiresConfirmation(
                        selectedPatch: selectedPatch,
                        currentPatch: $0
                    )
                } ?? true
                if entry.needsConfirmation != needsConfirmation {
                    metadata.changelists[listIndex].entries[entryIndex]
                        .needsConfirmation = needsConfirmation
                    changed = true
                }
            }
        }
        if changed {
            persistMetadata()
        }
    }

    private func runMutation(
        title: String,
        rootURL: URL,
        onError: ((Error) -> Bool)? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        Task {
            do {
                try await operationRegistry.run(
                    workspaceURL: workspaceURL,
                    rootURL: rootURL,
                    title: title,
                    isMutation: true,
                    operation: operation
                )
                await refresh()
            } catch {
                if onError?(error) == true {
                    errorMessage = nil
                    errorGuidanceKey = nil
                    await refresh()
                    return
                }
                errorMessage = error.localizedDescription
                if title.hasPrefix("Push"),
                   (
                       error.localizedDescription.localizedCaseInsensitiveContains(
                           "rejected"
                       ) || error.localizedDescription.localizedCaseInsensitiveContains(
                           "non-fast-forward"
                       )
                   )
                {
                    errorGuidanceKey = "Push 被拒绝；请先选择 Merge 或 Rebase 更新后重试。"
                } else if error.localizedDescription.contains("index.lock") {
                    errorGuidanceKey = "Git Index 正被其他进程使用；Breath 不会删除 index.lock。"
                } else {
                    errorGuidanceKey = nil
                }
                await refresh()
            }
        }
    }

    private func ensureNoSequencedOperation() -> Bool {
        guard let sequencedOperation else { return true }
        errorGuidanceKey = "请先 Continue、Skip 或 Abort 当前 Git 序列操作。"
        errorMessage = sequencedOperation.kind.rawValue
        return false
    }

    private func withSafetySnapshot(
        action: String,
        root: GitRootSnapshot,
        onError: ((Error) -> Bool)? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        let retention = preferencesStore.preferences.snapshotRetentionWorkingDays
        runMutation(
            title: action,
            rootURL: root.rootURL,
            onError: onError
        ) {
            _ = await self.snapshotStore.create(
                rootURL: root.rootURL,
                action: action,
                retentionWorkingDays: retention
            )
            try await operation()
        }
    }

    private func synchronizeMutation(
        title: String,
        operation: @escaping @Sendable (
            GitWorkbenchService,
            GitRootSnapshot
        ) async throws -> Void
    ) {
        let roots = snapshot.roots.filter { !$0.isSubmoduleRoot }
        let service = service
        let registry = operationRegistry
        let workspaceURL = workspaceURL
        let snapshotStore = snapshotStore
        let retention = preferencesStore.preferences.snapshotRetentionWorkingDays
        Task {
            var failures: [String] = []
            await withTaskGroup(of: String?.self) { group in
                for root in roots {
                    group.addTask {
                        do {
                            _ = await snapshotStore.create(
                                rootURL: root.rootURL,
                                action: title,
                                retentionWorkingDays: retention
                            )
                            try await registry.run(
                                workspaceURL: workspaceURL,
                                rootURL: root.rootURL,
                                title: title,
                                isMutation: true
                            ) {
                                try await operation(service, root)
                            }
                            return nil
                        } catch {
                            return "\(root.rootURL.lastPathComponent): "
                                + error.localizedDescription
                        }
                    }
                }
                for await failure in group {
                    if let failure {
                        failures.append(failure)
                    }
                }
            }
            if !failures.isEmpty {
                errorMessage = failures.joined(separator: "\n")
            }
            await refresh()
        }
    }

    @discardableResult
    private func persistMetadata() -> Task<Bool, Never> {
        let metadata = metadata
        let previousSave = metadataSaveTask
        let store = metadataStore
        let workspaceURL = workspaceURL
        let task = Task { [weak self] in
            _ = await previousSave?.value
            do {
                try await store.save(metadata, workspaceURL: workspaceURL)
                return true
            } catch {
                self?.errorMessage = error.localizedDescription
                return false
            }
        }
        metadataSaveTask = task
        return task
    }

    private func present(_ error: Error) {
        if case GitExecutableError.unsupportedVersion(
            let actual,
            let minimum
        ) = error {
            errorGuidanceKey = "Git 版本过旧；请升级 Git 后重试。"
            errorMessage = "Git \(actual) · ≥ \(minimum)"
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private func startRefreshLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.isActive ? 3.0 : 15.0
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    private func refreshServiceConfigurationIfNeeded() {
        let executableURL = preferencesStore.resolvedGitExecutableURL
        guard service.gitExecutableURL != executableURL.standardizedFileURL else {
            return
        }
        service = GitWorkbenchService(
            workspaceURL: workspaceURL,
            gitExecutableURL: executableURL,
            metadataStore: metadataStore
        )
        snapshotStore = GitSafetySnapshotStore(
            gitExecutableURL: executableURL
        )
    }

    private func configureRepositoryWatcher() {
        let urls = snapshot.roots.flatMap { root -> [URL] in
            var watched = [
                root.rootURL,
                root.rootURL.appendingPathComponent(".git", isDirectory: true),
            ]
            watched += Set(
                root.changes.map {
                    root.rootURL
                        .appendingPathComponent($0.path)
                        .deletingLastPathComponent()
                }
            )
            return watched
        }
        let paths = Set(urls.map(\.standardizedFileURL.path))
        guard repositoryWatcher?.watchedPaths != paths else { return }
        repositoryWatcher = GitRepositoryWatcher(urls: urls) { [weak self] in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    private func startAutoFetchLoop() {
        autoFetchTask?.cancel()
        let minutes = preferencesStore.preferences.autoFetchMinutes
        guard minutes > 0 else { return }
        autoFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let multiplier = self.isActive ? 1.0 : 3.0
                try? await Task.sleep(
                    for: .seconds(Double(minutes) * 60 * multiplier)
                )
                guard !Task.isCancelled else { return }
                self.fetch()
            }
        }
    }

    private func resolvedSelectedRootID() -> GitRootID? {
        if let path = metadata.selectedRootPath,
           let root = snapshot.roots.first(where: { $0.rootURL.path == path })
        {
            return root.id
        }
        return snapshot.roots.first?.id
    }

    private var selectedRootsForRead: [GitRootSnapshot] {
        if let selectedRootID,
           let root = snapshot.roots.first(where: { $0.id == selectedRootID })
        {
            return [root]
        }
        return snapshot.roots
    }

    private var selectedRootsForMutation: [GitRootSnapshot] {
        if let selectedRoot {
            return [selectedRoot]
        }
        return snapshot.roots.filter { !$0.isSubmoduleRoot }
    }

    private var selectedChange: GitLocalChange? {
        snapshot.roots
            .flatMap(\.changes)
            .first { $0.id == selectedChangeID }
    }

    private var selectedDiffRoot: GitRootSnapshot? {
        guard let rootID = selectedDiff?.rootID else {
            return selectedRoot
        }
        return snapshot.roots.first { $0.id == rootID }
    }

    private func root(containing change: GitLocalChange) -> GitRootSnapshot? {
        if let selectedRoot,
           selectedRoot.changes.contains(where: { $0.id == change.id })
        {
            return selectedRoot
        }
        return snapshot.roots.first {
            $0.changes.contains(where: { $0.id == change.id })
        }
    }

    private var defaultChangelistIndex: Int? {
        guard let id = metadata.defaultChangelistID else {
            return metadata.changelists.indices.first
        }
        return metadata.changelists.firstIndex { $0.id == id }
    }

    private var commitDraftKey: String {
        switch metadata.workflow {
        case .staging:
            return "staging:\(selectedRootID?.rawValue ?? "all")"
        case .changelists:
            return "changelist:\(metadata.defaultChangelistID?.uuidString ?? "default")"
        }
    }
}

private extension GitWorkbenchService {
    func replaceIndexFile(
        rootURL: URL,
        path: String,
        contents: String
    ) async throws {
        let modeResult = try await requiredGit(
            rootURL: rootURL,
            arguments: ["ls-files", "-s", "--", path]
        )
        let mode = modeResult.standardOutput
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? "100644"
        let hashResult = try await runner.run(
            arguments: ["-C", rootURL.path, "hash-object", "-w", "--stdin"],
            standardInput: Data(contents.utf8)
        )
        guard hashResult.exitCode == 0 else {
            throw GitCommandError.failed(
                command: hashResult.displayCommand,
                exitCode: hashResult.exitCode,
                output: hashResult.combinedOutput
            )
        }
        let objectID = hashResult.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await requiredGit(
            rootURL: rootURL,
            arguments: [
                "update-index",
                "--cacheinfo",
                "\(mode),\(objectID),\(path)",
            ]
        )
    }
}

private extension String {
    var gitFingerprint: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    var nilIfEmpty: String? { isEmpty ? nil : self }
}
