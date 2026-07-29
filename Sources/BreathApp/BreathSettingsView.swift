import AppKit
import BreathAgents
import BreathCore
import BreathNotes
import CoreText
import SwiftUI

enum BreathSettingsTab: Hashable, CaseIterable {
    case application
    case network
    case terminal
    case notes
    case git
    case worktrees
    case agentIntegrations
    case shortcuts
    case archives
}

private extension BreathSettingsTab {
    var title: String {
        switch self {
        case .application: "应用配置"
        case .network: "网络"
        case .terminal: "终端配置"
        case .notes: "笔记"
        case .git: "Git"
        case .worktrees: "Worktree"
        case .agentIntegrations: "Agent 集成"
        case .shortcuts: "快捷键"
        case .archives: "已归档"
        }
    }

    var systemImage: String {
        switch self {
        case .application: "paintbrush"
        case .network: "network"
        case .terminal: "terminal"
        case .notes: "note.text"
        case .git: "point.topleft.down.to.point.bottomright.curvepath"
        case .worktrees: "arrow.triangle.branch"
        case .agentIntegrations: "point.3.connected.trianglepath.dotted"
        case .shortcuts: "keyboard"
        case .archives: "archivebox"
        }
    }
}

private enum SettingsLayout {
    static let tabVisualHeight: CGFloat = 24
    static let contentInset: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 3
    static let controlColumnWidth: CGFloat = 160
    static let controlHeight: CGFloat = 24
    static let gitExecutableControlWidth: CGFloat = 320
    static let networkControlWidth: CGFloat = 360
}

private struct ShortcutReference: Identifiable {
    let action: String
    let keys: String

    var id: String { action }
}

private struct WorktreeInventoryStatePresentation {
    let title: String
    let systemImage: String
    let needsAttention: Bool
}

private enum WorktreeInventoryDeletionKind: Equatable {
    case branch
    case directory
}

private struct PendingWorktreeInventoryDeletion: Identifiable {
    let kind: WorktreeInventoryDeletionKind
    let item: ManagedWorktreeInventoryItem

    var id: String {
        "\(kind)-\(item.id)"
    }
}

struct BreathSettingsView: View {
    private static let availableFontFamilies: [String] = {
        let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return families.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }()

    private static let supportedShortcuts = [
        ShortcutReference(action: "新建工作会话", keys: "⌘T"),
        ShortcutReference(action: "切换会话 Tab", keys: "⌘1…⌘9"),
        ShortcutReference(action: "上一个分屏", keys: "⌘["),
        ShortcutReference(action: "下一个分屏", keys: "⌘]"),
        ShortcutReference(action: "横向分屏", keys: "⌘D"),
        ShortcutReference(action: "纵向分屏", keys: "⌘⇧D"),
        ShortcutReference(action: "关闭当前分屏或工作会话", keys: "⌘W"),
    ]

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: BreathApplicationModel
    @StateObject private var gitPreferencesStore = GitPreferencesStore.shared
    @State private var selectedTab: BreathSettingsTab
    @State private var archiveToDelete: WorkSession?
    @State private var pendingWorktreeInventoryDeletion:
        PendingWorktreeInventoryDeletion?
    @State private var gitExecutableTestResult: String?
    @State private var proxyTestAddress = "https://www.google.com"
    @State private var proxyTestResult: NetworkProxyTestResult?
    @State private var isTestingProxy = false
    @State private var proxyTestTask: Task<Void, Never>?
    @State private var proxyTestRequestID = UUID()

    init(
        model: BreathApplicationModel,
        selectedTab: BreathSettingsTab = .application
    ) {
        self.model = model
        _selectedTab = State(initialValue: selectedTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar
            Divider()
            selectedSettingsContent
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity
        )
        .onDisappear {
            proxyTestTask?.cancel()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .font(applicationFont())
        .disabled(!model.isReady)
        .onAppear {
            model.synchronizeTerminalAppearance(resolvedAppearance)
        }
        .onChange(of: colorScheme) { _, _ in
            model.synchronizeTerminalAppearance(resolvedAppearance)
        }
        .alert(
            localizer.string("永久删除归档？"),
            isPresented: deleteAlertPresented,
            presenting: archiveToDelete
        ) { session in
            Button(localizer.string("取消"), role: .cancel) { archiveToDelete = nil }
            Button(localizer.string("永久删除"), role: .destructive) {
                model.deleteArchive(session.id)
                archiveToDelete = nil
            }
        } message: { session in
            if let managedWorktree = session.managedWorktree {
                Text(
                    localizer.format(
                        "将删除托管 Worktree 目录，但保留绑定分支 %@。存在未提交修改或未受分支保护的提交时会拒绝删除。",
                        managedWorktree.branchName
                    )
                )
            } else {
                Text(localizer.string("只会删除 Breath 元数据，不会删除项目文件或 Agent CLI 自己保存的会话。"))
            }
        }
        .alert(
            worktreeInventoryDeletionTitle,
            isPresented: worktreeInventoryDeletionPresented,
            presenting: pendingWorktreeInventoryDeletion
        ) { deletion in
            Button(localizer.string("取消"), role: .cancel) {
                pendingWorktreeInventoryDeletion = nil
            }
            Button(
                localizer.string(
                    deletion.kind == .branch
                        ? "删除分支"
                        : "删除文件目录"
                ),
                role: .destructive
            ) {
                switch deletion.kind {
                case .branch:
                    model.deleteManagedWorktreeInventoryBranch(
                        deletion.item
                    )
                case .directory:
                    model.deleteManagedWorktreeInventoryDirectory(
                        deletion.item
                    )
                }
                pendingWorktreeInventoryDeletion = nil
            }
        } message: { deletion in
            switch deletion.kind {
            case .branch:
                Text(
                    localizer.format(
                        "将永久删除残留分支 %@。如果提交没有其他引用，之后可能无法恢复。",
                        deletion.item.branchName ?? ""
                    )
                )
            case .directory:
                if deletion.item.state == .directoryOnly {
                    Text(
                        localizer.format(
                            "将文件目录 %@ 移入 macOS 废纸篓，可从废纸篓恢复。",
                            deletion.item.directoryPath ?? ""
                        )
                    )
                } else {
                    Text(
                        localizer.format(
                            "将删除未关联会话的 Git Worktree 目录 %@，但保留其分支。目录存在未提交修改或已锁定时会拒绝删除。",
                            deletion.item.directoryPath ?? ""
                        )
                    )
                }
            }
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 12) {
            Text(localizer.string("设置"))
                .font(.headline)
                .fixedSize()

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(BreathSettingsTab.allCases, id: \.self) { tab in
                            settingsTabButton(tab)
                                .id(tab)
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedTab, anchor: .center)
                }
                .onChange(of: selectedTab) { _, tab in
                    proxy.scrollTo(tab, anchor: .center)
                }
            }
        }
        .pageToolbarLeadingPadding()
        .padding(.trailing, WorkbenchLayout.pageToolbarTrailingInset)
        .frame(height: WorkbenchLayout.pageToolbarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsTabButton(_ tab: BreathSettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Label(
                localizer.string(tab.title),
                systemImage: tab.systemImage
            )
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: SettingsLayout.tabVisualHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(applicationFont(offset: -1, weight: .medium))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedTab {
        case .application:
            applicationSettings
        case .network:
            networkSettings
        case .terminal:
            terminalSettings
        case .notes:
            notesSettings
        case .git:
            gitSettings
        case .worktrees:
            worktreesSettings
        case .agentIntegrations:
            agentIntegrationsSettings
        case .shortcuts:
            shortcutsSettings
        case .archives:
            archivesSettings
        }
    }

    private var applicationSettings: some View {
        settingsList {
            settingsControlRow("外观") {
                settingsMenuPicker(
                    selection: applicationAppearance,
                    options: [
                        (localizer.string("跟随系统"), ApplicationAppearance.system),
                        (localizer.string("浅色"), ApplicationAppearance.light),
                        (localizer.string("深色"), ApplicationAppearance.dark),
                    ],
                    accessibilityLabel: localizer.string("外观")
                )
                .foregroundStyle(settingsControlForegroundColor)
                .id(colorScheme)
            }
            settingsControlRow("语言") {
                settingsMenuPicker(
                    selection: applicationLanguage,
                    options: [
                        (localizer.string("系统"), ApplicationLanguage.system),
                        (localizer.string("中文"), ApplicationLanguage.chinese),
                        (localizer.string("英文"), ApplicationLanguage.english),
                    ],
                    accessibilityLabel: localizer.string("语言")
                )
                .foregroundStyle(settingsControlForegroundColor)
                .id(model.settings.application.language)
            }
            settingsControlRow("字体大小") {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("\(Int(applicationFontSize.wrappedValue)) px")
                        .monospacedDigit()
                    Stepper(
                        "",
                        value: applicationFontSize,
                        in: ApplicationSettings.fontSizeRange,
                        step: 1
                    )
                    .labelsHidden()
                }
                .frame(width: SettingsLayout.controlColumnWidth)
                .accessibilityLabel(localizer.string("应用字体大小"))
            }
        }
    }

