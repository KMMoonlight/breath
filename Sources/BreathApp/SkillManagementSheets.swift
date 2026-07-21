import BreathCore
import BreathSkills
import SwiftUI
import UniformTypeIdentifiers

struct SkillInstallationWizard: View {
    let service: GlobalSkillsService
    let snapshot: GlobalSkillsSnapshot
    let language: ApplicationLanguage
    let onComplete: (SkillOperationResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.source
    @State private var sourceMode = SourceMode.zip
    @State private var githubInput = ""
    @State private var skillsShInput = ""
    @State private var showsFileImporter = false
    @State private var batch: SkillCandidateBatch?
    @State private var selectedCandidateIDs: Set<UUID> = []
    @State private var selectedAgents: Set<AgentKind> = []
    @State private var searchResults: [SkillsShSearchResult] = []
    @State private var preview: SkillInstallationPreview?
    @State private var replacementChoices: [SkillInstallationTargetID: SkillReplacementChoice] = [:]
    @State private var confirmedRiskCandidateIDs: Set<UUID> = []
    @State private var result: SkillOperationResult?
    @State private var isWorking = false
    @State private var sourceMessage: String?
    @State private var sourceActivity: SourceActivity?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.string("安装 Skill"))
                        .font(.title2.weight(.semibold))
                    Text(stepTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isWorking, sourceActivity == nil {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(20)
            Divider()
            Group {
                switch step {
                case .source: sourceStep
                case .candidates: candidateStep
                case .targets: targetStep
                case .review: reviewStep
                case .result: resultStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { response in
            switch response {
            case .success(let urls):
                guard let url = urls.first else { return }
                discoverZip(url)
            case .failure(let error):
                sourceMessage = localizer.string(error.localizedDescription)
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onDisappear {
            guard result == nil, let batch else { return }
            Task { await service.cancel(batch) }
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: language)
    }

    private var stepTitle: String {
        switch step {
        case .source: localizer.string("选择来源")
        case .candidates: localizer.string("选择候选 Skill")
        case .targets: localizer.string("选择 Skill 安装目标")
        case .review: localizer.string("检查并确认")
        case .result: localizer.string("安装结果")
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker(localizer.string("来源"), selection: $sourceMode) {
                Text("ZIP").tag(SourceMode.zip)
                Text("GitHub").tag(SourceMode.github)
                Text("skills.sh").tag(SourceMode.skillsSh)
            }
            .pickerStyle(.segmented)

            switch sourceMode {
            case .zip: zipSourcePane
            case .github: githubSourcePane
            case .skillsSh: skillsShSourcePane
            }

            if let sourceMessage {
                Label(sourceMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: sourceMode) { _, _ in
            sourceMessage = nil
        }
    }

    private var zipSourcePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizer.string("选择 ZIP 文件"))
                .font(.headline)
            Text(localizer.string("ZIP 可以包含一个或多个 Skill；导入前不会执行其中的脚本。"))
                .foregroundStyle(.secondary)
            Button(localizer.string("选择 ZIP…")) {
                showsFileImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var githubSourcePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizer.string("输入公开 GitHub Repo"))
                .font(.headline)
            HStack {
                TextField("owner/repo", text: $githubInput)
                    .textFieldStyle(.roundedBorder)
                if sourceActivity == .github {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(localizer.string("正在下载…"))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Button(localizer.string("下载并检查…"), action: resolveGitHubInput)
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            githubInput.trimmingCharacters(in: .whitespaces).isEmpty
                                || isWorking
                        )
                }
            }
            Text(localizer.string("仅支持无需认证的公开 GitHub Repo；私有 Repo 请改用 ZIP。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(localizer.string(
                "选择“下载并检查…”后，Breath 会从 GitHub 下载来源并进入安装内容检查；确认前不会写入任何 Agent 目录。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var skillsShSourcePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizer.string("搜索 skills.sh"))
                .font(.headline)
            HStack {
                TextField(localizer.string("搜索关键词"), text: $skillsShInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(searchSkillsSh)
                Button(localizer.string("搜索"), action: searchSkillsSh)
                    .buttonStyle(.borderedProminent)
                    .disabled(skillsShInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !searchResults.isEmpty {
                Text(localizer.string(
                    "选择“下载并检查…”后，Breath 会从 GitHub 下载来源并进入安装内容检查；确认前不会写入任何 Agent 目录。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List(searchResults) { item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).fontWeight(.medium)
                            Text(item.description ?? localizer.string("暂无说明"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(item.source)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                            HStack(spacing: 6) {
                                RiskBadge(audit: item.securityAudit, localizer: localizer)
                                Text(localizer.string(item.securityAudit.summary))
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                            if let checkedAt = item.securityAudit.checkedAt {
                                Text(localizer.format(
                                    "检查于 %@",
                                    checkedAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                ))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(localizer.format("%d 次安装", item.installs))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if sourceActivity == .catalog(item.id) {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(localizer.string("正在下载…"))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            } else {
                                Button(localizer.string("下载并检查…")) {
                                    discoverCatalogResult(item)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isWorking)
                                .accessibilityHint(localizer.string(
                                    "从 GitHub 下载来源并进入安装内容检查"
                                ))
                            }
                        }
                    }
                }
                .frame(minHeight: 260)
            }
        }
    }

    private var candidateStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizer.string("只会安装你明确选择的候选 Skill。"))
                .foregroundStyle(.secondary)
            List {
                ForEach(batch?.candidates ?? []) { candidate in
                    Toggle(isOn: membership(candidate.id, in: $selectedCandidateIDs)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(candidate.name).fontWeight(.semibold)
                                if candidate.securityAudit.riskLevel != .unknown {
                                    RiskBadge(
                                        audit: candidate.securityAudit,
                                        localizer: localizer
                                    )
                                }
                            }
                            Text(candidate.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(localizer.format("%d 个文件", candidate.files.count))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            ForEach(candidate.warnings) { warning in
                                Label(
                                    localizedSkillMessage(warning.message, localizer: localizer),
                                    systemImage: "exclamationmark.triangle"
                                )
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                if let rejections = batch?.rejectedCandidates,
                   !rejections.isEmpty
                {
                    Section(localizer.string("无法安装的候选 Skill")) {
                        ForEach(rejections) { rejection in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rejection.sourceRelativePath)
                                    .font(.body.monospaced())
                                Text(localizer.string(rejection.message))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private var targetStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizer.string("每次安装默认不选择任何 Agent。每个目标将获得完整独立副本。"))
                .foregroundStyle(.secondary)
            List(snapshot.targets) { target in
                Toggle(isOn: membership(target.agent, in: $selectedAgents)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.displayName).fontWeight(.medium)
                        Text(target.directory?.path ?? localizer.string("目录无法解析"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if case .unavailable(let reason) = target.availability {
                            Text(localizedSkillMessage(reason, localizer: localizer))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!target.availability.isSelectable)
            }
        }
        .padding(20)
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let batch {
                    LabeledContent(localizer.string("来源"), value: batch.sourceLabel)
                }
                ForEach(preview?.items ?? []) { item in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent(localizer.string("说明"), value: item.candidate.description)
                            if let license = item.candidate.declarations.license {
                                LabeledContent(localizer.string("许可证"), value: license)
                            }
                            if let compatibility = item.candidate.declarations.compatibility {
                                LabeledContent(localizer.string("兼容性"), value: compatibility)
                            }
                            if let metadata = item.candidate.declarations.metadata {
                                LabeledContent(localizer.string("元数据声明"), value: metadata)
                            }
                            if let allowedTools = item.candidate.declarations.allowedTools {
                                LabeledContent(localizer.string("允许的工具"), value: allowedTools)
                            }
                            ForEach(item.candidate.warnings) { warning in
                                Label(
                                    localizedSkillMessage(warning.message, localizer: localizer),
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                            LabeledContent(localizer.string("Agent"), value: item.agentDisplayName)
                            LabeledContent(localizer.string("真实目录"), value: item.targetDirectory.path)
                            if let provenance = item.candidate.remoteProvenance {
                                LabeledContent(
                                    localizer.string("仓库"),
                                    value: provenance.repository
                                )
                                LabeledContent(
                                    localizer.string("引用"),
                                    value: "\(provenance.reference.kind.rawValue) · \(provenance.reference.value)"
                                )
                                LabeledContent(
                                    localizer.string("提交"),
                                    value: provenance.resolvedCommit
                                )
                            }
                            LabeledContent(
                                localizer.string("写入行为"),
                                value: item.action.displayName(localizer)
                            )
                            if let existingDescription = item.existingDescription,
                               item.action != .alreadyInstalled
                            {
                                Divider()
                                Text(localizer.string("现有说明"))
                                    .font(.caption.weight(.semibold))
                                Text(existingDescription).foregroundStyle(.secondary)
                                Picker(
                                    localizer.string("同名处理"),
                                    selection: replacementBinding(for: item)
                                ) {
                                    Text(localizer.string("跳过（默认）")).tag(SkillReplacementChoice.skip)
                                    Text(localizer.string("覆盖")).tag(SkillReplacementChoice.replace)
                                }
                                .pickerStyle(.segmented)
                            }
                            DisclosureGroup(localizer.format("文件（%d）", item.candidate.files.count)) {
                                ForEach(item.candidate.files) { file in
                                    Text(file.relativePath)
                                        .font(.caption.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            DisclosureGroup(localizer.format("文件变化（%d）", item.changes.count)) {
                                ForEach(item.changes) { change in
                                    Text("\(change.kind.rawValue) · \(change.relativePath)")
                                        .font(.caption.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            DisclosureGroup("SKILL.md") {
                                Text(item.candidate.manifest)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            LabeledContent(
                                localizer.string("安全审计"),
                                value: item.candidate.securityAudit.riskLevel.displayName(localizer)
                            )
                            Text(localizer.string(item.candidate.securityAudit.summary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let checkedAt = item.candidate.securityAudit.checkedAt {
                                Text(localizer.format(
                                    "检查于 %@",
                                    checkedAt.formatted(date: .abbreviated, time: .shortened)
                                ))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            if item.candidate.securityAudit.riskLevel.requiresExtraConfirmation {
                                Toggle(
                                    localizer.string("我已审阅高风险提示并仍要安装"),
                                    isOn: membership(
                                        item.candidate.id,
                                        in: $confirmedRiskCandidateIDs
                                    )
                                )
                                .toggleStyle(.checkbox)
                                .foregroundStyle(.red)
                            }
                        }
                    } label: {
                        Text("\(item.candidate.name) · \(item.agentDisplayName)")
                    }
                }
            }
            .padding(22)
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(result?.items ?? []) { item in
                HStack(alignment: .top) {
                    Image(systemName: item.status.presentation.systemImage)
                        .foregroundStyle(item.status.presentation.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.skillName) · \(item.agentDisplayName)")
                            .fontWeight(.medium)
                        Text(localizer.string(item.message))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let diagnostic = item.diagnostic {
                            Text(diagnostic)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Text(localizer.string("新的或重启后的 Agent 会话可能才会加载变更；Breath 没有停止任何运行中会话。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Button(step == .result ? localizer.string("关闭") : localizer.string("取消")) {
                if step == .result, let result {
                    onComplete(result)
                } else {
                    if let batch { Task { await service.cancel(batch) } }
                    dismiss()
                }
            }
            Spacer()
            if step != .source && step != .result {
                Button(localizer.string("上一步"), action: goBack)
                    .disabled(isWorking)
            }
            switch step {
            case .source:
                if batch != nil {
                    Button(localizer.string("下一步")) { step = .candidates }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                }
            case .candidates:
                Button(localizer.string("下一步")) { step = .targets }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCandidateIDs.isEmpty)
            case .targets:
                Button(localizer.string("下一步"), action: preparePreview)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAgents.isEmpty || isWorking)
            case .review:
                Button(localizer.string("安装"), action: performInstall)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canInstall || isWorking)
            case .result:
                EmptyView()
            }
        }
        .padding(16)
    }

    private var canInstall: Bool {
        guard let preview else { return false }
        let highRiskIDs = Set(preview.items.compactMap {
            $0.candidate.securityAudit.riskLevel.requiresExtraConfirmation
                ? $0.candidate.id
                : nil
        })
        return highRiskIDs.isSubset(of: confirmedRiskCandidateIDs)
    }

    private func discoverZip(_ url: URL) {
        runSourceTask {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return try await service.discoverSkills(inZip: url)
        }
    }

    private func resolveGitHubInput() {
        let input = githubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        runSourceTask(activity: .github) {
            try await service.discoverSkills(fromGitHub: input)
        }
    }

    private func searchSkillsSh() {
        let input = skillsShInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        sourceMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                searchResults = try await service.searchSkillsSh(query: input)
                if searchResults.isEmpty {
                    sourceMessage = localizer.string("没有找到 skills.sh 结果")
                }
            } catch {
                searchResults = []
                sourceMessage = localizedSourceMessage(for: error)
            }
        }
    }

    private func discoverCatalogResult(_ item: SkillsShSearchResult) {
        runSourceTask(activity: .catalog(item.id)) {
            try await service.discoverSkill(fromSkillsSh: item)
        }
    }

    private func runSourceTask(
        activity: SourceActivity? = nil,
        _ operation: @escaping @Sendable () async throws -> SkillCandidateBatch
    ) {
        sourceMessage = nil
        isWorking = true
        sourceActivity = activity
        Task {
            defer {
                isWorking = false
                sourceActivity = nil
            }
            do {
                if let batch { await service.cancel(batch) }
                let discovered = try await operation()
                batch = discovered
                selectedCandidateIDs = []
                selectedAgents = []
                replacementChoices = [:]
                confirmedRiskCandidateIDs = []
                step = .candidates
            } catch {
                sourceMessage = localizedSourceMessage(for: error)
            }
        }
    }

    private func localizedSourceMessage(for error: Error) -> String {
        return localizer.string(error.localizedDescription)
    }

    private func preparePreview() {
        guard let batch else { return }
        isWorking = true
        Task {
            preview = await service.previewInstallation(
                batch: batch,
                candidateIDs: selectedCandidateIDs,
                targetAgents: selectedAgents,
                replacementChoices: replacementChoices
            )
            isWorking = false
            step = .review
        }
    }

    private func refreshPreview() {
        guard step == .review else { return }
        preparePreview()
    }

    private func performInstall() {
        guard let preview else { return }
        isWorking = true
        Task {
            result = await service.install(
                preview,
                confirmedRiskCandidateIDs: confirmedRiskCandidateIDs
            )
            isWorking = false
            step = .result
        }
    }

    private func goBack() {
        switch step {
        case .source: break
        case .candidates: step = .source
        case .targets: step = .candidates
        case .review: step = .targets
        case .result: break
        }
    }

    private func replacementBinding(
        for item: SkillInstallationPreviewItem
    ) -> Binding<SkillReplacementChoice> {
        Binding(
            get: { replacementChoices[item.targetID] ?? .skip },
            set: { choice in
                replacementChoices[item.targetID] = choice
                refreshPreview()
            }
        )
    }

    private func membership<Element: Hashable>(
        _ element: Element,
        in selection: Binding<Set<Element>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(element) },
            set: { selected in
                if selected { selection.wrappedValue.insert(element) }
                else { selection.wrappedValue.remove(element) }
            }
        )
    }

    private enum Step {
        case source
        case candidates
        case targets
        case review
        case result
    }

    private enum SourceMode: Hashable {
        case zip
        case github
        case skillsSh
    }

    private enum SourceActivity: Equatable {
        case github
        case catalog(String)
    }
}

struct SkillUpdateReviewView: View {
    let service: GlobalSkillsService
    let update: SkillAvailableUpdate
    let language: ApplicationLanguage
    let onComplete: (SkillOperationResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAgents: Set<AgentKind>
    @State private var preview: SkillInstallationPreview?
    @State private var result: SkillOperationResult?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmedRiskCandidateIDs: Set<UUID> = []

    init(
        service: GlobalSkillsService,
        update: SkillAvailableUpdate,
        language: ApplicationLanguage,
        onComplete: @escaping (SkillOperationResult) -> Void
    ) {
        self.service = service
        self.update = update
        self.language = language
        self.onComplete = onComplete
        _selectedAgents = State(initialValue: Set(
            update.targets.filter(\.isSelectedByDefault).map(\.agent)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(localizer.format("更新 %@", update.skillName))
                        .font(.title2.weight(.semibold))
                    Text("\(update.oldCommits.joined(separator: ", ")) → \(update.newCommit)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
            }
            .padding(20)
            Divider()
            if let result {
                List(result.items) { item in
                    HStack(alignment: .top) {
                        Image(systemName: item.status.presentation.systemImage)
                            .foregroundStyle(item.status.presentation.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.skillName) · \(item.agentDisplayName)")
                                .fontWeight(.medium)
                            Text(localizer.string(item.message))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let diagnostic = item.diagnostic {
                                Text(diagnostic)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            } else if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(update.candidate.description).font(.headline)
                        ForEach(preview.items) { item in
                            GroupBox("\(item.agentDisplayName) · \(item.action.displayName(localizer))") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.targetDirectory.path).font(.caption.monospaced())
                                    if let existingDescription = item.existingDescription {
                                        LabeledContent(
                                            localizer.string("现有说明"),
                                            value: existingDescription
                                        )
                                        LabeledContent(
                                            localizer.string("新说明"),
                                            value: item.candidate.description
                                        )
                                    }
                                    if item.changes.isEmpty {
                                        Text(localizer.string("没有文件变化"))
                                    } else {
                                        ForEach(item.changes) { change in
                                            Text("\(change.kind.rawValue) · \(change.relativePath)")
                                                .font(.caption.monospaced())
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        DisclosureGroup("SKILL.md") {
                            Text(update.candidate.manifest)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        LabeledContent(
                            localizer.string("安全审计"),
                            value: update.candidate.securityAudit.riskLevel.displayName(localizer)
                        )
                        Text(localizer.string(update.candidate.securityAudit.summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let checkedAt = update.candidate.securityAudit.checkedAt {
                            Text(localizer.format(
                                "检查于 %@",
                                checkedAt.formatted(date: .abbreviated, time: .shortened)
                            ))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        if update.candidate.securityAudit.riskLevel.requiresExtraConfirmation {
                            Toggle(
                                localizer.string("我已审阅高风险提示并仍要安装"),
                                isOn: Binding(
                                    get: {
                                        confirmedRiskCandidateIDs.contains(update.candidate.id)
                                    },
                                    set: { confirmed in
                                        if confirmed {
                                            confirmedRiskCandidateIDs.insert(update.candidate.id)
                                        } else {
                                            confirmedRiskCandidateIDs.remove(update.candidate.id)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                }
            } else {
                List(update.targets) { target in
                    Toggle(isOn: Binding(
                        get: { selectedAgents.contains(target.agent) },
                        set: { enabled in
                            if enabled { selectedAgents.insert(target.agent) }
                            else { selectedAgents.remove(target.agent) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.agentDisplayName).fontWeight(.medium)
                            Text(target.directory.path).font(.caption.monospaced())
                            if target.isLocallyModified {
                                Text(localizer.string("本地已修改，默认不选择"))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            if target.isSymbolicLink {
                                Text(localizer.string("更新后该链接会变成此 Agent 的独立实体目录"))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Divider()
            HStack {
                if result == nil {
                    Button(localizer.string("取消")) { dismiss() }
                }
                Spacer()
                if let result {
                    Button(localizer.string("关闭")) { onComplete(result) }
                        .buttonStyle(.borderedProminent)
                } else if preview == nil {
                    Button(localizer.string("预览更新"), action: makePreview)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedAgents.isEmpty || isWorking)
                } else {
                    Button(localizer.string("返回")) { self.preview = nil }
                    Button(localizer.string("安装更新"), action: install)
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            isWorking
                                || (update.candidate.securityAudit.riskLevel.requiresExtraConfirmation
                                    && !confirmedRiskCandidateIDs.contains(update.candidate.id))
                        )
                }
            }
            .padding(16)
        }
        .alert("Breath", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(localizer.string("好")) { errorMessage = nil }
        } message: { Text(localizer.string(errorMessage ?? "")) }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: language)
    }

    private func makePreview() {
        isWorking = true
        Task {
            preview = await service.previewUpdate(update, targetAgents: selectedAgents)
            isWorking = false
        }
    }

    private func install() {
        guard let preview else { return }
        isWorking = true
        Task {
            result = await service.install(
                preview,
                confirmedRiskCandidateIDs: confirmedRiskCandidateIDs
            )
            isWorking = false
        }
    }
}

struct SkillUninstallView: View {
    let service: GlobalSkillsService
    let skill: GlobalSkill
    let language: ApplicationLanguage
    let onComplete: (SkillUninstallResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAgents: Set<AgentKind> = []
    @State private var preview: SkillUninstallPreview?
    @State private var result: SkillUninstallResult?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizer.format("卸载 %@", skill.name))
                    .font(.title2.weight(.semibold))
                Text(localizer.string("只会从明确选择的 Agent 中移除 Skill。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            if let result {
                List(result.items) { item in
                    HStack(alignment: .top) {
                        Image(systemName: item.status.presentation.systemImage)
                            .foregroundStyle(item.status.presentation.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.skillName) · \(item.agentDisplayName)")
                                .fontWeight(.medium)
                            Text(localizer.string(item.message))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let diagnostic = item.diagnostic {
                                Text(diagnostic)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            } else if let preview {
                List(preview.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.agentDisplayName).fontWeight(.medium)
                        Text(item.directory.path).font(.caption.monospaced())
                        Text(item.action == .moveToTrash
                            ? localizer.string("移入 macOS 废纸篓，可恢复")
                            : localizer.string("只移除链接，共享目标保持不变"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                List(skill.copies) { copy in
                    Toggle(isOn: Binding(
                        get: { selectedAgents.contains(copy.agent) },
                        set: { enabled in
                            if enabled { selectedAgents.insert(copy.agent) }
                            else { selectedAgents.remove(copy.agent) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(copy.agentDisplayName).fontWeight(.medium)
                            Text(copy.directory.path).font(.caption.monospaced())
                            if copy.isSymbolicLink {
                                Text(localizer.string("外部符号链接"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Divider()
            HStack {
                if result == nil {
                    Button(localizer.string("取消")) { dismiss() }
                }
                Spacer()
                if let result {
                    Button(localizer.string("关闭")) { onComplete(result) }
                        .buttonStyle(.borderedProminent)
                } else if preview == nil {
                    Button(localizer.string("检查卸载"), action: makePreview)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedAgents.isEmpty || isWorking)
                } else {
                    Button(localizer.string("返回")) { self.preview = nil }
                    Button(localizer.string("卸载所选副本"), role: .destructive, action: uninstall)
                        .disabled(isWorking)
                }
            }
            .padding(16)
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: language)
    }

    private func makePreview() {
        isWorking = true
        Task {
            preview = await service.previewUninstall(
                skillID: skill.id,
                targetAgents: selectedAgents
            )
            isWorking = false
        }
    }

    private func uninstall() {
        guard let preview else { return }
        isWorking = true
        Task {
            result = await service.uninstall(preview)
            isWorking = false
        }
    }
}

private struct RiskBadge: View {
    let audit: SkillSecurityAudit
    let localizer: ApplicationLocalizer

    var body: some View {
        Text(audit.riskLevel.displayName(localizer))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(audit.riskLevel.requiresExtraConfirmation ? .red : .secondary)
            .background(.quaternary, in: Capsule())
            .help(audit.summary)
    }
}

private extension SkillRiskLevel {
    func displayName(_ localizer: ApplicationLocalizer) -> String {
        switch self {
        case .unknown: localizer.string("审计未知")
        case .none: localizer.string("无已知风险")
        case .low: localizer.string("低风险")
        case .medium: localizer.string("中风险")
        case .high: localizer.string("高风险")
        case .critical: localizer.string("严重风险")
        }
    }
}

private extension SkillInstallationAction {
    func displayName(_ localizer: ApplicationLocalizer) -> String {
        switch self {
        case .install: localizer.string("安装")
        case .alreadyInstalled: localizer.string("已安装相同内容")
        case .skip: localizer.string("跳过")
        case .replace: localizer.string("覆盖")
        case .unavailable: localizer.string("不可安装")
        }
    }
}

private extension SkillOperationStatus {
    var presentation: (systemImage: String, tint: Color) {
        switch self {
        case .succeeded, .alreadyInstalled: ("checkmark.circle.fill", .green)
        case .skipped: ("forward.circle.fill", .secondary)
        case .failed: ("xmark.octagon.fill", .red)
        }
    }
}
