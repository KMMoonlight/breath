import AppKit
import BreathAgents
import BreathAutomation
import BreathCore
import SwiftUI

enum AutomationAccessibility {
    static let panel = "自动化面板"
    static let create = "新建自动化"
    static let search = "搜索自动化"
    static let list = "自动化列表"
    static let detail = "自动化详情"
}

private enum AutomationViewLayout {
    static let compactWidth: CGFloat = 760
    static let listMinimumWidth: CGFloat = 310
    static let listIdealWidth: CGFloat = 370
    static let listMaximumWidth: CGFloat = 470
    static let contentPadding: CGFloat = 16
}

struct AutomationView: View {
    @ObservedObject var model: BreathApplicationModel
    @Environment(\.applicationLanguage) private var language
    @State private var selectedAutomationID: AutomationID?
    @State private var selectedRunID: AutomationRunID?
    @State private var searchText = ""
    @State private var showsCreator = false
    @State private var automationToEdit: Automation?
    @State private var automationToDelete: Automation?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { geometry in
                if geometry.size.width < AutomationViewLayout.compactWidth {
                    NavigationStack {
                        listPanel(navigatesToDetail: true)
                            .navigationDestination(for: AutomationID.self) { id in
                                detail(for: automation(with: id))
                            }
                    }
                } else {
                    HSplitView {
                        listPanel(navigatesToDetail: false)
                            .frame(
                                minWidth: AutomationViewLayout.listMinimumWidth,
                                idealWidth: AutomationViewLayout.listIdealWidth,
                                maxWidth: AutomationViewLayout.listMaximumWidth
                            )
                        detail(for: selectedAutomation)
                            .frame(
                                minWidth: 0,
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string(AutomationAccessibility.panel))
        .onAppear { selectFirstVisibleAutomationIfNeeded() }
        .onChange(of: filteredAutomations.map(\.id)) { _, _ in
            selectFirstVisibleAutomationIfNeeded()
        }
        .sheet(isPresented: $showsCreator) {
            AutomationEditorSheet(model: model, automation: nil) { id in
                selectedAutomationID = id
                showsCreator = false
            }
        }
        .sheet(item: $automationToEdit) { automation in
            AutomationEditorSheet(
                model: model,
                automation: automation
            ) { id in
                selectedAutomationID = id
                automationToEdit = nil
            }
        }
        .confirmationDialog(
            localizer.string("删除自动化？"),
            isPresented: deleteConfirmationPresented,
            presenting: automationToDelete
        ) { automation in
            Button(localizer.string("删除"), role: .destructive) {
                perform {
                    try await model.deleteAutomation(automation.id)
                    if selectedAutomationID == automation.id {
                        selectedAutomationID = nil
                    }
                    automationToDelete = nil
                }
            }
            Button(localizer.string("取消"), role: .cancel) {
                automationToDelete = nil
            }
        } message: { automation in
            Text(deleteConfirmationMessage(for: automation))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(localizer.string("自动化"))
                .font(.headline)
            Text(
                localizer.format(
                    "%d 个项目",
                    model.automationSnapshot.automations.count
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker(
                    localizer.string("最大并发数"),
                    selection: concurrencyBinding
                ) {
                    ForEach(1...4, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
            } label: {
                Label(
                    localizer.format(
                        "并发 %d",
                        model.automationSnapshot.concurrencyLimit
                    ),
                    systemImage: "square.stack.3d.up"
                )
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            Button {
                showsCreator = true
            } label: {
                Label(
                    localizer.string("新建自动化"),
                    systemImage: "plus"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel(
                localizer.string(AutomationAccessibility.create)
            )
        }
        .pageToolbarLeadingPadding()
        .padding(.trailing, WorkbenchLayout.pageToolbarTrailingInset)
        .frame(height: WorkbenchLayout.pageToolbarHeight)
    }

    private func listPanel(navigatesToDetail: Bool) -> some View {
        VStack(spacing: 0) {
            TextField(
                localizer.string("搜索名称或 Prompt"),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(
                localizer.string(AutomationAccessibility.search)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if navigatesToDetail {
                List {
                    if filteredAutomations.isEmpty {
                        compactEmptyListRow
                    } else {
                        ForEach(filteredAutomations) { automation in
                            HStack(spacing: 8) {
                                NavigationLink(value: automation.id) {
                                    automationRow(
                                        automation,
                                        includesActions: false
                                    )
                                }
                                .buttonStyle(.plain)
                                automationRowActions(automation)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel(
                    localizer.string(AutomationAccessibility.list)
                )
            } else {
                List(selection: $selectedAutomationID) {
                    if filteredAutomations.isEmpty {
                        compactEmptyListRow
                    } else {
                        ForEach(filteredAutomations) { automation in
                            automationRow(automation)
                                .tag(automation.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel(
                    localizer.string(AutomationAccessibility.list)
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var compactEmptyListRow: some View {
        if !model.automationSnapshot.automations.isEmpty {
            HStack(spacing: 8) {
                Text(localizer.string("没有匹配的自动化"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(localizer.string("清除搜索")) {
                    searchText = ""
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .listRowSeparator(.hidden)
        }
    }

    private func automationRow(
        _ automation: Automation,
        includesActions: Bool = true
    ) -> some View {
        let recentRun = runs(for: automation).first
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(automation.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if includesActions {
                    automationRowActions(automation)
                }
            }
            Text(automation.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 5) {
                Label(
                    agentName(automation.agent),
                    systemImage: "sparkles"
                )
                Text("·")
                Text(automation.workspaceDisplayName)
                Text("·")
                Text(triggerSummary(automation.trigger, localizer: localizer))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if let reason = automation.dependencyPauseReason {
                Label(
                    localizer.string(reason),
                    systemImage: "pause.circle"
                )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if automation.requiresExplicitReenable {
                Label(
                    localizer.string("依赖已恢复，请重新启用"),
                    systemImage: "pause.circle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
            }
            if let recentRun {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor(recentRun.status))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(statusLabel(recentRun.status, localizer: localizer))
                    Text(recentRun.queuedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if let nextDate = nextOccurrence(for: automation) {
                Text(
                    localizer.format(
                        "下次运行 %@",
                        nextDate.formatted(date: .abbreviated, time: .shortened)
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(automation.name)
    }

    private func automationRowActions(
        _ automation: Automation
    ) -> some View {
        let inFlight = runs(for: automation).contains {
            !$0.status.isTerminal
        }
        return HStack(spacing: 6) {
            Toggle(
                localizer.string("启用"),
                isOn: enabledBinding(for: automation)
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel(
                localizer.format("启用 %@", automation.name)
            )
            Button {
                runNow(automation)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(inFlight || !automation.canRun)
            .accessibilityLabel(
                localizer.format("立即运行 %@", automation.name)
            )
        }
    }

    @ViewBuilder
    private func detail(for automation: Automation?) -> some View {
        if let automation {
            AutomationDetailView(
                model: model,
                automation: automation,
                runs: runs(for: automation),
                selectedRunID: $selectedRunID,
                onRun: { runNow(automation) },
                onEdit: { automationToEdit = automation },
                onDelete: { automationToDelete = automation }
            )
            .accessibilityLabel(
                localizer.string(AutomationAccessibility.detail)
            )
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private var selectedAutomation: Automation? {
        guard let selectedAutomationID else { return nil }
        return automation(with: selectedAutomationID)
    }

    private var filteredAutomations: [Automation] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        guard !query.isEmpty else {
            return model.automationSnapshot.automations
        }
        return model.automationSnapshot.automations.filter { automation in
            automation.name.localizedLowercase.contains(query)
                || automation.prompt.localizedLowercase.contains(query)
        }
    }

    private func automation(with id: AutomationID) -> Automation? {
        model.automationSnapshot.automations.first { $0.id == id }
    }

    private func runs(for automation: Automation) -> [AutomationRun] {
        model.automationSnapshot.runs(for: automation.id)
    }

    private func selectFirstVisibleAutomationIfNeeded() {
        guard !filteredAutomations.isEmpty else {
            selectedAutomationID = nil
            return
        }
        if let selectedAutomationID,
           filteredAutomations.contains(where: { $0.id == selectedAutomationID })
        {
            return
        }
        selectedAutomationID = filteredAutomations.first?.id
        selectedRunID = nil
    }

    private func enabledBinding(for automation: Automation) -> Binding<Bool> {
        Binding(
            get: { automation.isEnabled },
            set: { value in
                perform {
                    try await model.setAutomationEnabled(
                        value,
                        for: automation.id
                    )
                }
            }
        )
    }

    private var concurrencyBinding: Binding<Int> {
        Binding(
            get: { model.automationSnapshot.concurrencyLimit },
            set: { value in
                perform {
                    try await model.setAutomationConcurrencyLimit(value)
                }
            }
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { automationToDelete != nil },
            set: { isPresented in
                if !isPresented { automationToDelete = nil }
            }
        )
    }

    private func runNow(_ automation: Automation) {
        perform {
            _ = try await model.runAutomationNow(automation.id)
        }
    }

    private func deleteConfirmationMessage(
        for automation: Automation
    ) -> String {
        let hasActiveRun = runs(for: automation).contains {
            !$0.status.isTerminal
        }
        if automation.trigger == .external, hasActiveRun {
            return localizer.format(
                "“%@”及其最近运行结果将被永久删除；活动运行会终止，外部短码会立即失效。",
                automation.name
            )
        }
        if automation.trigger == .external {
            return localizer.format(
                "“%@”及其最近运行结果将被永久删除；外部短码会立即失效。",
                automation.name
            )
        }
        if hasActiveRun {
            return localizer.format(
                "“%@”及其最近运行结果将被永久删除；活动运行会终止。",
                automation.name
            )
        }
        return localizer.format(
            "“%@”及其最近运行结果将被永久删除。",
            automation.name
        )
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await operation()
            } catch {
                model.lastError = localizer.string(
                    error.localizedDescription
                )
            }
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: language)
    }

    private func agentName(_ kind: AgentKind) -> String {
        model.adapters.first(where: { $0.kind == kind })?.displayName
            ?? kind.rawValue
    }
}

private struct AutomationDetailView: View {
    @ObservedObject var model: BreathApplicationModel
    let automation: Automation
    let runs: [AutomationRun]
    @Binding var selectedRunID: AutomationRunID?
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.applicationLanguage) private var language
    @State private var confirmsShortcodeRegeneration = false

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let reason = automation.dependencyPauseReason {
                        Label(
                            localizer.string(reason),
                            systemImage: "pause.circle.fill"
                        )
                            .foregroundStyle(.orange)
                            .accessibilityLabel(
                                localizer.format("自动化已暂停：%@", reason)
                            )
                    }
                    promptSection
                    configurationSection
                    if automation.trigger == .external {
                        externalTriggerSection
                    }
                    historySection
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(AutomationViewLayout.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectDefaultRunIfNeeded()
        }
        .onChange(of: automation.id) { _, _ in
            selectedRunID = nil
            selectDefaultRunIfNeeded()
        }
        .onChange(of: runs.map(\.id)) { _, _ in
            selectDefaultRunIfNeeded()
        }
        .confirmationDialog(
            localizer.string("重新生成自动化短码？"),
            isPresented: $confirmsShortcodeRegeneration
        ) {
            Button(
                localizer.string("重新生成"),
                role: .destructive
            ) {
                perform {
                    _ = try await model.regenerateAutomationShortcode(
                        for: automation.id
                    )
                }
            }
            Button(localizer.string("取消"), role: .cancel) {}
        } message: {
            Text(
                localizer.string(
                    "旧短码会立即失效，使用旧命令的本地调用将被拒绝。"
                )
            )
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(automation.name)
                    .font(.headline)
                Text(
                    automation.isEnabled
                        ? localizer.string("已启用")
                        : localizer.string("已禁用")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let activeRun {
                Button(localizer.string("取消运行")) {
                    perform {
                        try await model.cancelAutomationRun(activeRun.id)
                    }
                }
                .controlSize(.small)
            } else {
                Button {
                    onRun()
                } label: {
                    Label(
                        localizer.string("立即运行"),
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!automation.canRun)
            }
            Button(localizer.string("编辑"), action: onEdit)
                .controlSize(.small)
            Menu {
                Button(localizer.string("编辑"), action: onEdit)
                if let latestRun = runs.first {
                    Button(localizer.string("定位到最近运行")) {
                        selectedRunID = latestRun.id
                    }
                }
                if let shortcode = automation.externalShortcode {
                    Button(localizer.string("复制外部命令")) {
                        copy("breath trigger \(shortcode)")
                    }
                }
                Divider()
                Button(localizer.string("删除"), role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(localizer.string("更多操作"))
        }
        .pageToolbarLeadingPadding()
        .padding(.trailing, WorkbenchLayout.pageToolbarTrailingInset)
        .frame(height: WorkbenchLayout.pageToolbarHeight)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Prompt")
            Text(automation.prompt)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(localizer.string("配置"))
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                configurationRow(
                    localizer.string("工作区"),
                    automation.workspaceDisplayName
                )
                configurationRow(
                    "Agent",
                    model.adapters.first(where: {
                        $0.kind == automation.agent
                    })?.displayName ?? automation.agent.rawValue
                )
                configurationRow(
                    localizer.string("触发方式"),
                    triggerSummary(automation.trigger, localizer: localizer)
                )
                configurationRow(
                    localizer.string("当前时区"),
                    TimeZone.current.identifier
                )
                if let nextDate = nextOccurrence(for: automation) {
                    configurationRow(
                        localizer.string("下次运行"),
                        nextDate.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                configurationRow(
                    localizer.string("最大运行时长"),
                    localizer.format(
                        "%d 分钟",
                        automation.maximumDurationMinutes
                    )
                )
                configurationRow(
                    localizer.string("工作区访问"),
                    localizer.string("实时只读")
                )
            }
        }
    }

    private var externalTriggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(localizer.string("外部触发"))
            if let shortcode = automation.externalShortcode {
                HStack(spacing: 8) {
                    Text("breath trigger \(shortcode)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button(localizer.string("复制")) {
                        copy("breath trigger \(shortcode)")
                    }
                    .controlSize(.small)
                    Button(localizer.string("重新生成")) {
                        confirmsShortcodeRegeneration = true
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(
                    Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            switch model.automationCLIInstallationStatus {
            case .installed:
                Label(
                    localizer.string("breath 命令已安装"),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            case .notInstalled:
                HStack {
                    Text(
                        localizer.string(
                            "安装到 ~/.local/bin，不修改 PATH，也不需要管理员权限。"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(localizer.string("安装 breath 命令")) {
                        model.installAutomationCLI()
                    }
                    .controlSize(.small)
                }
            case .conflict:
                Label(
                    localizer.string(
                        "~/.local/bin/breath 已被其他文件占用，Breath 不会覆盖它。"
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(localizer.string("最近运行"))
                Spacer()
                Text(localizer.format("最多保留 %d 次", 5))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if runs.isEmpty {
                Text(localizer.string("还没有运行记录。"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(runs) { run in
                        Button {
                            selectedRunID = run.id
                            perform {
                                try await model.markAutomationRunViewed(run.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(statusColor(run.status))
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)
                                Text(statusLabel(run.status, localizer: localizer))
                                    .frame(width: 70, alignment: .leading)
                                Text(
                                    triggerSourceLabel(
                                        run.triggerSource,
                                        localizer: localizer
                                    )
                                )
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !run.isViewed
                                    && run.status.contributesToUnreadCount
                                {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                        .accessibilityLabel(
                                            localizer.string("未查看")
                                        )
                                }
                                Text(run.queuedAt, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(
                                selectedRunID == run.id
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(statusLabel(run.status, localizer: localizer))，"
                                + triggerSourceLabel(
                                    run.triggerSource,
                                    localizer: localizer
                                )
                        )
                        if run.id != runs.last?.id {
                            Divider().padding(.leading, 10)
                        }
                    }
                }
                .background(
                    Color.primary.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }

            if let selectedRun {
                runOutput(selectedRun)
            }
        }
    }

    @ViewBuilder
    private func runOutput(_ run: AutomationRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusLabel(run.status, localizer: localizer))
                    .font(.subheadline.weight(.semibold))
                if let startedAt = run.startedAt {
                    Text(startedAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let duration = run.effectiveDuration {
                    Text(
                        localizer.format(
                            "%.1f 秒",
                            duration
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let output = run.finalOutput {
                    Button(localizer.string("复制")) {
                        copy(output)
                    }
                    .controlSize(.small)
                }
            }
            Grid(
                alignment: .leading,
                horizontalSpacing: 16,
                verticalSpacing: 5
            ) {
                if let endedAt = run.endedAt {
                    runMetadataRow(
                        localizer.string("结束时间"),
                        endedAt.formatted(
                            date: .abbreviated,
                            time: .standard
                        )
                    )
                }
                if let scheduledAt = run.scheduledAt {
                    runMetadataRow(
                        localizer.string("计划时间"),
                        scheduledAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                runMetadataRow(
                    "Agent",
                    model.adapters.first(where: {
                        $0.kind == run.agent
                    })?.displayName ?? run.agent.rawValue
                )
                if let modelName = run.model {
                    runMetadataRow(localizer.string("模型"), modelName)
                }
                if let commit = run.startingGitCommit {
                    runMetadataRow(
                        localizer.string("起始 Git Commit"),
                        commit
                    )
                }
                runMetadataRow(
                    localizer.string("工作区快照"),
                    run.workspaceMayChangeDuringRun
                        ? localizer.string("实时目录，运行期间可能变化")
                        : localizer.string("固定快照")
                )
            }
            .font(.caption)
            if let output = run.finalOutput {
                MarkdownAutomationOutput(output: output)
                if run.outputWasTruncated {
                    Label(
                        localizer.string("输出超过 256 KiB，已保留开头和结尾。"),
                        systemImage: "scissors"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if let error = run.errorSummary {
                Text(localizer.string(error))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else if let missed = run.missedOccurrences {
                Text(
                    localizer.format(
                        "错过 %d 次计划，从 %@ 到 %@。",
                        missed.count,
                        missed.firstScheduledAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ),
                        missed.lastScheduledAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                )
                .foregroundStyle(.secondary)
            } else {
                Text(localizer.string("这次运行没有最终输出。"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var activeRun: AutomationRun? {
        runs.first { $0.status == .running || $0.status == .queued }
    }

    private var selectedRun: AutomationRun? {
        guard let selectedRunID else { return nil }
        return runs.first { $0.id == selectedRunID }
    }

    private func selectDefaultRunIfNeeded() {
        guard selectedRunID == nil else { return }
        selectedRunID = runs.first(where: \.isViewed)?.id
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
    }

    private func configurationRow(
        _ label: String,
        _ value: String
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func runMetadataRow(
        _ label: String,
        _ value: String
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await operation()
            } catch {
                model.lastError = localizer.string(
                    error.localizedDescription
                )
            }
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: language)
    }
}

private struct MarkdownAutomationOutput: View {
    let output: String

    var body: some View {
        Group {
            if let attributed = try? AttributedString(markdown: output) {
                Text(attributed)
            } else {
                Text(output)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum AutomationTriggerChoice: String, CaseIterable, Identifiable {
    case manual
    case once
    case daily
    case weekly
    case interval
    case cron
    case external

    var id: Self { self }
}

private struct AutomationEditorSheet: View {
    @ObservedObject var model: BreathApplicationModel
    let automation: Automation?
    let onSaved: (AutomationID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.applicationLanguage) private var language
    @State private var name: String
    @State private var workspaceID: WorkspaceID?
    @State private var prompt: String
    @State private var agent: AgentKind?
    @State private var triggerChoice: AutomationTriggerChoice
    @State private var onceDate: Date
    @State private var timeOfDay: Date
    @State private var weekdays: Set<Int>
    @State private var intervalValue: Int
    @State private var intervalUnit: AutomationIntervalUnit
    @State private var cronExpression: String
    @State private var maximumDurationMinutes: Int
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(
        model: BreathApplicationModel,
        automation: Automation?,
        onSaved: @escaping (AutomationID) -> Void
    ) {
        self.model = model
        self.automation = automation
        self.onSaved = onSaved
        let calendar = Calendar.current
        let now = Date()
        let defaultTime = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
        _name = State(initialValue: automation?.name ?? "")
        _workspaceID = State(
            initialValue: automation?.workspaceID
                ?? model.snapshot.workspaces.first?.id
        )
        _prompt = State(initialValue: automation?.prompt ?? "")
        _agent = State(
            initialValue: automation?.agent
                ?? model.availableAutomationAgents.first?.kind
        )
        _triggerChoice = State(
            initialValue: Self.choice(for: automation?.trigger ?? .manual)
        )
        _onceDate = State(
            initialValue: {
                guard let automation,
                      case .once(let date) = automation.trigger
                else {
                    return now.addingTimeInterval(3_600)
                }
                return date
            }()
        )
        _timeOfDay = State(
            initialValue: Self.timeDate(
                for: automation?.trigger,
                fallback: defaultTime,
                calendar: calendar
            )
        )
        _weekdays = State(
            initialValue: {
                guard let automation,
                      case .weekly(let days, _, _) = automation.trigger
                else {
                    return [2]
                }
                return Set(days)
            }()
        )
        _intervalValue = State(
            initialValue: {
                guard let automation,
                      case .interval(let interval) = automation.trigger
                else {
                    return 15
                }
                return interval.value
            }()
        )
        _intervalUnit = State(
            initialValue: {
                guard let automation,
                      case .interval(let interval) = automation.trigger
                else {
                    return .minutes
                }
                return interval.unit
            }()
        )
        _cronExpression = State(
            initialValue: {
                guard let automation,
                      case .cron(let expression) = automation.trigger
                else {
                    return "0 9 * * 1-5"
                }
                return expression
            }()
        )
        _maximumDurationMinutes = State(
            initialValue: automation?.maximumDurationMinutes ?? 60
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    automation == nil
                        ? localizer.string("新建自动化")
                        : localizer.string("编辑自动化")
                )
                .font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()
            Form {
                TextField(localizer.string("名称"), text: $name)
                Picker(
                    localizer.string("所属工作区"),
                    selection: $workspaceID
                ) {
                    if model.snapshot.workspaces.isEmpty {
                        Text(localizer.string("没有可选工作区"))
                            .tag(nil as WorkspaceID?)
                            .disabled(true)
                    }
                    ForEach(model.snapshot.workspaces) { workspace in
                        Text(workspace.displayName)
                            .tag(workspace.id as WorkspaceID?)
                    }
                }
                Picker("Agent", selection: $agent) {
                    ForEach(model.automationAgentOptions) { option in
                        Text(agentOptionLabel(option))
                            .tag(option.adapter.kind as AgentKind?)
                            .disabled(!option.availability.isAvailable)
                    }
                }
                if model.availableAutomationAgents.isEmpty {
                    Text(
                        localizer.string(
                            "没有兼容的 Agent。请先安装或升级一个支持的 Agent CLI。"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let selectedAgentReason {
                    Text(localizer.string(selectedAgentReason))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt")
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(minHeight: 130)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                }
                Picker(
                    localizer.string("触发方式"),
                    selection: $triggerChoice
                ) {
                    ForEach(AutomationTriggerChoice.allCases) { choice in
                        Text(triggerChoiceLabel(choice)).tag(choice)
                    }
                }
                triggerFields
                if showsTimeZone {
                    LabeledContent(
                        localizer.string("当前时区"),
                        value: TimeZone.current.identifier
                    )
                }
                if triggerChoice != .cron,
                   let nextDate = triggerPreview?.first
                {
                    LabeledContent(
                        localizer.string("下次运行"),
                        value: nextDate.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                Stepper(value: $maximumDurationMinutes, step: 1) {
                    Text(
                        localizer.format(
                            "最大运行时长：%d 分钟",
                            maximumDurationMinutes
                        )
                    )
                }
                if let validationMessage {
                    Label(
                        validationMessage,
                        systemImage: "exclamationmark.circle"
                    )
                    .foregroundStyle(.red)
                }
                Text(
                    localizer.string(
                        "Agent 直接读取真实工作区，但 macOS 沙盒会阻止它修改项目文件。"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(localizer.string("取消")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(localizer.string("保存")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || !canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 620)
        .onChange(of: maximumDurationMinutes) { _, value in
            if value < 1 {
                maximumDurationMinutes = 1
            }
        }
    }

    @ViewBuilder
    private var triggerFields: some View {
        switch triggerChoice {
        case .manual:
            EmptyView()
        case .external:
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    localizer.string(
                        "保存后会生成 breath trigger 短码。"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if model.automationCLIInstallationStatus == .notInstalled {
                    Button(localizer.string("安装 breath 命令")) {
                        model.installAutomationCLI()
                    }
                    .controlSize(.small)
                } else if model.automationCLIInstallationStatus == .conflict {
                    Label(
                        localizer.string(
                            "~/.local/bin/breath 已被其他文件占用，Breath 不会覆盖它。"
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        case .once:
            DatePicker(
                localizer.string("运行时间"),
                selection: $onceDate
            )
        case .daily:
            DatePicker(
                localizer.string("每天"),
                selection: $timeOfDay,
                displayedComponents: .hourAndMinute
            )
        case .weekly:
            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.string("星期"))
                HStack(spacing: 5) {
                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(
                            shortWeekday(weekday),
                            isOn: Binding(
                                get: { weekdays.contains(weekday) },
                                set: { selected in
                                    if selected {
                                        weekdays.insert(weekday)
                                    } else {
                                        weekdays.remove(weekday)
                                    }
                                }
                            )
                        )
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
                DatePicker(
                    localizer.string("时间"),
                    selection: $timeOfDay,
                    displayedComponents: .hourAndMinute
                )
            }
        case .interval:
            HStack {
                Stepper(
                    localizer.format("每 %d", intervalValue),
                    value: $intervalValue,
                    in: intervalRange
                )
                Picker("", selection: $intervalUnit) {
                    Text(localizer.string("分钟"))
                        .tag(AutomationIntervalUnit.minutes)
                    Text(localizer.string("小时"))
                        .tag(AutomationIntervalUnit.hours)
                    Text(localizer.string("天"))
                        .tag(AutomationIntervalUnit.days)
                }
                .labelsHidden()
                .frame(width: 100)
            }
        case .cron:
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    localizer.string("Cron 表达式"),
                    text: $cronExpression
                )
                .font(.system(.body, design: .monospaced))
                Text(
                    localizer.string(
                        "标准五字段：分钟 小时 日 月 星期，不支持秒和宏。"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let dates = cronPreview {
                    ForEach(dates, id: \.self) { date in
                        Text(
                            date.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text(localizer.string("Cron 表达式无效。"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && workspaceID != nil
            && agent != nil
            && selectedAgentIsAvailable
            && triggerIsValid
    }

    private var triggerIsValid: Bool {
        switch triggerChoice {
        case .weekly:
            !weekdays.isEmpty
        case .once:
            onceDate > Date()
        case .interval:
            (60...(30 * 86_400)).contains(
                AutomationInterval(
                    value: intervalValue,
                    unit: intervalUnit
                ).duration
            )
        case .cron:
            cronPreview != nil
        default:
            true
        }
    }

    private var cronPreview: [Date]? {
        guard triggerChoice == .cron else { return [] }
        return triggerPreview
    }

    private var triggerPreview: [Date]? {
        guard triggerIsStructurallyValid else { return nil }
        return try? AutomationService.previewOccurrences(
            for: trigger,
            after: Date(),
            timeZone: .current,
            count: triggerChoice == .cron ? 3 : 1
        )
    }

    private var triggerIsStructurallyValid: Bool {
        switch triggerChoice {
        case .weekly:
            !weekdays.isEmpty
        case .once:
            onceDate > Date()
        case .interval:
            (60...(30 * 86_400)).contains(
                AutomationInterval(
                    value: intervalValue,
                    unit: intervalUnit
                ).duration
            )
        case .cron:
            !cronExpression.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        case .manual, .daily, .external:
            true
        }
    }

    private var showsTimeZone: Bool {
        switch triggerChoice {
        case .once, .daily, .weekly, .cron:
            true
        case .manual, .interval, .external:
            false
        }
    }

    private var intervalRange: ClosedRange<Int> {
        switch intervalUnit {
        case .minutes: 1...(30 * 24 * 60)
        case .hours: 1...(30 * 24)
        case .days: 1...30
        }
    }

    private var selectedAgentIsAvailable: Bool {
        guard let agent else { return false }
        return model.automationAgentOptions.first {
            $0.adapter.kind == agent
        }?.availability.isAvailable == true
    }

    private var selectedAgentReason: String? {
        guard let agent else { return nil }
        return model.automationAgentOptions.first {
            $0.adapter.kind == agent
        }?.availability.unavailableReason
            ?? localizer.string("所选 Agent 当前不可用于自动化。")
    }

    private func agentOptionLabel(_ option: AutomationAgentOption) -> String {
        guard let reason = option.availability.unavailableReason else {
            return option.adapter.displayName
        }
        return "\(option.adapter.displayName) · \(reason)"
    }

    private func save() {
        validationMessage = nil
        guard let workspaceID, let agent else {
            validationMessage = localizer.string("请选择工作区和 Agent。")
            return
        }
        let draft = AutomationDraft(
            name: name,
            workspaceID: workspaceID,
            prompt: prompt,
            agent: agent,
            trigger: trigger,
            maximumDurationMinutes: maximumDurationMinutes
        )
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                if let automation {
                    try await model.updateAutomation(
                        automation.id,
                        with: draft
                    )
                    onSaved(automation.id)
                } else {
                    let id = try await model.createAutomation(draft)
                    onSaved(id)
                }
            } catch {
                validationMessage = localizer.string(
                    error.localizedDescription
                )
            }
        }
    }

    private var trigger: AutomationTrigger {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: timeOfDay
        )
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        return switch triggerChoice {
        case .manual:
            .manual
        case .once:
            .once(onceDate)
        case .daily:
            .daily(hour: hour, minute: minute)
        case .weekly:
            .weekly(
                weekdays: weekdays.sorted(),
                hour: hour,
                minute: minute
            )
        case .interval:
            .interval(
                AutomationInterval(
                    value: intervalValue,
                    unit: intervalUnit
                )
            )
        case .cron:
            .cron(cronExpression)
        case .external:
            .external
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: language)
    }

    private func triggerChoiceLabel(_ choice: AutomationTriggerChoice) -> String {
        switch choice {
        case .manual: localizer.string("手动")
        case .once: localizer.string("单次")
        case .daily: localizer.string("每天")
        case .weekly: localizer.string("每周")
        case .interval: localizer.string("固定间隔")
        case .cron: localizer.string("自定义 Cron")
        case .external: localizer.string("外部命令")
        }
    }

    private func shortWeekday(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols[weekday - 1]
    }

    private static func choice(
        for trigger: AutomationTrigger
    ) -> AutomationTriggerChoice {
        switch trigger {
        case .manual: .manual
        case .once: .once
        case .daily: .daily
        case .weekly: .weekly
        case .interval: .interval
        case .cron: .cron
        case .external: .external
        }
    }

    private static func timeDate(
        for trigger: AutomationTrigger?,
        fallback: Date,
        calendar: Calendar
    ) -> Date {
        let hour: Int
        let minute: Int
        switch trigger {
        case .daily(let storedHour, let storedMinute),
             .weekly(_, let storedHour, let storedMinute):
            hour = storedHour
            minute = storedMinute
        default:
            return fallback
        }
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: fallback
        ) ?? fallback
    }
}

private func triggerSummary(
    _ trigger: AutomationTrigger,
    localizer: ApplicationLocalizer
) -> String {
    switch trigger {
    case .manual:
        localizer.string("手动")
    case .once(let date):
        "\(localizer.string("单次")) · "
            + date.formatted(date: .abbreviated, time: .shortened)
    case .daily(let hour, let minute):
        "\(localizer.string("每天")) · "
            + String(format: "%02d:%02d", hour, minute)
    case .weekly(let weekdays, let hour, let minute):
        "\(localizer.string("每周")) "
            + "\(weekdays.map(String.init).joined(separator: ",")) · "
            + String(format: "%02d:%02d", hour, minute)
    case .interval(let interval):
        "\(localizer.string("每")) \(interval.value) "
            + intervalUnitLabel(interval.unit, localizer: localizer)
    case .cron(let expression):
        "Cron · \(expression)"
    case .external:
        localizer.string("外部命令")
    }
}

private func intervalUnitLabel(
    _ unit: AutomationIntervalUnit,
    localizer: ApplicationLocalizer
) -> String {
    switch unit {
    case .minutes: localizer.string("分钟")
    case .hours: localizer.string("小时")
    case .days: localizer.string("天")
    }
}

private func statusLabel(
    _ status: AutomationRunStatus,
    localizer: ApplicationLocalizer
) -> String {
    switch status {
    case .queued: localizer.string("已排队")
    case .running: localizer.string("运行中")
    case .succeeded: localizer.string("成功")
    case .failed: localizer.string("失败")
    case .timedOut: localizer.string("已超时")
    case .canceled: localizer.string("已取消")
    case .interrupted: localizer.string("已中断")
    case .skipped: localizer.string("已跳过")
    case .missed: localizer.string("已错过")
    }
}

private func statusColor(_ status: AutomationRunStatus) -> Color {
    switch status {
    case .succeeded: .green
    case .failed, .timedOut: .red
    case .interrupted, .missed: .orange
    case .running: .blue
    case .queued: .secondary
    case .canceled, .skipped: .secondary
    }
}

private func triggerSourceLabel(
    _ source: AutomationTriggerSource,
    localizer: ApplicationLocalizer
) -> String {
    switch source {
    case .manual: localizer.string("手动")
    case .scheduled: localizer.string("计划")
    case .external: localizer.string("外部命令")
    }
}

private func nextOccurrence(for automation: Automation) -> Date? {
    guard automation.isEnabled, automation.canRun else { return nil }
    switch automation.trigger {
    case .manual, .external:
        return nil
    default:
        return try? AutomationService.previewOccurrences(
            for: automation.trigger,
            anchor: automation.intervalAnchor,
            after: Date(),
            timeZone: .current,
            count: 1
        ).first
    }
}
