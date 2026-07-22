import AppKit
import BreathCore
import BreathTerminal
import SwiftUI

enum WorkbenchAccessibility {
    static let addWorkspace = "添加工作区"
    static let noSelectedWorkSession = "没有选中的工作会话"
    static let openWorkspace = "打开工作区"
    static let openSettings = "打开设置"
    static let openGitWorkbench = "打开 Git 工作台"
    static let openTaskView = "打开任务视图"
    static let openSkills = "打开 Skills"
    static let taskViewPanel = "任务视图面板"
}

private enum WorkbenchDetailMode: Equatable {
    case workspace
    case tasks
    case skills
    case settings
    case gitWorkbench(WorkspaceID?)
}

struct WorkbenchView: View {
    @ObservedObject var model: BreathApplicationModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var pendingArchive: WorkSession?
    @State private var pendingWorkspaceRemoval: Workspace?
    @State private var dismissedUnavailableWorkspaces: Set<WorkspaceID> = []
    @State private var expandedWorkspaceIDs: Set<WorkspaceID> = []
    @State private var expandedSessionIDs: Set<WorkSessionID> = []
    @State private var hoveredSessionID: WorkSessionID?
    @State private var pendingTerminalFocusID: TerminalPaneID?
    @State private var detailMode = WorkbenchDetailMode.workspace
    @StateObject private var gitCoordinator = GitWorkbenchCoordinator()

