import AppKit
import BreathAgents
import BreathCore
import CoreText
import SwiftUI

enum BreathSettingsTab: Hashable {
    case application
    case terminal
    case git
    case agentIntegrations
    case shortcuts
    case archives
}

private struct ShortcutReference: Identifiable {
    let action: String
    let keys: String

    var id: String { action }
}

struct BreathSettingsView: View {
    private static let availableFontFamilies: [String] = {
        let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return families.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }()

    private static let supportedShortcuts = [
        ShortcutReference(action: "打开主窗口", keys: "⌘N"),
        ShortcutReference(action: "新建工作会话", keys: "⌘T"),
        ShortcutReference(action: "切换到第 1–9 个终端", keys: "⌘1…⌘9"),
        ShortcutReference(action: "横向分屏", keys: "⌘D"),
        ShortcutReference(action: "纵向分屏", keys: "⌘⇧D"),
        ShortcutReference(action: "关闭当前分屏终端", keys: "⌘W"),
    ]

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: BreathApplicationModel
    @StateObject private var gitPreferencesStore = GitPreferencesStore.shared
    @State private var selectedTab: BreathSettingsTab
    @State private var archiveToDelete: WorkSession?
    @State private var gitExecutableTestResult: String?

    init(
        model: BreathApplicationModel,
        selectedTab: BreathSettingsTab = .application
    ) {
        self.model = model
        _selectedTab = State(initialValue: selectedTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            VStack {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text(localizer.string("外观"))
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: applicationAppearance) {
                            Text(localizer.string("跟随系统")).tag(ApplicationAppearance.system)
                            Text(localizer.string("浅色")).tag(ApplicationAppearance.light)
                            Text(localizer.string("深色")).tag(ApplicationAppearance.dark)
                        }
                        .labelsHidden()
                        .frame(width: 160, alignment: .leading)
                        .foregroundStyle(settingsControlForegroundColor)
                        .id(colorScheme)
                        .accessibilityLabel(localizer.string("外观"))
                    }
                    GridRow {
                        Text(localizer.string("语言"))
                        Picker("", selection: applicationLanguage) {
                            Text(localizer.string("系统")).tag(ApplicationLanguage.system)
                            Text(localizer.string("中文")).tag(ApplicationLanguage.chinese)
                            Text(localizer.string("英文")).tag(ApplicationLanguage.english)
                        }
                        .labelsHidden()
                        .frame(width: 160, alignment: .leading)
                        .foregroundStyle(settingsControlForegroundColor)
                        .id(model.settings.application.language)
                        .accessibilityLabel(localizer.string("语言"))
                    }
                    GridRow {
                        Text(localizer.string("字体大小"))
                        Stepper(
                            value: applicationFontSize,
                            in: ApplicationSettings.fontSizeRange,
                            step: 1
                        ) {
                            Text("\(Int(applicationFontSize.wrappedValue)) px")
                                .monospacedDigit()
                        }
                        .frame(width: 160, alignment: .leading)
                        .accessibilityLabel(localizer.string("应用字体大小"))
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .tabItem { Label(localizer.string("应用配置"), systemImage: "paintbrush") }
            .tag(BreathSettingsTab.application)

            VStack {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text(localizer.string("字体"))
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: terminalFontFamily) {
                            ForEach(Self.availableFontFamilies, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityLabel(localizer.string("字体"))
                    }
                    GridRow {
                        Text(localizer.string("字号"))
                        TextField(
                            "",
                            value: terminalFontSize,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 64)
                        .accessibilityLabel(localizer.string("字号"))
                    }
                    GridRow {
                        Text(localizer.string("颜色主题"))
                        Picker("", selection: terminalColorTheme) {
                            ForEach(
                                TerminalColorTheme.compatible(with: resolvedAppearance),
                                id: \.rawValue
                            ) { theme in
                                Text(localizer.string(theme.displayName)).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160, alignment: .leading)
                        .accessibilityLabel(localizer.string("颜色主题"))
                    }
                    GridRow {
                        Text(localizer.string("光标"))
                        Picker("", selection: terminalCursorStyle) {
                            Text(localizer.string("方块")).tag(TerminalCursorStyle.block)
                            Text(localizer.string("竖线")).tag(TerminalCursorStyle.bar)
                            Text(localizer.string("下划线")).tag(TerminalCursorStyle.underline)
                        }
                        .labelsHidden()
                        .frame(width: 160, alignment: .leading)
                        .accessibilityLabel(localizer.string("光标"))
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .tabItem { Label(localizer.string("终端配置"), systemImage: "terminal") }
            .tag(BreathSettingsTab.terminal)

            gitSettings
                .tabItem {
                    Label(
                        localizer.string("Git"),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
                .tag(BreathSettingsTab.git)

            List(model.adapters, id: \.kind) { adapter in
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
                .padding(.vertical, 3)
            }
            .padding(12)
            .onAppear {
                model.refreshAgentCLIStatuses()
            }
            .tabItem {
                Label(localizer.string("Agent 集成"), systemImage: "point.3.connected.trianglepath.dotted")
            }
            .tag(BreathSettingsTab.agentIntegrations)

            List {
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
                        .padding(.vertical, 4)
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
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(12)
            .tabItem { Label(localizer.string("快捷键"), systemImage: "keyboard") }
            .tag(BreathSettingsTab.shortcuts)

            List {
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
                            }
                            Spacer()
                            Button(localizer.string("恢复")) {
                                model.restoreArchive(session.id)
                            }
                            Button(localizer.string("永久删除"), role: .destructive) {
                                archiveToDelete = session
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(12)
            .tabItem { Label(localizer.string("已归档"), systemImage: "archivebox") }
            .tag(BreathSettingsTab.archives)
        }
        .frame(width: 650, height: 440)
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
        } message: { _ in
            Text(localizer.string("只会删除 Breath 元数据，不会删除项目文件或 Agent CLI 自己保存的会话。"))
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

    private var gitSettings: some View {
        Form {
            Section(localizer.string("Git CLI")) {
                HStack {
                    TextField(
                        localizer.string("Git 可执行文件"),
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
                    Button(localizer.string("选择…")) {
                        chooseGitExecutable()
                    }
                    Button(localizer.string("测试")) {
                        testGitExecutable()
                    }
                }
                if let gitExecutableTestResult {
                    Text(gitExecutableTestResult)
                        .font(applicationFont(offset: -1))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section(localizer.string("Remote 同步")) {
                Stepper(
                    value: Binding(
                        get: { gitPreferencesStore.preferences.autoFetchMinutes },
                        set: { value in
                            var preferences = gitPreferencesStore.preferences
                            preferences.autoFetchMinutes = max(0, value)
                            gitPreferencesStore.preferences = preferences
                        }
                    ),
                    in: 0...240
                ) {
                    Text(
                        gitPreferencesStore.preferences.autoFetchMinutes == 0
                            ? localizer.string("自动 Fetch：关闭")
                            : localizer.format(
                                "自动 Fetch：%d 分钟",
                                gitPreferencesStore.preferences.autoFetchMinutes
                            )
                    )
                }
            }

            Section(localizer.string("Diff")) {
                Picker(
                    localizer.string("默认布局"),
                    selection: Binding(
                        get: { gitPreferencesStore.preferences.diff.layout },
                        set: { value in
                            var preferences = gitPreferencesStore.preferences
                            preferences.diff.layout = value
                            gitPreferencesStore.preferences = preferences
                        }
                    )
                ) {
                    Text(localizer.string("并排")).tag(GitDiffLayout.sideBySide)
                    Text(localizer.string("统一")).tag(GitDiffLayout.unified)
                }
                Toggle(
                    localizer.string("忽略全部空白"),
                    isOn: gitDiffPreference(\.ignoreWhitespace)
                )
                Toggle(
                    localizer.string("显示空白字符"),
                    isOn: gitDiffPreference(\.showWhitespace)
                )
                Toggle(
                    localizer.string("自动换行"),
                    isOn: gitDiffPreference(\.softWrap)
                )
                Toggle(
                    localizer.string("折叠未变更区域"),
                    isOn: gitDiffPreference(\.foldUnchanged)
                )
            }

            Section(localizer.string("本地恢复与诊断")) {
                Stepper(
                    value: Binding(
                        get: {
                            gitPreferencesStore.preferences.snapshotRetentionWorkingDays
                        },
                        set: { value in
                            var preferences = gitPreferencesStore.preferences
                            preferences.snapshotRetentionWorkingDays = max(0, value)
                            gitPreferencesStore.preferences = preferences
                        }
                    ),
                    in: 0...30
                ) {
                    Text(
                        localizer.format(
                            "Git 安全快照保留：%d 个修改工作日",
                            gitPreferencesStore.preferences.snapshotRetentionWorkingDays
                        )
                    )
                }
                Toggle(
                    localizer.string("跨重启保存 Git Console"),
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
                Toggle(
                    localizer.string("合并展示 Git Stash 与 Shelf"),
                    isOn: Binding(
                        get: { gitPreferencesStore.preferences.combineStashAndShelf },
                        set: { value in
                            var preferences = gitPreferencesStore.preferences
                            preferences.combineStashAndShelf = value
                            gitPreferencesStore.preferences = preferences
                        }
                    )
                )
            }
        }
        .formStyle(.grouped)
        .padding(12)
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

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { archiveToDelete != nil },
            set: { if !$0 { archiveToDelete = nil } }
        )
    }
}

private extension TerminalColorTheme {
    var displayName: String {
        switch self {
        case .dark: "Breath 深色"
        case .light: "Breath 浅色"
        case .solarizedDark: "Solarized Dark"
        case .solarizedLight: "Solarized Light"
        case .dracula: "Dracula"
        case .nord: "Nord"
        case .gruvboxDark: "Gruvbox Dark"
        case .gruvboxLight: "Gruvbox Light"
        case .catppuccinMocha: "Catppuccin Mocha"
        case .catppuccinLatte: "Catppuccin Latte"
        case .tokyoNight: "Tokyo Night"
        case .tokyoNightDay: "Tokyo Night Day"
        case .atomOneDark: "Atom One Dark"
        case .atomOneLight: "Atom One Light"
        }
    }
}
