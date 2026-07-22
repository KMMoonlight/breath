import AppKit
import BreathAgents
import BreathCore
import CoreText
import SwiftUI

enum BreathSettingsTab: Hashable, CaseIterable {
    case application
    case terminal
    case git
    case agentIntegrations
    case shortcuts
    case archives
}

private extension BreathSettingsTab {
    var title: String {
        switch self {
        case .application: "应用配置"
        case .terminal: "终端配置"
        case .git: "Git"
        case .agentIntegrations: "Agent 集成"
        case .shortcuts: "快捷键"
        case .archives: "已归档"
        }
    }

    var systemImage: String {
        switch self {
        case .application: "paintbrush"
        case .terminal: "terminal"
        case .git: "point.topleft.down.to.point.bottomright.curvepath"
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
        ShortcutReference(action: "新建工作会话", keys: "⌘T"),
        ShortcutReference(action: "下一个会话 Tab", keys: "⌘N"),
        ShortcutReference(action: "上一个分屏", keys: "⌘["),
        ShortcutReference(action: "下一个分屏", keys: "⌘]"),
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
        } message: { _ in
            Text(localizer.string("只会删除 Breath 元数据，不会删除项目文件或 Agent CLI 自己保存的会话。"))
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
        .padding(.leading, WorkbenchLayout.pageToolbarLeadingInset)
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
        case .terminal:
            terminalSettings
        case .git:
            gitSettings
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
            settingsControlRow("颜色主题") {
                settingsMenuPicker(
                    selection: terminalColorTheme,
                    options: TerminalColorTheme.compatible(with: resolvedAppearance).map {
                        (localizer.string($0.displayName), $0)
                    },
                    accessibilityLabel: localizer.string("颜色主题")
                )
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
        controlWidth: CGFloat = SettingsLayout.controlColumnWidth,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            Text(localizer.string(title))
                .lineLimit(1)
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
