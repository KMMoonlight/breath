import AppKit
import BreathAutomation
import BreathCore
import BreathNotes
import BreathTerminal
import SwiftUI

enum WorkbenchAccessibility {
    static let addWorkspace = "添加工作区"
    static let noSelectedWorkSession = "没有选中的工作会话"
    static let openWorkspace = "打开工作区"
    static let openNotes = "打开笔记"
    static let openSettings = "打开设置"
    static let openGitWorkbench = "打开 Git 工作台"
    static let openAutomation = "打开自动化"
    static let openSkills = "打开 Skills"
    static let openAgentQuota = "打开额度"
    static let automationPanel = "自动化面板"
}

private enum WorkbenchDetailMode: Hashable {
    case workspace
    case notes
    case automation
    case skills
    case agentQuota
    case settings
    case gitWorkbench
}

private struct RetainedPageIsActiveEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var retainedPageIsActive: Bool {
        get { self[RetainedPageIsActiveEnvironmentKey.self] }
        set { self[RetainedPageIsActiveEnvironmentKey.self] = newValue }
    }
}

struct RetainedPageSelection<Page: Hashable>: Equatable {
    private(set) var selected: Page
    private(set) var retainedPages: [Page]

    init(initial: Page) {
        selected = initial
        retainedPages = [initial]
    }

    mutating func select(_ page: Page) {
        if !retainedPages.contains(page) {
            retainedPages.append(page)
        }
        selected = page
    }
}

struct RetainedPageDeck<Page: Hashable, Content: View>: View {
    let selection: RetainedPageSelection<Page>
    private let content: (Page) -> Content

    init(
        selection: RetainedPageSelection<Page>,
        @ViewBuilder content: @escaping (Page) -> Content
    ) {
        self.selection = selection
        self.content = content
    }

    var body: some View {
        ZStack {
            ForEach(selection.retainedPages, id: \.self) { page in
                content(page)
                    .environment(
                        \.retainedPageIsActive,
                        selection.selected == page
                    )
                    .opacity(selection.selected == page ? 1 : 0)
                    .allowsHitTesting(selection.selected == page)
                    .accessibilityHidden(selection.selected != page)
                    .zIndex(selection.selected == page ? 1 : 0)
            }
        }
    }
}

struct WorkbenchView: View {
    @ObservedObject var model: BreathApplicationModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var pendingWorkspaceRemoval: Workspace?
    @State private var pendingWorktreeWorkspace: Workspace?
    @State private var pendingWorktreeMergeSession: WorkSession?
    @State private var pendingWorktreeDeletion: WorkSession?
    @State private var worktreeCreationError: String?
    @State private var worktreeMergeError: String?
    @State private var mergingWorktreeSessionID: WorkSessionID?
    @State private var worktreeMergeSuccessMessage: String?
    @State private var dismissedUnavailableWorkspaces: Set<WorkspaceID> = []
    @State private var expandedWorkspaceIDs: Set<WorkspaceID> = []
    @State private var expandedSessionIDs: Set<WorkSessionID> = []
    @State private var hoveredSessionID: WorkSessionID?
    @State private var pendingTerminalFocusID: TerminalPaneID?
    @State private var pageSelection = RetainedPageSelection(
        initial: WorkbenchDetailMode.workspace
    )
    @State private var selectedGitWorkspace: Workspace?
    @State private var isWindowFullScreen = false
    @StateObject private var gitCoordinator = GitWorkbenchCoordinator()

    var body: some View {
        workbenchSheets
    }

    private var workbenchLifecycle: some View {
        workbenchRoot
            .ignoresSafeArea(.container, edges: .top)
            .frame(minWidth: 900, minHeight: 600)
            .disabled(!model.isReady)
            .allowsHitTesting(model.canPerformCommands)
            .overlay {
                if !model.isReady {
                    ProgressView(localizer.string("正在恢复上次工作区…"))
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear {
                model.synchronizeTerminalAppearance(resolvedAppearance)
                model.start()
                offerRemovalForUnavailableWorkspace()
            }
            .onChange(of: colorScheme) { _, _ in
                model.synchronizeTerminalAppearance(resolvedAppearance)
            }
            .onChange(of: pageSelection.selected, initial: true) { _, mode in
                model.setNotesActive(mode == .notes)
            }
            .onChange(of: model.snapshot) { previousSnapshot, snapshot in
                updateWorkspaceExpansion(from: previousSnapshot, to: snapshot)
                offerRemovalForUnavailableWorkspace()
                focusPendingTerminalAfterViewUpdate()
                if let selectedGitWorkspace,
                   !gitWorkspaceChoices(for: snapshot).contains(where: {
                       $0.id == GitWorkspaceChoice(
                           workspace: selectedGitWorkspace
                       ).id
                   })
                {
                    self.selectedGitWorkspace = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .breathOpenGitWorkbench)) { _ in
                openGitWorkbench()
            }
            .onReceive(NotificationCenter.default.publisher(for: .breathOpenSettings)) { _ in
                selectDetailMode(.settings)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .breathSelectWorkSessionTab)
            ) { notification in
                guard pageSelection.selected != .notes else { return }
                guard let tab = notification.object as? WorkSessionTabShortcut else { return }
                selectWorkSessionTab(at: tab.selectionIndex)
            }
            .onReceive(NotificationCenter.default.publisher(for: .breathSelectPreviousPane)) { _ in
                guard pageSelection.selected != .notes else { return }
                focusAdjacentPane(previous: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .breathSelectNextPane)) { _ in
                guard pageSelection.selected != .notes else { return }
                focusAdjacentPane(previous: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .breathCloseTerminalTarget)) { _ in
                guard pageSelection.selected != .notes else { return }
                closeTerminalTarget()
            }
            .onReceive(NotificationCenter.default.publisher(for: .breathGitCommit)) { _ in
                guard let workspace = gitCommandWorkspace else { return }
                selectGitWorkspace(workspace)
                gitCoordinator.model(for: workspace).shouldFocusCommitMessage = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .breathGitPush)) { _ in
                guard let workspace = gitCommandWorkspace else { return }
                selectGitWorkspace(workspace)
                gitCoordinator.model(for: workspace).shouldPresentPushReview = true
            }
    }

    private var workbenchAlerts: some View {
        workbenchLifecycle
            .alert(
                localizer.string("移除工作区？"),
                isPresented: workspaceAlertPresented,
                presenting: pendingWorkspaceRemoval
            ) { workspace in
                Button(localizer.string("取消"), role: .cancel) {
                    dismissedUnavailableWorkspaces.insert(workspace.id)
                    pendingWorkspaceRemoval = nil
                }
                Button(localizer.string("停止并移除"), role: .destructive) {
                    model.removeWorkspace(workspace.id)
                    pendingWorkspaceRemoval = nil
                }
            } message: { workspace in
                if model.snapshot.workSessions.contains(where: {
                    $0.workspaceID == workspace.id && $0.managedWorktree != nil
                }) {
                    Text(
                        localizer.format(
                            "移除含 Worktree 的工作区说明 %@",
                            workspace.path
                        )
                    )
                } else {
                    Text(localizer.format("移除工作区说明 %@", workspace.path))
                }
            }
            .alert(
                localizer.string("删除 Worktree 及目录？"),
                isPresented: worktreeDeletionAlertPresented,
                presenting: pendingWorktreeDeletion
            ) { session in
                Button(localizer.string("取消"), role: .cancel) {
                    pendingWorktreeDeletion = nil
                }
                Button(
                    localizer.string("删除"),
                    role: .destructive
                ) {
                    deleteManagedWorktreeSession(session)
                    pendingWorktreeDeletion = nil
                }
            } message: { session in
                if let worktree = session.managedWorktree {
                    Text(
                        localizer.format(
                            "删除 Worktree 及目录说明 %@ %@",
                            worktree.rootPath,
                            worktree.branchName
                        )
                    )
                }
            }
            .alert(
                localizer.string("合并完成"),
                isPresented: worktreeMergeSuccessAlertPresented
            ) {
                Button(localizer.string("好")) {
                    worktreeMergeSuccessMessage = nil
                }
            } message: {
                Text(worktreeMergeSuccessMessage ?? "")
            }
            .alert("Breath", isPresented: errorAlertPresented) {
                Button(localizer.string("好")) { model.lastError = nil }
            } message: {
                Text(model.lastError ?? localizer.string("未知错误"))
            }
    }

    private var workbenchSheets: some View {
        workbenchAlerts
            .sheet(item: $pendingWorktreeWorkspace) { workspace in
                ManagedWorktreeCreationSheet(
                    workspace: workspace,
                    isCreating: model.creatingWorktreeWorkspaceIDs.contains(
                        workspace.id
                    ),
                    errorMessage: worktreeCreationError,
                    loadStartBranches: {
                        try await model.managedWorktreeStartBranches(
                            in: workspace.id
                        )
                    },
                    onCancel: {
                        worktreeCreationError = nil
                        pendingWorktreeWorkspace = nil
                    },
                    onCreate: { startBranch in
                        worktreeCreationError = nil
                        model.lastError = nil
                        createManagedWorktreeSession(
                            in: workspace,
                            startBranch: startBranch
                        ) { succeeded in
                            if succeeded {
                                pendingWorktreeWorkspace = nil
                            } else {
                                worktreeCreationError = model.lastError
                                    ?? localizer.string("创建 Worktree 失败。")
                                model.lastError = nil
                            }
                        }
                    }
                )
            }
            .sheet(item: $pendingWorktreeMergeSession) { session in
                if let managedWorktree = session.managedWorktree {
                    ManagedWorktreeMergeSheet(
                        session: session,
                        worktree: managedWorktree,
                        isMerging: mergingWorktreeSessionID == session.id,
                        errorMessage: worktreeMergeError,
                        loadTargetBranches: {
                            try await model.managedWorktreeMergeTargets(
                                for: session.id
                            )
                        },
                        onCancel: {
                            worktreeMergeError = nil
                            pendingWorktreeMergeSession = nil
                        },
                        onMerge: { targetBranch in
                            mergeManagedWorktreeSession(
                                session,
                                into: targetBranch
                            )
                        }
                    )
                }
            }
    }

