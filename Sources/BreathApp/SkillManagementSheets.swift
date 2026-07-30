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
    @State private var sourceMode = SourceMode.skillsSh
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
    @State private var sourceMessage: String?
    @State private var activity: Activity?
    @State private var preinstalledAgents: Set<AgentKind> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.string("安装 Skill"))
                        .font(.title2.weight(.semibold))
                    if let stepExplanation {
                        ExplanationLabel(stepExplanation) {
                            Text(stepTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(stepTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
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

    private var isWorking: Bool { activity != nil }

    private var isSearchingSkillsSh: Bool {
        if case .searchingSkillsSh = activity { return true }
        return false
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

    private var stepExplanation: String? {
        switch step {
        case .source, .review:
            nil
        case .candidates:
            localizer.string("只会安装你明确选择的候选 Skill。")
        case .targets:
            localizer.string(
                "每次安装默认不选择任何 Agent。每个目标将获得完整独立副本。"
            )
        case .result:
            localizer.string(
                "新的或重启后的 Agent 会话可能才会加载变更；Breath 没有停止任何运行中会话。"
            )
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker(localizer.string("来源"), selection: $sourceMode) {
                Text("skills.sh").tag(SourceMode.skillsSh)
                Text("GitHub").tag(SourceMode.github)
                Text("ZIP").tag(SourceMode.zip)
            }
            .pickerStyle(.segmented)
            .disabled(isWorking)

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
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: sourceMode) { _, _ in
            sourceMessage = nil
        }
    }

    private var zipSourcePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExplanationLabel(
                localizer.string(
                    "ZIP 可以包含一个或多个 Skill；导入前不会执行其中的脚本。"
                )
            ) {
                Text(localizer.string("选择 ZIP 文件"))
                    .font(.headline)
            }
            if activity == .checkingZip {
                progressStatus("正在检查 ZIP…")
            } else {
                Button(localizer.string("选择 ZIP…")) {
                    showsFileImporter = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
    }

    private var githubSourcePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExplanationLabel(
                localizer.string(
                    "仅支持无需认证的公开 GitHub Repo；私有 Repo 请改用 ZIP。"
                )
            ) {
                Text(localizer.string("输入公开 GitHub Repo"))
                    .font(.headline)
            }
            HStack {
                TextField("owner/repo", text: $githubInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isWorking)
                if activity == .downloadingGitHub {
                    progressStatus("正在下载…")
                } else {
                    Button(localizer.string("安装"), action: resolveGitHubInput)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(localizer.string("安装 GitHub Repo"))
                        .disabled(
                            githubInput.trimmingCharacters(in: .whitespaces).isEmpty
                                || isWorking
                        )
                }
            }
        }
    }

    private var skillsShSourcePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizer.string("搜索 skills.sh"))
                .font(.headline)
            HStack {
                TextField(localizer.string("搜索关键词"), text: $skillsShInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isWorking && !isSearchingSkillsSh)
                if isSearchingSkillsSh {
                    progressStatus("正在搜索…")
                }
            }
            if !searchResults.isEmpty {
                List(searchResults) { item in
                    let installedCopies = installedCopies(matching: item)
                    let installedAgents = installedAgentNames(in: installedCopies)
                    let submitter = catalogSubmitter(for: item)
                    let isInstalled = !installedAgents.isEmpty
                    let installedAgentKinds = Set(installedCopies.map(\.agent))
                    let canInstallToOtherAgent = snapshot.targets.contains {
                        $0.availability.isSelectable
                            && !installedAgentKinds.contains($0.agent)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).fontWeight(.medium)
                            if let submitter {
                                Text(localizer.format("提交者：%@", submitter))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if let description = item.description,
                               !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if item.securityAudit.riskLevel != .unknown {
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
                            if isInstalled {
                                Text(localizer.format(
                                    "已安装于 %@",
                                    installedAgents.joined(separator: ", ")
                                ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(localizer.format("%d 次安装", item.installs))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if activity == .preparingInstalledCopy(item.id) {
                                progressStatus("正在准备本地副本…")
                            } else if activity == .downloadingCatalog(item.id) {
                                progressStatus("正在下载…")
                            } else if isInstalled && !canInstallToOtherAgent {
                                Text(localizer.string("此 Skill 已安装"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button(localizer.string(
                                    isInstalled ? "安装到其他 Agent" : "安装"
                                )) {
                                    beginCatalogInstallation(
                                        item,
                                        installedCopies: installedCopies
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isWorking)
                                .accessibilityLabel(localizer.format(
                                    isInstalled ? "将 %@ 安装到其他 Agent" : "安装 %@",
                                    item.name
                                ))
                                .accessibilityHint(localizer.string(
                                    isInstalled
                                        ? "从本地已安装副本准备内容并选择其他 Agent"
                                        : "从 GitHub 下载来源并进入安装内容检查"
                                ))
                            }
                        }
                    }
                }
                .frame(minHeight: 260, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .task(id: skillsShInput) {
            await searchSkillsShAfterDebounce()
        }
    }

    private func installedCopies(matching item: SkillsShSearchResult) -> [InstalledSkillCopy] {
        return snapshot.skills
            .flatMap(\.copies)
            .filter { $0.matchesSkillsShCatalogEntry(item) }
            .sorted {
                let leftIsShared = $0.installationOrigin?.sharedProvenance != nil
                let rightIsShared = $1.installationOrigin?.sharedProvenance != nil
                if leftIsShared != rightIsShared { return leftIsShared }
                if $0.isLocallyModified != $1.isLocallyModified {
                    return !$0.isLocallyModified
                }
                return $0.agentDisplayName.localizedStandardCompare($1.agentDisplayName)
                    == .orderedAscending
            }
    }

    private func installedAgentNames(in copies: [InstalledSkillCopy]) -> [String] {
        Array(Set(copies.map(\.agentDisplayName))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func catalogSubmitter(for item: SkillsShSearchResult) -> String? {
        let components = item.source.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }
        return String(components[0])
    }

    private func progressStatus(_ title: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(localizer.string(title))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var candidateStep: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                            if let author = candidate.declarations.author {
                                Text(localizer.format("作者：%@", author))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
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
            List(snapshot.targets) { target in
                let isAlreadyInstalled = preinstalledAgents.contains(target.agent)
                Toggle(isOn: membership(target.agent, in: $selectedAgents)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.displayName).fontWeight(.medium)
                        Text(target.directory?.path ?? localizer.string("目录无法解析"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if isAlreadyInstalled {
                            Text(localizer.string("此 Skill 已安装"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if case .unavailable(let reason) = target.availability {
                            Text(localizedSkillMessage(reason, localizer: localizer))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!target.availability.isSelectable || isAlreadyInstalled)
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
                            if let author = item.candidate.declarations.author {
                                LabeledContent(localizer.string("作者"), value: author)
                            }
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
                            if let existingMatch = item.existingMatch {
                                LabeledContent(
                                    localizer.string("安装状态"),
                                    value: existingMatch.displayName(localizer)
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
                                    (item.existingMatch ?? .sameName).replacementLabel(localizer),
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
                if activity == .preparingPreview {
                    progressStatus("正在生成预览…")
                } else {
                    Button(localizer.string("下一步"), action: preparePreview)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedAgents.isEmpty || isWorking)
                }
            case .review:
                if activity == .preparingPreview {
                    progressStatus("正在生成预览…")
                } else if activity == .installing {
                    progressStatus("正在安装…")
                } else {
                    Button(localizer.string("安装"), action: performInstall)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canInstall || isWorking)
                }
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
        runSourceTask(activity: .checkingZip) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return try await service.discoverSkills(inZip: url)
        }
    }

    private func resolveGitHubInput() {
        let input = githubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        runSourceTask(activity: .downloadingGitHub) {
            try await service.discoverSkills(fromGitHub: input)
        }
    }

    private func searchSkillsShAfterDebounce() async {
        let input = skillsShInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            searchResults = []
            sourceMessage = nil
            if isSearchingSkillsSh { activity = nil }
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        if activity != nil, !isSearchingSkillsSh { return }
        sourceMessage = nil
        activity = .searchingSkillsSh(input)
        defer {
            if activity == .searchingSkillsSh(input) {
                activity = nil
            }
        }
        do {
            let results = try await service.searchSkillsSh(query: input)
            guard !Task.isCancelled else { return }
            searchResults = results
            if results.isEmpty {
                sourceMessage = localizer.string("没有找到 skills.sh 结果")
            }
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            sourceMessage = localizedSourceMessage(for: error)
        }
    }

    private func beginCatalogInstallation(
        _ item: SkillsShSearchResult,
        installedCopies: [InstalledSkillCopy]
    ) {
        if let sourceCopy = installedCopies.first {
            let sourceLabel = localizer.format(
                "本地副本 · %@",
                sourceCopy.agentDisplayName
            )
            runSourceTask(
                activity: .preparingInstalledCopy(item.id),
                installedAgentsToExclude: Set(installedCopies.map(\.agent)),
                nextStep: .targets,
                selectsDiscoveredCandidates: true
            ) {
                try await service.discoverSkill(
                    fromInstalledCopy: sourceCopy,
                    sourceLabel: sourceLabel,
                    securityAudit: item.securityAudit
                )
            }
        } else {
            runSourceTask(activity: .downloadingCatalog(item.id)) {
                try await service.discoverSkill(fromSkillsSh: item)
            }
        }
    }

    private func runSourceTask(
        activity newActivity: Activity,
        installedAgentsToExclude: Set<AgentKind> = [],
        nextStep: Step = .candidates,
        selectsDiscoveredCandidates: Bool = false,
        _ operation: @escaping @Sendable () async throws -> SkillCandidateBatch
    ) {
        guard activity == nil else { return }
        sourceMessage = nil
        activity = newActivity
        Task {
            defer { activity = nil }
            do {
                if let batch { await service.cancel(batch) }
                let discovered = try await operation()
                batch = discovered
                selectedCandidateIDs = selectsDiscoveredCandidates
                    ? Set(discovered.candidates.map(\.id))
                    : []
                selectedAgents = []
                preinstalledAgents = installedAgentsToExclude
                replacementChoices = [:]
                confirmedRiskCandidateIDs = []
                step = nextStep
            } catch {
                sourceMessage = localizedSourceMessage(for: error)
            }
        }
    }

    private func localizedSourceMessage(for error: Error) -> String {
        return localizer.string(error.localizedDescription)
    }

    private func preparePreview() {
        guard let batch, activity == nil else { return }
        activity = .preparingPreview
        Task {
            defer { activity = nil }
            preview = await service.previewInstallation(
                batch: batch,
                candidateIDs: selectedCandidateIDs,
                targetAgents: selectedAgents,
                replacementChoices: replacementChoices
            )
            step = .review
        }
    }

    private func refreshPreview() {
        guard step == .review else { return }
        preparePreview()
    }

    private func performInstall() {
        guard let preview, activity == nil else { return }
        activity = .installing
        Task {
            defer { activity = nil }
            result = await service.install(
                preview,
                confirmedRiskCandidateIDs: confirmedRiskCandidateIDs
            )
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

    private enum Activity: Equatable {
        case checkingZip
        case downloadingGitHub
        case searchingSkillsSh(String)
        case downloadingCatalog(String)
        case preparingInstalledCopy(String)
        case preparingPreview
        case installing
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
                                        BreathEmptyState(
                                            title: localizer.string("没有文件变化"),
                                            style: .passive,
                                            placement: .inline
                                        )
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
                                ExplanationLabel(
                                    localizer.string("本地已修改，默认不选择")
                                ) {
                                    Text(localizer.string("本地已修改"))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            if target.isSymbolicLink {
                                ExplanationLabel(
                                    localizer.string(
                                        "更新后该链接会变成此 Agent 的独立实体目录"
                                    )
                                ) {
                                    Text(localizer.string("外部符号链接"))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
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

struct SkillUninstallSelectionPresentation: Equatable {
    let selectableCopies: [InstalledSkillCopy]
    let sharedCopies: [InstalledSkillSharedCopyGroup]

    init(skill: GlobalSkill) {
        selectableCopies = skill.independentCopies
        sharedCopies = skill.sharedDiscoveryCopyGroups
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
                ExplanationLabel(
                    localizer.string(
                        selectionPresentation.sharedCopies.isEmpty
                            ? "只会从明确选择的 Agent 中移除 Skill。"
                            : "共享副本会整体删除；独立副本只会从明确选择的 Agent 中移除。"
                    )
                ) {
                    Text(localizer.format("卸载 %@", skill.name))
                        .font(.title2.weight(.semibold))
                }
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
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                item.scope == .sharedLibrary
                                    ? localizer.string("共享 Skill")
                                    : item.agentDisplayName
                            )
                            .fontWeight(.medium)
                            Text(item.directory.path).font(.caption.monospaced())
                            if item.scope == .sharedLibrary {
                                Text(localizer.format(
                                    "将同时从以下 Agent 中移除：%@",
                                    formattedAgentNames(item.affectedAgentDisplayNames)
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        ExplanationLabel(
                            item.action == .moveToTrash
                                ? localizer.string("移入 macOS 废纸篓，可恢复")
                                : localizer.string("只移除链接，共享目标保持不变")
                        ) {
                            Text(
                                localizer.string(
                                    item.action == .moveToTrash
                                        ? "移入废纸篓"
                                        : "移除链接"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                List(selectionPresentation.selectableCopies) { copy in
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
                ForEach(selectionPresentation.sharedCopies) { sharedCopy in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localizer.string("共享 Skill"))
                            .fontWeight(.medium)
                        Text(sharedCopy.directory.path)
                            .font(.caption.monospaced())
                        Text(localizer.format(
                            "删除后，此 Skill 将同时从以下 Agent 中移除：%@",
                            formattedAgentNames(sharedCopy.affectedAgentDisplayNames)
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
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
                        .disabled(
                            selectedAgents.isEmpty
                                && selectionPresentation.sharedCopies.isEmpty
                                || isWorking
                        )
                } else {
                    Button(localizer.string("返回")) { self.preview = nil }
                    Button(localizer.string("卸载 Skill"), role: .destructive, action: uninstall)
                        .disabled(isWorking)
                }
            }
            .padding(16)
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: language)
    }

    private var selectionPresentation: SkillUninstallSelectionPresentation {
        SkillUninstallSelectionPresentation(skill: skill)
    }

    private func formattedAgentNames(_ names: [String]) -> String {
        names.formatted(
            .list(type: .and, width: .standard)
                .locale(localizer.locale)
        )
    }

    private func makePreview() {
        isWorking = true
        Task {
            preview = await service.previewUninstall(
                skillID: skill.id,
                targetAgents: selectedAgents,
                includeSharedDiscoveryCopies: !selectionPresentation.sharedCopies.isEmpty
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
        ExplanationLabel(localizer.string(audit.summary)) {
            Text(audit.riskLevel.displayName(localizer))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(
                    audit.riskLevel.requiresExtraConfirmation ? .red : .secondary
                )
                .background(.quaternary, in: Capsule())
        }
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

private extension ExistingSkillMatch {
    func displayName(_ localizer: ApplicationLocalizer) -> String {
        switch self {
        case .sameSourceIdentity: localizer.string("此 Skill 已安装")
        case .sameName: localizer.string("已安装同名 Skill")
        }
    }

    func replacementLabel(_ localizer: ApplicationLocalizer) -> String {
        switch self {
        case .sameSourceIdentity: localizer.string("已安装处理")
        case .sameName: localizer.string("同名处理")
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