    private var terminalSettings: some View {
        settingsList {
            settingsControlRow("字体") {
                settingsMenuPicker(
                    selection: terminalFontFamily,
                    options: Self.availableFontFamilies.map { ($0, $0) },
                    accessibilityLabel: localizer.string("字体")
                )
            }
            settingsControlRow("字号") {
                TextField(
                    "",
                    value: terminalFontSize,
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: SettingsLayout.controlColumnWidth)
                .accessibilityLabel(localizer.string("字号"))
            }
            VStack(spacing: 8) {
                settingsControlRow("颜色主题") {
                    TerminalThemePicker(
                        selection: terminalColorTheme,
                        options: TerminalColorTheme.compatible(with: resolvedAppearance).map {
                            (localizer.string($0.displayName), $0)
                        },
                        accessibilityLabel: localizer.string("颜色主题")
                    )
                }
                TerminalThemeCodePreview(
                    theme: terminalColorTheme.wrappedValue,
                    accessibilityLabel: localizer.string("主题预览")
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            settingsControlRow("光标") {
                settingsMenuPicker(
                    selection: terminalCursorStyle,
                    options: [
                        (localizer.string("方块"), TerminalCursorStyle.block),
                        (localizer.string("竖线"), TerminalCursorStyle.bar),
                        (localizer.string("下划线"), TerminalCursorStyle.underline),
                    ],
                    accessibilityLabel: localizer.string("光标")
                )
            }
        }
    }

    private var notesSettings: some View {
        NotesSettingsPane(applicationModel: model)
    }

    private var networkSettings: some View {
        settingsList {
            Section {
                settingsControlRow("代理方式") {
                    settingsMenuPicker(
                        selection: networkProxyMode,
                        options: [
                            (
                                localizer.string("不使用代理"),
                                NetworkProxyMode.none
                            ),
                            (
                                localizer.string("使用系统代理"),
                                NetworkProxyMode.system
                            ),
                            (
                                localizer.string("使用手动代理"),
                                NetworkProxyMode.manual
                            ),
                        ],
                        accessibilityLabel: localizer.string("代理方式")
                    )
                }

                if model.settings.networkProxy.mode == .manual {
                    settingsControlRow(
                        "代理 URL",
                        explanation: localizer.string(
                            "支持 HTTP、HTTPS 和 SOCKS5 代理，例如 http://127.0.0.1:7890。"
                        ),
                        controlWidth: SettingsLayout.networkControlWidth
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(
                                "http://127.0.0.1:7890",
                                text: manualProxyURL
                            )
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(localizer.string("代理 URL"))
                            if let error = model.networkProxyConfigurationError {
                                Label(
                                    proxyConfigurationErrorMessage(error),
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(applicationFont(offset: -1))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    settingsControlRow(
                        "用户名（可选）",
                        controlWidth: SettingsLayout.networkControlWidth
                    ) {
                        TextField("", text: manualProxyUsername)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(localizer.string("代理用户名"))
                    }
                    settingsControlRow(
                        "密码（可选）",
                        explanation: localizer.string(
                            "代理密码保存在 macOS Keychain 中，不会写入 Breath 设置数据库。"
                        ),
                        controlWidth: SettingsLayout.networkControlWidth
                    ) {
                        SecureField("", text: manualProxyPassword)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(localizer.string("代理密码"))
                    }
                }
            } header: {
                ExplanationLabel(
                    localizer.string(
                        "适用于 Breath 内置网络请求和 Breath 发起的 Git HTTP(S) 操作；不会修改终端命令、应用更新或 macOS 系统代理设置。"
                    )
                ) {
                    Text(localizer.string("网络代理"))
                }
            }

            Section(localizer.string("代理测试")) {
                settingsControlRow(
                    "测试地址",
                    controlWidth: SettingsLayout.networkControlWidth
                ) {
                    HStack(spacing: 8) {
                        TextField(
                            "https://www.google.com",
                            text: $proxyTestAddress
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(localizer.string("代理测试地址"))
                        .onChange(of: proxyTestAddress) { _, _ in
                            resetProxyTest()
                        }
                        Button(localizer.string("测试连接")) {
                            testNetworkProxy()
                        }
                        .disabled(
                            isTestingProxy
                                || model.networkProxyConfigurationError != nil
                        )
                    }
                }

                if isTestingProxy {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text(localizer.string("正在测试连接…"))
                    }
                    .font(applicationFont(offset: -1))
                    .foregroundStyle(.secondary)
                } else if let proxyTestResult {
                    proxyTestResultView(proxyTestResult)
                }
            }
        }
    }

    private func settingsList<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        List {
            content()
        }
        .padding(SettingsLayout.contentInset)
    }

    private func settingsMenuPicker<Value: Hashable>(
        selection: Binding<Value>,
        options: [(title: String, value: Value)],
        accessibilityLabel: String
    ) -> some View {
        let selectedTitle = options.first(where: { $0.value == selection.wrappedValue })?
            .title ?? ""

        return Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection.wrappedValue = option.value
                } label: {
                    HStack {
                        Text(option.title)
                        if option.value == selection.wrappedValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(
                width: SettingsLayout.controlColumnWidth,
                height: SettingsLayout.controlHeight
            )
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(accessibilityLabel)
    }

    private func settingsControlRow<Control: View>(
        _ title: String,
        explanation: String? = nil,
        controlWidth: CGFloat = SettingsLayout.controlColumnWidth,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            if let explanation {
                ExplanationLabel(explanation) {
                    Text(localizer.string(title))
                        .lineLimit(1)
                }
            } else {
                Text(localizer.string(title))
                    .lineLimit(1)
            }
            Spacer(minLength: 24)
            control()
                .frame(width: controlWidth, alignment: .trailing)
        }
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }

    private var agentIntegrationsSettings: some View {
        settingsList {
            ForEach(model.adapters, id: \.kind) { adapter in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(adapter.displayName)
                        Text(integrationDescription(adapter))
                            .font(applicationFont(offset: -1))
                            .foregroundStyle(.secondary)
                        Text(adapter.userConfigurationPath)
                            .font(applicationFont(offset: -2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        agentInstallationStatus(adapter)
                        Toggle("", isOn: integrationBinding(adapter))
                            .labelsHidden()
                            .disabled(!model.canToggleAgentIntegration(adapter))
                    }
                }
                .padding(.vertical, SettingsLayout.rowVerticalPadding)
            }
        }
        .onAppear {
            model.refreshAgentCLIStatuses()
        }
    }

    private var shortcutsSettings: some View {
        settingsList {
            Section(localizer.string("终端中的快捷键")) {
                settingsControlRow(
                    "快捷键优先级",
                    explanation: localizer.string(
                        "选择终端聚焦时，由 Breath 还是终端内应用优先获得冲突快捷键。"
                    )
                ) {
                    settingsMenuPicker(
                        selection: terminalShortcutPolicy,
                        options: [
                            (
                                localizer.string("Breath 优先"),
                                TerminalShortcutPolicy.breathFirst
                            ),
                            (
                                localizer.string("终端优先"),
                                TerminalShortcutPolicy.terminalFirst
                            ),
                        ],
                        accessibilityLabel: localizer.string("快捷键优先级")
                    )
                }
            }
            Section(localizer.string("Breath")) {
                ForEach(Self.supportedShortcuts) { shortcut in
                    HStack {
                        Text(localizer.string(shortcut.action))
                        Spacer()
                        Text(shortcut.keys)
                            .font(applicationFont(design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 96, alignment: .trailing)
                    }
                    .padding(.vertical, SettingsLayout.rowVerticalPadding)
                }
            }
            Section(localizer.string("Git 工作台")) {
                ForEach(gitPreferencesStore.preferences.shortcuts) { shortcut in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizer.string(gitShortcutTitle(shortcut.commandID)))
                            Text(localizer.string(gitShortcutScopeTitle(shortcut.scope)))
                                .font(applicationFont(offset: -2))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField(
                            localizer.string("快捷键"),
                            text: gitShortcutBinding(shortcut.commandID)
                        )
                        .font(applicationFont(design: .monospaced))
                        .frame(width: 110)
                        if conflictingGitShortcutIDs.contains(shortcut.commandID) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(localizer.string("快捷键冲突"))
                        }
                    }
                    .padding(.vertical, SettingsLayout.rowVerticalPadding)
                }
            }
        }
    }

    private var archivesSettings: some View {
        settingsList {
            if model.snapshot.archivedWorkSessions.isEmpty {
                Text(localizer.string("暂无已归档工作会话"))
                    .font(applicationFont(offset: -1))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot.archivedWorkSessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title)
                            Text(workspaceName(for: session))
                                .font(applicationFont(offset: -1))
                                .foregroundStyle(.secondary)
                            if let managedWorktree = session.managedWorktree {
                                Text(managedWorktree.branchName)
                                    .font(applicationFont(offset: -1))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(localizer.string("恢复")) {
                            model.restoreArchive(session.id)
                        }
                        Button(localizer.string("永久删除"), role: .destructive) {
                            archiveToDelete = session
                        }
                    }
                    .padding(.vertical, SettingsLayout.rowVerticalPadding)
                }
            }
        }
    }