    private var workbenchRoot: some View {
        HStack(spacing: 0) {
            activityBar
            workbenchContent
        }
        .background {
            WindowFullScreenObserver(isFullScreen: $isWindowFullScreen)
                .frame(width: 0, height: 0)
        }
        .environment(\.breathWindowIsFullScreen, isWindowFullScreen)
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: model.settings.application.language)
    }

    private var resolvedAppearance: ResolvedApplicationAppearance {
        colorScheme == .dark ? .dark : .light
    }

    private var workbenchContent: some View {
        RetainedPageDeck(selection: pageSelection) { page in
            workbenchPage(for: page)
                .font(applicationFont(for: model))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    private var activityBar: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: WorkbenchLayout.windowControlsHeight)
                .accessibilityHidden(true)

            activityBarButton(
                systemName: "folder",
                accessibilityLabel: WorkbenchAccessibility.openWorkspace,
                isSelected: pageSelection.selected == .workspace
            ) {
                selectDetailMode(.workspace)
            }

            activityBarButton(
                systemName: "note.text",
                accessibilityLabel: WorkbenchAccessibility.openNotes,
                isSelected: pageSelection.selected == .notes
            ) {
                selectDetailMode(.notes)
            }

            activityBarButton(
                accessibilityLabel: automationAccessibilityLabel,
                isSelected: pageSelection.selected == .automation,
                action: { selectDetailMode(.automation) }
            ) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "clock.arrow.2.circlepath")
                    if model.automationSnapshot.unreadCount > 0 {
                        Text(automationBadgeText)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(.red, in: Capsule())
                            .offset(x: 8, y: -7)
                            .accessibilityHidden(true)
                    }
                }
            }

            activityBarButton(
                accessibilityLabel: WorkbenchAccessibility.openGitWorkbench,
                isSelected: isGitWorkbenchSelected,
                action: openGitWorkbench
            ) {
                GitBranchIcon()
            }

            activityBarButton(
                accessibilityLabel: WorkbenchAccessibility.openSkills,
                isSelected: pageSelection.selected == .skills,
                action: { selectDetailMode(.skills) }
            ) {
                SkillActivityIcon()
            }

            activityBarButton(
                systemName: "gauge.with.dots.needle.67percent",
                accessibilityLabel: WorkbenchAccessibility.openAgentQuota,
                isSelected: pageSelection.selected == .agentQuota
            ) {
                selectDetailMode(.agentQuota)
            }

            Spacer(minLength: 0)

            activityBarButton(
                systemName: "gearshape",
                accessibilityLabel: WorkbenchAccessibility.openSettings,
                isSelected: pageSelection.selected == .settings
            ) {
                selectDetailMode(.settings)
            }
        }
        .frame(width: WorkbenchLayout.activityBarWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .trailing) {
            Color(nsColor: .separatorColor)
                .frame(width: WorkbenchLayout.splitDividerThickness)
                .padding(.top, WorkbenchLayout.windowControlsHeight)
        }
    }

    private func activityBarButton(
        systemName: String,
        accessibilityLabel: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        activityBarButton(
            accessibilityLabel: accessibilityLabel,
            isSelected: isSelected,
            action: action
        ) {
            Image(systemName: systemName)
        }
    }

    private func activityBarButton<Icon: View>(
        accessibilityLabel: String,
        isSelected: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .symbolRenderingMode(.monochrome)
                .font(.system(size: WorkbenchLayout.activityBarIconSize, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary : sidebarActionForegroundColor)
                .frame(
                    width: WorkbenchLayout.activityBarIconSize,
                    height: WorkbenchLayout.activityBarIconSize
                )
                .frame(
                    width: WorkbenchLayout.activityBarSelectionSize,
                    height: WorkbenchLayout.activityBarSelectionSize
                )
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    }
                }
                .frame(
                    width: WorkbenchLayout.activityBarItemSize,
                    height: WorkbenchLayout.activityBarItemSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(ActivityBarButtonStyle())
        .accessibilityLabel(localizer.string(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(localizer.string(accessibilityLabel))
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localizer.string("工作区"))
                    .font(applicationFont(for: model, offset: 1, weight: .semibold))
                Spacer()
                Menu {
                    Button(localizer.string("选择已有文件夹"), systemImage: "folder") {
                        chooseWorkspace()
                    }
                    Button(localizer.string("创建新文件夹"), systemImage: "folder.badge.plus") {
                        createWorkspace()
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .tint(.primary)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(localizer.string(WorkbenchAccessibility.addWorkspace))
                .help(localizer.string(WorkbenchAccessibility.addWorkspace))
            }
            .pageToolbarLeadingPadding()
            .padding(.trailing, WorkbenchLayout.pageToolbarTrailingInset)
            .frame(height: WorkbenchLayout.pageToolbarHeight)

            Divider()

            if model.snapshot.workspaces.isEmpty {
                BreathEmptyState(
                    title: localizer.string("添加工作区"),
                    systemImage: "folder.badge.plus"
                )
            } else {
                List {
                    ForEach(model.snapshot.workspaces) { workspace in
                        workspaceSection(workspace)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .font(applicationFont(for: model))
                .controlSize(.regular)
                .environment(
                    \.defaultMinListRowHeight,
                    WorkbenchLayout.sidebarRowHeight
                )
            }

        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func workspaceSection(_ workspace: Workspace) -> some View {
        DisclosureGroup(isExpanded: workspaceExpansionBinding(for: workspace.id)) {
            let sessions = model.snapshot.activeWorkSessions.filter {
                $0.workspaceID == workspace.id
            }
            ForEach(sessions) { session in
                sessionTree(session)
            }
            if model.creatingWorktreeWorkspaceIDs.contains(workspace.id) {
                HStack(spacing: WorkbenchLayout.sidebarItemSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text(localizer.string("正在创建 Worktree…"))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, WorkbenchLayout.sidebarPaneLeadingInset)
            }
        } label: {
            HStack(spacing: WorkbenchLayout.sidebarItemSpacing) {
                Image(systemName: model.isWorkspaceAvailable(workspace) ? "folder" : "folder.badge.questionmark")
                    .foregroundStyle(
                        model.isWorkspaceAvailable(workspace)
                            ? Color.secondary
                            : Color.orange
                    )
                Text(workspace.displayName)
                    .font(applicationFont(for: model))
                    .lineLimit(1)
                Spacer()
                Menu {
                    workspaceMenuItems(workspace)
                } label: {
                    SidebarActionIcon(
                        systemName: "ellipsis",
                        color: sidebarActionForegroundColor
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(sidebarActionForegroundColor)
                .controlSize(.small)
                .frame(
                    width: WorkbenchLayout.sidebarActionFrameSize,
                    height: WorkbenchLayout.sidebarActionFrameSize
                )
                .help(localizer.string("工作区菜单"))
                Button {
                    createWorkSession(in: workspace.id)
                } label: {
                    SidebarActionIcon(
                        systemName: "plus",
                        color: sidebarActionForegroundColor
                    )
                }
                .buttonStyle(.borderless)
                .tint(sidebarActionForegroundColor)
                .controlSize(.small)
                .frame(
                    width: WorkbenchLayout.sidebarActionFrameSize,
                    height: WorkbenchLayout.sidebarActionFrameSize
                )
                .help(localizer.string("新建工作会话"))
            }
            .padding(.leading, WorkbenchLayout.sidebarWorkspaceDisclosureSpacing)
            .contextMenu {
                workspaceMenuItems(workspace)
            }
        }
    }

    @ViewBuilder
    private func workspaceMenuItems(_ workspace: Workspace) -> some View {
        Button(localizer.string("新建工作会话")) {
            createWorkSession(in: workspace.id)
        }
        Button(localizer.string("新建 Worktree 会话…")) {
            worktreeCreationError = nil
            pendingWorktreeWorkspace = workspace
        }
        .disabled(model.creatingWorktreeWorkspaceIDs.contains(workspace.id))
        Divider()
        Button(localizer.string("移除工作区…"), role: .destructive) {
            pendingWorkspaceRemoval = workspace
        }
    }

    @ViewBuilder
    private func sessionTree(_ session: WorkSession) -> some View {
        let panes = session.layout.panes
        if panes.count == 1 {
            sessionRow(session, pane: panes[0])
        } else {
            HStack(spacing: 0) {
                Button {
                    toggleSessionExpansion(session.id)
                } label: {
                    Image(
                        systemName: expandedSessionIDs.contains(session.id)
                            ? "chevron.down"
                            : "chevron.right"
                    )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(
                            width: WorkbenchLayout.sidebarSessionDisclosureWidth,
                            height: WorkbenchLayout.sidebarActionFrameSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    localizer.string(
                        expandedSessionIDs.contains(session.id)
                            ? "收起终端窗格"
                            : "展开终端窗格"
                    )
                )
                sessionRowContent(
                    session,
                    pane: nil,
                    selectionBackgroundLeadingPadding: -25,
                    contentLeadingPadding: WorkbenchLayout.sidebarDisclosureLabelSpacing
                )
            }
            if expandedSessionIDs.contains(session.id) {
                ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                    Button {
                        requestTerminalFocus(session: session, pane: pane)
                    } label: {
                        HStack(spacing: WorkbenchLayout.sidebarItemSpacing) {
                            StateDot(state: pane.state)
                            if let agent = pane.agentBinding?.agent {
                                AgentTypeLabel(agent: agent)
                            }
                            Text(
                                pane.agentBinding?.nativeTitle
                                    ?? localizer.format("终端 %d", index + 1)
                            )
                                .font(applicationFont(for: model))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, WorkbenchLayout.sidebarPaneLeadingInset)
                }
            }
        }
    }

    private func toggleSessionExpansion(_ sessionID: WorkSessionID) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if expandedSessionIDs.contains(sessionID) {
                expandedSessionIDs.remove(sessionID)
            } else {
                expandedSessionIDs.insert(sessionID)
            }
        }
    }

    private func requestTerminalFocus(session: WorkSession, pane: TerminalPane) {
        pendingTerminalFocusID = pane.id
        selectWorkSession(session.id)
        focusPendingTerminalAfterViewUpdate()
    }

    private func selectWorkSession(_ sessionID: WorkSessionID) {
        selectDetailMode(.workspace)
        model.selectWorkSession(sessionID)
    }

    private func selectWorkSessionTab(at index: Int) {
        guard let workspaceID = model.currentWorkspaceID,
              let sessionID = model.snapshot.activeWorkSessionID(
                  at: index,
                  in: workspaceID
              ),
              let session = model.snapshot.activeWorkSessions.first(where: {
                  $0.id == sessionID
              })
        else {
            return
        }
        pendingTerminalFocusID = model.shortcutPriority
            .lastFocusedTerminalPaneID(in: session.id)
            .flatMap { paneID in
                session.layout.paneIDs.contains(paneID) ? paneID : nil
            }
            ?? session.layout.paneIDs.first
        selectWorkSession(sessionID)
    }

    private func closeTerminalTarget() {
        guard pageSelection.selected == .workspace,
              let selectedSessionID = model.snapshot.selectedWorkSessionID,
              let session = model.snapshot.activeWorkSessions.first(where: {
                  $0.id == selectedSessionID
              })
        else {
            return
        }
        let preferredPaneID = [
            model.shortcutPriority.focusedTerminalPaneID,
            model.shortcutPriority.lastFocusedTerminalPaneID(in: session.id),
        ]
        .compactMap { $0 }
        .first(where: { session.layout.paneIDs.contains($0) })
        switch TerminalCloseShortcutResolver.target(
            for: session,
            preferredPaneID: preferredPaneID
        ) {
        case .pane(let paneID):
            model.closePane(paneID)
        case .workSession:
            archive(session)
        }
    }

    private func focusAdjacentPane(previous: Bool) {
        guard let selectedSessionID = model.snapshot.selectedWorkSessionID,
              let session = model.snapshot.activeWorkSessions.first(where: {
                  $0.id == selectedSessionID
              })
        else {
            return
        }
        let currentPaneID = [
            model.shortcutPriority.focusedTerminalPaneID,
            model.shortcutPriority.lastFocusedTerminalPaneID(in: session.id),
            model.shortcutPriority.lastFocusedTerminalPaneID,
        ]
        .compactMap { $0 }
        .first(where: { session.layout.paneIDs.contains($0) })
        let targetPaneID: TerminalPaneID?
        if let currentPaneID {
            targetPaneID = previous
                ? session.layout.previousPaneID(from: currentPaneID)
                : session.layout.nextPaneID(from: currentPaneID)
        } else {
            targetPaneID = session.layout.paneIDs.first
        }
        guard let targetPaneID else { return }
        selectDetailMode(.workspace)
        pendingTerminalFocusID = targetPaneID
        focusPendingTerminalAfterViewUpdate()
    }

    private func focusPendingTerminalAfterViewUpdate() {
        guard pendingTerminalFocusID != nil else { return }
        DispatchQueue.main.async {
            guard let paneID = pendingTerminalFocusID,
                  TerminalInputFocus.move(
                      to: paneID,
                      using: model.terminalEngine
                  )
            else {
                return
            }
            if pendingTerminalFocusID == paneID {
                pendingTerminalFocusID = nil
            }
        }
    }

    private func sessionRow(_ session: WorkSession, pane: TerminalPane) -> some View {
        sessionRowContent(session, pane: pane)
    }

    private func sessionRowContent(
        _ session: WorkSession,
        pane: TerminalPane?,
        selectionBackgroundLeadingPadding: CGFloat = -5,
        contentLeadingPadding: CGFloat = 0
    ) -> some View {
        let showsArchiveButton = hoveredSessionID == session.id
        return HStack(spacing: WorkbenchLayout.sidebarItemSpacing) {
            if let managedWorktree = session.managedWorktree {
                ManagedWorktreeMarker(
                    worktree: managedWorktree,
                    workingDirectory: model.workingDirectory(for: session),
                    localizer: localizer
                )
            }
            if let pane { StateDot(state: pane.state) }
            if let agent = pane?.agentBinding?.agent {
                AgentTypeLabel(agent: agent)
            }
            Button {
                selectWorkSession(session.id)
            } label: {
                HStack(spacing: 7) {
                    Text(session.title)
                        .font(applicationFont(for: model))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                archive(session)
            } label: {
                Image(systemName: "archivebox")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                localizer.string("归档并停止该会话的所有终端进程")
            )
            .help(localizer.string("归档并停止该会话的所有终端进程"))
            .opacity(showsArchiveButton ? 1 : 0)
            .allowsHitTesting(showsArchiveButton)
        }
        .padding(.vertical, 1)
        .padding(.leading, contentLeadingPadding)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                hoveredSessionID = session.id
            } else if hoveredSessionID == session.id {
                hoveredSessionID = nil
            }
        }
        .background {
            if model.snapshot.selectedWorkSessionID == session.id {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        Color.accentColor.opacity(
                            colorScheme == .dark ? 0.28 : 0.16
                        )
                    )
                    .padding(.leading, selectionBackgroundLeadingPadding)
                    .padding(.trailing, -5)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            if let managedWorktree = session.managedWorktree {
                let workingDirectory = model.workingDirectory(for: session)
                Button(localizer.string("在 Finder 中显示")) {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(
                            fileURLWithPath: workingDirectory,
                            isDirectory: true
                        ),
                    ])
                }
                Button(localizer.string("复制路径")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(
                        workingDirectory,
                        forType: .string
                    )
                }
                Divider()
                Button {
                    worktreeMergeError = nil
                    pendingWorktreeMergeSession = session
                } label: {
                    Label(
                        localizer.string("合并到目标分支…"),
                        systemImage: "arrow.triangle.merge"
                    )
                }
                .disabled(managedWorktree.state != .available)
                Button(role: .destructive) {
                    pendingWorktreeDeletion = session
                } label: {
                    Label(
                        localizer.string("删除 Worktree 及目录…"),
                        systemImage: "trash"
                    )
                }
                Divider()
            }
            Button(
                localizer.string("归档并停止该会话的所有终端进程"),
                role: .destructive
            ) {
                archive(session)
            }
        }
    }

    private func archive(_ session: WorkSession) {
        model.archive(
            session.id,
            selecting: model.snapshot.archiveFallbackWorkSessionID(
                for: session.id
            )
        )
    }

    private func mergeManagedWorktreeSession(
        _ session: WorkSession,
        into targetBranch: ManagedWorktreeStartBranch
    ) {
        guard mergingWorktreeSessionID == nil,
              let worktree = session.managedWorktree
        else {
            return
        }
        mergingWorktreeSessionID = session.id
        worktreeMergeError = nil
        model.lastError = nil
        model.mergeManagedWorktreeSession(
            session.id,
            into: targetBranch
        ) { succeeded in
            mergingWorktreeSessionID = nil
            if succeeded {
                pendingWorktreeMergeSession = nil
                worktreeMergeSuccessMessage = localizer.format(
                    "已将 %@ 合并到 %@。",
                    worktree.branchName,
                    targetBranch.name
                )
            } else {
                worktreeMergeError = model.lastError
                    ?? localizer.string("合并 Worktree 失败。")
                model.lastError = nil
            }
        }
    }

    private func deleteManagedWorktreeSession(_ session: WorkSession) {
        model.deleteManagedWorktreeSession(
            session.id,
            selecting: model.snapshot.archiveFallbackWorkSessionID(
                for: session.id
            )
        )
    }

    private func createWorkSession(in workspaceID: WorkspaceID) {
        expandedWorkspaceIDs.insert(workspaceID)
        model.createWorkSession(in: workspaceID)
    }

    private func createManagedWorktreeSession(
        in workspace: Workspace,
        startBranch: ManagedWorktreeStartBranch,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        expandedWorkspaceIDs.insert(workspace.id)
        model.createManagedWorktreeSession(
            in: workspace.id,
            startBranch: startBranch,
            completion: completion
        )
    }

    private var isGitWorkbenchSelected: Bool {
        pageSelection.selected == .gitWorkbench
    }

    private var gitCommandWorkspace: Workspace? {
        if pageSelection.selected == .gitWorkbench, let selectedGitWorkspace {
            return selectedGitWorkspace
        }
        if let currentWorkspaceID = model.currentWorkspaceID {
            return model.gitWorkspace(for: currentWorkspaceID)
        }
        return selectedGitWorkspace
    }

    private func openGitWorkbench() {
        if selectedGitWorkspace == nil,
           let currentWorkspaceID = model.currentWorkspaceID
        {
            selectedGitWorkspace = model.gitWorkspace(for: currentWorkspaceID)
        }
        selectDetailMode(.gitWorkbench)
    }

    private var gitWorkspaceChoices: [GitWorkspaceChoice] {
        gitWorkspaceChoices(for: model.snapshot)
    }

    private func gitWorkspaceChoices(
        for snapshot: WorkbenchSnapshot
    ) -> [GitWorkspaceChoice] {
        var choices: [GitWorkspaceChoice] = []
        var paths: Set<String> = []
        for workspace in snapshot.workspaces {
            let workspaceChoice = GitWorkspaceChoice(workspace: workspace)
            if paths.insert(workspaceChoice.id).inserted {
                choices.append(workspaceChoice)
            }
            for session in snapshot.activeWorkSessions where
                session.workspaceID == workspace.id
            {
                guard let worktree = session.managedWorktree,
                      worktree.state == .available
                else {
                    continue
                }
                let worktreeWorkspace = Workspace(
                    id: workspace.id,
                    path: worktree.workingDirectory,
                    displayName: workspace.displayName
                )
                let choice = GitWorkspaceChoice(
                    workspace: worktreeWorkspace,
                    displayName: "\(workspace.displayName) · \(worktree.branchName)"
                )
                if paths.insert(choice.id).inserted {
                    choices.append(choice)
                }
            }
        }
        return choices
    }

    private func selectGitWorkspace(_ workspacePath: String) {
        guard let workspace = gitWorkspaceChoices.first(where: {
            $0.id == workspacePath
        })?.workspace else {
            return
        }
        selectGitWorkspace(workspace)
    }

    private func selectGitWorkspace(_ workspace: Workspace) {
        selectedGitWorkspace = workspace
        selectDetailMode(.gitWorkbench)
    }

    private var sidebarActionForegroundColor: Color {
        controlActiveState == .inactive ? .secondary : .primary
    }

    private func updateWorkspaceExpansion(
        from previousSnapshot: WorkbenchSnapshot,
        to snapshot: WorkbenchSnapshot
    ) {
        let currentWorkspaceIDs = Set(snapshot.workspaces.map(\.id))
        expandedWorkspaceIDs.formIntersection(currentWorkspaceIDs)
        guard model.isReady else { return }

        let previousWorkspaceIDs = Set(previousSnapshot.workspaces.map(\.id))
        expandedWorkspaceIDs.formUnion(
            currentWorkspaceIDs.subtracting(previousWorkspaceIDs)
        )
    }

    private func workspaceExpansionBinding(for workspaceID: WorkspaceID) -> Binding<Bool> {
        Binding(
            get: { expandedWorkspaceIDs.contains(workspaceID) },
            set: { isExpanded in
                if isExpanded {
                    expandedWorkspaceIDs.insert(workspaceID)
                } else {
                    expandedWorkspaceIDs.remove(workspaceID)
                }
            }
        )
    }

    private func selectDetailMode(_ mode: WorkbenchDetailMode) {
        guard pageSelection.selected != mode else { return }
        TerminalInputFocus.resignCurrentInput()
        pageSelection.select(mode)
    }

    @ViewBuilder
    private func workbenchPage(for page: WorkbenchDetailMode) -> some View {
        switch page {
        case .workspace:
            SidebarResizeContainer {
                sidebar
            } detail: {
                sessionDetail
            }
        case .settings:
            BreathSettingsView(model: model)
        case .notes:
            NotesView(applicationModel: model)
        case .skills:
            SkillsView(service: model.skillsService)
        case .agentQuota:
            AgentQuotaView(service: model.agentQuotaService)
        case .automation:
            AutomationView(model: model)
        case .gitWorkbench:
            if let workspace = selectedGitWorkspace {
                GitWorkbenchView(
                    workspace: workspace,
                    workspaces: gitWorkspaceChoices,
                    model: gitCoordinator.model(for: workspace),
                    isVisible: pageSelection.selected == .gitWorkbench,
                    onAddWorkspace: { model.addWorkspace($0) },
                    onSelectWorkspace: selectGitWorkspace
                )
                .id(workspace.path)
            } else {
                GitWorkbenchUnselectedView(
                    workspaces: gitWorkspaceChoices,
                    onSelectWorkspace: selectGitWorkspace
                )
            }
        }
    }

    private var automationBadgeText: String {
        let count = model.automationSnapshot.unreadCount
        return count > 99 ? "99+" : "\(count)"
    }

    private var automationAccessibilityLabel: String {
        let count = model.automationSnapshot.unreadCount
        guard count > 0 else {
            return localizer.string(WorkbenchAccessibility.openAutomation)
        }
        return localizer.format(
            "打开自动化，%d 个未查看结果",
            count
        )
    }

    @ViewBuilder
    private var sessionDetail: some View {
        if let selectedID = model.snapshot.selectedWorkSessionID,
           let session = model.snapshot.activeWorkSessions.first(where: {
               $0.id == selectedID
           })
        {
            let sessions = model.snapshot.activeWorkSessions.filter {
                $0.workspaceID == session.workspaceID
            }
            VStack(spacing: 0) {
                WorkSessionTabBar(
                    sessions: sessions,
                    selectedSessionID: selectedID,
                    workspacePath: model.workingDirectory(for: session),
                    model: model,
                    onSelect: selectWorkSession,
                    onCreate: { createWorkSession(in: session.workspaceID) },
                    onArchive: archive
                )
                WorkSessionTerminalLayoutView(
                    session: session,
                    model: model
                )
                .id(session.id)
            }
        } else {
            ZStack {
                model.effectiveTerminalColorTheme.canvasColor
                BreathEmptyState(
                    title: localizer.string(
                        WorkbenchAccessibility.noSelectedWorkSession
                    ),
                    systemImage: "terminal"
                )
            }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localizer.string(WorkbenchAccessibility.noSelectedWorkSession))
        }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = localizer.string("添加")
        panel.message = localizer.string("选择一个项目目录")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addWorkspace(url)
    }

    private func createWorkspace() {
        let panel = NSSavePanel()
        panel.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        panel.title = localizer.string("创建新文件夹")
        panel.prompt = localizer.string("创建")
        panel.message = localizer.string("选择位置并输入新文件夹名称")
        panel.nameFieldLabel = localizer.string("文件夹名称：")
        panel.nameFieldStringValue = localizer.string("新建文件夹")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: false
            )
            model.addWorkspace(url)
        } catch {
            model.lastError = localizer.format(
                "无法创建文件夹：%@",
                error.localizedDescription
            )
        }
    }

    private func offerRemovalForUnavailableWorkspace() {
        guard pendingWorkspaceRemoval == nil,
              let workspace = model.snapshot.workspaces.first(where: { workspace in
                  !model.isWorkspaceAvailable(workspace)
                      && !dismissedUnavailableWorkspaces.contains(workspace.id)
                      && !model.snapshot.workSessions.contains(where: { session in
                          session.workspaceID == workspace.id
                              && session.managedWorktree?.state == .available
                      })
              })
        else {
            return
        }
        pendingWorkspaceRemoval = workspace
    }

    private var workspaceAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingWorkspaceRemoval != nil },
            set: { if !$0 { pendingWorkspaceRemoval = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }

    private var worktreeDeletionAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingWorktreeDeletion != nil },
            set: { if !$0 { pendingWorktreeDeletion = nil } }
        )
    }

    private var worktreeMergeSuccessAlertPresented: Binding<Bool> {
        Binding(
            get: { worktreeMergeSuccessMessage != nil },
            set: { if !$0 { worktreeMergeSuccessMessage = nil } }
        )
    }
}