    var body: some View {
        HStack(spacing: 0) {
            activityBar
            workbenchContent
        }
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
        .onChange(of: model.snapshot) { previousSnapshot, snapshot in
            updateWorkspaceExpansion(from: previousSnapshot, to: snapshot)
            offerRemovalForUnavailableWorkspace()
            focusPendingTerminalAfterViewUpdate()
            if previousSnapshot.selectedWorkSessionID != snapshot.selectedWorkSessionID {
                if case .gitWorkbench = detailMode {
                    detailMode = .gitWorkbench(model.currentWorkspaceID)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .breathOpenGitWorkbench)) { _ in
            guard GitWorkbenchReleaseGate.isEnabled else { return }
            detailMode = .gitWorkbench(model.currentWorkspaceID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .breathOpenSettings)) { _ in
            detailMode = .settings
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .breathSelectWorkSessionTab)
        ) { notification in
            guard let tab = notification.object as? WorkSessionTabShortcut else { return }
            selectWorkSessionTab(at: tab.selectionIndex)
        }
        .onReceive(NotificationCenter.default.publisher(for: .breathSelectPreviousPane)) { _ in
            focusAdjacentPane(previous: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .breathSelectNextPane)) { _ in
            focusAdjacentPane(previous: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .breathGitCommit)) { _ in
            guard GitWorkbenchReleaseGate.isEnabled else { return }
            guard let workspaceID = model.currentWorkspaceID,
                  let workspace = model.snapshot.workspaces.first(where: {
                      $0.id == workspaceID
                  })
            else {
                return
            }
            detailMode = .gitWorkbench(workspaceID)
            gitCoordinator.model(for: workspace).shouldFocusCommitMessage = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .breathGitPush)) { _ in
            guard GitWorkbenchReleaseGate.isEnabled else { return }
            guard let workspaceID = model.currentWorkspaceID,
                  let workspace = model.snapshot.workspaces.first(where: {
                      $0.id == workspaceID
                  })
            else {
                return
            }
            detailMode = .gitWorkbench(workspaceID)
            gitCoordinator.model(for: workspace).shouldPresentPushReview = true
        }
        .alert(
            localizer.string("归档工作会话？"),
            isPresented: archiveAlertPresented,
            presenting: pendingArchive
        ) { session in
            Button(localizer.string("取消"), role: .cancel) { pendingArchive = nil }
            Button(localizer.string("停止并归档"), role: .destructive) {
                model.archive(
                    session.id,
                    selecting: model.snapshot.archiveFallbackWorkSessionID(
                        for: session.id
                    )
                )
                pendingArchive = nil
            }
        } message: { _ in
            Text(localizer.string("该会话中的所有终端进程都会停止。会话之后可在设置的“已归档”中恢复。"))
        }
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
            Text(localizer.format("移除工作区说明 %@", workspace.path))
        }
        .alert("Breath", isPresented: errorAlertPresented) {
            Button(localizer.string("好")) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? localizer.string("未知错误"))
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: model.settings.application.language)
    }

    private var resolvedAppearance: ResolvedApplicationAppearance {
        colorScheme == .dark ? .dark : .light
    }

    @ViewBuilder
    private var workbenchContent: some View {
        if detailMode == .workspace {
            SidebarResizeContainer {
                sidebar
                    .font(applicationFont(for: model))
            } detail: {
                sessionDetail
                    .font(applicationFont(for: model))
            }
        } else {
            detail
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
                isSelected: detailMode == .workspace
            ) {
                detailMode = .workspace
            }

            activityBarButton(
                systemName: "checklist",
                accessibilityLabel: WorkbenchAccessibility.openTaskView,
                isSelected: detailMode == .tasks
            ) {
                detailMode = .tasks
            }

            if GitWorkbenchReleaseGate.isEnabled {
                activityBarButton(
                    accessibilityLabel: WorkbenchAccessibility.openGitWorkbench,
                    isSelected: isGitWorkbenchSelected,
                    action: openGitWorkbenchForCurrentWorkspace
                ) {
                    GitBranchIcon()
                }
            }

            activityBarButton(
                accessibilityLabel: WorkbenchAccessibility.openSkills,
                isSelected: detailMode == .skills,
                action: { detailMode = .skills }
            ) {
                SkillActivityIcon()
            }

            activityBarButton(
                systemName: "gearshape",
                accessibilityLabel: WorkbenchAccessibility.openSettings,
                isSelected: detailMode == .settings
            ) {
                detailMode = .settings
            }

            Spacer(minLength: 0)
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
            .padding(.leading, WorkbenchLayout.pageToolbarLeadingInset)
            .padding(.trailing, WorkbenchLayout.pageToolbarTrailingInset)
            .frame(height: WorkbenchLayout.pageToolbarHeight)

            Divider()

            if model.snapshot.workspaces.isEmpty {
                Text(localizer.string("添加工作区"))
                    .font(applicationFont(for: model, offset: -1))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        detailMode = .workspace
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
        detailMode = .workspace
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
                pendingArchive = session
            } label: {
                Image(systemName: "archivebox")
            }
            .buttonStyle(.plain)
            .help(localizer.string("归档"))
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
            }
        }
    }

    private func createWorkSession(in workspaceID: WorkspaceID) {
        expandedWorkspaceIDs.insert(workspaceID)
        model.createWorkSession(in: workspaceID)
    }

    private var isGitWorkbenchSelected: Bool {
        if case .gitWorkbench = detailMode {
            return true
        }
        return false
    }

    private func openGitWorkbenchForCurrentWorkspace() {
        detailMode = .gitWorkbench(model.currentWorkspaceID)
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

    @ViewBuilder
    private var detail: some View {
        if detailMode == .settings {
            BreathSettingsView(model: model)
        } else if detailMode == .skills {
            SkillsView(service: model.skillsService)
        } else if detailMode == .tasks {
            Color(nsColor: .windowBackgroundColor)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localizer.string(WorkbenchAccessibility.taskViewPanel))
        } else if GitWorkbenchReleaseGate.isEnabled,
                  case .gitWorkbench(let workspaceID) = detailMode
        {
            if let workspaceID,
               let workspace = model.snapshot.workspaces.first(where: {
                   $0.id == workspaceID
               })
            {
                GitWorkbenchView(
                    workspace: workspace,
                    model: gitCoordinator.model(for: workspace),
                    onAddWorkspace: { model.addWorkspace($0) }
                )
            } else {
                GitWorkbenchUnselectedView(
                    workspaces: model.snapshot.workspaces,
                    onSelectWorkspace: { workspaceID in
                        detailMode = .gitWorkbench(workspaceID)
                    }
                )
            }
        } else {
            sessionDetail
        }
    }

    @ViewBuilder
    private var sessionDetail: some View {
        if let selectedID = model.snapshot.selectedWorkSessionID,
           let session = model.snapshot.activeWorkSessions.first(where: {
               $0.id == selectedID
           })
        {
            let workspace = model.snapshot.workspaces.first(where: {
                $0.id == session.workspaceID
            })
            let sessions = model.snapshot.activeWorkSessions.filter {
                $0.workspaceID == session.workspaceID
            }
            VStack(spacing: 0) {
                WorkSessionTabBar(
                    sessions: sessions,
                    selectedSessionID: selectedID,
                    model: model,
                    onSelect: selectWorkSession,
                    onCreate: { createWorkSession(in: session.workspaceID) },
                    onArchive: { pendingArchive = $0 }
                )
                WorkSessionTerminalLayoutView(
                    session: session,
                    workspacePath: workspace?.path ?? "",
                    model: model
                )
                .id(session.id)
            }
        } else {
            model.effectiveTerminalColorTheme.canvasColor
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
              let workspace = model.snapshot.workspaces.first(where: {
                  !model.isWorkspaceAvailable($0)
                      && !dismissedUnavailableWorkspaces.contains($0.id)
              })
        else {
            return
        }
        pendingWorkspaceRemoval = workspace
    }

    private var archiveAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingArchive != nil },
            set: { if !$0 { pendingArchive = nil } }
        )
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
}