    private var applicationAppearance: Binding<ApplicationAppearance> {
        Binding(
            get: { model.settings.application.appearance },
            set: { value in
                var settings = model.settings.application
                settings.appearance = value
                model.saveApplicationSettings(settings)
            }
        )
    }

    private var networkProxyMode: Binding<NetworkProxyMode> {
        Binding(
            get: { model.settings.networkProxy.mode },
            set: { mode in
                var settings = model.settings.networkProxy
                settings.mode = mode
                model.saveNetworkProxySettings(settings)
                resetProxyTest()
            }
        )
    }

    private var manualProxyURL: Binding<String> {
        networkProxyBinding(\.manualURL)
    }

    private var manualProxyUsername: Binding<String> {
        networkProxyBinding(\.username)
    }

    private var manualProxyPassword: Binding<String> {
        Binding(
            get: { model.networkProxyPassword },
            set: { password in
                model.saveNetworkProxyPassword(password)
                resetProxyTest()
            }
        )
    }

    private func networkProxyBinding<Value>(
        _ keyPath: WritableKeyPath<NetworkProxySettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.settings.networkProxy[keyPath: keyPath] },
            set: { value in
                var settings = model.settings.networkProxy
                settings[keyPath: keyPath] = value
                model.saveNetworkProxySettings(settings)
                resetProxyTest()
            }
        )
    }

    private func testNetworkProxy() {
        guard !isTestingProxy else { return }
        proxyTestTask?.cancel()
        let requestID = UUID()
        proxyTestRequestID = requestID
        isTestingProxy = true
        proxyTestResult = nil
        let address = proxyTestAddress
        proxyTestTask = Task {
            let result = await model.testNetworkProxy(address: address)
            guard !Task.isCancelled, proxyTestRequestID == requestID else {
                return
            }
            proxyTestResult = result
            isTestingProxy = false
            proxyTestTask = nil
        }
    }

    private func resetProxyTest() {
        proxyTestTask?.cancel()
        proxyTestTask = nil
        proxyTestRequestID = UUID()
        proxyTestResult = nil
        isTestingProxy = false
    }

    @ViewBuilder
    private func proxyTestResultView(
        _ result: NetworkProxyTestResult
    ) -> some View {
        switch result {
        case .success(let statusCode, let elapsedMilliseconds):
            Label(
                localizer.format(
                    "连接成功 · HTTP %d · %d ms",
                    statusCode,
                    elapsedMilliseconds
                ),
                systemImage: "checkmark.circle.fill"
            )
            .font(applicationFont(offset: -1))
            .foregroundStyle(.green)
        case .failure(let failure):
            Label(
                proxyTestFailureMessage(failure),
                systemImage: "xmark.circle.fill"
            )
            .font(applicationFont(offset: -1))
            .foregroundStyle(.red)
        }
    }

    private func proxyTestFailureMessage(
        _ failure: NetworkProxyTestFailure
    ) -> String {
        switch failure {
        case .invalidAddress:
            localizer.string("测试地址必须是有效的 HTTP 或 HTTPS URL。")
        case .invalidProxyConfiguration(let error):
            proxyConfigurationErrorMessage(error)
        case .invalidResponse:
            localizer.string("连接失败：服务器没有返回 HTTP 响应。")
        case .httpStatus(let statusCode):
            localizer.format("连接失败：HTTP %d。", statusCode)
        case .requestFailed(let message):
            localizer.format("连接失败：%@", message)
        }
    }

    private func proxyConfigurationErrorMessage(
        _ error: NetworkProxyConfigurationError
    ) -> String {
        switch error {
        case .emptyURL:
            localizer.string("请输入代理 URL。")
        case .invalidURL:
            localizer.string("代理 URL 无效。")
        case .unsupportedScheme:
            localizer.string("代理协议仅支持 HTTP、HTTPS 或 SOCKS5。")
        case .missingHost:
            localizer.string("代理 URL 缺少主机名。")
        case .invalidPort:
            localizer.string("代理端口无效。")
        case .credentialsInURL:
            localizer.string("请在用户名和密码字段填写凭据，不要写入代理 URL。")
        }
    }

    private var gitSettings: some View {
        settingsList {
            Section(localizer.string("Git CLI")) {
                settingsControlRow(
                    "Git 可执行文件",
                    controlWidth: SettingsLayout.gitExecutableControlWidth
                ) {
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            text: Binding(
                                get: {
                                    gitPreferencesStore.preferences.gitExecutablePath
                                        ?? gitPreferencesStore.resolvedGitExecutableURL.path
                                },
                                set: { path in
                                    var preferences = gitPreferencesStore.preferences
                                    preferences.gitExecutablePath = path.isEmpty ? nil : path
                                    gitPreferencesStore.preferences = preferences
                                }
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(localizer.string("Git 可执行文件"))
                        Button(localizer.string("选择…")) {
                            chooseGitExecutable()
                        }
                        Button(localizer.string("测试")) {
                            testGitExecutable()
                        }
                    }
                }
                if let gitExecutableTestResult {
                    settingsControlRow(
                        "",
                        controlWidth: SettingsLayout.gitExecutableControlWidth
                    ) {
                        Text(gitExecutableTestResult)
                            .font(applicationFont(offset: -1))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section(localizer.string("Remote 同步")) {
                settingsControlRow("自动 Fetch") {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text(
                            gitPreferencesStore.preferences.autoFetchMinutes == 0
                                ? localizer.string("关闭")
                                : localizer.format(
                                    "%d 分钟",
                                    gitPreferencesStore.preferences.autoFetchMinutes
                                )
                        )
                        .monospacedDigit()
                        Stepper(
                            "",
                            value: Binding(
                                get: { gitPreferencesStore.preferences.autoFetchMinutes },
                                set: { value in
                                    var preferences = gitPreferencesStore.preferences
                                    preferences.autoFetchMinutes = max(0, value)
                                    gitPreferencesStore.preferences = preferences
                                }
                            ),
                            in: 0...240
                        )
                        .labelsHidden()
                    }
                }
            }

            Section(localizer.string("Diff")) {
                settingsControlRow("默认布局") {
                    settingsMenuPicker(
                        selection: Binding(
                            get: { gitPreferencesStore.preferences.diff.layout },
                            set: { value in
                                var preferences = gitPreferencesStore.preferences
                                preferences.diff.layout = value
                                gitPreferencesStore.preferences = preferences
                            }
                        ),
                        options: [
                            (localizer.string("并排"), GitDiffLayout.sideBySide),
                            (localizer.string("统一"), GitDiffLayout.unified),
                        ],
                        accessibilityLabel: localizer.string("默认布局")
                    )
                }
                settingsControlRow("忽略全部空白") {
                    Toggle("", isOn: gitDiffPreference(\.ignoreWhitespace))
                        .labelsHidden()
                }
                settingsControlRow("显示空白字符") {
                    Toggle("", isOn: gitDiffPreference(\.showWhitespace))
                        .labelsHidden()
                }
                settingsControlRow("自动换行") {
                    Toggle("", isOn: gitDiffPreference(\.softWrap))
                        .labelsHidden()
                }
                settingsControlRow("折叠未变更区域") {
                    Toggle("", isOn: gitDiffPreference(\.foldUnchanged))
                        .labelsHidden()
                }
            }

            Section(localizer.string("本地恢复与诊断")) {
                settingsControlRow("Git 安全快照保留") {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text(
                            localizer.format(
                                "%d 个修改工作日",
                                gitPreferencesStore.preferences.snapshotRetentionWorkingDays
                            )
                        )
                        .monospacedDigit()
                        Stepper(
                            "",
                            value: Binding(
                                get: {
                                    gitPreferencesStore.preferences
                                        .snapshotRetentionWorkingDays
                                },
                                set: { value in
                                    var preferences = gitPreferencesStore.preferences
                                    preferences.snapshotRetentionWorkingDays = max(0, value)
                                    gitPreferencesStore.preferences = preferences
                                }
                            ),
                            in: 0...30
                        )
                        .labelsHidden()
                    }
                }
                settingsControlRow("跨重启保存 Git Console") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { gitPreferencesStore.preferences.persistConsole },
                            set: { value in
                                var preferences = gitPreferencesStore.preferences
                                preferences.persistConsole = value
                                gitPreferencesStore.preferences = preferences
                                Task {
                                    await GitOperationRegistry.shared
                                        .setPersistenceEnabled(value)
                                }
                            }
                        )
                    )
                    .labelsHidden()
                }
                settingsControlRow("合并展示 Git Stash 与 Shelf") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { gitPreferencesStore.preferences.combineStashAndShelf },
                            set: { value in
                                var preferences = gitPreferencesStore.preferences
                                preferences.combineStashAndShelf = value
                                gitPreferencesStore.preferences = preferences
                            }
                        )
                    )
                    .labelsHidden()
                }
            }
        }
    }

    private var worktreesSettings: some View {
        settingsList {
            Section {
                if let error = model.managedWorktreeInventoryError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if model.managedWorktreeInventory.isEmpty {
                    if model.isRefreshingManagedWorktreeInventory {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(localizer.string("正在扫描 Worktree…"))
                                .foregroundStyle(.secondary)
                        }
                    } else if model.managedWorktreeInventoryError != nil {
                        Button(localizer.string("重新加载")) {
                            model.refreshManagedWorktreeInventory()
                        }
                    } else {
                        Text(localizer.string("没有 Worktree 分支或目录"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.managedWorktreeInventory) { item in
                        worktreeInventoryRow(item)
                    }
                }
            } header: {
                HStack {
                    ExplanationLabel(
                        localizer.string(
                            "列出 Breath 会话分支与托管目录。仅剩分支、目录残留和未关联会话的检出目录会继续占用本地资源。"
                        )
                    ) {
                        Text(localizer.string("Worktree 库存"))
                    }
                    Spacer()
                    if model.isRefreshingManagedWorktreeInventory {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            model.refreshManagedWorktreeInventory()
                        } label: {
                            Label(
                                localizer.string("刷新"),
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            model.refreshManagedWorktreeInventory()
        }
    }

    private func worktreeInventoryRow(
        _ item: ManagedWorktreeInventoryItem
    ) -> some View {
        let presentation = worktreeInventoryPresentation(item.state)
        let isDeleting = model.deletingManagedWorktreeInventoryItemIDs
            .contains(item.id)
        return HStack(spacing: 10) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(
                    presentation.needsAttention
                        ? Color.orange
                        : Color.secondary
                )
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    item.branchName
                        ?? localizer.string("无法识别分支")
                )
                .font(applicationFont(weight: .medium))
                .lineLimit(1)
                if !item.repositoryName.isEmpty {
                    Text(
                        item.repositoryPath.isEmpty
                            ? item.repositoryName
                            : "\(item.repositoryName) · \(item.repositoryPath)"
                    )
                    .font(applicationFont(offset: -2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                if let directoryPath = item.directoryPath {
                    Text(directoryPath)
                        .font(applicationFont(offset: -2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 12)

            statusChip(
                localizer.string(presentation.title),
                foreground: presentation.needsAttention
                    ? .orange
                    : .secondary
            )

            if isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else if let directoryPath = item.directoryPath {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(
                            fileURLWithPath: directoryPath,
                            isDirectory: true
                        ),
                    ])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help(localizer.string("在 Finder 中显示"))
                .accessibilityLabel(localizer.string("在 Finder 中显示"))
            }
        }
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .contextMenu {
            if let branchName = item.branchName {
                Button(localizer.string("复制分支名称")) {
                    copyToPasteboard(branchName)
                }
            }
            if let directoryPath = item.directoryPath {
                Button(localizer.string("复制路径")) {
                    copyToPasteboard(directoryPath)
                }
            }
            if item.state == .branchOnly, item.branchName != nil {
                Divider()
                Button(
                    localizer.string("删除残留分支…"),
                    role: .destructive
                ) {
                    pendingWorktreeInventoryDeletion =
                        PendingWorktreeInventoryDeletion(
                            kind: .branch,
                            item: item
                        )
                }
                .disabled(
                    isDeleting
                        || model.isRefreshingManagedWorktreeInventory
                )
            }
            if item.state == .directoryOnly
                || item.state == .orphanedCheckout
            {
                Divider()
                Button(
                    localizer.string("删除文件目录…"),
                    role: .destructive
                ) {
                    pendingWorktreeInventoryDeletion =
                        PendingWorktreeInventoryDeletion(
                            kind: .directory,
                            item: item
                        )
                }
                .disabled(
                    isDeleting
                        || model.isRefreshingManagedWorktreeInventory
                )
            }
        }
    }

    private func worktreeInventoryPresentation(
        _ state: ManagedWorktreeInventoryState
    ) -> WorktreeInventoryStatePresentation {
        switch state {
        case .tracked:
            WorktreeInventoryStatePresentation(
                title: "会话使用中",
                systemImage: "checkmark.circle",
                needsAttention: false
            )
        case .unavailable:
            WorktreeInventoryStatePresentation(
                title: "工作树不可用",
                systemImage: "exclamationmark.triangle.fill",
                needsAttention: true
            )
        case .branchOnly:
            WorktreeInventoryStatePresentation(
                title: "仅剩分支",
                systemImage: "arrow.triangle.branch",
                needsAttention: true
            )
        case .directoryOnly:
            WorktreeInventoryStatePresentation(
                title: "目录残留",
                systemImage: "folder.badge.questionmark",
                needsAttention: true
            )
        case .orphanedCheckout:
            WorktreeInventoryStatePresentation(
                title: "未关联会话",
                systemImage: "exclamationmark.triangle",
                needsAttention: true
            )
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var applicationLanguage: Binding<ApplicationLanguage> {
        Binding(
            get: { model.settings.application.language },
            set: { value in
                var settings = model.settings.application
                settings.language = value
                model.saveApplicationSettings(settings)
            }
        )
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: model.settings.application.language)
    }

    private var settingsControlForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var applicationFontSize: Binding<Double> {
        Binding(
            get: { model.settings.application.fontSize },
            set: { value in
                var settings = model.settings.application
                settings.fontSize = min(
                    max(value.rounded(), ApplicationSettings.fontSizeRange.lowerBound),
                    ApplicationSettings.fontSizeRange.upperBound
                )
                model.saveApplicationSettings(settings)
            }
        )
    }

    private func applicationFont(
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

    private var terminalFontFamily: Binding<String> {
        terminalBinding(\.fontFamily)
    }

    private var terminalFontSize: Binding<Double> {
        Binding(
            get: { model.settings.terminal.fontSize },
            set: { value in
                var settings = model.settings.terminal
                settings.fontSize = min(max(value.rounded(), 9), 32)
                model.saveTerminalSettings(settings)
            }
        )
    }

    private var terminalColorTheme: Binding<TerminalColorTheme> {
        Binding(
            get: {
                model.settings.terminal.colorTheme.resolved(for: resolvedAppearance)
            },
            set: { value in
                var settings = model.settings.terminal
                settings.colorTheme = value
                model.saveTerminalSettings(settings)
            }
        )
    }

    private var resolvedAppearance: ResolvedApplicationAppearance {
        colorScheme == .dark ? .dark : .light
    }

    private var terminalCursorStyle: Binding<TerminalCursorStyle> {
        terminalBinding(\.cursorStyle)
    }

    private var terminalShortcutPolicy: Binding<TerminalShortcutPolicy> {
        Binding(
            get: { model.settings.terminalShortcutPolicy },
            set: { model.saveTerminalShortcutPolicy($0) }
        )
    }

    private func terminalBinding<Value>(
        _ keyPath: WritableKeyPath<TerminalSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.settings.terminal[keyPath: keyPath] },
            set: { value in
                var settings = model.settings.terminal
                settings[keyPath: keyPath] = value
                model.saveTerminalSettings(settings)
            }
        )
    }

    private func gitDiffPreference(
        _ keyPath: WritableKeyPath<GitDiffPreferences, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { gitPreferencesStore.preferences.diff[keyPath: keyPath] },
            set: { value in
                var preferences = gitPreferencesStore.preferences
                preferences.diff[keyPath: keyPath] = value
                gitPreferencesStore.preferences = preferences
            }
        )
    }

    private func chooseGitExecutable() {
        let panel = NSOpenPanel()
        panel.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = localizer.string("选择")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var preferences = gitPreferencesStore.preferences
        preferences.gitExecutablePath = url.path
        gitPreferencesStore.preferences = preferences
        testGitExecutable()
    }

    private func testGitExecutable() {
        let url = gitPreferencesStore.resolvedGitExecutableURL
        gitExecutableTestResult = localizer.string("正在测试 Git…")
        Task {
            do {
                let info = try await GitExecutableInspector.inspect(url)
                if info.supportsCoreWorkbench {
                    gitExecutableTestResult = localizer.format(
                        "Git %@ · %@",
                        info.version,
                        info.executableURL.path
                    )
                } else {
                    gitExecutableTestResult = localizer.format(
                        "Git %@ 版本过旧；需要 %@ 或更高版本 · %@",
                        info.version,
                        GitExecutableInfo.minimumCoreVersion.displayValue,
                        info.executableURL.path
                    )
                }
            } catch {
                gitExecutableTestResult = localizer.format(
                    "Git 测试失败：%@",
                    error.localizedDescription
                )
            }
        }
    }

    private func gitShortcutBinding(_ commandID: String) -> Binding<String> {
        Binding(
            get: {
                gitPreferencesStore.preferences.shortcuts.first {
                    $0.commandID == commandID
                }?.keys ?? ""
            },
            set: { value in
                var preferences = gitPreferencesStore.preferences
                guard let index = preferences.shortcuts.firstIndex(where: {
                    $0.commandID == commandID
                }) else {
                    return
                }
                preferences.shortcuts[index].keys = value
                gitPreferencesStore.preferences = preferences
            }
        )
    }

    private var conflictingGitShortcutIDs: Set<String> {
        let bindings = gitPreferencesStore.preferences.shortcuts
        var conflicts: Set<String> = []
        for binding in bindings where !binding.keys.isEmpty {
            let matches = bindings.filter {
                $0.commandID != binding.commandID
                    && $0.keys == binding.keys
                    && ($0.scope == binding.scope
                        || $0.scope == .global
                        || binding.scope == .global)
            }
            if !matches.isEmpty {
                conflicts.insert(binding.commandID)
            }
        }
        return conflicts
    }

    private func gitShortcutTitle(_ commandID: String) -> String {
        switch commandID {
        case "git.open": "打开 Git 工作台"
        case "git.commit": "Commit"
        case "git.commitAndPush": "Commit and Push"
        case "git.push": "Push"
        case "git.fetch": "Fetch"
        case "git.refresh": "刷新"
        case "git.nextDifference": "下一个差异"
        case "git.previousDifference": "上一个差异"
        case "git.branches": "分支"
        case "git.logSearch": "搜索提交"
        case "git.pullMerge": "使用 Merge 更新"
        case "git.pullRebase": "使用 Rebase 更新"
        case "git.newBranch": "新建分支"
        case "git.merge": "Merge 到当前分支"
        case "git.rebase": "Rebase 当前分支到这里"
        case "git.cherryPick": "Cherry-pick"
        case "git.revert": "Revert Commit"
        case "git.fileHistory": "File History"
        case "git.blame": "Blame / Annotate"
        case "git.stash": "Git Stash"
        case "git.shelf": "Shelf"
        case "git.console": "Git Console"
        case "git.resolveConflicts": "解决冲突"
        case "git.undoLastCommit": "Undo Last Commit…"
        default: commandID
        }
    }

    private func gitShortcutScopeTitle(_ scope: GitShortcutScope) -> String {
        switch scope {
        case .global: "全局"
        case .gitWorkbench: "仅 Git 工作台焦点"
        }
    }

    private func integrationBinding(_ adapter: AgentAdapterDescriptor) -> Binding<Bool> {
        Binding(
            get: { model.enabledAgents.contains(adapter.kind) },
            set: { model.setAgentIntegration(adapter, enabled: $0) }
        )
    }

    private func integrationDescription(_ adapter: AgentAdapterDescriptor) -> String {
        switch adapter.integrationMechanism {
        case .userHooks:
            localizer.format("用户级 Hooks · 最低兼容 %@", adapter.minimumVersion)
        case .plugin:
            localizer.format("用户级 Plugin · 最低兼容 %@", adapter.minimumVersion)
        case .extension:
            localizer.format("用户级 Extension · 最低兼容 %@", adapter.minimumVersion)
        case .terminalParsing:
            localizer.string("终端输出解析")
        }
    }

    @ViewBuilder
    private func agentInstallationStatus(_ adapter: AgentAdapterDescriptor) -> some View {
        if model.updatingAgents.contains(adapter.kind) {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text(localizer.string("正在更新"))
                    .font(applicationFont(offset: -1))
                    .foregroundStyle(.secondary)
            }
        } else {
            switch model.agentCLIStatuses[adapter.kind] {
            case .none:
                ProgressView()
                    .controlSize(.small)
                    .help(localizer.string("正在检测本地安装状态"))
            case .some(.notInstalled):
                statusChip(localizer.string("未安装"), foreground: .secondary)
            case let .some(.installed(version, updateAvailable)):
                HStack(spacing: 6) {
                    statusChip(
                        version.map { "v\($0)" } ?? localizer.string("版本未知"),
                        foreground: .secondary
                    )
                    if updateAvailable {
                        Button {
                            model.updateAgentCLI(adapter)
                        } label: {
                            Label(localizer.string("可更新"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                        .help(localizer.string("自动更新到最新版本"))
                    }
                }
            }
        }
    }

    private func statusChip(_ title: String, foreground: Color) -> some View {
        Text(title)
            .font(applicationFont(offset: -1))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    private func workspaceName(for session: WorkSession) -> String {
        model.snapshot.workspaces.first(where: { $0.id == session.workspaceID })?
            .displayName ?? localizer.string("工作区已移除")
    }

    private var worktreeInventoryDeletionTitle: String {
        guard let deletion = pendingWorktreeInventoryDeletion else {
            return ""
        }
        return localizer.string(
            deletion.kind == .branch
                ? "删除残留分支？"
                : "删除文件目录？"
        )
    }

    private var worktreeInventoryDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingWorktreeInventoryDeletion != nil },
            set: {
                if !$0 {
                    pendingWorktreeInventoryDeletion = nil
                }
            }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { archiveToDelete != nil },
            set: { if !$0 { archiveToDelete = nil } }
        )
    }
}

private struct NotesSettingsPane: View {
    @Environment(\.applicationLanguage) private var applicationLanguage
    @ObservedObject var applicationModel: BreathApplicationModel
    @ObservedObject var model: NotesApplicationModel
    @State private var pendingLibraryURL: URL?

    init(applicationModel: BreathApplicationModel) {
        self.applicationModel = applicationModel
        model = applicationModel.notesModel
    }

    var body: some View {
        List {
            Section(localizer.string("笔记库")) {
                LabeledContent(localizer.string("路径")) {
                    Text(
                        model.snapshot.library?.rootPath
                            ?? localizer.string("尚未选择")
                    )
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent(localizer.string("状态")) {
                    Label(
                        model.isLibraryAvailable
                            ? localizer.string("可访问")
                            : localizer.string("不可访问"),
                        systemImage: model.isLibraryAvailable
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        model.isLibraryAvailable ? .green : .orange
                    )
                }
                HStack {
                    Button(
                        localizer.string("选择其他目录…"),
                        action: chooseLibrary
                    )
                    Button(localizer.string("重建全文索引")) {
                        model.rebuildSearchIndex()
                    }
                    .disabled(!model.isLibraryAvailable)
                }
            }

            Section(localizer.string("Markdown 主题")) {
                LabeledContent(localizer.string("浅色外观")) {
                    themeMenu(
                        selection: lightTheme,
                        options: NoteMarkdownTheme.lightThemes
                    )
                }
                LabeledContent(localizer.string("深色外观")) {
                    themeMenu(
                        selection: darkTheme,
                        options: NoteMarkdownTheme.darkThemes
                    )
                }
                Text(
                    localizer.string(
                        "六套 Typora 风格主题均随 Breath 离线发布；不支持导入、自定义 CSS 或自动更新。"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(localizer.string("写作")) {
                Toggle(
                    localizer.string("显示代码块行号"),
                    isOn: showsCodeLineNumbers
                )
                Toggle(
                    localizer.string("正文拼写检查"),
                    isOn: spellCheckEnabled
                )
                Text(
                    localizer.string(
                        "拼写检查只显示系统下划线，不启用自动更正；代码、链接、数学和 Mermaid 内容会被排除。"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(SettingsLayout.contentInset)
        .alert(
            localizer.string("更换笔记库？"),
            isPresented: Binding(
                get: { pendingLibraryURL != nil },
                set: { if !$0 { pendingLibraryURL = nil } }
            )
        ) {
            Button(localizer.string("取消"), role: .cancel) {
                pendingLibraryURL = nil
            }
            Button(
                localizer.string("结束对话并更换"),
                role: .destructive
            ) {
                guard let url = pendingLibraryURL else { return }
                pendingLibraryURL = nil
                Task {
                    if applicationModel.noteAgentModel.status != .idle {
                        await applicationModel.noteAgentModel.endConversation()
                    }
                    model.selectLibrary(
                        url,
                        discardUnsavedChanges: model.hasDirtyDocuments
                    )
                }
            }
        } message: {
            Text(
                localizer.string(
                    "继续会丢弃未保存的笔记并结束旧笔记库中的 Agent 对话。"
                )
            )
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }

    private func themeMenu(
        selection: Binding<NoteMarkdownTheme>,
        options: [NoteMarkdownTheme]
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { theme in
                Button {
                    selection.wrappedValue = theme
                } label: {
                    HStack {
                        Text(theme.displayName)
                        if selection.wrappedValue == theme {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selection.wrappedValue.displayName)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: 180, height: SettingsLayout.controlHeight)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(localizer.string("Markdown 主题"))
    }

    private var lightTheme: Binding<NoteMarkdownTheme> {
        Binding(
            get: { model.snapshot.preferences.lightTheme },
            set: { value in
                model.updatePreferences { $0.lightTheme = value }
            }
        )
    }

    private var darkTheme: Binding<NoteMarkdownTheme> {
        Binding(
            get: { model.snapshot.preferences.darkTheme },
            set: { value in
                model.updatePreferences { $0.darkTheme = value }
            }
        )
    }

    private var showsCodeLineNumbers: Binding<Bool> {
        Binding(
            get: { model.snapshot.preferences.showsCodeLineNumbers },
            set: { value in
                model.updatePreferences {
                    $0.showsCodeLineNumbers = value
                }
            }
        )
    }

    private var spellCheckEnabled: Binding<Bool> {
        Binding(
            get: { model.snapshot.preferences.spellCheckEnabled },
            set: { value in
                model.updatePreferences { $0.spellCheckEnabled = value }
            }
        )
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = localizer.string("选择笔记库")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if model.hasDirtyDocuments
            || applicationModel.noteAgentModel.status != .idle
        {
            pendingLibraryURL = url
        } else {
            model.selectLibrary(url)
        }
    }
}

private struct TerminalThemePicker: View {
    @Binding var selection: TerminalColorTheme
    let options: [(title: String, value: TerminalColorTheme)]
    let accessibilityLabel: String

    var body: some View {
        ThemePopUpButton(selection: $selection, options: options)
        .frame(
            width: SettingsLayout.controlColumnWidth,
            height: SettingsLayout.controlHeight
        )
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Plain native pop-up button. Every option stays in the menu, so the
/// system's own selection anchoring, scrolling, and type-ahead apply.
private struct ThemePopUpButton: NSViewRepresentable {
    @Binding var selection: TerminalColorTheme
    let options: [(title: String, value: TerminalColorTheme)]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        button.autoenablesItems = false
        context.coordinator.attach(to: button)
        context.coordinator.update(options: options, selection: selection)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.update(options: options, selection: selection)
    }

    @MainActor final class Coordinator: NSObject {
        private let selectionBinding: Binding<TerminalColorTheme>

        private weak var button: NSPopUpButton?
        private var options: [(title: String, value: TerminalColorTheme)] = []
        private var lastOptionsKey = ""
        private var imageCache: [String: NSImage] = [:]

        init(selection: Binding<TerminalColorTheme>) {
            selectionBinding = selection
        }

        func attach(to button: NSPopUpButton) {
            self.button = button
        }

        func update(
            options: [(title: String, value: TerminalColorTheme)],
            selection: TerminalColorTheme
        ) {
            self.options = options
            let optionsKey = options.map(\.value.rawValue).joined(separator: "\n")
            if optionsKey != lastOptionsKey {
                lastOptionsKey = optionsKey
                rebuildMenu()
            }
            syncSelection(selection)
        }

        private func rebuildMenu() {
            guard let button else { return }
            button.removeAllItems()
            let selection = selectionBinding.wrappedValue
            for option in options {
                let item = NSMenuItem(
                    title: option.title,
                    action: #selector(selectTheme(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = option.value.rawValue
                item.image = swatchImage(for: option.value)
                item.state = option.value == selection ? .on : .off
                item.isEnabled = true
                button.menu?.addItem(item)
            }
        }

        private func syncSelection(_ selection: TerminalColorTheme) {
            guard let button, let menu = button.menu else { return }
            let item = menu.items.first {
                ($0.representedObject as? String) == selection.rawValue
            }
            button.select(item)
            for entry in menu.items {
                entry.state = entry === item ? .on : .off
            }
        }

        @objc private func selectTheme(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let theme = TerminalColorTheme(rawValue: rawValue)
            else { return }
            selectionBinding.wrappedValue = theme
        }

        private func swatchImage(for theme: TerminalColorTheme) -> NSImage {
            if let cached = imageCache[theme.rawValue] { return cached }
            let palette = theme.palette
            let stripes = [
                palette.background,
                palette.ansiColors[1],
                palette.ansiColors[2],
                palette.foreground,
            ]
            let image = NSImage(
                size: NSSize(width: 30, height: 12),
                flipped: false
            ) { rect in
                let clip = NSBezierPath(
                    roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                    xRadius: 2.5,
                    yRadius: 2.5
                )
                clip.addClip()
                let stripeWidth = rect.width / CGFloat(stripes.count)
                for (index, color) in stripes.enumerated() {
                    NSColor(
                        calibratedRed: CGFloat(color.red) / 255,
                        green: CGFloat(color.green) / 255,
                        blue: CGFloat(color.blue) / 255,
                        alpha: 1
                    ).setFill()
                    NSRect(
                        x: rect.minX + stripeWidth * CGFloat(index),
                        y: rect.minY,
                        width: stripeWidth + 0.5,
                        height: rect.height
                    ).fill()
                }
                NSColor.separatorColor.setStroke()
                clip.stroke()
                return true
            }
            imageCache[theme.rawValue] = image
            return image
        }
    }
}

private struct TerminalThemeCodePreview: View {
    let theme: TerminalColorTheme
    let accessibilityLabel: String

    private var palette: TerminalColorPalette {
        theme.palette
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                codeLine(1, content: lineOne)
                codeLine(2, content: lineTwo)
                codeLine(3, content: lineThree)
                codeLine(4, content: lineFour)
            }

            Rectangle()
                .fill(palette.foreground.swiftUIColor.opacity(0.14))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 4) {
                shellLine(
                    prompt: "❯ ",
                    command: "git status --short"
                )
                token(" M ", color: palette.ansiColors[3])
                    + token("Sources/BreathApp/BreathSettingsView.swift", color: palette.foreground)
                shellLine(
                    prompt: "❯ ",
                    command: "swift build --product Breath"
                )
                token("Build complete! ", color: palette.ansiColors[2])
                    + token("(1.24s)", color: palette.foreground, opacity: 0.55)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.background.swiftUIColor)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(palette.foreground.swiftUIColor.opacity(0.18), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(theme.displayName)
    }

    private func codeLine(_ number: Int, content: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .foregroundStyle(palette.foreground.swiftUIColor.opacity(0.32))
                .frame(width: 14, alignment: .trailing)
            content
        }
    }

    private func shellLine(prompt: String, command: String) -> Text {
        token(prompt, color: palette.ansiColors[6])
            + token(command, color: palette.foreground)
    }

    private var lineOne: Text {
        token("let ", color: palette.ansiColors[5])
            + token("workspace ", color: palette.foreground)
            + token("= ", color: palette.ansiColors[8])
            + token(#""Breath""#, color: palette.ansiColors[2])
    }

    private var lineTwo: Text {
        token("if ", color: palette.ansiColors[5])
            + token("workspace", color: palette.foreground)
            + token(".isReady ", color: palette.ansiColors[6])
            + token("{", color: palette.foreground)
    }

    private var lineThree: Text {
        token("    print", color: palette.ansiColors[4])
            + token("(", color: palette.foreground)
            + token(#""Ready to build""#, color: palette.ansiColors[2])
            + token(")", color: palette.foreground)
    }

    private var lineFour: Text {
        token("}", color: palette.foreground)
    }

    private func token(
        _ value: String,
        color: TerminalRGBColor,
        opacity: Double = 1
    ) -> Text {
        Text(value).foregroundColor(color.swiftUIColor.opacity(opacity))
    }
}

private extension TerminalRGBColor {
    var swiftUIColor: Color {
        Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}