private struct ManagedWorktreeMergeSheet: View {
    let session: WorkSession
    let worktree: ManagedWorktree
    let isMerging: Bool
    let errorMessage: String?
    let loadTargetBranches: () async throws -> [ManagedWorktreeStartBranch]
    let onCancel: () -> Void
    let onMerge: (ManagedWorktreeStartBranch) -> Void

    @Environment(\.applicationLanguage) private var applicationLanguage
    @State private var targetBranches: [ManagedWorktreeStartBranch] = []
    @State private var selectedTargetBranch: ManagedWorktreeStartBranch?
    @State private var isLoadingTargetBranches = true
    @State private var targetBranchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                ExplanationLabel(
                    localizer.string(
                        "将 Worktree 分支合并到所选本地分支。只会合并已提交内容；不会删除源 Worktree。若发生冲突，Breath 会自动中止合并。"
                    )
                ) {
                    Text(localizer.string("合并 Worktree 分支"))
                        .font(.headline)
                }
                Text(session.title)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 10) {
                branchBadge(worktree.branchName)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .frame(height: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizer.string("目标分支"))
                        .font(.subheadline.weight(.medium))
                    if isLoadingTargetBranches {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(localizer.string("正在加载分支…"))
                                .foregroundStyle(.secondary)
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 28,
                            alignment: .leading
                        )
                    } else if let targetBranchError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(targetBranchError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                            Button(localizer.string("重新加载")) {
                                Task { await reloadTargetBranches() }
                            }
                        }
                    } else {
                        ManagedWorktreeStartBranchPicker(
                            startBranches: targetBranches,
                            selectedStartBranch: $selectedTargetBranch
                        )
                        .disabled(isMerging)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(localizer.string("取消"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isMerging)
                Button {
                    if let selectedTargetBranch {
                        onMerge(selectedTargetBranch)
                    }
                } label: {
                    if isMerging {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(localizer.string("合并"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canMerge || isMerging)
            }
        }
        .padding(20)
        .frame(width: 500)
        .interactiveDismissDisabled(isMerging)
        .task(id: session.id) {
            await reloadTargetBranches()
        }
    }

    private func branchBadge(_ branchName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            Text(branchName)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            Color.primary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private var canMerge: Bool {
        selectedTargetBranch != nil && targetBranchError == nil
    }

    @MainActor
    private func reloadTargetBranches() async {
        isLoadingTargetBranches = true
        targetBranchError = nil
        do {
            let loadedBranches = try await loadTargetBranches()
            targetBranches = loadedBranches
            selectedTargetBranch = selectedTargetBranch.flatMap {
                selectedBranch in
                loadedBranches.first {
                    $0.reference == selectedBranch.reference
                }
            } ?? loadedBranches.first(where: \.isCurrent)
                ?? loadedBranches.first
            if loadedBranches.isEmpty {
                targetBranchError = localizer.string(
                    "没有可用的本地目标分支"
                )
            }
        } catch {
            targetBranches = []
            selectedTargetBranch = nil
            targetBranchError = localizer.format(
                "加载分支失败：%@",
                error.localizedDescription
            )
        }
        isLoadingTargetBranches = false
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private struct ManagedWorktreeCreationSheet: View {
    let workspace: Workspace
    let isCreating: Bool
    let errorMessage: String?
    let loadStartBranches: () async throws -> [ManagedWorktreeStartBranch]
    let onCancel: () -> Void
    let onCreate: (ManagedWorktreeStartBranch) -> Void

    @Environment(\.applicationLanguage) private var applicationLanguage
    @State private var startBranches: [ManagedWorktreeStartBranch] = []
    @State private var selectedStartBranch: ManagedWorktreeStartBranch?
    @State private var isLoadingStartBranches = true
    @State private var startBranchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(localizer.string("新建 Worktree 会话"))
                    .font(.headline)
                Text(workspace.displayName)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ExplanationLabel(startBranchHelp) {
                    Text(localizer.string("起始分支"))
                        .font(.subheadline.weight(.medium))
                }
                if isLoadingStartBranches {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(localizer.string("正在加载分支…"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                } else if let startBranchError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(startBranchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                        Button(localizer.string("重新加载")) {
                            Task { await reloadStartBranches() }
                        }
                    }
                } else {
                    ManagedWorktreeStartBranchPicker(
                        startBranches: startBranches,
                        selectedStartBranch: $selectedStartBranch
                    )
                    .disabled(isCreating)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button(localizer.string("取消"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)
                Button {
                    if let selectedStartBranch {
                        onCreate(selectedStartBranch)
                    }
                } label: {
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(localizer.string("创建"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || isCreating)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(isCreating)
        .task(id: workspace.id) {
            await reloadStartBranches()
        }
    }

    private var canCreate: Bool {
        selectedStartBranch != nil && startBranchError == nil
    }

    @MainActor
    private func reloadStartBranches() async {
        isLoadingStartBranches = true
        startBranchError = nil
        do {
            let loadedStartBranches = try await loadStartBranches()
            startBranches = loadedStartBranches
            let refreshedSelection = selectedStartBranch.flatMap {
                selectedBranch in
                loadedStartBranches.first {
                    $0.reference == selectedBranch.reference
                }
            }
            selectedStartBranch =
                refreshedSelection
                ?? loadedStartBranches.first(where: \.isCurrent)
                ?? loadedStartBranches.first
            if loadedStartBranches.isEmpty {
                startBranchError = localizer.string("没有可用分支")
            }
        } catch {
            startBranches = []
            selectedStartBranch = nil
            startBranchError = localizer.format(
                "加载分支失败：%@",
                error.localizedDescription
            )
        }
        isLoadingStartBranches = false
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }

    private var startBranchHelp: String {
        localizer.string(
            "Breath 会从所选分支的当前提交创建独立会话分支。原检出的未提交修改不会复制；删除 Worktree 时会保留会话分支。"
        )
    }
}

private struct ManagedWorktreeStartBranchPicker: View {
    let startBranches: [ManagedWorktreeStartBranch]
    @Binding var selectedStartBranch: ManagedWorktreeStartBranch?

    @Environment(\.applicationLanguage) private var applicationLanguage
    @State private var isPresented = false
    @State private var query = ""
    @FocusState private var focusesSearch: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                Text(selectedStartBranch?.name ?? localizer.string("选择分支"))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selectedStartBranch?.isCurrent == true {
                    Text(localizer.string("当前"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    localizer.string("搜索分支"),
                    text: $query
                )
                .textFieldStyle(.roundedBorder)
                .focused($focusesSearch)
                .onSubmit {
                    if let firstStartBranch = filteredStartBranches.first {
                        selectedStartBranch = firstStartBranch
                        isPresented = false
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        startBranchSection(
                            title: localizer.string("本地分支"),
                            startBranches: filteredStartBranches.filter {
                                $0.kind == .localBranch
                            }
                        )
                        startBranchSection(
                            title: localizer.string("远程分支"),
                            startBranches: filteredStartBranches.filter {
                                $0.kind == .remoteBranch
                            }
                        )
                        if filteredStartBranches.isEmpty {
                            BreathEmptyState(
                                title: localizer.string("没有匹配的分支"),
                                style: .passive
                            )
                            .frame(minHeight: 80)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 260)
            }
            .padding(12)
            .frame(width: 360)
            .onAppear {
                query = ""
                focusesSearch = true
            }
        }
    }

    @ViewBuilder
    private func startBranchSection(
        title: String,
        startBranches: [ManagedWorktreeStartBranch]
    ) -> some View {
        if !startBranches.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                ForEach(startBranches) { startBranch in
                    let isSelected =
                        selectedStartBranch?.reference == startBranch.reference
                    Button {
                        selectedStartBranch = startBranch
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(
                                systemName:
                                    isSelected
                                        ? "checkmark"
                                        : "arrow.triangle.branch"
                            )
                            .frame(width: 14)
                            Text(startBranch.name)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if startBranch.isCurrent {
                                Text(localizer.string("当前"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var filteredStartBranches: [ManagedWorktreeStartBranch] {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else { return startBranches }
        return startBranches.filter {
            $0.name.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.reference.localizedCaseInsensitiveContains(
                    normalizedQuery
                )
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private struct ManagedWorktreeMarker: View {
    let worktree: ManagedWorktree
    let workingDirectory: String
    let localizer: ApplicationLocalizer

    var body: some View {
        Image(
            systemName: worktree.state == .available
                ? "arrow.triangle.branch"
                : "exclamationmark.triangle.fill"
        )
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(
            worktree.state == .available ? Color.secondary : Color.orange
        )
        .frame(
            width: WorkbenchLayout.agentIconFrameSize,
            height: WorkbenchLayout.agentIconFrameSize
        )
        .help(
            [
                localizer.format("Worktree 分支：%@", worktree.branchName),
                workingDirectory,
                localizer.format(
                    "创建基线：%@",
                    String(worktree.baselineCommit.prefix(8))
                ),
            ].joined(separator: "\n")
        )
        .accessibilityLabel(
            [
                localizer.format("Worktree 分支：%@", worktree.branchName),
                workingDirectory,
                localizer.format(
                    "创建基线：%@",
                    String(worktree.baselineCommit.prefix(8))
                ),
            ].joined(separator: "\n")
        )
    }
}

extension Notification.Name {
    static let breathOpenSettings = Notification.Name("Breath.OpenSettings")
    static let breathOpenGitWorkbench = Notification.Name("Breath.OpenGitWorkbench")
    static let breathSelectWorkSessionTab = Notification.Name(
        "Breath.SelectWorkSessionTab"
    )
    static let breathSelectPreviousPane = Notification.Name("Breath.SelectPreviousPane")
    static let breathSelectNextPane = Notification.Name("Breath.SelectNextPane")
    static let breathCloseTerminalTarget = Notification.Name(
        "Breath.CloseTerminalTarget"
    )
    static let breathGitCommit = Notification.Name("Breath.GitCommit")
    static let breathGitPush = Notification.Name("Breath.GitPush")
    static let breathGitPreviousDifference = Notification.Name(
        "Breath.GitPreviousDifference"
    )
    static let breathGitNextDifference = Notification.Name(
        "Breath.GitNextDifference"
    )
}

private struct SidebarResizeContainer<Sidebar: View, Detail: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        NativeSplitView(
            orientation: .horizontal,
            position: .points(WorkbenchLayout.sidebarDefaultWidth),
            minimumPosition: .points(WorkbenchLayout.sidebarMinimumWidth),
            maximumPosition: .points(WorkbenchLayout.sidebarMaximumWidth),
            minimumSecondLength: 520,
            updatesPosition: false
        ) {
            sidebar
        } second: {
            detail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }
}

private struct StateDot: View {
    let state: TerminalState
    @Environment(\.applicationLanguage) private var applicationLanguage

    var body: some View {
        Circle()
            .fill(color)
            .frame(
                width: WorkbenchLayout.sidebarStateDotSize,
                height: WorkbenchLayout.sidebarStateDotSize
            )
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch state {
        case .idle: .secondary
        case .running: .blue
        case .needsAttention: .orange
        case .turnCompleted: .green
        }
    }

    private var label: String {
        let key = switch state {
        case .idle: "空闲或已退出"
        case .running: "运行中"
        case .needsAttention: "需要处理"
        case .turnCompleted: "回合完成"
        }
        return ApplicationLocalizer(language: applicationLanguage).string(key)
    }
}

struct WorkSessionTabPresentation: Equatable {
    let title: String
    let shortcutLabel: String?

    init(
        session: WorkSession,
        index: Int,
        placeholderTitle: String
    ) {
        title = session.titleSource == nil ? placeholderTitle : session.title
        shortcutLabel = BreathShortcut.workSessionTabs.indices.contains(index)
            ? "⌘\(index + 1)"
            : nil
    }
}

private struct WorkSessionTabBar: View {
    let sessions: [WorkSession]
    let selectedSessionID: WorkSessionID
    let workspacePath: String
    @ObservedObject var model: BreathApplicationModel
    let onSelect: (WorkSessionID) -> Void
    let onCreate: () -> Void
    let onArchive: (WorkSession) -> Void
    @Environment(\.applicationLanguage) private var applicationLanguage
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredSessionID: WorkSessionID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(
                            Array(sessions.enumerated()),
                            id: \.element.id
                        ) { index, session in
                            sessionTab(session, at: index)
                                .id(session.id)
                        }

                        Button(action: onCreate) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .frame(
                                    width: WorkbenchLayout.sessionTabActionSize,
                                    height: WorkbenchLayout.sessionTabActionSize
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(localizer.string("新建工作会话"))
                        .help(localizer.string("新建工作会话（⌘T）"))
                        .padding(.horizontal, 3)
                    }
                }
                .onAppear {
                    scrollSelectedTabIntoView(using: proxy)
                }
                .onChange(of: selectedSessionID) { _, _ in
                    scrollSelectedTabIntoView(using: proxy)
                }
            }

            Divider()

            WorkspaceEditorLauncher(
                workspacePath: workspacePath,
                barHeight: WorkbenchLayout.sessionTabBarHeight
            )
            .padding(.trailing, 6)
        }
        .frame(height: WorkbenchLayout.sessionTabBarHeight)
        .background {
            ZStack(alignment: .bottom) {
                Color(nsColor: .windowBackgroundColor)
                Divider()
            }
        }
    }

    private func sessionTab(_ session: WorkSession, at index: Int) -> some View {
        let isSelected = session.id == selectedSessionID
        let showsArchive = isSelected || hoveredSessionID == session.id
        let presentation = WorkSessionTabPresentation(
            session: session,
            index: index,
            placeholderTitle: localizer.string("新会话")
        )
        return HStack(spacing: 0) {
            Button {
                onSelect(session.id)
            } label: {
                HStack(spacing: 7) {
                    sessionMarker(session)
                    Text(presentation.title)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let shortcutLabel = presentation.shortcutLabel {
                        Text(shortcutLabel)
                            .font(
                                .system(
                                    size: 10,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()
                            .foregroundStyle(
                                isSelected ? Color.accentColor : Color.secondary
                            )
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        isSelected
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.primary.opacity(0.08)
                                    )
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                onArchive(session)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(
                        width: WorkbenchLayout.sessionTabActionSize,
                        height: WorkbenchLayout.sessionTabActionSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                localizer.string("归档并停止该会话的所有终端进程")
            )
            .help(localizer.string("归档并停止该会话的所有终端进程"))
            .opacity(showsArchive ? 1 : 0)
            .allowsHitTesting(showsArchive)
        }
        .font(applicationFont(for: model, offset: -1))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .frame(
            width: WorkbenchLayout.sessionTabWidth,
            height: WorkbenchLayout.sessionTabBarHeight
        )
        .background {
            if isSelected {
                UnevenRoundedRectangle(
                    topLeadingRadius: WorkbenchLayout.sessionTabCornerRadius,
                    topTrailingRadius: WorkbenchLayout.sessionTabCornerRadius
                )
                .fill(
                    Color.accentColor.opacity(
                        colorScheme == .dark ? 0.18 : 0.1
                    )
                )
            } else if hoveredSessionID == session.id {
                Color.primary.opacity(0.06)
            }
        }
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(
                        height: WorkbenchLayout.sessionTabSelectionIndicatorHeight
                    )
            }
        }
        .overlay(alignment: .trailing) {
            if !isSelected {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: WorkbenchLayout.sessionTabSeparatorWidth)
                    .padding(.vertical, 7)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                hoveredSessionID = session.id
            } else if hoveredSessionID == session.id {
                hoveredSessionID = nil
            }
        }
        .contextMenu {
            Button(
                localizer.string("归档并停止该会话的所有终端进程"),
                role: .destructive
            ) {
                onArchive(session)
            }
        }
    }

    @ViewBuilder
    private func sessionMarker(_ session: WorkSession) -> some View {
        if let managedWorktree = session.managedWorktree {
            ManagedWorktreeMarker(
                worktree: managedWorktree,
                workingDirectory: model.workingDirectory(for: session),
                localizer: localizer
            )
        } else if session.layout.panes.count == 1 {
            if let agent = session.layout.panes.first?.agentBinding?.agent {
                AgentTypeLabel(agent: agent)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: WorkbenchLayout.agentIconFrameSize,
                        height: WorkbenchLayout.agentIconFrameSize
                    )
            }
        } else {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(
                    width: WorkbenchLayout.agentIconFrameSize,
                    height: WorkbenchLayout.agentIconFrameSize
                )
        }
    }

    private func scrollSelectedTabIntoView(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(selectedSessionID, anchor: .center)
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private struct WorkSessionTerminalLayoutView: View {
    let session: WorkSession
    @ObservedObject var model: BreathApplicationModel

    var body: some View {
        PaneLayoutView(
            layout: session.layout,
            workSessionID: session.id,
            path: [],
            paneOrder: session.layout.paneIDs,
            model: model
        )
    }
}

private struct PaneLayoutView: View {
    let layout: PaneLayout
    let workSessionID: WorkSessionID
    let path: [SplitBranch]
    let paneOrder: [TerminalPaneID]
    @ObservedObject var model: BreathApplicationModel

    @ViewBuilder
    var body: some View {
        switch layout {
        case .pane(let pane):
            TerminalPaneView(
                pane: pane,
                workSessionID: workSessionID,
                canClose: paneOrder.count > 1,
                model: model
            )
            .id(pane.id)
        case .split(let orientation, let fraction, let first, let second):
            SplitContainer(
                orientation: orientation,
                fraction: fraction,
                onResize: { newFraction in
                    model.resizeSplit(
                        in: workSessionID,
                        path: path,
                        fraction: newFraction
                    )
                }
            ) {
                PaneLayoutView(
                    layout: first,
                    workSessionID: workSessionID,
                    path: path + [.first],
                    paneOrder: paneOrder,
                    model: model
                )
            } second: {
                PaneLayoutView(
                    layout: second,
                    workSessionID: workSessionID,
                    path: path + [.second],
                    paneOrder: paneOrder,
                    model: model
                )
            }
        }
    }

}

private struct SplitContainer<First: View, Second: View>: View {
    let orientation: SplitOrientation
    let fraction: Double
    let onResize: (Double) -> Void
    @ViewBuilder let first: First
    @ViewBuilder let second: Second

    init(
        orientation: SplitOrientation,
        fraction: Double,
        onResize: @escaping (Double) -> Void,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.orientation = orientation
        self.fraction = fraction
        self.onResize = onResize
        self.first = first()
        self.second = second()
    }

    var body: some View {
        NativeSplitView(
            orientation: orientation,
            position: .fraction(fraction),
            minimumPosition: .fraction(0.1),
            maximumPosition: .fraction(0.9),
            minimumSecondLength: 1,
            updatesPosition: true,
            onResize: onResize
        ) {
            first
        } second: {
            second
        }
    }
}

enum NativeSplitPosition: Equatable {
    case points(CGFloat)
    case fraction(Double)

    func coordinate(availableLength: CGFloat) -> CGFloat {
        switch self {
        case .points(let points):
            points
        case .fraction(let fraction):
            availableLength * CGFloat(fraction)
        }
    }
}

@MainActor
protocol SplitDividerTrackingState: AnyObject {
    var isTrackingDividerForDescendants: Bool { get }
    func ancestorSplitDividerTrackingDidEnd()
}

extension SplitDividerTrackingState {
    func ancestorSplitDividerTrackingDidEnd() {}
}

@MainActor
func notifyDescendantSplitDividerTrackingEnded(in view: NSView) {
    for subview in view.subviews {
        if let splitView = subview as? SplitDividerTrackingState {
            splitView.ancestorSplitDividerTrackingDidEnd()
        }
        notifyDescendantSplitDividerTrackingEnded(in: subview)
    }
}

struct NativeSplitView<First: View, Second: View>: NSViewRepresentable {
    let orientation: SplitOrientation
    let position: NativeSplitPosition
    let minimumPosition: NativeSplitPosition
    let maximumPosition: NativeSplitPosition
    let minimumSecondLength: CGFloat
    let drawsDivider: Bool
    let updatesPosition: Bool
    let onResize: ((Double) -> Void)?
    @ViewBuilder let first: First
    @ViewBuilder let second: Second

    init(
        orientation: SplitOrientation,
        position: NativeSplitPosition,
        minimumPosition: NativeSplitPosition,
        maximumPosition: NativeSplitPosition,
        minimumSecondLength: CGFloat,
        drawsDivider: Bool = true,
        updatesPosition: Bool,
        onResize: ((Double) -> Void)? = nil,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.orientation = orientation
        self.position = position
        self.minimumPosition = minimumPosition
        self.maximumPosition = maximumPosition
        self.minimumSecondLength = minimumSecondLength
        self.drawsDivider = drawsDivider
        self.updatesPosition = updatesPosition
        self.onResize = onResize
        self.first = first()
        self.second = second()
    }

    func makeNSView(context: Context) -> NativeSplitNSView {
        let splitView = NativeSplitNSView()
        splitView.setContent(first: AnyView(first), second: AnyView(second))
        splitView.configure(
            orientation: orientation,
            position: position,
            minimumPosition: minimumPosition,
            maximumPosition: maximumPosition,
            minimumSecondLength: minimumSecondLength,
            drawsDivider: drawsDivider,
            onResize: onResize,
            appliesPosition: true
        )
        return splitView
    }

    func updateNSView(_ splitView: NativeSplitNSView, context: Context) {
        splitView.setContent(first: AnyView(first), second: AnyView(second))
        splitView.configure(
            orientation: orientation,
            position: position,
            minimumPosition: minimumPosition,
            maximumPosition: maximumPosition,
            minimumSecondLength: minimumSecondLength,
            drawsDivider: drawsDivider,
            onResize: onResize,
            appliesPosition: updatesPosition
        )
    }
}

@MainActor
final class NativeSplitNSView:
    NSSplitView,
    SplitDividerTrackingState
{
    private let firstHostingView = NativeSplitHostingView(rootView: AnyView(EmptyView()))
    private let secondHostingView = NativeSplitHostingView(rootView: AnyView(EmptyView()))
    private lazy var splitViewDelegate = NativeSplitNSViewDelegate(owner: self)
    private var minimumPosition = NativeSplitPosition.fraction(0)
    private var maximumPosition = NativeSplitPosition.fraction(1)
    private var minimumSecondLength: CGFloat = 0
    private var drawsDivider = true
    private var configuredPosition: NativeSplitPosition?
    private var pendingPosition: NativeSplitPosition?
    private var isApplyingPosition = false
    private var isTrackingDivider = false
    private var pendingContent: (first: AnyView, second: AnyView)?
    private var onResize: ((Double) -> Void)?
    private var dividerTrackingArea: NSTrackingArea?

    var isTrackingDividerForDescendants: Bool { isTrackingDivider }

    override var isFlipped: Bool { true }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        dividerStyle = .thin
        delegate = splitViewDelegate
        firstHostingView.wantsLayer = true
        firstHostingView.layer?.masksToBounds = true
        secondHostingView.wantsLayer = true
        secondHostingView.layer?.masksToBounds = true
        addArrangedSubview(firstHostingView)
        addArrangedSubview(secondHostingView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.window != nil,
                  !self.isTrackingDivider,
                  let configuredPosition = self.configuredPosition
            else {
                return
            }
            self.pendingPosition = configuredPosition
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
    }

    func setContent(first: AnyView, second: AnyView) {
        guard !isTrackingDivider, !hasTrackingSplitAncestor else {
            pendingContent = (first, second)
            return
        }
        pendingContent = nil
        firstHostingView.rootView = first
        secondHostingView.rootView = second
    }

    func configure(
        orientation: SplitOrientation,
        position: NativeSplitPosition,
        minimumPosition: NativeSplitPosition,
        maximumPosition: NativeSplitPosition,
        minimumSecondLength: CGFloat,
        drawsDivider: Bool = true,
        onResize: ((Double) -> Void)?,
        appliesPosition: Bool
    ) {
        let updatedIsVertical = orientation == .horizontal
        let orientationChanged = isVertical != updatedIsVertical
        isVertical = updatedIsVertical
        firstHostingView.configureDividerCursor(
            edge: isVertical ? .trailing : .bottom,
            cursor: isVertical ? .resizeLeftRight : .resizeUpDown
        )
        secondHostingView.configureDividerCursor(
            edge: isVertical ? .leading : .top,
            cursor: isVertical ? .resizeLeftRight : .resizeUpDown
        )
        self.minimumPosition = minimumPosition
        self.maximumPosition = maximumPosition
        self.minimumSecondLength = minimumSecondLength
        if self.drawsDivider != drawsDivider {
            self.drawsDivider = drawsDivider
            needsDisplay = true
        }
        self.onResize = onResize
        if appliesPosition {
            configuredPosition = position
            if isTrackingDivider {
                pendingPosition = nil
            } else if hasTrackingSplitAncestor {
                pendingPosition = position
            } else if needsPositionUpdate(for: position) {
                pendingPosition = position
                needsLayout = true
            } else {
                pendingPosition = nil
            }
        }
        if orientationChanged {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func layout() {
        super.layout()
        applyPendingPositionIfNeeded()
        updateTrackingAreas()
    }

    override func drawDivider(in rect: NSRect) {
        guard drawsDivider else { return }
        super.drawDivider(in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard effectiveDividerRect.contains(location) else { return }
        pendingPosition = nil
        isTrackingDivider = true
        dividerCursor.set()

        // NSSplitView performs live resizing while it tracks the mouse. Keep
        // SwiftUI content and persisted layout updates deferred until mouse-up,
        // but never replace the live resize with a detached guide line.
        super.mouseDown(with: event)

        isTrackingDivider = false
        applyPendingContentIfNeeded()
        notifyDescendantSplitDividerTrackingEnded(in: self)
        window?.invalidateCursorRects(for: self)
        onResize?(currentFraction)
    }

    func ancestorSplitDividerTrackingDidEnd() {
        guard !isTrackingDivider, !hasTrackingSplitAncestor else { return }
        applyPendingPositionIfNeeded()
        applyPendingContentIfNeeded()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        if let dividerTrackingArea {
            removeTrackingArea(dividerTrackingArea)
        }
        super.updateTrackingAreas()
        guard arrangedSubviews.count > 1, !effectiveDividerRect.isEmpty else {
            dividerTrackingArea = nil
            return
        }
        let trackingArea = NSTrackingArea(
            rect: effectiveDividerRect,
            options: [
                .cursorUpdate,
                .activeInKeyWindow,
                .enabledDuringMouseDrag,
            ],
            owner: self,
            userInfo: nil
        )
        dividerTrackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard event.trackingArea === dividerTrackingArea else {
            super.cursorUpdate(with: event)
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        if effectiveDividerRect.contains(location) {
            dividerCursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard arrangedSubviews.count > 1 else { return }
        let drawnRect = isVertical
            ? NSRect(
                x: currentDividerCoordinate,
                y: 0,
                width: dividerThickness,
                height: bounds.height
            )
            : NSRect(
                x: 0,
                y: currentDividerCoordinate,
                width: bounds.width,
                height: dividerThickness
            )
        let effectiveRect = isVertical
            ? drawnRect.insetBy(dx: -4, dy: 0)
            : drawnRect.insetBy(dx: 0, dy: -4)
        addCursorRect(
            effectiveRect,
            cursor: isVertical ? .resizeLeftRight : .resizeUpDown
        )
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        max(proposedMinimumPosition, minimumCoordinate)
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        min(proposedMaximumPosition, maximumCoordinate)
    }

    func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        isVertical
            ? proposedEffectiveRect.insetBy(dx: -4, dy: 0)
            : proposedEffectiveRect.insetBy(dx: 0, dy: -4)
    }

    private var availableLength: CGFloat {
        max(0, (isVertical ? bounds.width : bounds.height) - dividerThickness)
    }

    private var minimumCoordinate: CGFloat {
        min(
            max(0, minimumPosition.coordinate(availableLength: availableLength)),
            availableLength
        )
    }

    private var maximumCoordinate: CGFloat {
        let configuredMaximum = maximumPosition.coordinate(availableLength: availableLength)
        return max(
            minimumCoordinate,
            min(
                availableLength,
                configuredMaximum,
                max(0, availableLength - minimumSecondLength)
            )
        )
    }

    private var dividerCursor: NSCursor {
        isVertical ? .resizeLeftRight : .resizeUpDown
    }

    private var effectiveDividerRect: NSRect {
        let drawnRect = isVertical
            ? NSRect(
                x: currentDividerCoordinate,
                y: 0,
                width: dividerThickness,
                height: bounds.height
            )
            : NSRect(
                x: 0,
                y: currentDividerCoordinate,
                width: bounds.width,
                height: dividerThickness
            )
        return isVertical
            ? drawnRect.insetBy(dx: -4, dy: 0)
            : drawnRect.insetBy(dx: 0, dy: -4)
    }

    private var currentFraction: Double {
        guard availableLength > 0, let firstSubview = arrangedSubviews.first else {
            return 0.5
        }
        let firstLength = isVertical ? firstSubview.frame.width : firstSubview.frame.height
        return min(max(Double(firstLength / availableLength), 0.1), 0.9)
    }

    private func needsPositionUpdate(for position: NativeSplitPosition) -> Bool {
        guard availableLength > 0 else {
            return pendingPosition != position
        }
        return abs(currentDividerCoordinate - coordinate(for: position)) > 0.5
    }

    private func coordinate(for position: NativeSplitPosition) -> CGFloat {
        min(
            max(
                position.coordinate(availableLength: availableLength),
                minimumCoordinate
            ),
            maximumCoordinate
        )
    }

    private func applyPendingPositionIfNeeded() {
        guard !isTrackingDivider,
              !hasTrackingSplitAncestor,
              !isApplyingPosition,
              let pendingPosition,
              availableLength > 0
        else {
            return
        }
        self.pendingPosition = nil
        let coordinate = coordinate(for: pendingPosition)
        guard abs(currentDividerCoordinate - coordinate) > 0.5 else { return }
        isApplyingPosition = true
        setPosition(coordinate, ofDividerAt: 0)
        isApplyingPosition = false
    }

    private func applyPendingContentIfNeeded() {
        guard !hasTrackingSplitAncestor, let pendingContent else { return }
        self.pendingContent = nil
        firstHostingView.rootView = pendingContent.first
        secondHostingView.rootView = pendingContent.second
    }

    private var currentDividerCoordinate: CGFloat {
        guard let firstSubview = arrangedSubviews.first else { return 0 }
        return isVertical ? firstSubview.frame.maxX : firstSubview.frame.maxY
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
private final class NativeSplitNSViewDelegate: NSObject, NSSplitViewDelegate {
    private weak var owner: NativeSplitNSView?

    init(owner: NativeSplitNSView) {
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
}

@MainActor
final class NativeSplitHostingView: NSHostingView<AnyView> {
    enum DividerEdge: Equatable {
        case leading
        case trailing
        case top
        case bottom
    }

    private var dividerEdge: DividerEdge?
    private var dividerCursor: NSCursor?

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    func configureDividerCursor(edge: DividerEdge, cursor: NSCursor) {
        guard dividerEdge != edge || dividerCursor !== cursor else { return }
        dividerEdge = edge
        dividerCursor = cursor
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let dividerEdge, let dividerCursor else { return }
        let hitThickness: CGFloat = 5
        let cursorRect: NSRect = switch dividerEdge {
        case .leading:
            NSRect(x: 0, y: 0, width: hitThickness, height: bounds.height)
        case .trailing:
            NSRect(
                x: max(0, bounds.width - hitThickness),
                y: 0,
                width: hitThickness,
                height: bounds.height
            )
        case .top:
            NSRect(
                x: 0,
                y: isFlipped ? 0 : max(0, bounds.height - hitThickness),
                width: bounds.width,
                height: hitThickness
            )
        case .bottom:
            NSRect(
                x: 0,
                y: isFlipped ? max(0, bounds.height - hitThickness) : 0,
                width: bounds.width,
                height: hitThickness
            )
        }
        addCursorRect(cursorRect, cursor: dividerCursor)
    }
}

private struct TerminalPaneView: View {
    let pane: TerminalPane
    let workSessionID: WorkSessionID
    let canClose: Bool
    @ObservedObject var model: BreathApplicationModel
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.applicationLanguage) private var applicationLanguage
    @State private var hasInputFocus = false
    @State private var isClosing = false

    private var showsInputFocus: Bool {
        hasInputFocus && controlActiveState == .key
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StateDot(state: pane.state)
                if let agent = pane.agentBinding?.agent {
                    AgentTypeLabel(agent: agent)
                }
                terminalTitle
                Spacer()
                Button {
                    model.split(pane.id, orientation: .horizontal)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .foregroundStyle(.primary)
                }
                .breathKeyboardShortcut(
                    BreathShortcutCatalog.splitHorizontally,
                    priority: model.shortcutPriority,
                    targeting: pane.id
                )
                .help(localizer.string("横向分屏（⌘D）"))
                Button {
                    model.split(pane.id, orientation: .vertical)
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .foregroundStyle(.primary)
                }
                .breathKeyboardShortcut(
                    BreathShortcutCatalog.splitVertically,
                    priority: model.shortcutPriority,
                    targeting: pane.id
                )
                .help(localizer.string("纵向分屏（⌘⇧D）"))
                if canClose {
                    Button(role: .destructive) {
                        closePane()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .disabled(isClosing)
                    .help(localizer.string("关闭窗格（⌘W）"))
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                showsInputFocus
                    ? Color.accentColor.opacity(0.28)
                    : Color.clear
            )
            .background(.bar)

            TerminalNativeView(
                engine: model.terminalEngine,
                paneID: pane.id,
                placeholder: localizer.string("终端正在启动…"),
                shortcutPolicy: model.settings.terminalShortcutPolicy,
                onFocusChange: { isFocused in
                    hasInputFocus = isFocused
                    model.updateTerminalInputFocus(
                        paneID: pane.id,
                        workSessionID: workSessionID,
                        isFocused: isFocused
                    )
                },
                breathShortcutMatch: { event in
                    if let match = BreathShortcutCatalog.match(for: event) {
                        return match
                    }
                    if GitShortcutResolver.commandID(
                            matching: event,
                            preferences: GitPreferencesStore.shared.preferences,
                            requiredScope: .global
                    ) != nil {
                        return .application
                    }
                    return nil
                }
            )
        }
        .background(model.effectiveTerminalColorTheme.canvasColor)
    }

    private var terminalTitle: some View {
        Button(action: focusTerminal) {
            Text(pane.agentBinding?.nativeTitle ?? localizer.string("终端"))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .font(applicationFont(for: model, offset: -1))
    }

    private func focusTerminal() {
        guard let terminalView = model.terminalEngine.view(for: pane.id),
              let window = terminalView.window
        else {
            return
        }
        window.makeFirstResponder(terminalView)
    }

    private func closePane() {
        guard !isClosing else { return }
        isClosing = true
        model.closePane(pane.id) { didClose in
            if !didClose {
                isClosing = false
            }
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private struct GitBranchIcon: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 14
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scale, y: y * scale)
            }

            var branches = Path()
            branches.move(to: point(3.5, 4.7))
            branches.addLine(to: point(3.5, 9.3))
            branches.move(to: point(5.2, 4.8))
            branches.addCurve(
                to: point(10.5, 3.5),
                control1: point(7.4, 4.8),
                control2: point(8.5, 3.5)
            )
            context.stroke(
                branches,
                with: .foreground,
                style: StrokeStyle(
                    lineWidth: 1.25 * scale,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            for center in [point(3.5, 3.2), point(10.8, 3.2), point(3.5, 10.8)] {
                let circle = CGRect(
                    x: center.x - 1.55 * scale,
                    y: center.y - 1.55 * scale,
                    width: 3.1 * scale,
                    height: 3.1 * scale
                )
                context.stroke(
                    Path(ellipseIn: circle),
                    with: .foreground,
                    lineWidth: 1.2 * scale
                )
            }
        }
    }
}

private struct SkillActivityIcon: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 14, height: 14)
                .offset(x: 1, y: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 7, weight: .semibold))
                .offset(x: -2, y: -2)
        }
    }
}

private struct AgentTypeLabel: View {
    let agent: AgentKind

    var body: some View {
        AgentBrandIcon(agent: agent)
            .accessibilityLabel(agent.displayName)
            .help(agent.displayName)
    }
}

private struct SidebarActionIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: WorkbenchLayout.sidebarActionIconSize, weight: .medium))
            .foregroundStyle(color)
            .frame(
                width: WorkbenchLayout.sidebarActionFrameSize,
                height: WorkbenchLayout.sidebarActionFrameSize
            )
            .contentShape(Rectangle())
    }
}

private struct ActivityBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

enum WorkbenchLayout {
    static let windowControlsHeight: CGFloat = 32
    static let activityBarWidth: CGFloat = 44
    static let activityBarItemSize: CGFloat = 44
    static let activityBarSelectionSize: CGFloat = 32
    static let activityBarIconSize: CGFloat = 16
    static let pageToolbarHeight: CGFloat = 32
    static let pageToolbarLeadingInset: CGFloat = 44
    static let fullScreenPageToolbarLeadingInset: CGFloat = 12
    static let pageToolbarTrailingInset: CGFloat = 12
    static let sidebarDefaultWidth: CGFloat = 220
    static let sidebarMinimumWidth: CGFloat = 140
    static let sidebarMaximumWidth: CGFloat = 380
    static let sidebarRowHeight: CGFloat = 36
    static let sidebarItemSpacing: CGFloat = 8
    static let sidebarDisclosureLabelSpacing: CGFloat = 3
    static let sidebarWorkspaceDisclosureSpacing: CGFloat = 6
    static let sidebarSessionDisclosureWidth: CGFloat = 17
    static let sidebarPaneLeadingInset: CGFloat = 21
    static let sidebarStateDotSize: CGFloat = 8
    static let sidebarActionFrameSize: CGFloat = 20
    static let sidebarActionIconSize: CGFloat = 12
    static let sessionTabBarHeight: CGFloat = 34
    static let sessionTabWidth: CGFloat = 180
    static let sessionTabActionSize: CGFloat = 28
    static let sessionTabSeparatorWidth: CGFloat = 1
    static let sessionTabSelectionIndicatorHeight: CGFloat = 2
    static let sessionTabCornerRadius: CGFloat = 6
    static let bottomBarHeight: CGFloat = 32
    static let agentIconFrameSize: CGFloat = 16
    static let agentIconGlyphSize: CGFloat = 14
    static let splitDividerThickness: CGFloat = 1

    static func pageToolbarLeadingInset(isFullScreen: Bool) -> CGFloat {
        isFullScreen
            ? fullScreenPageToolbarLeadingInset
            : pageToolbarLeadingInset
    }
}

@MainActor
private func applicationFont(
    for model: BreathApplicationModel,
    offset: CGFloat = 0,
    weight: Font.Weight = .regular,
    design: Font.Design = .default
) -> Font {
    .system(
        size: max(1, CGFloat(model.settings.application.fontSize) + offset),
        weight: weight,
        design: design
    )
}

private extension AgentKind {
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude"
        case .antigravityCLI: "Antigravity"
        case .githubCopilotCLI: "Copilot"
        case .qwenCode: "Qwen"
        case .cursorAgent: "Cursor"
        case .factoryDroid: "Droid"
        case .openCode: "OpenCode"
        case .pi: "Pi"
        case .kimiCode: "Kimi"
        }
    }
}

private extension TerminalColorTheme {
    var canvasColor: Color {
        let background = palette.background
        return Color(
            red: Double(background.red) / 255,
            green: Double(background.green) / 255,
            blue: Double(background.blue) / 255
        )
    }
}

private struct TerminalNativeView: NSViewRepresentable {
    @Environment(\.retainedPageIsActive) private var retainedPageIsActive
    let engine: any TerminalViewProviding
    let paneID: TerminalPaneID
    let placeholder: String
    let shortcutPolicy: TerminalShortcutPolicy
    let onFocusChange: (Bool) -> Void
    let breathShortcutMatch: (NSEvent) -> BreathShortcutMatch?

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.onFocusChange = onFocusChange
        host.shortcutPolicy = shortcutPolicy
        host.breathShortcutMatch = breathShortcutMatch
        host.handleTerminalShortcut = { event in
            _ = engine.handleShortcutKeyDown(event, for: paneID)
        }
        host.isHidden = !retainedPageIsActive
        host.install(engine.view(for: paneID), placeholder: placeholder)
        return host
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        nsView.onFocusChange = onFocusChange
        nsView.shortcutPolicy = shortcutPolicy
        nsView.breathShortcutMatch = breathShortcutMatch
        nsView.handleTerminalShortcut = { event in
            _ = engine.handleShortcutKeyDown(event, for: paneID)
        }
        nsView.isHidden = !retainedPageIsActive
        nsView.install(engine.view(for: paneID), placeholder: placeholder)
    }
}

@MainActor
enum TerminalInputFocus {
    @discardableResult
    static func move(
        to paneID: TerminalPaneID,
        using provider: any TerminalViewProviding
    ) -> Bool {
        guard let terminalView = provider.view(for: paneID),
              let window = terminalView.window
        else {
            return false
        }
        let previousHost = (window.firstResponder as? NSView)?
            .superview as? TerminalHostView
        let targetHost = terminalView.superview as? TerminalHostView
        let didMoveFocus = window.makeFirstResponder(terminalView)
        if didMoveFocus {
            previousHost?.synchronizeFocusState()
            targetHost?.synchronizeFocusState()
        }
        return didMoveFocus
    }

    static func resignCurrentInput() {
        guard let window = NSApp.keyWindow else { return }
        var view = window.firstResponder as? NSView
        while let currentView = view {
            if let host = currentView as? TerminalHostView {
                host.relinquishInputFocus()
                return
            }
            view = currentView.superview
        }
        window.makeFirstResponder(nil)
    }
}

@MainActor
final class TerminalHostView: NSView {
    private weak var hostedView: NSView?
    private weak var monitoredWindow: NSWindow?
    private var focusEventMonitor: Any?
    private var lastReportedFocus: Bool?
    private var retainsInputFocus = false
    private weak var requestedTerminalView: NSView?
    private var requestedPlaceholder = "终端正在启动…"
    var onFocusChange: ((Bool) -> Void)?
    var shortcutPolicy: TerminalShortcutPolicy = .breathFirst
    var breathShortcutMatch: ((NSEvent) -> BreathShortcutMatch?)?
    var handleTerminalShortcut: ((NSEvent) -> Void)?
    var isMonitoringFocusEvents: Bool { focusEventMonitor != nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachRequestedViewIfNeeded()
        synchronizeHostedViewGeometry()
        updateFocusMonitoring()
        reportFocusAfterEvent()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        attachRequestedViewIfNeeded()
        synchronizeHostedViewGeometry()
        updateFocusMonitoring()
    }

    override func viewDidHide() {
        super.viewDidHide()
        relinquishInputFocus(in: window)
        stopFocusMonitoring()
    }

    override func layout() {
        super.layout()
        synchronizeHostedViewGeometry()
    }

    func install(
        _ terminalView: NSView?,
        placeholder: String = "终端正在启动…"
    ) {
        requestedTerminalView = terminalView
        requestedPlaceholder = placeholder
        attachRequestedViewIfNeeded()
        synchronizeHostedViewGeometry()
    }

    private func attachRequestedViewIfNeeded() {
        let terminalView = requestedTerminalView
        if let terminalView,
           hostedView === terminalView,
           terminalView.superview === self
        {
            return
        }
        if let terminalView,
           terminalView.superview !== self,
           !isVisibleInWindow,
           let currentHost = terminalView.superview as? TerminalHostView,
           currentHost.isVisibleInWindow
        {
            return
        }
        hostedView?.removeFromSuperview()
        let view = terminalView
            ?? NSTextField(labelWithString: requestedPlaceholder)
        hostedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        reportFocusAfterEvent()
    }

    private func synchronizeHostedViewGeometry() {
        guard let hostedView else { return }
        let expectedFrame = NSRect(origin: .zero, size: bounds.size)
        guard hostedView.frame != expectedFrame else { return }
        hostedView.frame = expectedFrame
    }

    func synchronizeFocusState() {
        if let window,
           let focusedHost = Self.terminalHost(containing: window.firstResponder),
           focusedHost !== self
        {
            retainsInputFocus = false
        }
        reportCurrentFocus()
    }

    func relinquishInputFocus() {
        relinquishInputFocus(in: window)
    }

    private func updateFocusMonitoring() {
        let previousWindow = monitoredWindow
        guard isVisibleInWindow else {
            stopFocusMonitoring()
            relinquishInputFocus(in: previousWindow)
            return
        }
        guard monitoredWindow !== window || focusEventMonitor == nil else {
            return
        }
        stopFocusMonitoring()
        monitoredWindow = window
        guard let window else {
            relinquishInputFocus(in: previousWindow)
            return
        }
        focusEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            guard self.isVisibleInWindow else { return event }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.reconcileFocusAfterMouseEvent()
            } else {
                // Preflight only collisions before SwiftUI/menu equivalents.
                // Ordinary terminal input must keep using keyDown and the IME path.
                let eventToForward = TerminalShortcutArbitrator.eventToForward(
                    event,
                    policy: self.shortcutPolicy,
                    terminalHasInputFocus: self.hasInputFocus(in: window),
                    shortcutMatch: self.breathShortcutMatch ?? { _ in nil },
                    terminalHandler: self.handleTerminalShortcut ?? { _ in }
                )
                guard let eventToForward else { return nil }
                self.reportFocusAfterEvent()
                return eventToForward
            }
            return event
        }
    }

    private func stopFocusMonitoring() {
        if let focusEventMonitor {
            NSEvent.removeMonitor(focusEventMonitor)
            self.focusEventMonitor = nil
        }
        monitoredWindow = nil
    }

    private func reconcileFocusAfterMouseEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.reconcileFocusAfterMouseEventDispatch()
        }
    }

    private func reconcileFocusAfterMouseEventDispatch() {
        guard let window,
              window.isKeyWindow,
              isVisibleInWindow
        else {
            reportFocus(false)
            return
        }
        if hasInputFocus(in: window) {
            reportFocus(true)
            return
        }
        if let focusedHost = Self.terminalHost(containing: window.firstResponder),
           focusedHost !== self
        {
            retainsInputFocus = false
            reportFocus(false)
            return
        }
        guard retainsInputFocus,
              let hostedView,
              window.makeFirstResponder(hostedView)
        else {
            reportFocus(false)
            return
        }
        reportFocus(true)
    }

    private func reportFocusAfterEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.reportCurrentFocus()
        }
    }

    private func reportCurrentFocus() {
        reportFocus(hasInputFocus)
    }

    private var hasInputFocus: Bool {
        guard let window,
              window.isKeyWindow
        else {
            return false
        }
        return hasInputFocus(in: window)
    }

    private func hasInputFocus(in window: NSWindow) -> Bool {
        guard let hostedView,
              let firstResponder = window.firstResponder as? NSView
        else {
            return false
        }
        return firstResponder === hostedView
            || firstResponder.isDescendant(of: hostedView)
    }

    private var isVisibleInWindow: Bool {
        guard window != nil else { return false }
        var view: NSView? = self
        while let currentView = view {
            if currentView.isHidden { return false }
            view = currentView.superview
        }
        return true
    }

    private func relinquishInputFocus(in window: NSWindow?) {
        retainsInputFocus = false
        if let window,
           Self.terminalHost(containing: window.firstResponder) === self
        {
            window.makeFirstResponder(nil)
        }
        reportFocus(false)
    }

    private static func terminalHost(containing responder: NSResponder?) -> TerminalHostView? {
        var view = responder as? NSView
        while let currentView = view {
            if let terminalHost = currentView as? TerminalHostView {
                return terminalHost
            }
            view = currentView.superview
        }
        return nil
    }

    private func reportFocus(_ isFocused: Bool) {
        if isFocused {
            retainsInputFocus = true
        }
        guard lastReportedFocus != isFocused else { return }
        lastReportedFocus = isFocused
        onFocusChange?(isFocused)
    }
}