extension Notification.Name {
    static let breathOpenSettings = Notification.Name("Breath.OpenSettings")
    static let breathOpenGitWorkbench = Notification.Name("Breath.OpenGitWorkbench")
    static let breathSelectWorkSessionTab = Notification.Name(
        "Breath.SelectWorkSessionTab"
    )
    static let breathSelectPreviousPane = Notification.Name("Breath.SelectPreviousPane")
    static let breathSelectNextPane = Notification.Name("Breath.SelectNextPane")
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
    @ObservedObject var model: BreathApplicationModel
    let onSelect: (WorkSessionID) -> Void
    let onCreate: () -> Void
    let onArchive: (WorkSession) -> Void
    @Environment(\.applicationLanguage) private var applicationLanguage
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
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.08))
                            }
                    }
                }
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
            .accessibilityLabel(localizer.string("归档"))
            .help(localizer.string("归档"))
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
                .fill(.bar)
            } else if hoveredSessionID == session.id {
                Color.primary.opacity(0.06)
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
            Button(localizer.string("归档"), role: .destructive) {
                onArchive(session)
            }
        }
    }

    @ViewBuilder
    private func sessionMarker(_ session: WorkSession) -> some View {
        if session.layout.panes.count == 1 {
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
    let workspacePath: String
    @ObservedObject var model: BreathApplicationModel

    var body: some View {
        VStack(spacing: 0) {
            PaneLayoutView(
                layout: session.layout,
                workSessionID: session.id,
                path: [],
                paneOrder: session.layout.paneIDs,
                model: model
            )
            WorkSessionBottomBar(workspacePath: workspacePath)
        }
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
            onResize: onResize,
            appliesPosition: updatesPosition
        )
    }
}

