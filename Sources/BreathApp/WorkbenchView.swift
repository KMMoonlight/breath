import AppKit
import BreathCore
import BreathTerminal
import SwiftUI

struct WorkbenchView: View {
    @ObservedObject var model: BreathApplicationModel
    @State private var pendingArchive: WorkSession?
    @State private var pendingWorkspaceRemoval: Workspace?
    @State private var pendingPaneClose: TerminalPaneID?
    @State private var dismissedUnavailableWorkspaces: Set<WorkspaceID> = []

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 600)
        .disabled(!model.isReady)
        .overlay {
            if !model.isReady {
                ProgressView("正在恢复上次工作区…")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            model.start()
            offerRemovalForUnavailableWorkspace()
        }
        .onChange(of: model.snapshot) { _, _ in
            offerRemovalForUnavailableWorkspace()
        }
        .alert("归档工作会话？", isPresented: archiveAlertPresented, presenting: pendingArchive) { session in
            Button("取消", role: .cancel) { pendingArchive = nil }
            Button("停止并归档", role: .destructive) {
                model.archive(session.id)
                pendingArchive = nil
            }
        } message: { _ in
            Text("该会话中的所有终端进程都会停止。会话之后可在设置的“已归档”中恢复。")
        }
        .alert("移除工作区？", isPresented: workspaceAlertPresented, presenting: pendingWorkspaceRemoval) { workspace in
            Button("取消", role: .cancel) {
                dismissedUnavailableWorkspaces.insert(workspace.id)
                pendingWorkspaceRemoval = nil
            }
            Button("停止并移除", role: .destructive) {
                model.removeWorkspace(workspace.id)
                pendingWorkspaceRemoval = nil
            }
        } message: { workspace in
            Text("将停止相关终端并删除 Breath 元数据，不会修改 \(workspace.path) 中的任何文件。")
        }
        .alert("关闭终端窗格？", isPresented: paneCloseAlertPresented) {
            Button("取消", role: .cancel) { pendingPaneClose = nil }
            Button("停止并关闭", role: .destructive) {
                if let paneID = pendingPaneClose { model.closePane(paneID) }
                pendingPaneClose = nil
            }
        } message: {
            Text("该终端中的进程会停止。")
        }
        .alert("Breath", isPresented: errorAlertPresented) {
            Button("好") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "未知错误")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("工作区")
                    .font(.headline)
                Spacer()
                Button(action: chooseWorkspace) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .help("添加工作区")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if model.snapshot.workspaces.isEmpty {
                ContentUnavailableView(
                    "还没有工作区",
                    systemImage: "folder",
                    description: Text("添加一个项目目录以打开第一个空终端。")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.snapshot.workspaces) { workspace in
                        workspaceSection(workspace)
                    }
                }
                .listStyle(.sidebar)
                .environment(
                    \.defaultMinListRowHeight,
                    model.settings.application.sidebarDensity == .compact ? 24 : 30
                )
            }
        }
    }

    @ViewBuilder
    private func workspaceSection(_ workspace: Workspace) -> some View {
        DisclosureGroup {
            let sessions = model.snapshot.activeWorkSessions.filter {
                $0.workspaceID == workspace.id
            }
            ForEach(sessions) { session in
                sessionTree(session)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: model.isWorkspaceAvailable(workspace) ? "folder" : "folder.badge.questionmark")
                    .foregroundStyle(
                        model.isWorkspaceAvailable(workspace)
                            ? Color.secondary
                            : Color.orange
                    )
                Text(workspace.displayName)
                    .lineLimit(1)
                Spacer()
                Button {
                    model.createWorkSession(in: workspace.id)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("新建工作会话")
            }
            .contextMenu {
                Button("新建工作会话") {
                    model.createWorkSession(in: workspace.id)
                }
                Divider()
                Button("移除工作区…", role: .destructive) {
                    pendingWorkspaceRemoval = workspace
                }
            }
        }
    }

    @ViewBuilder
    private func sessionTree(_ session: WorkSession) -> some View {
        let panes = session.layout.panes
        if panes.count == 1 {
            sessionRow(session, pane: panes[0])
        } else {
            DisclosureGroup {
                ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                    Button {
                        model.selectWorkSession(session.id)
                    } label: {
                        HStack(spacing: 7) {
                            StateDot(state: pane.state)
                            if let agent = pane.agentBinding?.agent {
                                AgentTypeLabel(agent: agent)
                            }
                            Image(systemName: "rectangle.split.2x1")
                                .foregroundStyle(.secondary)
                            Text(pane.agentBinding?.nativeTitle ?? "终端 \(index + 1)")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            } label: {
                sessionRowContent(session, pane: nil)
            }
        }
    }

    private func sessionRow(_ session: WorkSession, pane: TerminalPane) -> some View {
        sessionRowContent(session, pane: pane)
    }

    private func sessionRowContent(_ session: WorkSession, pane: TerminalPane?) -> some View {
        HStack(spacing: 7) {
            if let pane { StateDot(state: pane.state) }
            if let agent = pane?.agentBinding?.agent {
                AgentTypeLabel(agent: agent)
            }
            Button {
                model.selectWorkSession(session.id)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .foregroundStyle(.secondary)
                    Text(session.title)
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
            .help("归档")
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .background {
            if model.snapshot.selectedWorkSessionID == session.id {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.16))
                    .padding(.horizontal, -5)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedID = model.snapshot.selectedWorkSessionID,
           let session = model.snapshot.activeWorkSessions.first(where: { $0.id == selectedID })
        {
            PaneLayoutView(
                layout: session.layout,
                workSessionID: session.id,
                path: [],
                paneCount: session.layout.paneIDs.count,
                model: model,
                requestClose: { pendingPaneClose = $0 }
            )
            .id(session.id)
        } else {
            ContentUnavailableView(
                "选择一个工作会话",
                systemImage: "terminal",
                description: Text("只会在选中时恢复对应布局和 Agent 会话。")
            )
        }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"
        panel.message = "选择一个项目目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addWorkspace(url)
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

    private var paneCloseAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingPaneClose != nil },
            set: { if !$0 { pendingPaneClose = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }
}

private struct StateDot: View {
    let state: TerminalState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
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
        switch state {
        case .idle: "空闲或已退出"
        case .running: "运行中"
        case .needsAttention: "需要处理"
        case .turnCompleted: "回合完成"
        }
    }
}

private struct PaneLayoutView: View {
    let layout: PaneLayout
    let workSessionID: WorkSessionID
    let path: [SplitBranch]
    let paneCount: Int
    @ObservedObject var model: BreathApplicationModel
    let requestClose: (TerminalPaneID) -> Void

    @ViewBuilder
    var body: some View {
        switch layout {
        case .pane(let pane):
            TerminalPaneView(
                pane: pane,
                canClose: paneCount > 1,
                model: model,
                requestClose: requestClose
            )
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
                    paneCount: paneCount,
                    model: model,
                    requestClose: requestClose
                )
            } second: {
                PaneLayoutView(
                    layout: second,
                    workSessionID: workSessionID,
                    path: path + [.second],
                    paneCount: paneCount,
                    model: model,
                    requestClose: requestClose
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
    @State private var liveFraction: Double
    @State private var dragOriginFraction: Double?

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
        _liveFraction = State(initialValue: fraction)
    }

    var body: some View {
        GeometryReader { proxy in
            if orientation == .horizontal {
                HStack(spacing: 0) {
                    first.frame(width: max(1, proxy.size.width * liveFraction - 2))
                    divider(total: proxy.size.width, cursor: .resizeLeftRight)
                    second
                }
            } else {
                VStack(spacing: 0) {
                    first.frame(height: max(1, proxy.size.height * liveFraction - 2))
                    divider(total: proxy.size.height, cursor: .resizeUpDown)
                    second
                }
            }
        }
        .onChange(of: fraction) { _, newValue in
            liveFraction = newValue
        }
    }

    private func divider(total: CGFloat, cursor: NSCursor) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(
                width: orientation == .horizontal ? 4 : nil,
                height: orientation == .vertical ? 4 : nil
            )
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering { cursor.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let origin = dragOriginFraction ?? liveFraction
                        dragOriginFraction = origin
                        let translation = orientation == .horizontal
                            ? value.translation.width
                            : value.translation.height
                        liveFraction = min(
                            max(origin + Double(translation / max(total, 1)), 0.1),
                            0.9
                        )
                    }
                    .onEnded { _ in
                        dragOriginFraction = nil
                        onResize(liveFraction)
                    }
            )
    }
}

private struct TerminalPaneView: View {
    let pane: TerminalPane
    let canClose: Bool
    @ObservedObject var model: BreathApplicationModel
    let requestClose: (TerminalPaneID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StateDot(state: pane.state)
                if let agent = pane.agentBinding?.agent {
                    AgentTypeLabel(agent: agent)
                }
                Text(pane.agentBinding?.nativeTitle ?? "终端")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button {
                    model.split(pane.id, orientation: .horizontal)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("横向分屏")
                Button {
                    model.split(pane.id, orientation: .vertical)
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                }
                .help("纵向分屏")
                if canClose {
                    Button(role: .destructive) {
                        requestClose(pane.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("关闭窗格")
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.bar)

            TerminalNativeView(engine: model.terminalEngine, paneID: pane.id)
        }
        .background(Color(nsColor: .black))
    }
}

private struct AgentTypeLabel: View {
    let agent: AgentKind

    var body: some View {
        Text(agent.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .fixedSize()
    }
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
}

private struct TerminalNativeView: NSViewRepresentable {
    let engine: GhosttyTerminalEngine
    let paneID: TerminalPaneID

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.install(engine.view(for: paneID))
        return host
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        nsView.install(engine.view(for: paneID))
    }
}

@MainActor
private final class TerminalHostView: NSView {
    private weak var hostedView: NSView?

    func install(_ terminalView: NSView?) {
        if let terminalView, hostedView === terminalView { return }
        hostedView?.removeFromSuperview()
        let view = terminalView ?? NSTextField(labelWithString: "终端正在启动…")
        hostedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
