import AppKit
import BreathCore
import SwiftUI
import UniformTypeIdentifiers

private enum GitWorkbenchFocusField: Hashable {
    case branchSearch
    case commitMessage
    case logSearch
}

private enum GitToolbarMetrics {
    static let iconPointSize: CGFloat = 12
    static let iconFrameSize: CGFloat = 14
}

enum GitErrorPresentation {
    private static let maximumLines = 8
    private static let maximumCharacters = 640

    static func summary(
        _ message: String,
        truncationNotice: String
    ) -> String {
        let normalized = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let lines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        var visible = lines.prefix(maximumLines).joined(separator: "\n")
        var wasTruncated = lines.count > maximumLines
        if visible.count > maximumCharacters {
            visible = String(visible.prefix(maximumCharacters))
            wasTruncated = true
        }
        guard wasTruncated else { return normalized }
        return visible.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\n"
            + truncationNotice
    }
}

enum GitCommitTimeFormatter {
    static func string(
        for date: Date,
        relativeTo now: Date = Date(),
        locale: Locale,
        justNow: String
    ) -> String {
        guard abs(date.timeIntervalSince(now)) >= 60 else {
            return justNow
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

private struct GitDiffFileRequest: Equatable {
    let id = UUID()
    let path: String
}

private struct GitUpstreamRequest: Identifiable {
    var id: String { branch.id }

    let branch: GitReference
    let choices: [GitReference]
}

private struct GitDialogAction: Identifiable {
    let id = UUID()
    let title: String
    let role: ButtonRole?
    let isDefault: Bool
    let perform: () -> Void
}

private enum GitDialogContent {
    case text(
        initialValue: String,
        placeholder: String?,
        submitTitle: String,
        submit: (String) -> Void
    )
    case confirmation(actions: [GitDialogAction])
}

private struct GitDialogRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let content: GitDialogContent
}

struct GitWorkspaceChoice: Identifiable, Equatable {
    let id: String
    let workspace: Workspace
    let displayName: String

    init(workspace: Workspace, displayName: String? = nil) {
        id = URL(
            fileURLWithPath: workspace.path,
            isDirectory: true
        ).standardizedFileURL.path
        self.workspace = workspace
        self.displayName = displayName ?? workspace.displayName
    }
}

struct GitWorkbenchUnselectedView: View {
    let workspaces: [GitWorkspaceChoice]
    let onSelectWorkspace: (String) -> Void

    @Environment(\.applicationLanguage) private var applicationLanguage

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(localizer.string("Git 工作台"))
                    .font(.headline)

                Picker("", selection: workspaceSelection) {
                    Text(localizer.string("请选择")).tag(String?.none)
                    ForEach(workspaces) { workspace in
                        Text(workspace.displayName).tag(Optional(workspace.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(localizer.string("Git 目录"))

                Spacer(minLength: 0)
            }
            .pageToolbarLeadingPadding()
            .padding(.trailing, WorkbenchLayout.pageToolbarTrailingInset)
            .frame(height: WorkbenchLayout.pageToolbarHeight)

            Divider()
            Color(nsColor: .windowBackgroundColor)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string("Git 工作台"))
    }

    private var workspaceSelection: Binding<String?> {
        Binding(
            get: { nil },
            set: { workspacePath in
                guard let workspacePath else { return }
                onSelectWorkspace(workspacePath)
            }
        )
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

struct GitWorkbenchView: View {
    let workspace: Workspace
    let workspaces: [GitWorkspaceChoice]
    @ObservedObject var model: GitWorkspaceViewModel
    @ObservedObject private var preferencesStore: GitPreferencesStore
    let isVisible: Bool
    let onAddWorkspace: (URL) -> Void
    let onSelectWorkspace: (String) -> Void

    @Environment(\.applicationLanguage) private var applicationLanguage
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingBranchCreator = false
    @State private var showingPush = false
    @State private var showingAuthentication = false
    @State private var showingStashes = false
    @State private var showingWorkspaceSettings = false
    @State private var showingSnapshots = false
    @State private var showingEditor = false
    @State private var showingConflictResolver = false
    @State private var showingFileHistory = false
    @State private var showingBlame = false
    @State private var showingInteractiveRebase = false
    @State private var showingRemoteBranches = false
    @State private var branchName = ""
    @State private var remoteName = "origin"
    @State private var includeTags = false
    @State private var forceWithLease = false
    @State private var pushUpToOID: String?
    @State private var stashMessage = ""
    @State private var stashIncludeUntracked = true
    @State private var stashKeepIndex = false
    @State private var shelfName = ""
    @State private var commitSearch = ""
    @State private var historyPath = ""
    @State private var rebaseBase = ""
    @State private var rebaseSteps: [GitHistoryEditStep] = []
    @State private var selectedBranchReferenceID: String?
    @State private var upstreamRequest: GitUpstreamRequest?
    @State private var selectedDiffFileRequest: GitDiffFileRequest?
    @State private var dialogRequest: GitDialogRequest?
    @FocusState private var focusedField: GitWorkbenchFocusField?

    init(
        workspace: Workspace,
        workspaces: [GitWorkspaceChoice],
        model: GitWorkspaceViewModel,
        isVisible: Bool,
        onAddWorkspace: @escaping (URL) -> Void,
        onSelectWorkspace: @escaping (String) -> Void
    ) {
        self.workspace = workspace
        self.workspaces = workspaces
        _model = ObservedObject(wrappedValue: model)
        _preferencesStore = ObservedObject(
            wrappedValue: model.preferencesStore
        )
        self.isVisible = isVisible
        self.onAddWorkspace = onAddWorkspace
        self.onSelectWorkspace = onSelectWorkspace
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            externalRootWarnings
            conflictBanner
            content
            console
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            shortcutCommandHost
        }
        .task {
            await Task.yield()
            presentPendingCommand()
        }
        .onChange(of: isVisible, initial: true) { _, visible in
            if visible {
                model.activate()
            } else {
                model.deactivate()
            }
        }
        .onDisappear {
            model.deactivate()
        }
        .onChange(of: workspace.id) { _, _ in
            selectedBranchReferenceID = nil
        }
        .onChange(of: model.selectedRootID) { _, _ in
            selectedBranchReferenceID = nil
        }
        .onChange(of: model.metadata.logFilter) { _, _ in
            Task { await model.refresh() }
        }
        .onChange(of: preferencesStore.preferences.diff.ignoreWhitespace) { _, _ in
            Task { await model.reloadSelectedDetail() }
        }
        .onChange(of: preferencesStore.preferences.diff.foldUnchanged) { _, _ in
            Task { await model.reloadSelectedDetail() }
        }
        .onChange(of: preferencesStore.preferences) { previous, current in
            model.applyGlobalPreferencesChange(from: previous, to: current)
        }
        .alert(
            localizer.string("Git 操作失败"),
            isPresented: errorPresented
        ) {
            Button(localizer.string("查看 Git Console")) {
                model.metadata.layout.isConsoleVisible = true
                model.saveWorkspaceMetadata()
                model.errorMessage = nil
                model.errorGuidanceKey = nil
            }
            Button(localizer.string("好")) {
                model.errorMessage = nil
                model.errorGuidanceKey = nil
            }
        } message: {
            Text(
                GitErrorPresentation.summary(
                    [
                        model.errorGuidanceKey.map(localizer.string),
                        model.errorMessage,
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n\n"),
                    truncationNotice: localizer.string(
                        "完整输出已省略，请在 Git Console 中查看。"
                    )
                )
            )
        }
        .sheet(isPresented: $showingBranchCreator) {
            branchCreator
        }
        .sheet(isPresented: $showingPush) {
            pushSheet
        }
        .sheet(isPresented: $showingAuthentication) {
            authenticationSheet
        }
        .sheet(isPresented: $showingStashes) {
            stashAndShelfSheet
        }
        .sheet(isPresented: $showingWorkspaceSettings) {
            workspaceSettingsSheet
        }
        .sheet(isPresented: $showingSnapshots) {
            snapshotSheet
        }
        .sheet(isPresented: $showingEditor) {
            editableFileSheet
        }
        .sheet(isPresented: $showingConflictResolver) {
            conflictResolverSheet
        }
        .sheet(isPresented: $showingFileHistory) {
            fileHistorySheet
        }
        .sheet(isPresented: $showingBlame) {
            blameSheet
        }
        .sheet(isPresented: $showingInteractiveRebase) {
            interactiveRebaseSheet
        }
        .sheet(item: $upstreamRequest) { request in
            upstreamSheet(request)
        }
        .sheet(item: checkoutConflictBinding) { request in
            checkoutConflictDialog(request)
        }
        .sheet(item: primaryDialogRequest) { request in
            gitDialog(request)
        }
        .onChange(of: model.shouldPresentPushReview) { _, shouldPresent in
            guard shouldPresent else { return }
            presentPendingCommand()
        }
        .onChange(of: model.shouldFocusCommitMessage) { _, shouldFocus in
            guard shouldFocus else { return }
            presentPendingCommand()
        }
        .onChange(of: showingPush) { _, isShowing in
            if !isShowing && !showingAuthentication {
                model.clearAuthentication()
            }
        }
        .onChange(of: showingAuthentication) { _, isShowing in
            if !isShowing && !showingPush {
                model.clearAuthentication()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string("Git 工作台"))
    }

    private var primaryDialogRequest: Binding<GitDialogRequest?> {
        Binding(
            get: { showingStashes ? nil : dialogRequest },
            set: { request in
                if !showingStashes {
                    dialogRequest = request
                }
            }
        )
    }

    private func gitDialog(_ request: GitDialogRequest) -> some View {
        GitCompactDialog(
            request: request,
            cancelTitle: localizer.string("取消"),
            onDismiss: { dialogRequest = nil }
        )
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(localizer.string("Git 工作台"))
                .font(.headline)

            workspacePicker
            if model.snapshot.roots.count > 1 {
                rootPicker
            }
            toolbarButton(
                "arrow.clockwise",
                "刷新",
                shortcutID: "git.refresh",
                requiresRoot: false
            ) {
                Task { await model.refresh() }
            }
            .gitKeyboardShortcut(
                "git.refresh",
                preferences: model.preferencesStore.preferences
            )

            Spacer(minLength: 8)

            toolbarLabeledButton(
                "arrow.down.circle",
                "Fetch",
                shortcutID: "git.fetch",
                requiresRoot: false
            ) {
                model.fetch()
            }
            .gitKeyboardShortcut(
                "git.fetch",
                preferences: model.preferencesStore.preferences
            )

            toolbarLabeledButton(
                "arrow.down.to.line",
                "Pull"
            ) {
                model.pull(strategy: preferredPullStrategy)
            }
            .disabled(
                model.selectedRoot == nil || model.sequencedOperation != nil
            )

            toolbarLabeledButton(
                "arrow.up.to.line",
                "Push",
                shortcutID: "git.push"
            ) {
                pushUpToOID = nil
                showingPush = true
            }
            .gitKeyboardShortcut(
                "git.push",
                preferences: model.preferencesStore.preferences
            )
            .disabled(
                model.selectedRoot == nil || model.sequencedOperation != nil
            )

            Menu {
                Button {
                    model.setPreferredPullStrategy(.merge)
                } label: {
                    if preferredPullStrategy == .merge {
                        Label(localizer.string("Merge"), systemImage: "checkmark")
                    } else {
                        Text(localizer.string("Merge"))
                    }
                }
                Button {
                    model.setPreferredPullStrategy(.rebase)
                } label: {
                    if preferredPullStrategy == .rebase {
                        Label(localizer.string("Rebase"), systemImage: "checkmark")
                    } else {
                        Text(localizer.string("Rebase"))
                    }
                }
            } label: {
                toolbarIcon("wrench.and.screwdriver")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(localizer.string("Pull 更新策略"))
            .accessibilityLabel(localizer.string("Pull 更新策略"))
            .accessibilityValue(
                localizer.string(
                    preferredPullStrategy == .merge ? "Merge" : "Rebase"
                )
            )
            .disabled(model.selectedRoot == nil)

            Spacer()
                .frame(width: 4)

            Menu {
                Button(localizer.string("Git Stash 与 Shelf")) {
                    showingStashes = true
                }
                Button(localizer.string("Git 安全快照")) {
                    showingSnapshots = true
                }
                Button(localizer.string("Undo Last Commit…")) {
                    confirmUndoLastCommit()
                }
                .disabled(model.selectedRoot == nil)
                Divider()
                Button(localizer.string("工作区 Git 设置")) {
                    showingWorkspaceSettings = true
                }
            } label: {
                toolbarIcon("ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(localizer.string("更多 Git 操作"))
        }
        .pageToolbarLeadingPadding()
        .padding(.trailing, WorkbenchLayout.pageToolbarTrailingInset)
        .frame(height: WorkbenchLayout.pageToolbarHeight)
    }

    private var workspacePicker: some View {
        Picker(
            "",
            selection: Binding(
                get: { selectedWorkspaceID },
                set: { workspacePath in
                    guard workspacePath != selectedWorkspaceID else { return }
                    onSelectWorkspace(workspacePath)
                }
            )
        ) {
            ForEach(workspaces) { candidate in
                Text(candidate.displayName).tag(candidate.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
        .fixedSize()
        .help(workspace.path)
        .accessibilityLabel(localizer.string("Git 目录"))
    }

    private var selectedWorkspaceID: String {
        URL(
            fileURLWithPath: workspace.path,
            isDirectory: true
        ).standardizedFileURL.path
    }

    private var preferredPullStrategy: GitPullStrategy {
        model.metadata.preferredPullStrategy ?? .merge
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView(localizer.string("正在读取 Git 仓库…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.snapshot.roots.isEmpty {
            emptyState
        } else {
            GitThreeColumnLayout(
                initialLeftWidth: model.metadata.layout.leftWidth,
                initialCenterWidth: model.metadata.layout.centerWidth,
                resizeAccessibilityLabel: localizer.string("调整 Git 列宽"),
                onResizeEnded: { leftWidth, centerWidth in
                    model.metadata.layout.leftWidth = leftWidth
                    model.metadata.layout.centerWidth = centerWidth
                    model.saveWorkspaceMetadata()
                },
                left: { changesAndCommitPane },
                center: { logPane },
                right: { detailsPane }
            )
        }
    }

    private func diffLayoutButton(
        _ layout: GitDiffLayout,
        systemImage: String,
        title: String
    ) -> some View {
        let isSelected = preferencesStore.preferences.diff.layout == layout
        return Button {
            preferencesStore.setDiffLayout(layout)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 26, height: 20)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.14))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizer.string(title))
            .help(localizer.string(title))
    }

    private var changesAndCommitPane: some View {
        VStack(spacing: 0) {
            branchList
            Divider()
            changesHeader
            changesList
            Divider()
            commitPanel
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string("分支与本地变更"))
    }

    private var branchList: some View {
        let localBranches = visibleBranches(of: .localBranch)
        let remoteBranches = visibleBranches(of: .remoteBranch)
        let branchFilter = model.metadata.branchFilter ?? ""
        let remoteBranchesAreVisible = showingRemoteBranches
            || !branchFilter.isEmpty
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(localizer.string("分支"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.selectedRoot == nil, model.snapshot.roots.count > 1 {
                    allRepositoriesBranchMenu
                }
                Button {
                    showingBranchCreator = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help(localizer.string("新建分支"))
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            TextField(
                localizer.string("搜索分支"),
                text: Binding(
                    get: { model.metadata.branchFilter ?? "" },
                    set: {
                        model.metadata.branchFilter = $0
                        model.saveWorkspaceMetadata()
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 9)
            .focused($focusedField, equals: .branchSearch)
            .gitKeyboardShortcut(
                "git.branches",
                preferences: preferencesStore.preferences
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .opacity(0)
                            .frame(width: 10)
                        Text(localizer.string("本地分支"))
                        Spacer(minLength: 4)
                        Text("\(localBranches.count)")
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.top, 3)

                    ForEach(localBranches) { reference in
                        branchRow(reference)
                    }

                    if localBranches.isEmpty, remoteBranches.isEmpty {
                        BreathEmptyState(
                            title: localizer.string(
                                branchFilter.isEmpty
                                    ? "没有可用的分支"
                                    : "没有匹配的分支"
                            ),
                            style: .passive,
                            placement: .inline
                        )
                        .padding(.horizontal, 9)
                    }

                    if !remoteBranches.isEmpty {
                        Button {
                            showingRemoteBranches.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(
                                    systemName: remoteBranchesAreVisible
                                        ? "chevron.down"
                                        : "chevron.right"
                                )
                                    .frame(width: 10)
                                Text(localizer.string("远程分支"))
                                Spacer(minLength: 4)
                                Text("\(remoteBranches.count)")
                                    .monospacedDigit()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.top, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if remoteBranchesAreVisible {
                            ForEach(remoteBranches) { reference in
                                branchRow(reference)
                                    .padding(.leading, 10)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
        }
    }

    private func visibleBranches(of kind: GitReferenceKind) -> [GitReference] {
        let filter = model.metadata.branchFilter ?? ""
        let favorites = model.metadata.favoriteReferenceNames ?? []
        return model.references.filter { reference in
            reference.kind == kind
                && (
                    filter.isEmpty
                        || reference.shortName.localizedCaseInsensitiveContains(filter)
                )
        }.sorted {
            let leftFavorite = favorites.contains($0.fullName)
            let rightFavorite = favorites.contains($1.fullName)
            if leftFavorite != rightFavorite {
                return leftFavorite
            }
            return $0.shortName.localizedStandardCompare($1.shortName)
                == .orderedAscending
        }
    }

    private func branchRow(_ reference: GitReference) -> some View {
        Button {
            selectedBranchReferenceID = reference.id
        } label: {
            HStack(spacing: 6) {
                Image(
                    systemName: reference.isCurrent
                        ? "checkmark"
                        : "arrow.triangle.branch"
                )
                    .frame(width: 14)
                    .foregroundStyle(reference.isCurrent ? .green : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(reference.shortName)
                        .lineLimit(1)
                    if reference.shortName.contains("/") {
                        Text(
                            reference.shortName.split(
                                separator: "/"
                            ).dropLast().joined(separator: "/")
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(
                    systemName: (
                        model.metadata.favoriteReferenceNames ?? []
                    ).contains(reference.fullName)
                        ? "star.fill"
                        : "star"
                )
                .foregroundStyle(.secondary)
                if let track = reference.upstreamTrack, !track.isEmpty {
                    Text(track)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if isBranchSelected(reference) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            Color(nsColor: .selectedContentBackgroundColor)
                                .opacity(colorScheme == .dark ? 0.42 : 0.24)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    checkoutBranch(reference)
                }
        )
        .contextMenu {
            branchContextMenu(reference)
        }
        .accessibilityLabel(
            reference.isCurrent
                ? localizer.format("当前分支 %@", reference.shortName)
                : reference.shortName
        )
        .accessibilityAddTraits(
            isBranchSelected(reference) ? .isSelected : []
        )
        .accessibilityAction(named: Text(localizer.string("Checkout"))) {
            checkoutBranch(reference)
        }
    }

    private func checkoutBranch(_ reference: GitReference) {
        guard !reference.isCurrent else { return }
        model.checkout(reference: reference)
    }

    @ViewBuilder
    private func branchContextMenu(_ reference: GitReference) -> some View {
        Button(localizer.string("收藏分支")) {
            model.toggleFavoriteReference(reference)
        }
        Button(localizer.string("从此分支创建…")) {
            branchName = ""
            commitSearch = reference.shortName
            showingBranchCreator = true
        }
        Button(localizer.string("Checkout")) {
            model.checkout(reference: reference)
        }
        Button(localizer.string("Checkout and Update")) {
            model.checkoutAndUpdate(reference: reference)
        }
        Button(localizer.string("Merge 到当前分支")) {
            confirmBranchOperation(
                kind: "Merge",
                reference: reference.shortName
            )
        }
        Button(localizer.string("Rebase 当前分支到这里")) {
            confirmBranchOperation(
                kind: "Rebase",
                reference: reference.shortName
            )
        }
        if reference.kind == .localBranch {
            Divider()
            Button(localizer.string("重命名…")) {
                promptRenameBranch(reference.shortName)
            }
            Button(localizer.string("设置 Upstream…")) {
                upstreamRequest = GitUpstreamRequest(
                    branch: reference,
                    choices: model.references.filter {
                        $0.kind == .remoteBranch
                    }
                )
            }
            Button(
                localizer.string("删除分支"),
                role: .destructive
            ) {
                confirmDeleteBranch(reference.shortName)
            }
        } else {
            Divider()
            Button(
                localizer.string("删除远程分支"),
                role: .destructive
            ) {
                confirmDeleteRemoteBranch(reference)
            }
        }
    }

    private func isBranchSelected(_ reference: GitReference) -> Bool {
        if let selectedBranchReferenceID,
           model.references.contains(where: { $0.id == selectedBranchReferenceID })
        {
            return selectedBranchReferenceID == reference.id
        }
        return reference.isCurrent
    }

    private var changesHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Label(localizer.string("本地变更"), systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.metadata.workflow == .changelists {
                    Button {
                        promptCreateChangelist()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(localizer.string("新建变更列表"))
                }
                Picker(
                    "",
                    selection: Binding(
                        get: { model.metadata.workflow },
                        set: { model.setWorkflow($0) }
                    )
                ) {
                    Text(localizer.string("变更列表")).tag(GitChangeWorkflow.changelists)
                    Text(localizer.string("暂存区")).tag(GitChangeWorkflow.staging)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .labelsHidden()
                .accessibilityLabel(localizer.string("本地变更工作流"))
            }
            TextField(
                localizer.string("过滤文件"),
                text: Binding(
                    get: { model.metadata.localFilter },
                    set: {
                        model.metadata.localFilter = $0
                        model.saveWorkspaceMetadata()
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var changesList: some View {
        List(selection: $model.selectedChangeListID) {
            if model.metadata.workflow == .staging {
                Section {
                    ForEach(model.visibleChanges.filter { $0.workingTree != nil }) {
                        changeRow($0, stagedSection: false)
                    }
                } header: {
                    stagingSectionHeader(
                        title: localizer.string("未暂存"),
                        actionTitle: localizer.string("全部暂存"),
                        systemImage: "plus.circle",
                        isDisabled: !model.hasUnstagedChanges,
                        action: model.stageAll
                    )
                }
                Section {
                    ForEach(model.visibleChanges.filter { $0.index != nil }) {
                        changeRow($0, stagedSection: true)
                    }
                } header: {
                    stagingSectionHeader(
                        title: localizer.string("已暂存"),
                        actionTitle: localizer.string("全部取消暂存"),
                        systemImage: "minus.circle",
                        isDisabled: !model.hasStagedChanges,
                        action: model.unstageAll
                    )
                }
            } else {
                ForEach(model.metadata.changelists) { changelist in
                    Section {
                        ForEach(changes(in: changelist)) { change in
                            changeRow(change, stagedSection: false)
                        }
                        ForEach(
                            changelist.entries.filter { $0.patch != nil }
                        ) { entry in
                            HStack {
                                Image(systemName: "scope")
                                    .foregroundStyle(
                                        entry.needsConfirmation
                                            ? .orange
                                            : .secondary
                                    )
                                Text(entry.path)
                                    .lineLimit(1)
                                Spacer()
                                if entry.needsConfirmation {
                                    Button(localizer.string("确认片段归属")) {
                                        model.confirmChangelistEntry(entry.id)
                                    }
                                } else {
                                    Text(localizer.string("部分修改"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        let unassigned = unassignedChanges(for: changelist)
                        ForEach(unassigned) { change in
                            changeRow(change, stagedSection: false)
                        }
                    } header: {
                        HStack {
                            Button {
                                model.setDefaultChangelist(changelist.id)
                            } label: {
                                Image(
                                    systemName: model.metadata.defaultChangelistID == changelist.id
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                            .buttonStyle(.plain)
                            Text(changelist.name)
                            Spacer()
                            Text("\(changelist.entries.count)")
                                .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button(localizer.string("重命名…")) {
                                promptRenameChangelist(changelist)
                            }
                            Button(
                                localizer.string("删除变更列表"),
                                role: .destructive
                            ) {
                                model.deleteChangelist(changelist.id)
                            }
                            .disabled(model.metadata.changelists.count == 1)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .scrollPosition(
            id: Binding(
                get: { model.metadata.localScrollAnchor },
                set: { anchor in
                    guard model.metadata.localScrollAnchor != anchor else { return }
                    model.metadata.localScrollAnchor = anchor
                }
            )
        )
        .onChange(of: model.selectedChangeListID) { _, selectionID in
            guard let selectionID,
                  let parsed = parseChangeSelection(selectionID),
                  let change = model.snapshot.roots
                    .flatMap(\.changes)
                    .first(where: { $0.id == parsed.changeID })
            else {
                return
            }
            Task {
                await model.selectChange(
                    change,
                    source: parsed.staged ? .staged : .workingTree
                )
            }
        }
    }

    private func stagingSectionHeader(
        title: String,
        actionTitle: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Label(actionTitle, systemImage: systemImage)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .help(actionTitle)
            .accessibilityLabel(actionTitle)
        }
    }

    private func changeRow(
        _ change: GitLocalChange,
        stagedSection: Bool
    ) -> some View {
        HStack(spacing: 6) {
            changeStatusIcon(change, stagedSection: stagedSection)
            VStack(alignment: .leading, spacing: 0) {
                Text(change.path)
                    .lineLimit(1)
                if model.selectedRoot == nil,
                   let root = model.snapshot.roots.first(where: {
                       $0.changes.contains(where: { $0.id == change.id })
                   })
                {
                    Text(root.rootURL.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if model.metadata.workflow == .staging {
                Button {
                    stagedSection ? model.unstage(change) : model.stage(change)
                } label: {
                    Image(systemName: stagedSection ? "minus.circle" : "plus.circle")
                }
                .buttonStyle(.plain)
                .help(localizer.string(stagedSection ? "取消暂存" : "暂存"))
            } else {
                Button {
                    model.toggleChangeInDefaultChangelist(change)
                } label: {
                    Image(
                        systemName: isInDefaultChangelist(change)
                            ? "checkmark.square.fill"
                            : "square"
                    )
                }
                .buttonStyle(.plain)
                .help(localizer.string("包含在默认变更列表"))
            }
        }
        .tag(changeSelectionID(change, staged: stagedSection))
        .contextMenu {
            Button(localizer.string("在可编辑 Diff 中打开")) {
                model.openEditableFile(
                    path: change.path,
                    staged: stagedSection,
                    rootID: change.rootID
                )
                showingEditor = true
            }
            Button(localizer.string("File History")) {
                historyPath = change.path
                model.loadFileHistory(change: change)
                showingFileHistory = true
            }
            Button(localizer.string("Blame / Annotate")) {
                historyPath = change.path
                model.loadBlame(change: change)
                showingBlame = true
            }
            if change.index == .conflicted || change.workingTree == .conflicted {
                Button(localizer.string("解决冲突…")) {
                    model.loadConflict(
                        path: change.path,
                        rootID: change.rootID
                    )
                    showingConflictResolver = true
                }
            }
            if stagedSection {
                Button(localizer.string("取消暂存")) { model.unstage(change) }
            } else {
                Button(localizer.string("暂存")) { model.stage(change) }
                if model.metadata.workflow == .changelists {
                    Menu(localizer.string("移动到变更列表")) {
                        ForEach(model.metadata.changelists) { changelist in
                            Button(changelist.name) {
                                model.moveChange(change, to: changelist.id)
                            }
                        }
                    }
                }
                Button(localizer.string("Rollback 文件"), role: .destructive) {
                    confirmRollback(change)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            localizer.format(
                "Git 变更 %@ %@",
                change.path,
                changeStatusLabel(change, stagedSection: stagedSection)
            )
        )
    }

    private var commitPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if model.selectedRoot == nil, model.snapshot.roots.count > 1 {
                    let roots = model.snapshot.roots.filter { !$0.isSubmoduleRoot }
                    ExplanationLabel(
                        localizer.format(
                            "将分别提交 %d 个 Root，不保证跨 Root 原子性",
                            roots.count
                        )
                            + "\n"
                            + roots.map {
                                "• \($0.rootURL.lastPathComponent): "
                                    + localizer.format(
                                        "%d 个文件",
                                        $0.changes.count
                                    )
                            }.joined(separator: "\n")
                    ) {
                        Text(localizer.string("提交信息"))
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text(localizer.string("提交信息"))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Menu {
                    if !model.recentCommitMessages.isEmpty {
                        Menu(localizer.string("最近提交信息")) {
                            ForEach(model.recentCommitMessages, id: \.self) { message in
                                Button(message.components(separatedBy: "\n").first ?? message) {
                                    model.currentCommitDraft = message
                                }
                            }
                        }
                        Divider()
                    }
                    Button(localizer.string("Amend")) {
                        confirmAmend()
                    }
                    Button(localizer.string("签名提交")) {
                        model.commit(sign: true)
                    }
                    Button(localizer.string("本次跳过 Hooks")) {
                        model.commit(skipHooks: true)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            GitCommitMessageEditor(
                text: Binding(
                    get: { model.currentCommitDraft },
                    set: { model.currentCommitDraft = $0 }
                ),
                isFocused: Binding(
                    get: { focusedField == .commitMessage },
                    set: { isFocused in
                        if isFocused {
                            focusedField = .commitMessage
                        } else if focusedField == .commitMessage {
                            focusedField = nil
                        }
                    }
                )
            )
            .frame(minHeight: 72, maxHeight: 130)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.25))
            }
            .accessibilityLabel(localizer.string("提交信息"))

            HStack {
                Button(localizer.string("Commit")) {
                    model.commit()
                }
                .gitKeyboardShortcut(
                    "git.commit",
                    preferences: model.preferencesStore.preferences
                )
                .disabled(isCommitActionDisabled)
                Button(localizer.string("Commit and Push")) {
                    model.commit(pushAfter: true)
                }
                .gitKeyboardShortcut(
                    "git.commitAndPush",
                    preferences: model.preferencesStore.preferences
                )
                .disabled(isCommitActionDisabled)
                Spacer()
            }
        }
        .padding(10)
    }

    private var isCommitActionDisabled: Bool {
        model.currentCommitDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty || model.sequencedOperation != nil
    }

    private var logPane: some View {
        let graphLayout = GitGraphLayout(commits: model.commits)
        return NativeSplitView(
            orientation: .vertical,
            position: .fraction(0.6),
            minimumPosition: .points(180),
            maximumPosition: .fraction(0.8),
            minimumSecondLength: 170,
            updatesPosition: false
        ) {
            commitHistoryList(graphLayout: graphLayout)
        } second: {
            selectedCommitInspector
        }
        .accessibilityLabel(localizer.string("Diff 与提交详情"))
    }

    private func commitHistoryList(graphLayout: GitGraphLayout) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ExplanationLabel(
                    localizer.string(
                        "支持 author:、since:、until:、path:、branch:、tag:、hash: 和 root:"
                    )
                ) {
                    Label(
                        localizer.string("提交历史"),
                        systemImage: "point.3.filled.connected.trianglepath.dotted"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 4)
                TextField(
                    localizer.string("搜索提交"),
                    text: Binding(
                        get: { model.metadata.logFilter },
                        set: {
                            model.metadata.logFilter = $0
                            model.saveWorkspaceMetadata()
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(minWidth: 100, idealWidth: 170, maxWidth: 210)
                .focused($focusedField, equals: .logSearch)
                .gitKeyboardShortcut(
                    "git.logSearch",
                    preferences: preferencesStore.preferences
                )
                .accessibilityLabel(localizer.string("搜索提交"))
                Text("\(model.commits.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            Divider()

            List(selection: $model.selectedCommitIDs) {
                ForEach(model.commits) { commit in
                    commitRow(
                        commit,
                        graphRow: graphLayout.rows[commit.id]
                            ?? GitGraphRow(
                                nodeLane: 0,
                                laneCount: 1,
                                connectsFromPreviousRow: false,
                                segments: []
                            )
                    )
                        .tag(commit.id)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            commitContextMenu(commit)
                        }
                }
                if model.hasMoreCommits {
                    Button(localizer.string("加载更多")) {
                        model.loadMoreCommits()
                    }
                }
            }
            .listStyle(.plain)
            .scrollPosition(
                id: Binding(
                    get: { model.metadata.logScrollAnchor },
                    set: { anchor in
                        guard model.metadata.logScrollAnchor != anchor else { return }
                        model.metadata.logScrollAnchor = anchor
                    }
                )
            )
            .onChange(of: model.selectedCommitIDs) { _, objectIDs in
                model.updateCommitSelection(objectIDs)
            }
            .accessibilityLabel(localizer.string("Commit Graph"))
            .accessibilityHint(localizer.string("按时间和拓扑顺序列出提交，可使用方向键浏览"))
        }
    }

    private func commitRow(
        _ commit: GitCommitSummary,
        graphRow: GitGraphRow
    ) -> some View {
        HStack(spacing: 8) {
            GitGraphGlyph(
                row: graphRow,
                isMerge: commit.parentIDs.count > 1
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(commit.subject)
                        .lineLimit(1)
                    if !commit.decorations.isEmpty {
                        Text(commit.decorations.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text(commit.authorName)
                    if let date = commit.authoredAt {
                        Text(
                            GitCommitTimeFormatter.string(
                                for: date,
                                locale: localizer.locale,
                                justNow: localizer.string("刚刚")
                            )
                        )
                    }
                    Text(String(commit.objectID.prefix(8)))
                        .monospaced()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.snapshot.roots.count > 1 {
                Text(rootName(commit.rootID))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: GitCommitGraphMetrics.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            localizer.format(
                "提交 %@，作者 %@，哈希 %@",
                commit.subject,
                commit.authorName,
                String(commit.objectID.prefix(8))
            )
        )
        .accessibilityHint(
            localizer.format(
                "拓扑顺序，%d 个父提交",
                commit.parentIDs.count
            )
        )
    }

    @ViewBuilder
    private var detailsPane: some View {
        VStack(spacing: 0) {
            HStack {
                if let details = model.selectedCommitDetails {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(details.commit.subject)
                            .font(.headline)
                            .lineLimit(1)
                        Text(localizer.format("Commit %@", details.commit.objectID))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } else if model.isLoadingSelectedDetail,
                          let commit = model.focusedCommitForAction
                {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.subject)
                            .font(.headline)
                            .lineLimit(1)
                        Text(localizer.format("Commit %@", commit.objectID))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } else if let diff = model.selectedDiff {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diff.path ?? localizer.string("本地变更"))
                            .font(.headline)
                            .lineLimit(1)
                        Text(diffSourceLabel(diff.source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(localizer.string("选择一个变更或提交"))
                        .font(.headline)
                }
                Spacer()
                diffControls
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            Divider()

            if let lfs = model.selectedLFSFileInfo {
                HStack {
                    Image(systemName: "externaldrive.badge.icloud")
                    Text(
                        lfs.isPointer
                            ? localizer.format(
                                "Git LFS Pointer · %@ · %d 字节",
                                lfs.objectID ?? localizer.string("未知"),
                                lfs.declaredSize ?? 0
                            )
                            : localizer.string("Git LFS 对象已下载")
                    )
                    Spacer()
                }
                .font(.caption)
                .padding(8)
                .background(Color.blue.opacity(0.08))
            }

            if model.isLoadingSelectedDetail {
                GitDelayedLoadingView(
                    label: localizer.string("正在载入 Diff…")
                )
            } else if let diff = model.selectedDiff {
                GitStructuredDiffView(
                    diff: diff,
                    targetFileRequest: selectedDiffFileRequest,
                    preferences: model.preferencesStore.preferences.diff,
                    shortcutPreferences: model.preferencesStore.preferences,
                    workflow: model.metadata.workflow,
                    changelists: model.metadata.changelists,
                    onStageHunk: { file, hunk, reverse in
                        model.stageHunk(hunk, file: file, reverse: reverse)
                    },
                    onStageLines: { file, hunk, lineIDs, reverse in
                        model.stageLines(
                            lineIDs,
                            hunk: hunk,
                            file: file,
                            reverse: reverse
                        )
                    },
                    onAddHunkToChangelist: { file, hunk, changelistID in
                        guard let root = model.selectedRoot else { return }
                        model.addHunkToChangelist(
                            file: file,
                            hunk: hunk,
                            rootURL: root.rootURL,
                            changelistID: changelistID
                        )
                    },
                    onAddLinesToChangelist: { file, hunk, lineIDs, changelistID in
                        guard let root = model.selectedRoot else { return }
                        model.addLinesToChangelist(
                            file: file,
                            hunk: hunk,
                            lineIDs: lineIDs,
                            rootURL: root.rootURL,
                            changelistID: changelistID
                        )
                    },
                    onApplyHunk: { file, hunk in
                        model.applyPreviewPatch(file: file, hunk: hunk)
                    },
                    onApplyLines: { file, hunk, lineIDs in
                        model.applyPreviewPatch(
                            file: file,
                            hunk: hunk,
                            selectedLineIDs: lineIDs
                        )
                    },
                    onSystemPreview: {
                        model.openSelectedFileWithSystemPreview()
                    },
                    onShelveHunk: { file, hunk in
                        presentTextPrompt(
                            title: localizer.string("Shelve Hunk"),
                            submitTitle: localizer.string("创建"),
                            initialValue: file.newPath ?? file.oldPath ?? "Shelf"
                        ) { name in
                            model.shelvePatch(
                                name: name,
                                file: file,
                                hunk: hunk
                            )
                        }
                    },
                    onShelveLines: { file, hunk, lineIDs in
                        presentTextPrompt(
                            title: localizer.string("Shelve 所选行"),
                            submitTitle: localizer.string("创建"),
                            initialValue: file.newPath ?? file.oldPath ?? "Shelf"
                        ) { name in
                            model.shelvePatch(
                                name: name,
                                file: file,
                                hunk: hunk,
                                selectedLineIDs: lineIDs
                            )
                        }
                    },
                    onRollback: { file, hunk, lineIDs in
                        confirmPartialRollback {
                            model.rollbackHunk(
                                hunk,
                                file: file,
                                selectedLineIDs: lineIDs
                            )
                        }
                    }
                )
            } else {
                BreathEmptyState(
                    title: localizer.string("选择一个变更或提交"),
                    style: .passive
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string("Diff 与提交详情"))
    }

    private var diffControls: some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                diffLayoutButton(
                    .sideBySide,
                    systemImage: "rectangle.split.2x1",
                    title: "并排"
                )
                diffLayoutButton(
                    .unified,
                    systemImage: "rectangle.split.1x2",
                    title: "统一"
                )
            }
            .padding(2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(localizer.string("Diff 布局"))

            if let path = model.selectedDiff?.path {
                Button {
                    let staged = model.selectedDiff?.source == .staged
                    model.openEditableFile(path: path, staged: staged)
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help(localizer.string("编辑真实文件或暂存区"))
            }
        }
    }

    private var console: some View {
        GitResizableConsole(
            isVisible: model.metadata.layout.isConsoleVisible,
            initialHeight: model.metadata.layout.consoleHeight,
            resizeAccessibilityLabel: localizer.string("调整 Git Console 高度"),
            onResizeEnded: { height in
                model.metadata.layout.consoleHeight = height
                model.saveWorkspaceMetadata()
            },
            header: { consoleHeader },
            records: { consoleRecords }
        )
    }

    private var consoleHeader: some View {
        HStack {
            Button {
                model.metadata.layout.isConsoleVisible.toggle()
                model.saveWorkspaceMetadata()
            } label: {
                Label(
                    localizer.string("Git Console"),
                    systemImage: model.metadata.layout.isConsoleVisible
                        ? "chevron.down"
                        : "chevron.right"
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if model.operationRegistry.runningCount > 0 {
                Label(
                    "\(model.operationRegistry.runningCount)",
                    systemImage: "progress.indicator"
                )
                .foregroundStyle(.blue)
            }
            if model.operationRegistry.failedCount > 0 {
                Label(
                    "\(model.operationRegistry.failedCount)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
            Button(localizer.string("清空")) {
                Task {
                    await model.operationRegistry.clear(
                        workspacePath: model.workspaceURL.path
                    )
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: WorkbenchLayout.bottomBarHeight)
    }

    private var consoleRecords: some View {
        List(model.consoleRecords) { record in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: operationIcon(record.status))
                        .foregroundStyle(operationColor(record.status))
                    Text(record.title)
                    Text(operationStatusLabel(record.status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(record.startedAt, style: .time)
                        .foregroundStyle(.secondary)
                    if let endedAt = record.endedAt {
                        Text("→")
                            .foregroundStyle(.tertiary)
                        Text(endedAt, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
                if let command = record.command {
                    Text(command)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if !record.output.isEmpty {
                    Text(record.output)
                        .font(.caption.monospaced())
                        .foregroundStyle(record.status == .failed ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
            .id(record.id)
            .listRowBackground(
                record.id == model.highlightedOperationID
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
        }
        .scrollPosition(id: $model.highlightedOperationID)
        .accessibilityLabel(localizer.string("Git 命令与结果"))
    }

    private var shortcutCommandHost: some View {
        GitShortcutEventHost(
            preferences: preferencesStore.preferences,
            onCommand: performShortcutCommand
        )
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func performShortcutCommand(_ commandID: String) {
        switch commandID {
        case "git.refresh":
            Task { await model.refresh() }
        case "git.fetch":
            model.fetch()
        case "git.pullMerge":
            model.pull(strategy: .merge)
        case "git.pullRebase":
            model.pull(strategy: .rebase)
        case "git.push":
            pushUpToOID = nil
            showingPush = true
        case "git.commit":
            model.commit()
        case "git.commitAndPush":
            model.commit(pushAfter: true)
        case "git.newBranch":
            showingBranchCreator = true
        case "git.branches", "git.merge", "git.rebase":
            focusedField = .branchSearch
        case "git.logSearch":
            focusedField = .logSearch
        case "git.cherryPick":
            if model.selectedCommitIDs.count > 1 {
                model.cherryPickSelectedCommits()
            } else if let commit = model.focusedCommitForAction {
                model.cherryPick(commit)
            }
        case "git.revert":
            if let commit = model.focusedCommitForAction {
                model.revert(commit)
            }
        case "git.fileHistory":
            if let change = model.focusedChangeForAction {
                historyPath = change.path
                model.loadFileHistory(change: change)
                showingFileHistory = true
            }
        case "git.blame":
            if let change = model.focusedChangeForAction {
                historyPath = change.path
                model.loadBlame(change: change)
                showingBlame = true
            }
        case "git.stash", "git.shelf":
            showingStashes = true
        case "git.console":
            model.metadata.layout.isConsoleVisible.toggle()
            model.saveWorkspaceMetadata()
        case "git.resolveConflicts":
            if let conflict = model.sequencedOperation?.conflictedPaths.first {
                model.loadConflict(path: conflict)
                showingConflictResolver = true
            }
        case "git.undoLastCommit":
            confirmUndoLastCommit()
        case "git.previousDifference":
            NotificationCenter.default.post(
                name: .breathGitPreviousDifference,
                object: nil
            )
        case "git.nextDifference":
            NotificationCenter.default.post(
                name: .breathGitNextDifference,
                object: nil
            )
        default:
            break
        }
    }

    @ViewBuilder
    private var externalRootWarnings: some View {
        ForEach(model.snapshot.externalRootCandidates, id: \.path) { root in
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(localizer.format("检测到工作区外的 Git Root：%@", root.path))
                    .lineLimit(1)
                Spacer()
                Button(localizer.string("允许访问")) {
                    model.authorizeExternalRoot(root)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.orange.opacity(0.08))
        }
    }

    @ViewBuilder
    private var conflictBanner: some View {
        if let operation = model.sequencedOperation {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(
                    localizer.format(
                        "正在进行 %@ · %d 个冲突",
                        operation.kind.rawValue,
                        operation.conflictedPaths.count
                    )
                )
                Spacer()
                if let firstConflict = operation.conflictedPaths.first {
                    Button(localizer.string("解决冲突…")) {
                        model.loadConflict(path: firstConflict)
                        showingConflictResolver = true
                    }
                }
                Button(localizer.string("Continue")) {
                    model.continueSequence()
                }
                .disabled(!operation.canContinue)
                if operation.canSkip {
                    Button(localizer.string("Skip")) {
                        model.skipSequence()
                    }
                }
                Button(localizer.string("Abort"), role: .destructive) {
                    model.abortSequence()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.orange.opacity(0.1))
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyState: some View {
        BreathEmptyState(
            title: localizer.string("此工作区还不是 Git 仓库"),
            systemImage: "point.topleft.down.to.point.bottomright.curvepath"
        ) {
            HStack {
                Button(localizer.string("初始化 Git 仓库")) {
                    model.initializeRepository()
                }
                Button(localizer.string("克隆到新目录")) {
                    cloneRepository()
                }
            }
        }
    }

    private var rootPicker: some View {
        Picker(
            "",
            selection: Binding<GitRootID?>(
                get: { model.snapshot.roots.count > 1 ? model.selectedRootID : model.selectedRoot?.id },
                set: { model.selectRoot($0) }
            )
        ) {
            if model.snapshot.roots.count > 1 {
                Text(localizer.string("所有仓库")).tag(GitRootID?.none)
            }
            ForEach(model.snapshot.roots) { root in
                Text(
                    root.isSubmoduleRoot
                        ? localizer.format(
                            "%@ · Submodule",
                            root.rootURL.lastPathComponent
                        )
                        : root.rootURL.lastPathComponent
                )
                    .tag(Optional(root.id))
            }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(localizer.string("Git Root"))
    }

    private var allRepositoriesBranchMenu: some View {
        Menu {
            if model.metadata.synchronizeMultiRootOperations {
                ForEach(model.references.filter { $0.kind == .localBranch }) { reference in
                    Menu(reference.shortName) {
                        Button(localizer.string("Checkout")) {
                            model.synchronizeCheckout(
                                reference: reference.shortName
                            )
                        }
                        Button(localizer.string("Merge 到当前分支")) {
                            confirmSynchronizedBranchOperation(
                                kind: "Merge",
                                reference: reference.shortName
                            )
                        }
                        Button(localizer.string("Rebase 当前分支到这里")) {
                            confirmSynchronizedBranchOperation(
                                kind: "Rebase",
                                reference: reference.shortName
                            )
                        }
                        Button(localizer.string("Hard Reset 到此引用")) {
                            confirmSynchronizedBranchOperation(
                                kind: "Reset --hard",
                                reference: reference.shortName
                            )
                        }
                    }
                }
                Divider()
                Button(localizer.string("Push 所有当前分支")) {
                    confirmSynchronizedPush(remote: "origin")
                }
            } else {
                Text(localizer.string("未启用"))
            }
        } label: {
            Image(systemName: "square.stack.3d.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(
            localizer.string(
                model.metadata.synchronizeMultiRootOperations
                    ? "同步多 Git Root 分支操作"
                    : "请在工作区 Git 设置中启用同步多 Root 分支操作"
            )
        )
        .accessibilityLabel(localizer.string("同步多 Git Root 分支操作"))
    }

    private func toolbarButton(
        _ systemName: String,
        _ title: String,
        shortcutID: String? = nil,
        requiresRoot: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarIcon(systemName)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(shortcutHelp(title: title, commandID: shortcutID))
        .accessibilityLabel(localizer.string(title))
        .disabled(requiresRoot && model.selectedRoot == nil)
    }

    private func toolbarLabeledButton(
        _ systemName: String,
        _ title: String,
        shortcutID: String? = nil,
        requiresRoot: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarActionLabel(title, systemName: systemName)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(shortcutHelp(title: title, commandID: shortcutID))
        .accessibilityLabel(localizer.string(title))
        .disabled(requiresRoot && model.selectedRoot == nil)
    }

    private func toolbarActionLabel(
        _ title: String,
        systemName: String
    ) -> some View {
        Label {
            Text(localizer.string(title))
        } icon: {
            toolbarIcon(systemName)
        }
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(
                .system(
                    size: GitToolbarMetrics.iconPointSize,
                    weight: .medium
                )
            )
            .frame(
                width: GitToolbarMetrics.iconFrameSize,
                height: GitToolbarMetrics.iconFrameSize
            )
    }

    private func shortcutHelp(
        title: String,
        commandID: String?
    ) -> String {
        guard let commandID,
              let binding = model.preferencesStore.preferences.shortcuts.first(
                  where: { $0.commandID == commandID }
              ),
              !binding.keys.isEmpty
        else {
            return localizer.string(title)
        }
        return "\(localizer.string(title)) (\(binding.keys))"
    }

    private var selectedCommitInspector: some View {
        VStack(spacing: 0) {
            HStack {
                Label(localizer.string("提交信息"), systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let details = model.selectedCommitDetails {
                    Text(localizer.format("%d 个文件", details.files.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            Divider()

            if model.isLoadingSelectedDetail {
                GitDelayedLoadingView(
                    label: localizer.string("正在载入提交信息…")
                )
            } else if let details = model.selectedCommitDetails {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(details.commit.subject)
                                .font(.subheadline.weight(.semibold))
                                .textSelection(.enabled)
                            HStack(spacing: 4) {
                                Text(details.commit.authorName)
                                Text("<\(details.commit.authorEmail)>")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let date = details.commit.authoredAt {
                                    Text(date, format: .dateTime)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(details.commit.objectID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if !details.commit.body.isEmpty {
                                Text(details.commit.body)
                                    .textSelection(.enabled)
                            }
                        }
                        .font(.caption)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        ForEach(details.files) { file in
                            Button {
                                selectedDiffFileRequest = GitDiffFileRequest(
                                    path: file.path
                                )
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: fileStatusIcon(file.status))
                                        .foregroundStyle(statusColor(file.status))
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(file.path)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        if let originalPath = file.originalPath {
                                            Text(originalPath)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 30,
                                alignment: .leading
                            )
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            } else {
                BreathEmptyState(
                    title: localizer.string("选择一个变更或提交"),
                    style: .passive
                )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func commitContextMenu(_ commit: GitCommitSummary) -> some View {
        if model.selectedCommitIDs.count > 1 {
            Button(
                localizer.format(
                    "按选择顺序 Cherry-pick %d 个提交",
                    model.selectedCommitIDs.count
                )
            ) {
                model.cherryPickSelectedCommits()
            }
        }
        Button(localizer.string("Cherry-pick")) {
            model.cherryPick(commit)
        }
        Button(localizer.string("Revert Commit")) {
            model.revert(commit)
        }
        Button(localizer.string("应用 Commit 到工作树")) {
            model.applyCommitToWorkingTree(commit)
        }
        Button(localizer.string("将当前修改 Fixup 到此提交…")) {
            confirmFixupCurrentChanges(into: commit)
        }
        .disabled(!hasCommitSelection(for: commit.rootID))
        Divider()
        Menu(localizer.string("Reset 当前分支到这里")) {
            ForEach(GitResetMode.allCases, id: \.rawValue) { mode in
                Button(mode.rawValue.capitalized) {
                    confirmReset(commit: commit, mode: mode)
                }
            }
        }
        Button(localizer.string("从此提交创建分支…")) {
            model.selectRoot(commit.rootID)
            branchName = ""
            commitSearch = commit.objectID
            showingBranchCreator = true
        }
        Button(localizer.string("Push 到此提交…")) {
            model.selectRoot(commit.rootID)
            pushUpToOID = commit.objectID
            showingPush = true
        }
        Button(localizer.string("Interactive Rebase 从这里开始…")) {
            prepareInteractiveRebase(from: commit)
        }
    }

    private var branchCreator: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizer.string("新建分支"))
                .font(.title3.weight(.semibold))
            TextField(localizer.string("分支名称"), text: $branchName)
            HStack {
                Button(localizer.string("取消")) {
                    showingBranchCreator = false
                }
                Spacer()
                Button(localizer.string("创建并 Checkout")) {
                    model.createBranch(
                        name: branchName,
                        startPoint: commitSearch.nilIfEmpty
                    )
                    branchName = ""
                    commitSearch = ""
                    showingBranchCreator = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var pushSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizer.string("Push"))
                .font(.title3.weight(.semibold))
            TextField(localizer.string("Remote"), text: $remoteName)
            Toggle(localizer.string("推送 Tags"), isOn: $includeTags)
            Toggle(localizer.string("Force with Lease"), isOn: $forceWithLease)
            if let root = model.selectedRoot {
                Text(localizer.format("目标：%@ / %@", root.rootURL.lastPathComponent, root.branch.name))
                    .foregroundStyle(.secondary)
            }
            if let pushUpToOID {
                Text(
                    localizer.format(
                        "截止 Commit：%@",
                        String(pushUpToOID.prefix(12))
                    )
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
            if let plan = model.pushPlan {
                Text(
                    localizer.format(
                        "%d 个 Outgoing Commits",
                        plan.outgoingCommits.count
                    )
                )
                .font(.headline)
                List(plan.outgoingCommits) { commit in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.subject)
                        Text(String(commit.objectID.prefix(8)))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 150)
                if let diff = model.pushPreviewDiff {
                    GitStructuredDiffView(
                        diff: diff,
                        targetFileRequest: nil,
                        preferences: model.preferencesStore.preferences.diff,
                        shortcutPreferences: model.preferencesStore.preferences,
                        workflow: model.metadata.workflow,
                        changelists: [],
                        onStageHunk: { _, _, _ in },
                        onStageLines: { _, _, _, _ in },
                        onAddHunkToChangelist: { _, _, _ in },
                        onAddLinesToChangelist: { _, _, _, _ in },
                        onApplyHunk: { _, _ in },
                        onApplyLines: { _, _, _ in },
                        onSystemPreview: {},
                        onShelveHunk: { _, _ in },
                        onShelveLines: { _, _, _ in },
                        onRollback: { _, _, _ in }
                    )
                    .frame(minHeight: 220)
                }
            } else {
                ProgressView(localizer.string("正在准备 Push Plan…"))
            }
            HStack {
                Button(localizer.string("凭证…")) {
                    showingAuthentication = true
                }
                Spacer()
                Button(localizer.string("取消")) {
                    model.clearAuthentication()
                    showingPush = false
                }
                Button(localizer.string("Push")) {
                    let authentication = authentication
                    model.push(
                        remote: remoteName,
                        includeTags: includeTags,
                        forceWithLease: forceWithLease,
                        authentication: authentication,
                        upTo: pushUpToOID
                    )
                    model.clearAuthentication()
                    showingPush = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.pushPlan == nil)
            }
        }
        .padding(20)
        .frame(width: 760, height: 640)
        .task(id: "\(remoteName)|\(includeTags)|\(forceWithLease)") {
            await model.preparePush(
                remote: remoteName,
                includeTags: includeTags,
                forceWithLease: forceWithLease,
                upTo: pushUpToOID
            )
        }
    }

    private var authenticationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplanationLabel(
                localizer.string("凭证只传递给当前 Git 进程，Breath 不会保存。")
            ) {
                Text(localizer.string("Git 凭证"))
                    .font(.title3.weight(.semibold))
            }
            TextField(localizer.string("用户名"), text: $model.authenticationUsername)
            SecureField(localizer.string("密码、Token 或 Passphrase"), text: $model.authenticationSecret)
            Toggle(
                localizer.string("允许本次 SSH Host Key 确认"),
                isOn: $model.authenticationConfirmHostKey
            )
            HStack {
                Button(localizer.string("Fetch")) {
                    let authentication = authentication
                    model.fetch(authentication: authentication)
                    model.clearAuthentication()
                    showingAuthentication = false
                }
                Button(localizer.string("Pull")) {
                    let authentication = authentication
                    model.pull(
                        strategy: .merge,
                        authentication: authentication
                    )
                    model.clearAuthentication()
                    showingAuthentication = false
                }
                Spacer()
                Button(localizer.string("完成")) {
                    showingAuthentication = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private var authentication: GitAuthentication? {
        guard !model.authenticationSecret.isEmpty else { return nil }
        return GitAuthentication(
            username: model.authenticationUsername,
            secret: model.authenticationSecret,
            allowHostKeyConfirmation: model.authenticationConfirmHostKey
        )
    }

    private var stashAndShelfSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localizer.string("Git Stash 与 Shelf"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localizer.string("完成")) {
                    showingStashes = false
                }
            }
            .padding()
            Divider()
            if model.preferencesStore.preferences.combineStashAndShelf {
                ScrollView {
                    VStack(spacing: 0) {
                        stashPane.frame(minHeight: 260)
                        Divider()
                        shelfPane.frame(minHeight: 260)
                    }
                }
            } else {
                HSplitView {
                    stashPane
                    shelfPane
                }
            }
        }
        .frame(width: 860, height: 580)
        .sheet(item: $dialogRequest) { request in
            gitDialog(request)
        }
    }

    private var stashPane: some View {
        VStack(alignment: .leading) {
            Text(localizer.string("Git Stash"))
                .font(.headline)
            HStack {
                TextField(localizer.string("Stash 消息"), text: $stashMessage)
                Button(localizer.string("创建")) {
                    model.createStash(
                        message: stashMessage.isEmpty ? "Breath stash" : stashMessage,
                        includeUntracked: stashIncludeUntracked,
                        keepIndex: stashKeepIndex
                    )
                    stashMessage = ""
                }
            }
            HStack {
                Toggle(
                    localizer.string("包含未跟踪文件"),
                    isOn: $stashIncludeUntracked
                )
                Toggle(
                    localizer.string("保留暂存区"),
                    isOn: $stashKeepIndex
                )
            }
            List(model.stashes) { stash in
                HStack {
                    VStack(alignment: .leading) {
                        Text(stash.reference)
                        Text(stash.subject)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(localizer.string("预览")) {
                        model.previewStash(stash)
                        showingStashes = false
                    }
                    Button(localizer.string("Apply")) {
                        confirmDestructiveGitAction(
                            title: localizer.string("Apply Git Stash？"),
                            message: stash.reference
                        ) {
                            model.applyStash(stash, pop: false)
                        }
                    }
                    Button(localizer.string("Pop")) {
                        confirmDestructiveGitAction(
                            title: localizer.string("Pop Git Stash？"),
                            message: stash.reference
                        ) {
                            model.applyStash(stash, pop: true)
                        }
                    }
                    Button(localizer.string("Drop"), role: .destructive) {
                        confirmDestructiveGitAction(
                            title: localizer.string("Drop Git Stash？"),
                            message: stash.reference
                        ) {
                            model.dropStash(stash)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private var shelfPane: some View {
        VStack(alignment: .leading) {
            Text(localizer.string("Shelf"))
                .font(.headline)
            HStack {
                TextField(localizer.string("Shelf 名称"), text: $shelfName)
                Button(localizer.string("Shelve 当前变更")) {
                    model.shelveCurrentChanges(
                        name: shelfName.isEmpty ? "Breath Shelf" : shelfName
                    )
                    shelfName = ""
                }
                Button(localizer.string("导入 Patch…")) {
                    importShelf()
                }
            }
            List(model.metadata.shelves) { shelf in
                HStack {
                    VStack(alignment: .leading) {
                        Text(shelf.name)
                        Text(shelf.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(localizer.string("预览")) {
                        model.previewShelf(shelf)
                        showingStashes = false
                    }
                    Button(localizer.string("Apply")) {
                        model.applyShelf(shelf)
                    }
                    Menu {
                        Button(localizer.string("重命名…")) {
                            renameShelf(shelf)
                        }
                        Button(localizer.string("导出 Patch…")) {
                            exportShelf(shelf)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button(localizer.string("删除"), role: .destructive) {
                        confirmDestructiveGitAction(
                            title: localizer.string("删除 Shelf？"),
                            message: shelf.name
                        ) {
                            model.deleteShelf(shelf)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private var workspaceSettingsSheet: some View {
        GitWorkspaceSettingsView(model: model)
            .frame(width: 560, height: 500)
    }

    private var snapshotSheet: some View {
        VStack(spacing: 0) {
            HStack {
                ExplanationLabel(
                    localizer.string(
                        "安全快照是尽力而为的本地缓存，不是连续 Local History。"
                    )
                ) {
                    Text(localizer.string("Git 安全快照"))
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Button(localizer.string("完成")) {
                    showingSnapshots = false
                }
            }
            .padding()
            Divider()
            List(model.safetySnapshots) { snapshot in
                DisclosureGroup {
                    ForEach(snapshot.files) { file in
                        HStack {
                            Text(file.path)
                                .font(.caption.monospaced())
                            Spacer()
                            Button(localizer.string("比较")) {
                                model.previewSnapshotFile(
                                    snapshot,
                                    path: file.path
                                )
                                showingSnapshots = false
                            }
                            Button(localizer.string("恢复文件")) {
                                model.restoreSnapshot(
                                    snapshot,
                                    paths: [file.path]
                                )
                            }
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snapshot.action)
                            Text(snapshot.createdAt, format: .dateTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(localizer.format("%d 个文件", snapshot.files.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(localizer.string("全部恢复")) {
                            model.restoreSnapshot(snapshot)
                        }
                    }
                }
            }
        }
        .frame(width: 620, height: 460)
    }

    private var editableFileSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.editableFilePath ?? localizer.string("编辑文件"))
                    .font(.headline)
                Spacer()
                Text(
                    model.isEditingStagedFile
                        ? localizer.string("正在编辑 Git 暂存区")
                        : localizer.string("正在编辑工作树")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            Divider()
            if model.isEditingStagedFile {
                HSplitView {
                    indexComparisonPane(
                        title: localizer.string("HEAD"),
                        contents: model.editableHeadContents
                    )
                    VStack(spacing: 0) {
                        Text(localizer.string("Staged"))
                            .font(.headline)
                            .padding(8)
                        Divider()
                        TextEditor(text: $model.editableFileContents)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .accessibilityLabel(
                                localizer.string("可编辑 Staged 结果")
                            )
                    }
                    indexComparisonPane(
                        title: localizer.string("Local"),
                        contents: model.editableLocalContents
                    )
                }
            } else {
                TextEditor(text: $model.editableFileContents)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
            }
            Divider()
            HStack {
                Spacer()
                Button(localizer.string("取消")) {
                    showingEditor = false
                }
                Button(localizer.string("保存")) {
                    model.saveEditableFile()
                    showingEditor = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(
            width: model.isEditingStagedFile ? 1_080 : 760,
            height: 620
        )
    }

    private func indexComparisonPane(
        title: String,
        contents: String
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(8)
            Divider()
            ScrollView {
                Text(contents)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .topLeading
                    )
                    .padding(8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var conflictResolverSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.conflictFile?.path ?? localizer.string("解决冲突"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localizer.string("重新应用自动合并结果")) {
                    model.resetConflictResultToAutomaticMerge()
                }
                Button(localizer.string("取消")) {
                    showingConflictResolver = false
                }
                Button(localizer.string("保存并标记已解决")) {
                    model.saveConflictResult()
                    showingConflictResolver = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            if let conflict = model.conflictFile {
                VStack(spacing: 0) {
                    HSplitView {
                        conflictInputPane(
                            title: localizer.string("Ours / Local"),
                            contents: conflict.ours,
                            actionTitle: localizer.string("接受 Ours")
                        ) {
                            model.acceptConflictSide(ours: true)
                        }
                        conflictInputPane(
                            title: localizer.string("Theirs / Incoming"),
                            contents: conflict.theirs,
                            actionTitle: localizer.string("接受 Theirs")
                        ) {
                            model.acceptConflictSide(ours: false)
                        }
                        VStack(spacing: 0) {
                            HStack {
                                Text(localizer.string("Result"))
                                    .font(.headline)
                                Spacer()
                                Menu(localizer.string("Base")) {
                                    Text(conflict.base)
                                }
                            }
                            .padding(8)
                            Divider()
                            TextEditor(text: $model.conflictResult)
                                .font(.system(.caption, design: .monospaced))
                                .padding(6)
                                .accessibilityLabel(localizer.string("冲突合并结果"))
                        }
                    }
                    let blocks = GitConflictDocument(
                        contents: model.conflictResult
                    ).blocks
                    if !blocks.isEmpty {
                        Divider()
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(blocks) { block in
                                    HStack(spacing: 6) {
                                        Text(
                                            localizer.format(
                                                "未解决冲突块 · 行 %d",
                                                block.startLine + 1
                                            )
                                        )
                                        Button(localizer.string("接受 Ours")) {
                                            model.resolveConflictBlock(
                                                block,
                                                with: .ours
                                            )
                                        }
                                        Button(localizer.string("接受 Theirs")) {
                                            model.resolveConflictBlock(
                                                block,
                                                with: .theirs
                                            )
                                        }
                                        Button(localizer.string("接受 Both")) {
                                            model.resolveConflictBlock(
                                                block,
                                                with: .both
                                            )
                                        }
                                        Button(localizer.string("忽略双方")) {
                                            model.resolveConflictBlock(
                                                block,
                                                with: .ignore
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            } else {
                ProgressView(localizer.string("正在读取冲突内容…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 1_080, height: 680)
    }

    private func conflictInputPane(
        title: String,
        contents: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(actionTitle, action: action)
            }
            .padding(8)
            Divider()
            ScrollView {
                Text(contents)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }

    private var fileHistorySheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localizer.format("File History · %@", historyPath))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localizer.string("完成")) {
                    showingFileHistory = false
                }
            }
            .padding()
            Divider()
            List(model.fileHistory) { commit in
                Button {
                    Task { await model.selectCommit(commit) }
                    showingFileHistory = false
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(commit.subject)
                        HStack {
                            Text(commit.authorName)
                            Text(String(commit.objectID.prefix(8))).monospaced()
                            if let date = commit.authoredAt {
                                Text(date, style: .date)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 680, height: 520)
    }

    private var blameSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localizer.format("Blame · %@", historyPath))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localizer.string("完成")) {
                    showingBlame = false
                }
            }
            .padding()
            Divider()
            List(model.blameLines) { line in
                Button {
                    model.jumpToCommit(objectID: line.objectID)
                    showingBlame = false
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(line.lineNumber)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                                .font(.body.monospaced())
                            Text(
                                "\(line.author) · \(String(line.objectID.prefix(8))) · \(line.summary)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    localizer.format(
                        "第 %d 行，作者 %@，提交 %@",
                        line.lineNumber,
                        line.author,
                        String(line.objectID.prefix(8))
                    )
                )
            }
        }
        .frame(width: 860, height: 620)
    }

    private var interactiveRebaseSheet: some View {
        VStack(spacing: 0) {
            HStack {
                ExplanationLabel(
                    localizer.string(
                        "拖动提交可重新排序；受保护或已发布历史会被安全规则阻止。"
                    )
                ) {
                    Text(localizer.string("Interactive Rebase"))
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Text(localizer.format("Base %@", String(rebaseBase.prefix(8))))
                    .foregroundStyle(.secondary)
            }
            .padding()
            Divider()
            List {
                ForEach(Array(rebaseSteps.indices), id: \.self) { index in
                    let step = rebaseSteps[index]
                    HStack {
                        Picker(
                            "",
                            selection: Binding(
                                get: { rebaseSteps[index].action },
                                set: { rebaseSteps[index].action = $0 }
                            )
                        ) {
                            Text("pick").tag(GitHistoryEditAction.pick)
                            Text("reword").tag(GitHistoryEditAction.reword)
                            Text("edit").tag(GitHistoryEditAction.edit)
                            Text("squash").tag(GitHistoryEditAction.squash)
                            Text("fixup").tag(GitHistoryEditAction.fixup)
                            Text("drop").tag(GitHistoryEditAction.drop)
                        }
                        .labelsHidden()
                        .frame(width: 105)
                        Text(String(step.objectID.prefix(8)))
                            .font(.body.monospaced())
                        if step.action == .reword {
                            TextField(
                                localizer.string("新的提交信息"),
                                text: Binding(
                                    get: { rebaseSteps[index].subject },
                                    set: { rebaseSteps[index].subject = $0 }
                                )
                            )
                        } else {
                            Text(step.subject)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            rebaseSteps.swapAt(index, index - 1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == rebaseSteps.startIndex)
                        .accessibilityLabel(localizer.string("向上移动提交"))
                        Button {
                            rebaseSteps.swapAt(index, index + 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == rebaseSteps.index(before: rebaseSteps.endIndex))
                        .accessibilityLabel(localizer.string("向下移动提交"))
                    }
                }
                .onMove { source, destination in
                    rebaseSteps.move(fromOffsets: source, toOffset: destination)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(localizer.string("取消")) {
                    showingInteractiveRebase = false
                }
                Button(localizer.string("开始 Rebase")) {
                    model.interactiveRebase(
                        onto: rebaseBase,
                        steps: rebaseSteps
                    )
                    showingInteractiveRebase = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 760, height: 560)
    }

    private func prepareInteractiveRebase(from commit: GitCommitSummary) {
        model.selectRoot(commit.rootID)
        let rootCommits = model.commits.filter { $0.rootID == commit.rootID }
        guard let index = rootCommits.firstIndex(where: {
            $0.objectID == commit.objectID
        }), index > 0 else {
            return
        }
        rebaseBase = commit.objectID
        rebaseSteps = rootCommits[..<index].reversed().map {
            GitHistoryEditStep(
                action: .pick,
                objectID: $0.objectID,
                subject: $0.subject
            )
        }
        showingInteractiveRebase = true
    }

    private func promptRenameBranch(_ oldName: String) {
        presentTextPrompt(
            title: localizer.string("重命名分支"),
            submitTitle: localizer.string("重命名"),
            initialValue: oldName
        ) { newName in
            guard newName != oldName else { return }
            model.renameBranch(oldName: oldName, newName: newName)
        }
    }

    private func promptCreateChangelist() {
        presentTextPrompt(
            title: localizer.string("新建变更列表"),
            submitTitle: localizer.string("创建"),
            placeholder: localizer.string("变更列表名称")
        ) { name in
            model.createChangelist(name: name)
        }
    }

    private func promptRenameChangelist(_ changelist: GitChangelist) {
        presentTextPrompt(
            title: localizer.string("重命名变更列表"),
            submitTitle: localizer.string("重命名"),
            initialValue: changelist.name
        ) { name in
            guard name != changelist.name else { return }
            model.renameChangelist(changelist.id, name: name)
        }
    }

    private func presentTextPrompt(
        title: String,
        submitTitle: String,
        initialValue: String = "",
        placeholder: String? = nil,
        submit: @escaping (String) -> Void
    ) {
        dialogRequest = GitDialogRequest(
            title: title,
            message: nil,
            content: .text(
                initialValue: initialValue,
                placeholder: placeholder,
                submitTitle: submitTitle,
                submit: submit
            )
        )
    }

    private func presentConfirmation(
        title: String,
        message: String,
        actionTitle: String,
        role: ButtonRole? = nil,
        perform: @escaping () -> Void
    ) {
        dialogRequest = GitDialogRequest(
            title: title,
            message: message,
            content: .confirmation(
                actions: [
                    GitDialogAction(
                        title: actionTitle,
                        role: role,
                        isDefault: true,
                        perform: perform
                    ),
                ]
            )
        )
    }

    private func confirmDeleteBranch(_ name: String) {
        presentConfirmation(
            title: localizer.format("删除分支 %@？", name),
            message: localizer.string(
                "仅允许删除已合并分支；未合并分支需要在命令行中显式处理。"
            ),
            actionTitle: localizer.string("删除"),
            role: .destructive
        ) {
            model.deleteBranch(name)
        }
    }

    private func confirmReset(
        commit: GitCommitSummary,
        mode: GitResetMode
    ) {
        guard let root = model.snapshot.roots.first(where: {
            $0.id == commit.rootID
        }) else {
            return
        }
        presentConfirmation(
            title: localizer.format(
                "Reset %@ 到 %@？",
                root.branch.name,
                String(commit.objectID.prefix(12))
            ),
            message: localizer.format(
                "Root：%@\n模式：%@\nBreath 会在执行前尽力创建 Git 安全快照。",
                root.rootURL.path,
                mode.rawValue
            ),
            actionTitle: localizer.string("Reset"),
            role: mode == .hard || mode == .keep ? .destructive : nil
        ) {
            model.reset(commit: commit, mode: mode)
        }
    }

    private func confirmAmend() {
        guard let head = model.commits.first(where: {
            $0.objectID == model.selectedRoot?.branch.headOID
        }) ?? model.commits.first else {
            return
        }
        presentConfirmation(
            title: localizer.format(
                "Amend Commit %@？",
                String(head.objectID.prefix(12))
            ),
            message: localizer.format(
                "原提交：%@\n最终提交信息：\n%@",
                head.subject,
                model.currentCommitDraft
            ),
            actionTitle: localizer.string("Amend")
        ) {
            model.commit(amend: true)
        }
    }

    private func confirmUndoLastCommit() {
        guard let root = model.selectedRoot,
              let head = model.commits.first
        else {
            return
        }
        dialogRequest = GitDialogRequest(
            title: localizer.format(
                "Undo Last Commit %@？",
                String(head.objectID.prefix(12))
            ),
            message: localizer.format(
                "Root：%@\n分支：%@\n请选择如何保留该提交中的修改。",
                root.rootURL.path,
                root.branch.name
            ),
            content: .confirmation(
                actions: [
                    GitDialogAction(
                        title: localizer.string("保留在工作树"),
                        role: nil,
                        isDefault: false
                    ) {
                        model.undoLastCommit(keepIndex: false)
                    },
                    GitDialogAction(
                        title: localizer.string("保留在暂存区"),
                        role: nil,
                        isDefault: true
                    ) {
                        model.undoLastCommit(keepIndex: true)
                    },
                ]
            )
        )
    }

    private func confirmFixupCurrentChanges(into commit: GitCommitSummary) {
        presentConfirmation(
            title: localizer.format(
                "将当前修改 Fixup 到 %@？",
                String(commit.objectID.prefix(8))
            ),
            message: localizer.format(
                "目标提交：%@\n提交信息：%@\nBreath 将创建 Fixup Commit，并通过 Autosquash Rebase 写入未发布历史。",
                commit.objectID,
                commit.subject
            ),
            actionTitle: localizer.string("Fixup")
        ) {
            model.fixupCurrentChanges(into: commit)
        }
    }

    private func confirmBranchOperation(
        kind: String,
        reference: String
    ) {
        guard let root = model.selectedRoot else { return }
        presentConfirmation(
            title: localizer.format(
                "%@ %@ 到 %@？",
                kind,
                reference,
                root.branch.name
            ),
            message: localizer.format(
                "Root：%@\n源：%@\n目标：%@",
                root.rootURL.path,
                reference,
                root.branch.name
            ),
            actionTitle: kind
        ) {
            if kind == "Merge" {
                model.merge(reference: reference)
            } else {
                model.rebase(onto: reference)
            }
        }
    }

    private func confirmSynchronizedBranchOperation(
        kind: String,
        reference: String
    ) {
        let roots = model.snapshot.roots.filter { !$0.isSubmoduleRoot }
        presentConfirmation(
            title: localizer.format(
                "在 %d 个 Root 中执行 %@？",
                roots.count,
                kind
            ),
            message: roots.map {
                "\($0.rootURL.lastPathComponent): \($0.branch.name) ← \(reference)"
            }.joined(separator: "\n"),
            actionTitle: kind,
            role: kind == "Reset --hard" ? .destructive : nil
        ) {
            if kind == "Merge" {
                model.synchronizeMerge(reference: reference)
            } else if kind == "Rebase" {
                model.synchronizeRebase(onto: reference)
            } else {
                model.synchronizeReset(to: reference, mode: .hard)
            }
        }
    }

    private func confirmSynchronizedPush(remote: String) {
        let roots = model.snapshot.roots.filter { !$0.isSubmoduleRoot }
        presentConfirmation(
            title: localizer.format("Push %d 个 Root？", roots.count),
            message: roots.map {
                "\($0.rootURL.lastPathComponent): \($0.branch.name) → \(remote)/\($0.branch.name)"
            }.joined(separator: "\n"),
            actionTitle: localizer.string("Push")
        ) {
            model.synchronizePush(remote: remote)
        }
    }

    private func confirmDeleteRemoteBranch(_ reference: GitReference) {
        presentConfirmation(
            title: localizer.string("删除远程分支？"),
            message: localizer.format("完整引用：%@", reference.fullName),
            actionTitle: localizer.string("删除"),
            role: .destructive
        ) {
            model.deleteRemoteBranch(reference, authentication: authentication)
        }
    }

    private func renameShelf(_ shelf: GitShelf) {
        presentTextPrompt(
            title: localizer.string("重命名 Shelf"),
            submitTitle: localizer.string("重命名"),
            initialValue: shelf.name
        ) { name in
            guard name != shelf.name else { return }
            model.renameShelf(shelf, name: name)
        }
    }

    private func confirmDestructiveGitAction(
        title: String,
        message: String,
        perform: @escaping () -> Void
    ) {
        presentConfirmation(
            title: title,
            message: message,
            actionTitle: localizer.string("继续"),
            role: .destructive,
            perform: perform
        )
    }

    private func importShelf() {
        let panel = NSOpenPanel()
        applyDialogAppearance(to: panel)
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        model.importShelf(from: sourceURL)
    }

    private func exportShelf(_ shelf: GitShelf) {
        let panel = NSSavePanel()
        applyDialogAppearance(to: panel)
        panel.nameFieldStringValue = "\(shelf.name).patch"
        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }
        model.exportShelf(shelf, to: destinationURL)
    }

    private func cloneRepository() {
        presentTextPrompt(
            title: localizer.string("克隆 Git 仓库"),
            submitTitle: localizer.string("继续"),
            placeholder: "https://example.com/repository.git"
        ) { remoteURL in
            selectCloneDestination(remoteURL: remoteURL)
        }
    }

    private func selectCloneDestination(remoteURL: String) {
        let panel = NSSavePanel()
        applyDialogAppearance(to: panel)
        panel.title = localizer.string("选择新的克隆目录")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            if await model.cloneRepository(
                remoteURL: remoteURL,
                destinationURL: destination
            ) {
                onAddWorkspace(destination)
            }
        }
    }

    private func confirmRollback(_ change: GitLocalChange) {
        presentConfirmation(
            title: localizer.string("Rollback 本地修改？"),
            message: localizer.format(
                "将丢弃 %@ 中尚未提交的工作树修改。Breath 会先尽力创建 Git 安全快照。",
                change.path
            ),
            actionTitle: localizer.string("Rollback"),
            role: .destructive
        ) {
            model.rollback(change)
        }
    }

    private func confirmPartialRollback(perform: @escaping () -> Void) {
        presentConfirmation(
            title: localizer.string("Rollback 所选修改？"),
            message: localizer.string(
                "Breath 会先尽力创建 Git 安全快照，然后丢弃所选工作树修改。"
            ),
            actionTitle: localizer.string("Rollback"),
            role: .destructive,
            perform: perform
        )
    }

    private func applyDialogAppearance(to panel: NSPanel) {
        panel.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
    }

    private func changes(in changelist: GitChangelist) -> [GitLocalChange] {
        let keys = Set(changelist.entries.filter { $0.patch == nil }.map {
            "\($0.rootPath)\u{0}\($0.path)"
        })
        return model.snapshot.roots.flatMap { root in
            root.changes.filter {
                keys.contains("\(root.rootURL.path)\u{0}\($0.path)")
            }
        }
    }

    private func unassignedChanges(for changelist: GitChangelist) -> [GitLocalChange] {
        guard model.metadata.defaultChangelistID == changelist.id else { return [] }
        let allAssigned = Set(model.metadata.changelists.flatMap(\.entries).filter {
            $0.patch == nil
        }.map {
            "\($0.rootPath)\u{0}\($0.path)"
        })
        return model.snapshot.roots.flatMap { root in
            root.changes.filter {
                !allAssigned.contains("\(root.rootURL.path)\u{0}\($0.path)")
            }
        }
    }

    private func isInDefaultChangelist(_ change: GitLocalChange) -> Bool {
        guard let rootPath = change.rootID?.rawValue
            ?? model.selectedRoot?.rootURL.path
        else {
            return false
        }
        return model.defaultChangelist?.entries.contains {
            $0.rootPath == rootPath
                && $0.path == change.path
                && $0.patch == nil
        } == true
    }

    private func hasCommitSelection(for rootID: GitRootID) -> Bool {
        switch model.metadata.workflow {
        case .staging:
            return model.snapshot.roots.first(where: { $0.id == rootID })?
                .changes.contains(where: { $0.index != nil }) == true
        case .changelists:
            return model.defaultChangelist?.entries.contains(where: {
                $0.rootPath == rootID.rawValue && !$0.needsConfirmation
            }) == true
        }
    }

    private func changeSelectionID(
        _ change: GitLocalChange,
        staged: Bool
    ) -> String {
        (staged ? "staged:" : "working:") + change.id
    }

    private func parseChangeSelection(
        _ selectionID: String
    ) -> (changeID: String, staged: Bool)? {
        if selectionID.hasPrefix("staged:") {
            return (String(selectionID.dropFirst("staged:".count)), true)
        }
        if selectionID.hasPrefix("working:") {
            return (String(selectionID.dropFirst("working:".count)), false)
        }
        return nil
    }

    private func changeStatusIcon(
        _ change: GitLocalChange,
        stagedSection: Bool
    ) -> some View {
        let status = stagedSection ? change.index : change.workingTree
        return Text(statusAbbreviation(status))
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(statusColor(status))
            .frame(width: 16)
    }

    private func changeStatusLabel(
        _ change: GitLocalChange,
        stagedSection: Bool
    ) -> String {
        switch stagedSection ? change.index : change.workingTree {
        case .added: localizer.string("新增")
        case .modified: localizer.string("修改")
        case .deleted: localizer.string("删除")
        case .renamed: localizer.string("重命名")
        case .copied: localizer.string("复制")
        case .untracked: localizer.string("未跟踪")
        case .conflicted: localizer.string("冲突")
        case .typeChanged: localizer.string("类型改变")
        case nil: localizer.string("无")
        }
    }

    private func statusAbbreviation(_ status: GitChangeState?) -> String {
        switch status {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .untracked: "?"
        case .conflicted: "!"
        case .typeChanged: "T"
        case nil: "·"
        }
    }

    private func statusColor(_ status: GitChangeState?) -> Color {
        switch status {
        case .added: .green
        case .modified, .renamed, .copied, .typeChanged: .orange
        case .deleted: .red
        case .untracked, nil: .secondary
        case .conflicted: .purple
        }
    }

    private func fileStatusIcon(_ status: GitChangeState) -> String {
        switch status {
        case .added: "plus.circle"
        case .modified: "pencil.circle"
        case .deleted: "minus.circle"
        case .renamed: "arrow.right.circle"
        case .copied: "doc.on.doc"
        case .untracked: "questionmark.circle"
        case .conflicted: "exclamationmark.triangle"
        case .typeChanged: "arrow.triangle.2.circlepath"
        }
    }

    private func diffSourceLabel(_ source: GitDiffSource) -> String {
        switch source {
        case .workingTree: localizer.string("Local Changes · 工作树")
        case .staged: localizer.string("Local Changes · Git 暂存区")
        case .commit(let objectID):
            localizer.format("Commit %@", String(objectID.prefix(8)))
        case .between(let left, let right):
            "\(String(left.prefix(8)))…\(String(right.prefix(8)))"
        case .stash(let reference): reference
        }
    }

    private func rootName(_ rootID: GitRootID) -> String {
        model.snapshot.roots.first(where: { $0.id == rootID })?
            .rootURL.lastPathComponent ?? rootID.rawValue
    }

    private func operationIcon(_ status: GitOperationStatus) -> String {
        switch status {
        case .waiting: "clock"
        case .running: "progress.indicator"
        case .waitingForAuthentication: "key"
        case .waitingForConfirmation: "questionmark.circle"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "slash.circle"
        }
    }

    private func operationColor(_ status: GitOperationStatus) -> Color {
        switch status {
        case .waiting, .waitingForAuthentication, .waitingForConfirmation: .orange
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    private func operationStatusLabel(_ status: GitOperationStatus) -> String {
        switch status {
        case .waiting: localizer.string("等待")
        case .running: localizer.string("运行中")
        case .waitingForAuthentication: localizer.string("等待认证")
        case .waitingForConfirmation: localizer.string("等待确认")
        case .succeeded: localizer.string("成功")
        case .failed: localizer.string("失败")
        case .cancelled: localizer.string("已取消")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: {
                if !$0 {
                    model.errorMessage = nil
                    model.errorGuidanceKey = nil
                }
            }
        )
    }

    private var checkoutConflictBinding:
        Binding<GitCheckoutConflictRequest?>
    {
        Binding(
            get: { model.checkoutConflict },
            set: { request in
                if request == nil {
                    model.dismissCheckoutConflict()
                }
            }
        )
    }

    private func checkoutConflictDialog(
        _ conflict: GitCheckoutConflictRequest
    ) -> some View {
        let maximumVisiblePaths = 8
        let reportedPaths = conflict.rootConflicts.flatMap { rootConflict in
            rootConflict.paths.map { path in
                conflict.synchronizesRoots
                    ? rootConflict.root.rootURL.lastPathComponent + ": " + path
                    : path
            }
        }
        var paths = reportedPaths.prefix(maximumVisiblePaths)
            .joined(separator: "\n")
        if reportedPaths.isEmpty {
            paths = localizer.string("没有列出具体文件，请查看 Git Console。")
        } else if reportedPaths.count > maximumVisiblePaths {
            paths += "\n" + localizer.format(
                "另有 %d 个文件，请查看 Git Console。",
                reportedPaths.count - maximumVisiblePaths
            )
        }
        let message = localizer.format(
            "以下文件阻止切换到 %@：",
            conflict.reference.shortName
        )
            + "\n\n"
            + paths
            + "\n\n"
            + localizer.string(
                "Smart Checkout 会先暂存本地修改，切换后再恢复。Force Checkout 会丢弃这些修改，但可以从 Git 安全快照恢复。"
            )
        let request = GitDialogRequest(
            title: localizer.string("本地修改会被覆盖"),
            message: message,
            content: .confirmation(
                actions: [
                    GitDialogAction(
                        title: localizer.string("Smart Checkout"),
                        role: nil,
                        isDefault: true,
                        perform: {
                            model.resolveCheckoutConflict(
                                conflict,
                                using: .smart
                            )
                        }
                    ),
                    GitDialogAction(
                        title: localizer.string("Force Checkout"),
                        role: .destructive,
                        isDefault: false,
                        perform: {
                            model.resolveCheckoutConflict(
                                conflict,
                                using: .force
                            )
                        }
                    ),
                ]
            )
        )
        return GitCompactDialog(
            request: request,
            cancelTitle: localizer.string("取消"),
            onDismiss: model.dismissCheckoutConflict
        )
    }

    private func upstreamSheet(_ request: GitUpstreamRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ExplanationLabel(
                localizer.format(
                    "选择 %@ 要跟踪的远程分支。",
                    request.branch.shortName
                )
            ) {
                Text(localizer.string("设置 Upstream"))
                    .font(.headline)
            }

            Divider()

            if request.choices.isEmpty {
                BreathEmptyState(
                    title: localizer.string("没有可用的远程分支"),
                    style: .passive,
                    placement: .inline
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(request.choices) { remote in
                            Button {
                                model.setUpstream(
                                    branch: request.branch.shortName,
                                    upstream: remote.shortName
                                )
                                upstreamRequest = nil
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.branch")
                                        .foregroundStyle(.secondary)
                                    Text(remote.shortName)
                                    Spacer()
                                    if request.branch.upstream == remote.shortName {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            Divider()

            HStack {
                Button(localizer.string("取消 Upstream")) {
                    model.setUpstream(
                        branch: request.branch.shortName,
                        upstream: nil
                    )
                    upstreamRequest = nil
                }
                Spacer()
                Button(localizer.string("取消"), role: .cancel) {
                    upstreamRequest = nil
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }

    private func presentPendingCommand() {
        if model.shouldFocusCommitMessage {
            model.shouldFocusCommitMessage = false
            focusedField = .commitMessage
        }
        if model.shouldPresentPushReview {
            model.shouldPresentPushReview = false
            pushUpToOID = nil
            showingPush = true
        }
    }
}

private enum GitCompactDialogLayout {
    static let textWidth: CGFloat = 380
    static let confirmationWidth: CGFloat = 460
    static let padding: CGFloat = 18
    static let spacing: CGFloat = 14
}

private struct GitCompactDialog: View {
    let request: GitDialogRequest
    let cancelTitle: String
    let onDismiss: () -> Void

    @State private var textValue: String
    @FocusState private var isTextFieldFocused: Bool

    init(
        request: GitDialogRequest,
        cancelTitle: String,
        onDismiss: @escaping () -> Void
    ) {
        self.request = request
        self.cancelTitle = cancelTitle
        self.onDismiss = onDismiss
        switch request.content {
        case let .text(initialValue, _, _, _):
            _textValue = State(initialValue: initialValue)
        case .confirmation:
            _textValue = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GitCompactDialogLayout.spacing) {
            Text(request.title)
                .font(.headline)

            if let message = request.message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            switch request.content {
            case let .text(_, placeholder, submitTitle, submit):
                TextField(placeholder ?? "", text: $textValue)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        submitText(using: submit)
                    }

                HStack {
                    cancelButton
                    Spacer()
                    Button(submitTitle) {
                        submitText(using: submit)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedText.isEmpty)
                }
            case let .confirmation(actions):
                HStack {
                    cancelButton
                    Spacer()
                    ForEach(actions) { action in
                        actionButton(action)
                    }
                }
            }
        }
        .padding(GitCompactDialogLayout.padding)
        .frame(width: dialogWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if case .text = request.content {
                isTextFieldFocused = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.title)
    }

    private var cancelButton: some View {
        Button(cancelTitle, role: .cancel, action: onDismiss)
            .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private func actionButton(_ action: GitDialogAction) -> some View {
        if action.isDefault {
            Button(action.title, role: action.role) {
                perform(action)
            }
            .keyboardShortcut(.defaultAction)
        } else {
            Button(action.title, role: action.role) {
                perform(action)
            }
        }
    }

    private var trimmedText: String {
        textValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dialogWidth: CGFloat {
        switch request.content {
        case .text:
            GitCompactDialogLayout.textWidth
        case .confirmation:
            GitCompactDialogLayout.confirmationWidth
        }
    }

    private func submitText(using submit: @escaping (String) -> Void) {
        let value = trimmedText
        guard !value.isEmpty else { return }
        onDismiss()
        DispatchQueue.main.async {
            submit(value)
        }
    }

    private func perform(_ action: GitDialogAction) {
        onDismiss()
        DispatchQueue.main.async {
            action.perform()
        }
    }
}

private struct GitThreeColumnLayout<Left: View, Center: View, Right: View>: NSViewRepresentable {
    let initialLeftWidth: Double
    let initialCenterWidth: Double
    let resizeAccessibilityLabel: String
    let onResizeEnded: (Double, Double) -> Void
    let left: Left
    let center: Center
    let right: Right

    init(
        initialLeftWidth: Double,
        initialCenterWidth: Double,
        resizeAccessibilityLabel: String,
        onResizeEnded: @escaping (Double, Double) -> Void,
        @ViewBuilder left: () -> Left,
        @ViewBuilder center: () -> Center,
        @ViewBuilder right: () -> Right
    ) {
        self.initialLeftWidth = initialLeftWidth
        self.initialCenterWidth = initialCenterWidth
        self.resizeAccessibilityLabel = resizeAccessibilityLabel
        self.onResizeEnded = onResizeEnded
        self.left = left()
        self.center = center()
        self.right = right()
    }

    func makeNSView(context: Context) -> GitThreeColumnNSView {
        let splitView = GitThreeColumnNSView()
        splitView.setContent(
            left: AnyView(left),
            center: AnyView(center),
            right: AnyView(right)
        )
        splitView.configure(
            leftWidth: initialLeftWidth,
            centerWidth: initialCenterWidth,
            onResizeEnded: onResizeEnded,
            appliesPosition: true
        )
        splitView.setAccessibilityLabel(resizeAccessibilityLabel)
        return splitView
    }

    func updateNSView(_ splitView: GitThreeColumnNSView, context: Context) {
        splitView.setContent(
            left: AnyView(left),
            center: AnyView(center),
            right: AnyView(right)
        )
        splitView.configure(
            leftWidth: initialLeftWidth,
            centerWidth: initialCenterWidth,
            onResizeEnded: onResizeEnded,
            appliesPosition: true
        )
        splitView.setAccessibilityLabel(resizeAccessibilityLabel)
    }
}

@MainActor
final class GitThreeColumnNSView:
    NSSplitView,
    SplitDividerTrackingState
{
    private enum Metrics {
        static let minimumLeftWidth: CGFloat = 180
        static let maximumLeftWidth: CGFloat = 440
        static let minimumCenterWidth: CGFloat = 240
        static let minimumRightWidth: CGFloat = 360
        static let effectiveDividerInset: CGFloat = 4
    }

    private let leftHostingView = NativeSplitHostingView(rootView: AnyView(EmptyView()))
    private let centerHostingView = NativeSplitHostingView(rootView: AnyView(EmptyView()))
    private let rightHostingView = NativeSplitHostingView(rootView: AnyView(EmptyView()))
    private lazy var splitViewDelegate = GitThreeColumnNSViewDelegate(owner: self)
    private var pendingWidths: (left: CGFloat, center: CGFloat)?
    private var pendingContent: (left: AnyView, center: AnyView, right: AnyView)?
    private var isApplyingPositions = false
    private var isTrackingDivider = false
    private var onResizeEnded: ((Double, Double) -> Void)?
    private var dividerTrackingAreas: [NSTrackingArea] = []

    var isTrackingDividerForDescendants: Bool { isTrackingDivider }

    override var isFlipped: Bool { true }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isVertical = true
        dividerStyle = .thin
        delegate = splitViewDelegate
        for hostingView in [leftHostingView, centerHostingView, rightHostingView] {
            hostingView.wantsLayer = true
            hostingView.layer?.masksToBounds = true
            addArrangedSubview(hostingView)
        }
        setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        setHoldingPriority(.defaultLow, forSubviewAt: 2)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setContent(left: AnyView, center: AnyView, right: AnyView) {
        guard !isTrackingDivider, !hasTrackingSplitAncestor else {
            pendingContent = (left, center, right)
            return
        }
        pendingContent = nil
        leftHostingView.rootView = left
        centerHostingView.rootView = center
        rightHostingView.rootView = right
    }

    func configure(
        leftWidth: Double,
        centerWidth: Double,
        onResizeEnded: ((Double, Double) -> Void)?,
        appliesPosition: Bool
    ) {
        self.onResizeEnded = onResizeEnded
        guard appliesPosition, !isTrackingDivider else { return }
        let requestedWidths = (
            left: CGFloat(leftWidth),
            center: CGFloat(centerWidth)
        )
        if hasTrackingSplitAncestor {
            pendingWidths = requestedWidths
            return
        }
        guard needsPositionUpdate(for: requestedWidths) else {
            pendingWidths = nil
            return
        }
        pendingWidths = requestedWidths
        needsLayout = true
    }

    override func layout() {
        super.layout()
        applyPendingWidthsIfNeeded()
        updateTrackingAreas()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let previousWidths = currentWidths
        let parentWidthChanged = abs(oldSize.width - bounds.width) > 0.5
        let canPreservePrimaryWidths = parentWidthChanged
            && oldSize.width > 0
            && previousWidths.left > 0
            && previousWidths.center > 0

        super.resizeSubviews(withOldSize: oldSize)

        guard canPreservePrimaryWidths else { return }
        applyResolvedWidths(previousWidths)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard dividerIndex(at: location) != nil else { return }
        pendingWidths = nil
        isTrackingDivider = true
        NSCursor.resizeLeftRight.set()

        super.mouseDown(with: event)

        isTrackingDivider = false
        applyPendingContentIfNeeded()
        notifyDescendantSplitDividerTrackingEnded(in: self)
        window?.invalidateCursorRects(for: self)
        let widths = currentWidths
        onResizeEnded?(Double(widths.left), Double(widths.center))
    }

    func ancestorSplitDividerTrackingDidEnd() {
        guard !isTrackingDivider, !hasTrackingSplitAncestor else { return }
        applyPendingWidthsIfNeeded()
        applyPendingContentIfNeeded()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        dividerTrackingAreas.forEach(removeTrackingArea)
        dividerTrackingAreas.removeAll(keepingCapacity: true)
        super.updateTrackingAreas()
        guard arrangedSubviews.count == 3 else { return }
        for dividerIndex in 0..<2 {
            let trackingArea = NSTrackingArea(
                rect: effectiveDividerRect(at: dividerIndex),
                options: [
                    .cursorUpdate,
                    .activeInKeyWindow,
                    .enabledDuringMouseDrag,
                ],
                owner: self,
                userInfo: nil
            )
            dividerTrackingAreas.append(trackingArea)
            addTrackingArea(trackingArea)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if let trackingArea = event.trackingArea,
           dividerTrackingAreas.contains(where: { $0 === trackingArea })
        {
            NSCursor.resizeLeftRight.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard arrangedSubviews.count == 3 else { return }
        for dividerIndex in 0..<2 {
            addCursorRect(
                effectiveDividerRect(at: dividerIndex),
                cursor: .resizeLeftRight
            )
        }
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard !isApplyingPositions else { return proposedMinimumPosition }
        switch dividerIndex {
        case 0:
            return max(proposedMinimumPosition, Metrics.minimumLeftWidth)
        case 1:
            return max(
                proposedMinimumPosition,
                leftHostingView.frame.maxX
                    + dividerThickness
                    + Metrics.minimumCenterWidth
            )
        default:
            return proposedMinimumPosition
        }
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard !isApplyingPositions else { return proposedMaximumPosition }
        switch dividerIndex {
        case 0:
            return min(
                proposedMaximumPosition,
                Metrics.maximumLeftWidth,
                centerHostingView.frame.maxX
                    - dividerThickness
                    - Metrics.minimumCenterWidth
            )
        case 1:
            return min(
                proposedMaximumPosition,
                bounds.width - Metrics.minimumRightWidth
            )
        default:
            return proposedMaximumPosition
        }
    }

    func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        proposedEffectiveRect.insetBy(
            dx: -Metrics.effectiveDividerInset,
            dy: 0
        )
    }

    func splitView(
        _ splitView: NSSplitView,
        canCollapseSubview subview: NSView
    ) -> Bool {
        false
    }

    private func dividerIndex(at location: NSPoint) -> Int? {
        (0..<2).first { effectiveDividerRect(at: $0).contains(location) }
    }

    private func effectiveDividerRect(at dividerIndex: Int) -> NSRect {
        guard arrangedSubviews.indices.contains(dividerIndex) else { return .zero }
        let coordinate = arrangedSubviews[dividerIndex].frame.maxX
        return NSRect(
            x: coordinate,
            y: 0,
            width: dividerThickness,
            height: bounds.height
        )
        .insetBy(dx: -Metrics.effectiveDividerInset, dy: 0)
    }

    private var currentWidths: (left: CGFloat, center: CGFloat) {
        (
            left: leftHostingView.frame.width,
            center: centerHostingView.frame.width
        )
    }

    private func needsPositionUpdate(
        for requestedWidths: (left: CGFloat, center: CGFloat)
    ) -> Bool {
        guard bounds.width > 0, arrangedSubviews.count == 3 else { return true }
        let resolved = resolvedWidths(for: requestedWidths)
        let current = currentWidths
        return abs(current.left - resolved.left) > 0.5
            || abs(current.center - resolved.center) > 0.5
    }

    private func resolvedWidths(
        for requestedWidths: (left: CGFloat, center: CGFloat)
    ) -> (left: CGFloat, center: CGFloat) {
        let availableWidth = max(0, bounds.width - 2 * dividerThickness)
        let maximumLeftWidth = max(
            0,
            min(
                Metrics.maximumLeftWidth,
                availableWidth
                    - Metrics.minimumCenterWidth
                    - Metrics.minimumRightWidth
            )
        )
        let minimumLeftWidth = min(
            Metrics.minimumLeftWidth,
            maximumLeftWidth
        )
        let leftWidth = min(
            max(requestedWidths.left, minimumLeftWidth),
            maximumLeftWidth
        )
        let maximumCenterWidth = max(
            0,
            availableWidth - leftWidth - Metrics.minimumRightWidth
        )
        let minimumCenterWidth = min(
            Metrics.minimumCenterWidth,
            maximumCenterWidth
        )
        let centerWidth = min(
            max(requestedWidths.center, minimumCenterWidth),
            maximumCenterWidth
        )
        return (leftWidth, centerWidth)
    }

    private func applyPendingWidthsIfNeeded() {
        guard !isTrackingDivider,
              !hasTrackingSplitAncestor,
              !isApplyingPositions,
              let pendingWidths,
              bounds.width > 0,
              arrangedSubviews.count == 3
        else {
            return
        }
        self.pendingWidths = nil
        applyResolvedWidths(pendingWidths)
    }

    private func applyResolvedWidths(
        _ requestedWidths: (left: CGFloat, center: CGFloat)
    ) {
        let widths = resolvedWidths(for: requestedWidths)
        isApplyingPositions = true
        setPosition(widths.left, ofDividerAt: 0)
        setPosition(
            widths.left + dividerThickness + widths.center,
            ofDividerAt: 1
        )
        isApplyingPositions = false
    }

    private func applyPendingContentIfNeeded() {
        guard !isTrackingDivider,
              !hasTrackingSplitAncestor,
              let pendingContent
        else {
            return
        }
        self.pendingContent = nil
        leftHostingView.rootView = pendingContent.left
        centerHostingView.rootView = pendingContent.center
        rightHostingView.rootView = pendingContent.right
    }

    private var hasTrackingSplitAncestor: Bool {
        var candidate = superview
        while let view = candidate {
            if let splitView = view as? SplitDividerTrackingState,
               splitView.isTrackingDividerForDescendants
            {
                return true
            }
            candidate = view.superview
        }
        return false
    }
}

@MainActor
private final class GitThreeColumnNSViewDelegate: NSObject, NSSplitViewDelegate {
    private weak var owner: GitThreeColumnNSView?

    init(owner: GitThreeColumnNSView) {
        self.owner = owner
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        owner?.splitView(
            splitView,
            constrainMinCoordinate: proposedMinimumPosition,
            ofSubviewAt: dividerIndex
        ) ?? proposedMinimumPosition
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        owner?.splitView(
            splitView,
            constrainMaxCoordinate: proposedMaximumPosition,
            ofSubviewAt: dividerIndex
        ) ?? proposedMaximumPosition
    }

    func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        owner?.splitView(
            splitView,
            effectiveRect: proposedEffectiveRect,
            forDrawnRect: drawnRect,
            ofDividerAt: dividerIndex
        ) ?? proposedEffectiveRect
    }

    func splitView(
        _ splitView: NSSplitView,
        canCollapseSubview subview: NSView
    ) -> Bool {
        owner?.splitView(splitView, canCollapseSubview: subview) ?? false
    }
}

private struct GitResizableConsole<Header: View, Records: View>: View {
    let isVisible: Bool
    let initialHeight: Double
    let resizeAccessibilityLabel: String
    let onResizeEnded: (Double) -> Void
    let header: Header
    let records: Records

    @State private var height: Double
    @State private var dragStart: Double?

    init(
        isVisible: Bool,
        initialHeight: Double,
        resizeAccessibilityLabel: String,
        onResizeEnded: @escaping (Double) -> Void,
        @ViewBuilder header: () -> Header,
        @ViewBuilder records: () -> Records
    ) {
        self.isVisible = isVisible
        self.initialHeight = initialHeight
        self.resizeAccessibilityLabel = resizeAccessibilityLabel
        self.onResizeEnded = onResizeEnded
        self.header = header()
        self.records = records()
        _height = State(initialValue: initialHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                resizeHandle
            }
            header
                .overlay(alignment: .top) {
                    Divider()
                }
            if isVisible {
                records.frame(height: height)
            }
        }
        .onChange(of: initialHeight) { _, updatedHeight in
            guard dragStart == nil else { return }
            height = updatedHeight
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(height: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if dragStart == nil {
                            dragStart = height
                        }
                        let proposed = (dragStart ?? height)
                            - gesture.translation.height
                        height = min(max(proposed, 100), 420)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onResizeEnded(height)
                    }
            )
            .accessibilityLabel(resizeAccessibilityLabel)
    }
}

private enum GitCommitGraphMetrics {
    static let rowHeight: CGFloat = 44
}

private struct GitGraphGlyph: View {
    let row: GitGraphRow
    let isMerge: Bool

    var body: some View {
        Canvas { context, size in
            if row.connectsFromPreviousRow {
                var incomingPath = Path()
                let nodeX = laneX(row.nodeLane)
                incomingPath.move(to: CGPoint(x: nodeX, y: 0))
                incomingPath.addLine(
                    to: CGPoint(x: nodeX, y: size.height / 2)
                )
                context.stroke(
                    incomingPath,
                    with: .color(laneColor(row.nodeLane).opacity(0.8)),
                    lineWidth: 2.2
                )
            }
            for segment in row.segments {
                var path = Path()
                let from = laneX(segment.fromLane)
                let to = laneX(segment.toLane)
                let startY = segment.isParentEdge ? size.height / 2 : 0
                let endY = size.height
                path.move(to: CGPoint(x: from, y: startY))
                if from == to {
                    path.addLine(to: CGPoint(x: to, y: endY))
                } else {
                    let distance = endY - startY
                    path.addCurve(
                        to: CGPoint(x: to, y: endY),
                        control1: CGPoint(
                            x: from,
                            y: startY + distance * 0.42
                        ),
                        control2: CGPoint(
                            x: to,
                            y: startY + distance * 0.58
                        )
                    )
                }
                context.stroke(
                    path,
                    with: .color(laneColor(segment.toLane).opacity(0.8)),
                    lineWidth: segment.isParentEdge ? 2.2 : 1.6
                )
            }
            let diameter: CGFloat = isMerge ? 10 : 8
            let node = CGRect(
                x: laneX(row.nodeLane) - diameter / 2,
                y: size.height / 2 - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(
                Path(ellipseIn: node),
                with: .color(
                    isMerge ? .purple : laneColor(row.nodeLane)
                )
            )
        }
        .frame(
            width: max(16, CGFloat(row.laneCount) * 12 + 4),
            height: GitCommitGraphMetrics.rowHeight
        )
        .accessibilityHidden(true)
    }

    private func laneX(_ lane: Int) -> CGFloat {
        6 + CGFloat(lane) * 12
    }

    private func laneColor(_ lane: Int) -> Color {
        [
            Color.accentColor,
            .orange,
            .green,
            .purple,
            .pink,
            .cyan,
            .yellow,
        ][lane % 7]
    }
}

private struct GitDelayedLoadingView: View {
    let label: String

    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color.clear
            if isVisible {
                ProgressView(label)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            do {
                try await Task.sleep(for: .milliseconds(120))
                isVisible = true
            } catch {
                // The loading state completed before the delay elapsed.
            }
        }
    }
}

private enum GitUnifiedDocumentRow: Identifiable, Sendable {
    enum ID: Hashable {
        case file(String)
        case hunk(UUID)
        case line(UUID)
    }

    case file(GitPatchFile)
    case hunk(GitPatchFile, GitPatchHunk)
    case line(GitPatchLine)

    var id: ID {
        switch self {
        case let .file(file): .file(file.id)
        case let .hunk(_, hunk): .hunk(hunk.id)
        case let .line(line): .line(line.id)
        }
    }
}

@MainActor
private final class GitPatchDocumentStore: ObservableObject {
    private(set) var document = GitPatchDocument(patch: "")
    private(set) var unifiedRows: [GitUnifiedDocumentRow] = []
    private(set) var isLoading = true
    private var requestedPatch: String?

    func load(patch: String) async {
        guard requestedPatch != patch || isLoading else { return }
        requestedPatch = patch
        objectWillChange.send()
        isLoading = true

        let parsingTask = Task.detached(priority: .userInitiated) {
            let document = GitPatchDocument(patch: patch)
            return GitParsedPatch(
                document: document,
                unifiedRows: Self.makeUnifiedRows(document)
            )
        }
        let parsed = await withTaskCancellationHandler {
            await parsingTask.value
        } onCancel: {
            parsingTask.cancel()
        }

        guard !Task.isCancelled, requestedPatch == patch else { return }
        objectWillChange.send()
        document = parsed.document
        unifiedRows = parsed.unifiedRows
        isLoading = false
    }

    nonisolated private static func makeUnifiedRows(
        _ document: GitPatchDocument
    ) -> [GitUnifiedDocumentRow] {
        document.files.flatMap { file in
            [.file(file)] + file.hunks.flatMap { hunk in
                [.hunk(file, hunk)] + hunk.lines.map(GitUnifiedDocumentRow.line)
            }
        }
    }
}

private struct GitParsedPatch: Sendable {
    let document: GitPatchDocument
    let unifiedRows: [GitUnifiedDocumentRow]
}

private struct GitStructuredDiffView: View {
    let diff: GitFileDiff
    let targetFileRequest: GitDiffFileRequest?
    let preferences: GitDiffPreferences
    let shortcutPreferences: GitGlobalPreferences
    let workflow: GitChangeWorkflow
    let changelists: [GitChangelist]
    let onStageHunk: (GitPatchFile, GitPatchHunk, Bool) -> Void
    let onStageLines: (GitPatchFile, GitPatchHunk, Set<UUID>, Bool) -> Void
    let onAddHunkToChangelist: (GitPatchFile, GitPatchHunk, UUID) -> Void
    let onAddLinesToChangelist:
        (GitPatchFile, GitPatchHunk, Set<UUID>, UUID) -> Void
    let onApplyHunk: (GitPatchFile, GitPatchHunk) -> Void
    let onApplyLines: (GitPatchFile, GitPatchHunk, Set<UUID>) -> Void
    let onSystemPreview: () -> Void
    let onShelveHunk: (GitPatchFile, GitPatchHunk) -> Void
    let onShelveLines: (GitPatchFile, GitPatchHunk, Set<UUID>) -> Void
    let onRollback: (GitPatchFile, GitPatchHunk, Set<UUID>?) -> Void

    @Environment(\.applicationLanguage) private var applicationLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedLineIDs: Set<UUID> = []
    @State private var search = ""
    @State private var focusedHunkIndex = 0
    @StateObject private var documentStore: GitPatchDocumentStore

    init(
        diff: GitFileDiff,
        targetFileRequest: GitDiffFileRequest?,
        preferences: GitDiffPreferences,
        shortcutPreferences: GitGlobalPreferences,
        workflow: GitChangeWorkflow,
        changelists: [GitChangelist],
        onStageHunk: @escaping (GitPatchFile, GitPatchHunk, Bool) -> Void,
        onStageLines: @escaping (GitPatchFile, GitPatchHunk, Set<UUID>, Bool) -> Void,
        onAddHunkToChangelist: @escaping (GitPatchFile, GitPatchHunk, UUID) -> Void,
        onAddLinesToChangelist: @escaping (
            GitPatchFile,
            GitPatchHunk,
            Set<UUID>,
            UUID
        ) -> Void,
        onApplyHunk: @escaping (GitPatchFile, GitPatchHunk) -> Void,
        onApplyLines: @escaping (GitPatchFile, GitPatchHunk, Set<UUID>) -> Void,
        onSystemPreview: @escaping () -> Void,
        onShelveHunk: @escaping (GitPatchFile, GitPatchHunk) -> Void,
        onShelveLines: @escaping (GitPatchFile, GitPatchHunk, Set<UUID>) -> Void,
        onRollback: @escaping (GitPatchFile, GitPatchHunk, Set<UUID>?) -> Void
    ) {
        self.diff = diff
        self.targetFileRequest = targetFileRequest
        self.preferences = preferences
        self.shortcutPreferences = shortcutPreferences
        self.workflow = workflow
        self.changelists = changelists
        self.onStageHunk = onStageHunk
        self.onStageLines = onStageLines
        self.onAddHunkToChangelist = onAddHunkToChangelist
        self.onAddLinesToChangelist = onAddLinesToChangelist
        self.onApplyHunk = onApplyHunk
        self.onApplyLines = onApplyLines
        self.onSystemPreview = onSystemPreview
        self.onShelveHunk = onShelveHunk
        self.onShelveLines = onShelveLines
        self.onRollback = onRollback
        _documentStore = StateObject(
            wrappedValue: GitPatchDocumentStore()
        )
    }

    var body: some View {
        if diff.isBinary || diff.isTooLarge {
            BreathEmptyState(
                title: localizer.string(diff.isBinary ? "二进制文件" : "文件过大"),
                systemImage: diff.isBinary ? "doc.fill" : "doc.badge.ellipsis",
                message: localizer.format(
                    diff.isBinary
                        ? "大小：%d 字节，可使用系统预览。"
                        : "大小：%d 字节；为保持页面响应，未自动生成文本 Diff。",
                    diff.byteCount
                )
            ) {
                if diff.path != nil {
                    Button(localizer.string("使用系统应用打开")) {
                        onSystemPreview()
                    }
                }
            }
        } else if documentStore.isLoading {
            GitDelayedLoadingView(label: localizer.string("正在准备 Diff…"))
                .task(id: diff.patch) {
                    selectedLineIDs.removeAll()
                    focusedHunkIndex = 0
                    await documentStore.load(patch: diff.patch)
                }
        } else {
            VStack(spacing: 0) {
                HStack {
                    TextField(localizer.string("在 Diff 中搜索"), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    Button {
                        moveToHunk(offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .gitKeyboardShortcut(
                        "git.previousDifference",
                        preferences: shortcutPreferences
                    )
                    .disabled(focusedHunkIndex <= 0)
                    .accessibilityLabel(localizer.string("上一个差异"))
                    Button {
                        moveToHunk(offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .gitKeyboardShortcut(
                        "git.nextDifference",
                        preferences: shortcutPreferences
                    )
                    .disabled(focusedHunkIndex >= max(0, allHunkIDs.count - 1))
                    .accessibilityLabel(localizer.string("下一个差异"))
                    Spacer()
                    Text(localizer.format("%d 字节", diff.byteCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                Divider()
                ScrollViewReader { proxy in
                    Group {
                        if preferences.layout == .unified {
                            ScrollView(.vertical) {
                                unifiedDocument
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            GeometryReader { geometry in
                                ScrollView(.vertical) {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(document.files) { file in
                                            fileHeader(file)
                                            ForEach(file.hunks) { hunk in
                                                hunkHeader(file, hunk)
                                                    .id(hunk.id)
                                                sideBySideHunk(
                                                    hunk,
                                                    paneWidth: max(
                                                        1,
                                                        (geometry.size.width - 1) / 2
                                                    )
                                                )
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .onChange(of: focusedHunkIndex) { _, index in
                        guard allHunkIDs.indices.contains(index) else { return }
                        if reduceMotion {
                            proxy.scrollTo(allHunkIDs[index], anchor: .top)
                        } else {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(allHunkIDs[index], anchor: .top)
                            }
                        }
                    }
                    .onChange(of: targetFileRequest) { _, request in
                        guard let request,
                              let fileID = document.fileID(matching: request.path)
                        else {
                            return
                        }
                        proxy.scrollTo(fileID, anchor: .top)
                    }
                }
            }
            .task(id: diff.patch) {
                selectedLineIDs.removeAll()
                focusedHunkIndex = 0
                await documentStore.load(patch: diff.patch)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .breathGitPreviousDifference
                )
            ) { _ in
                moveToHunk(offset: -1)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .breathGitNextDifference
                )
            ) { _ in
                moveToHunk(offset: 1)
            }
        }
    }

    private var document: GitPatchDocument {
        documentStore.document
    }

    private var unifiedDocument: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(documentStore.unifiedRows) { row in
                unifiedRow(row)
            }
        }
    }

    @ViewBuilder
    private func unifiedRow(_ row: GitUnifiedDocumentRow) -> some View {
        switch row {
        case let .file(file):
            fileHeader(file)
        case let .hunk(file, hunk):
            hunkHeader(file, hunk)
                .id(hunk.id)
        case let .line(line):
            if search.isEmpty
                || line.content.localizedCaseInsensitiveContains(search)
            {
                unifiedLine(line)
            }
        }
    }

    private var allHunkIDs: [UUID] {
        document.files.flatMap(\.hunks).map(\.id)
    }

    private func moveToHunk(offset: Int) {
        guard !allHunkIDs.isEmpty else { return }
        focusedHunkIndex = min(
            max(focusedHunkIndex + offset, 0),
            allHunkIDs.count - 1
        )
    }

    private func fileHeader(_ file: GitPatchFile) -> some View {
        Text(file.newPath ?? file.oldPath ?? localizer.string("文件"))
            .font(.caption.monospaced().weight(.semibold))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
            .id(file.id)
    }

    private func hunkHeader(_ file: GitPatchFile, _ hunk: GitPatchHunk) -> some View {
        HStack {
            Text(hunk.header.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
            if workflow == .staging {
                Button(localizer.string(isStagedDiff ? "取消暂存 Hunk" : "暂存 Hunk")) {
                    onStageHunk(file, hunk, isStagedDiff)
                }
                .buttonStyle(.borderless)
                if !selectedLineIDs.isEmpty {
                    Button(localizer.string(isStagedDiff ? "取消暂存所选行" : "暂存所选行")) {
                        onStageLines(file, hunk, selectedLineIDs, isStagedDiff)
                        selectedLineIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Menu(localizer.string("加入变更列表")) {
                    ForEach(changelists) { changelist in
                        Button(changelist.name) {
                            onAddHunkToChangelist(
                                file,
                                hunk,
                                changelist.id
                            )
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if !selectedLineIDs.isEmpty {
                    Menu(localizer.string("将所选行加入变更列表")) {
                        ForEach(changelists) { changelist in
                            Button(changelist.name) {
                                onAddLinesToChangelist(
                                    file,
                                    hunk,
                                    selectedLineIDs,
                                    changelist.id
                                )
                                selectedLineIDs.removeAll()
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            if isApplicableHistoricalDiff {
                Button(localizer.string("应用 Hunk")) {
                    onApplyHunk(file, hunk)
                }
                .buttonStyle(.borderless)
                if !selectedLineIDs.isEmpty {
                    Button(localizer.string("应用所选行")) {
                        onApplyLines(file, hunk, selectedLineIDs)
                        selectedLineIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                }
            } else if diff.source == .workingTree {
                Menu {
                    Button(localizer.string("Shelve Hunk")) {
                        onShelveHunk(file, hunk)
                    }
                    if !selectedLineIDs.isEmpty {
                        Button(localizer.string("Shelve 所选行")) {
                            onShelveLines(file, hunk, selectedLineIDs)
                            selectedLineIDs.removeAll()
                        }
                    }
                    Divider()
                    Button(localizer.string("Rollback Hunk"), role: .destructive) {
                        onRollback(file, hunk, nil)
                    }
                    if !selectedLineIDs.isEmpty {
                        Button(localizer.string("Rollback 所选行"), role: .destructive) {
                            onRollback(file, hunk, selectedLineIDs)
                            selectedLineIDs.removeAll()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(localizer.string("Rollback 本地修改"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.secondary.opacity(0.06))
    }

    private func unifiedLine(_ line: GitPatchLine) -> some View {
        HStack(spacing: 0) {
            selectableIndicator(line)
            Text(displayed(line.raw.trimmingSuffix("\n")))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(preferences.softWrap ? nil : 1)
                .truncationMode(.tail)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(.horizontal, 5)
                .background(background(line.kind))
        }
        .frame(
            minHeight: 18,
            maxHeight: preferences.softWrap ? .infinity : 18,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(line))
    }

    @ViewBuilder
    private func sideBySideHunk(
        _ hunk: GitPatchHunk,
        paneWidth: CGFloat
    ) -> some View {
        let rows = filteredSideBySideRows(hunk.lines)
        if preferences.softWrap {
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    sideBySideCell(row.oldLine, wraps: true)
                        .frame(maxWidth: .infinity)
                    Divider()
                    sideBySideCell(row.newLine, wraps: true)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ScrollView(.horizontal) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            sideBySideCell(row.oldLine, wraps: false)
                                .frame(minWidth: paneWidth, alignment: .leading)
                        }
                    }
                    .frame(minWidth: paneWidth, alignment: .leading)
                }
                .frame(width: paneWidth)
                Divider()
                ScrollView(.horizontal) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            sideBySideCell(row.newLine, wraps: false)
                                .frame(minWidth: paneWidth, alignment: .leading)
                        }
                    }
                    .frame(minWidth: paneWidth, alignment: .leading)
                }
                .frame(width: paneWidth)
            }
        }
    }

    @ViewBuilder
    private func sideBySideCell(
        _ line: GitPatchLine?,
        wraps: Bool
    ) -> some View {
        if let line {
            HStack(spacing: 0) {
                selectableIndicator(line)
                Text(displayed(line.content))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: !wraps, vertical: true)
                    .frame(maxWidth: wraps ? .infinity : nil, alignment: .leading)
                    .padding(.horizontal, 5)
            }
            .frame(
                minHeight: 18,
                maxHeight: wraps ? .infinity : 18,
                alignment: .leading
            )
            .background(background(line.kind))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(line))
        } else {
            Color.clear.frame(height: 18)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func selectableIndicator(_ line: GitPatchLine) -> some View {
        if line.kind == .context || line.kind == .metadata {
            Color.clear
                .frame(width: 22)
                .accessibilityHidden(true)
        } else {
            Button {
                if selectedLineIDs.contains(line.id) {
                    selectedLineIDs.remove(line.id)
                } else {
                    selectedLineIDs.insert(line.id)
                }
            } label: {
                Image(
                    systemName: selectedLineIDs.contains(line.id)
                        ? "checkmark.square.fill"
                        : "square"
                )
                .frame(width: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizer.string("选择此修改行"))
        }
    }

    private func filteredLines(_ lines: [GitPatchLine]) -> [GitPatchLine] {
        guard !search.isEmpty else { return lines }
        return lines.filter {
            $0.content.localizedCaseInsensitiveContains(search)
        }
    }

    private func filteredSideBySideRows(
        _ lines: [GitPatchLine]
    ) -> [GitSideBySideRow] {
        let rows = GitSideBySideLayout.rows(for: lines)
        guard !search.isEmpty else { return rows }
        return rows.filter { row in
            row.oldLine?.content.localizedCaseInsensitiveContains(search) == true
                || row.newLine?.content.localizedCaseInsensitiveContains(search) == true
        }
    }

    private func displayed(_ value: String) -> String {
        guard preferences.showWhitespace else { return value }
        return value
            .replacingOccurrences(of: "\t", with: "→   ")
            .replacingOccurrences(of: " ", with: "·")
    }

    private func background(_ kind: GitPatchLineKind) -> Color {
        switch kind {
        case .addition: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        case .context, .metadata: .clear
        }
    }

    private func accessibilityLabel(_ line: GitPatchLine) -> String {
        let kind = switch line.kind {
        case .addition: localizer.string("新增行")
        case .deletion: localizer.string("删除行")
        case .context: localizer.string("上下文行")
        case .metadata: localizer.string("Diff 元数据")
        }
        return "\(kind)：\(line.content)"
    }

    private var isStagedDiff: Bool {
        diff.source == .staged
    }

    private var isApplicableHistoricalDiff: Bool {
        switch diff.source {
        case .stash, .commit:
            true
        case .workingTree, .staged, .between:
            false
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private struct GitWorkspaceSettingsView: View {
    @ObservedObject var model: GitWorkspaceViewModel
    @Environment(\.applicationLanguage) private var applicationLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var newProtectedPattern = ""
    @State private var newPreCommitCommand = ""
    @State private var newRemoteName = ""
    @State private var newRemoteURL = ""
    @State private var editingRemoteName: String?
    @State private var newTagName = ""
    @State private var signNewTag = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localizer.string("工作区 Git 设置"))
                    .font(.headline)
                Spacer()
                Button(localizer.string("完成")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider()

            Form {
            Picker(
                localizer.string("本地变更工作流"),
                selection: Binding(
                    get: { model.metadata.workflow },
                    set: { model.setWorkflow($0) }
                )
            ) {
                Text(localizer.string("变更列表")).tag(GitChangeWorkflow.changelists)
                Text(localizer.string("Git 暂存区")).tag(GitChangeWorkflow.staging)
            }

            Toggle(
                localizer.string("允许显式同步多个 Git Root 的分支操作"),
                isOn: Binding(
                    get: { model.metadata.synchronizeMultiRootOperations },
                    set: {
                        model.metadata.synchronizeMultiRootOperations = $0
                        model.saveWorkspaceMetadata()
                    }
                )
            )

            Section(localizer.string("受保护分支")) {
                ForEach(model.metadata.protectedBranchPatterns, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                        Spacer()
                        Button(role: .destructive) {
                            model.metadata.protectedBranchPatterns.removeAll { $0 == pattern }
                            model.saveWorkspaceMetadata()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                }
                HStack {
                    TextField(localizer.string("分支名称或模式"), text: $newProtectedPattern)
                    Button(localizer.string("添加")) {
                        guard !newProtectedPattern.isEmpty else { return }
                        model.metadata.protectedBranchPatterns.append(newProtectedPattern)
                        model.saveWorkspaceMetadata()
                        newProtectedPattern = ""
                    }
                }
            }

            Section(localizer.string("提交前命令")) {
                ForEach(model.metadata.preCommitCommands, id: \.self) { command in
                    HStack {
                        Text(command).font(.body.monospaced())
                        Spacer()
                        Button(role: .destructive) {
                            model.metadata.preCommitCommands.removeAll { $0 == command }
                            model.saveWorkspaceMetadata()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                }
                HStack {
                    TextField(localizer.string("例如：swift test"), text: $newPreCommitCommand)
                    Button(localizer.string("添加")) {
                        guard !newPreCommitCommand.isEmpty else { return }
                        model.metadata.preCommitCommands.append(newPreCommitCommand)
                        model.saveWorkspaceMetadata()
                        newPreCommitCommand = ""
                    }
                }
            }

            Section(localizer.string("Remotes")) {
                ForEach(model.remotes) { remote in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(remote.name)
                            Text(
                                GitSecretRedactor.redact(
                                    remote.fetchURL ?? ""
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            editingRemoteName = remote.name
                            newRemoteName = remote.name
                            newRemoteURL = remote.fetchURL ?? ""
                        } label: {
                            Image(systemName: "pencil")
                        }
                        Button(role: .destructive) {
                            model.removeRemote(remote.name)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                }
                HStack {
                    TextField(localizer.string("名称"), text: $newRemoteName)
                        .frame(width: 100)
                        .disabled(editingRemoteName != nil)
                    TextField(localizer.string("Remote URL"), text: $newRemoteURL)
                    Button(
                        localizer.string(
                            editingRemoteName == nil ? "添加" : "保存"
                        )
                    ) {
                        guard !newRemoteName.isEmpty, !newRemoteURL.isEmpty else {
                            return
                        }
                        model.setRemote(
                            name: newRemoteName,
                            url: newRemoteURL,
                            existing: editingRemoteName != nil
                        )
                        editingRemoteName = nil
                        newRemoteName = ""
                        newRemoteURL = ""
                    }
                    if editingRemoteName != nil {
                        Button(localizer.string("取消")) {
                            editingRemoteName = nil
                            newRemoteName = ""
                            newRemoteURL = ""
                        }
                    }
                }
            }

            Section(localizer.string("Tags")) {
                ForEach(model.references.filter { $0.kind == .tag }) { tag in
                    HStack {
                        Text(tag.shortName)
                        Text(String(tag.objectID.prefix(8)))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            model.deleteTag(tag.shortName)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                }
                HStack {
                    TextField(localizer.string("Tag 名称"), text: $newTagName)
                    Toggle(
                        localizer.string("签名"),
                        isOn: $signNewTag
                    )
                    Button(localizer.string("在 HEAD 创建")) {
                        guard !newTagName.isEmpty else { return }
                        model.createTag(
                            name: newTagName,
                            sign: signNewTag
                        )
                        newTagName = ""
                        signNewTag = false
                    }
                }
            }

            Section(localizer.string("Submodule 与 Git LFS")) {
                HStack {
                    Button(localizer.string("Init / Update Submodules")) {
                        model.updateSubmodules(initialize: true)
                    }
                    Button(localizer.string("Sync Submodule URLs")) {
                        model.synchronizeSubmoduleURLs()
                    }
                }
                ForEach(model.submodules) { submodule in
                    HStack {
                        Image(
                            systemName: submodule.isInitialized
                                ? "shippingbox.fill"
                                : "shippingbox"
                        )
                        Text(submodule.path)
                        Spacer()
                        Text(
                            submodule.hasRecordedChanges
                                ? localizer.string("指针已变化")
                                : submodule.description
                        )
                        .font(.caption)
                        .foregroundStyle(
                            submodule.hasRecordedChanges ? .orange : .secondary
                        )
                        Button(localizer.string("进入 Root")) {
                            model.selectSubmodule(submodule)
                        }
                    }
                }
                HStack {
                    Text(
                        model.lfsCapability.isInstalled
                            ? model.lfsCapability.version ?? localizer.string("Git LFS 已安装")
                            : localizer.string("Git LFS 未安装")
                    )
                    Spacer()
                    Button(localizer.string("LFS Fetch")) {
                        model.fetchLFS(pull: false)
                    }
                    .disabled(!model.lfsCapability.isInstalled)
                    Button(localizer.string("LFS Pull")) {
                        model.fetchLFS(pull: true)
                    }
                    .disabled(!model.lfsCapability.isInstalled)
                }
                ForEach(model.lfsLocks) { lock in
                    HStack {
                        Image(systemName: "lock.fill")
                        Text(lock.path)
                        Spacer()
                        Text(lock.owner)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    func trimmingSuffix(_ suffix: Character) -> String {
        last == suffix ? String(dropLast()) : self
    }
}