@MainActor
final class NativeSplitNSView:
    NSSplitView,
    NSSplitViewDelegate,
    SplitDividerTrackingState
{
    private let firstHostingView = NativeSplitHostingView(rootView: AnyView(EmptyView()))
    private let secondHostingView = NativeSplitHostingView(rootView: AnyView(EmptyView()))
    private var minimumPosition = NativeSplitPosition.fraction(0)
    private var maximumPosition = NativeSplitPosition.fraction(1)
    private var minimumSecondLength: CGFloat = 0
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
        delegate = self
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
        self.onResize = onResize
        if appliesPosition {
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
                    .breathKeyboardShortcut(
                        BreathShortcutCatalog.closePane,
                        priority: model.shortcutPriority,
                        targeting: pane.id
                    )
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
                onFocusChange: { isFocused in
                    hasInputFocus = isFocused
                    model.updateTerminalInputFocus(
                        paneID: pane.id,
                        workSessionID: workSessionID,
                        isFocused: isFocused
                    )
                },
                isBreathShortcut: { event in
                    BreathShortcutCatalog.matchesTerminalFirstShortcut(event)
                        || GitShortcutResolver.commandID(
                            matching: event,
                            preferences: GitPreferencesStore.shared.preferences,
                            requiredScope: .global
                        ) != nil
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

private struct WorkSessionBottomBar: View {
    let workspacePath: String

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            WorkspaceEditorLauncher(
                workspacePath: workspacePath,
                barHeight: WorkbenchLayout.bottomBarHeight
            )
        }
        .padding(.horizontal, 9)
        .frame(height: WorkbenchLayout.bottomBarHeight)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
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

private struct AgentBrandIcon: View {
    private static let iconCount: CGFloat = 9
    private static let sprite = Bundle.module
        .url(forResource: "AgentBrandIcons", withExtension: "svg")
        .flatMap(NSImage.init(contentsOf:))

    let agent: AgentKind

    var body: some View {
        Group {
            if let sprite = Self.sprite {
                GeometryReader { _ in
                    Image(nsImage: sprite)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(
                            width: WorkbenchLayout.agentIconGlyphSize * Self.iconCount,
                            height: WorkbenchLayout.agentIconGlyphSize
                        )
                        .offset(
                            x: -CGFloat(agent.brandIconIndex)
                                * WorkbenchLayout.agentIconGlyphSize
                        )
                }
                .frame(
                    width: WorkbenchLayout.agentIconGlyphSize,
                    height: WorkbenchLayout.agentIconGlyphSize
                )
                .clipped()
            } else {
                Image(systemName: "terminal")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .foregroundStyle(.secondary)
        .frame(
            width: WorkbenchLayout.agentIconFrameSize,
            height: WorkbenchLayout.agentIconFrameSize
        )
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
    static let sessionTabCornerRadius: CGFloat = 6
    static let bottomBarHeight: CGFloat = 32
    static let agentIconFrameSize: CGFloat = 16
    static let agentIconGlyphSize: CGFloat = 14
    static let splitDividerThickness: CGFloat = 1
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
        case .geminiCLI: "Gemini"
        case .githubCopilotCLI: "Copilot"
        case .qwenCode: "Qwen"
        case .cursorAgent: "Cursor"
        case .factoryDroid: "Droid"
        case .openCode: "OpenCode"
        case .pi: "Pi"
        }
    }

    var brandIconIndex: Int {
        switch self {
        case .codex: 0
        case .claudeCode: 1
        case .geminiCLI: 2
        case .githubCopilotCLI: 3
        case .qwenCode: 4
        case .cursorAgent: 5
        case .factoryDroid: 6
        case .openCode: 7
        case .pi: 8
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
    let engine: any TerminalViewProviding
    let paneID: TerminalPaneID
    let placeholder: String
    let onFocusChange: (Bool) -> Void
    let isBreathShortcut: (NSEvent) -> Bool

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.onFocusChange = onFocusChange
        host.isBreathShortcut = isBreathShortcut
        host.handleTerminalShortcut = { event in
            engine.handleShortcutKeyDown(event, for: paneID)
        }
        host.install(engine.view(for: paneID), placeholder: placeholder)
        return host
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        nsView.onFocusChange = onFocusChange
        nsView.isBreathShortcut = isBreathShortcut
        nsView.handleTerminalShortcut = { event in
            engine.handleShortcutKeyDown(event, for: paneID)
        }
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
}

@MainActor
final class TerminalHostView: NSView {
    private weak var hostedView: NSView?
    private weak var monitoredWindow: NSWindow?
    private var focusEventMonitor: Any?
    private var lastReportedFocus: Bool?
    private var retainsInputFocus = false
    var onFocusChange: ((Bool) -> Void)?
    var isBreathShortcut: ((NSEvent) -> Bool)?
    var handleTerminalShortcut: ((NSEvent) -> Bool)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFocusMonitoring()
        reportFocusAfterEvent()
    }

    override func viewDidHide() {
        super.viewDidHide()
        relinquishInputFocus(in: window)
    }

    func install(
        _ terminalView: NSView?,
        placeholder: String = "终端正在启动…"
    ) {
        if let terminalView, hostedView === terminalView { return }
        hostedView?.removeFromSuperview()
        let view = terminalView ?? NSTextField(labelWithString: placeholder)
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

    func synchronizeFocusState() {
        if let window,
           let focusedHost = Self.terminalHost(containing: window.firstResponder),
           focusedHost !== self
        {
            retainsInputFocus = false
        }
        reportCurrentFocus()
    }

    private func updateFocusMonitoring() {
        guard monitoredWindow !== window else { return }
        let previousWindow = monitoredWindow
        if let focusEventMonitor {
            NSEvent.removeMonitor(focusEventMonitor)
            self.focusEventMonitor = nil
        }
        monitoredWindow = window
        guard let window else {
            relinquishInputFocus(in: previousWindow)
            return
        }
        focusEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.reconcileFocusAfterMouseEvent()
            } else {
                // Preflight only collisions before SwiftUI/menu equivalents.
                // Ordinary terminal input must keep using keyDown and the IME path.
                let eventToForward = TerminalShortcutArbitrator.eventToForward(
                    event,
                    terminalHasInputFocus: self.hasInputFocus(in: window),
                    matchesBreathShortcut: self.isBreathShortcut ?? { _ in false },
                    terminalHandler: self.handleTerminalShortcut ?? { _ in false }
                )
                guard let eventToForward else { return nil }
                self.reportFocusAfterEvent()
                return eventToForward
            }
            return event
        }
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
