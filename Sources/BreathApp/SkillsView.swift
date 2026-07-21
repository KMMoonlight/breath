import AppKit
import BreathCore
import BreathSkills
import SwiftUI

struct SkillsView: View {
    @StateObject private var model: SkillsViewModel
    @Environment(\.applicationLanguage) private var language
    @State private var selectedSkillID: String?
    @State private var showsInstaller = false
    @State private var updateToReview: SkillAvailableUpdate?
    @State private var skillToUninstall: GlobalSkill?

    init(service: GlobalSkillsService) {
        _model = StateObject(wrappedValue: SkillsViewModel(service: service))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { geometry in
                if geometry.size.width < 720 {
                    NavigationStack {
                        skillList(navigatesToDetail: true)
                            .navigationDestination(for: String.self) { skillID in
                                detail(for: model.snapshot.skills.first { $0.id == skillID })
                            }
                    }
                } else {
                    NavigationSplitView {
                        skillList(navigatesToDetail: false)
                            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 460)
                    } detail: {
                        detail(for: selectedSkill)
                    }
                    .navigationSplitViewStyle(.balanced)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.activate()
            selectFirstVisibleSkillIfNeeded()
        }
        .onDisappear { model.deactivate() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            model.reconcileAfterApplicationActivation()
        }
        .onChange(of: model.filteredSkills.map(\.id)) { _, _ in
            selectFirstVisibleSkillIfNeeded()
        }
        .sheet(isPresented: $showsInstaller) {
            SkillInstallationWizard(
                service: model.service,
                snapshot: model.snapshot,
                language: language
            ) { result in
                model.accept(result)
                showsInstaller = false
            }
            .frame(minWidth: 760, minHeight: 620)
        }
        .sheet(item: $updateToReview) { update in
            SkillUpdateReviewView(
                service: model.service,
                update: update,
                language: language
            ) { result in
                model.accept(result)
                updateToReview = nil
            }
            .frame(minWidth: 680, minHeight: 540)
        }
        .sheet(item: $skillToUninstall) { skill in
            SkillUninstallView(
                service: model.service,
                skill: skill,
                language: language
            ) { result in
                model.accept(result)
                skillToUninstall = nil
            }
            .frame(minWidth: 560, minHeight: 420)
        }
        .alert("Breath", isPresented: errorPresented) {
            Button(localizer.string("好")) { model.errorMessage = nil }
        } message: {
            Text(localizer.string(model.errorMessage ?? "未知错误"))
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: language)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.string("Skills"))
                    .font(.title2.weight(.semibold))
                Text(localizer.format("%d 个全局 Skill", model.snapshot.skills.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(localizer.string("搜索名称或说明"), text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .accessibilityLabel(localizer.string("搜索 Skills"))
            filterMenu
            Button {
                model.refresh()
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label(localizer.string("刷新"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.isRefreshing)
            .accessibilityLabel(localizer.string("刷新 Skills"))
            Button {
                showsInstaller = true
            } label: {
                Label(localizer.string("安装 Skill…"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(localizer.string("安装 Skill"))
        }
        .padding(.top, 32)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var filterMenu: some View {
        Menu {
            Picker(localizer.string("Agent"), selection: $model.selectedAgent) {
                Text(localizer.string("全部 Agent")).tag(nil as AgentKind?)
                ForEach(model.snapshot.targets) { target in
                    Text(target.displayName).tag(target.agent as AgentKind?)
                }
            }
            Picker(localizer.string("来源"), selection: $model.selectedSource) {
                Text(localizer.string("全部来源")).tag(nil as SkillSourceKind?)
                ForEach(SkillSourceKind.allCases, id: \.self) { source in
                    Text(source.displayName(localizer)).tag(source as SkillSourceKind?)
                }
            }
            Picker(localizer.string("状态"), selection: $model.selectedStatus) {
                Text(localizer.string("全部状态")).tag(nil as SkillUpdateState?)
                ForEach(SkillUpdateState.allCasesForFiltering, id: \.self) { status in
                    Text(status.displayName(localizer)).tag(status as SkillUpdateState?)
                }
            }
            if model.selectedAgent != nil
                || model.selectedSource != nil
                || model.selectedStatus != nil
            {
                Divider()
                Button(localizer.string("清除筛选")) {
                    model.selectedAgent = nil
                    model.selectedSource = nil
                    model.selectedStatus = nil
                }
            }
        } label: {
            Label(localizer.string("筛选"), systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(localizer.string("筛选 Skills"))
    }

    private func skillList(navigatesToDetail: Bool) -> some View {
        List(selection: $selectedSkillID) {
            if model.filteredSkills.isEmpty {
                Text(model.snapshot.skills.isEmpty
                    ? localizer.string("尚未发现全局 Skill")
                    : localizer.string("没有符合筛选条件的 Skill"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.filteredSkills) { skill in
                    if navigatesToDetail {
                        NavigationLink(value: skill.id) {
                            SkillListRow(skill: skill, localizer: localizer)
                        }
                    } else {
                        SkillListRow(skill: skill, localizer: localizer)
                            .tag(skill.id)
                    }
                }
            }
            if !model.snapshot.unrecognizedItems.isEmpty {
                Section(localizer.string("无法识别的 Skill 项目")) {
                    ForEach(model.snapshot.unrecognizedItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.path.lastPathComponent)
                                .font(.body.weight(.medium))
                            Text("\(item.agentDisplayName) · \(localizedSkillMessage(item.reason, localizer: localizer))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            HStack {
                                Button(localizer.string("在 Finder 中显示")) {
                                    model.reveal(item.path)
                                }
                                Button(localizer.string("复制诊断")) {
                                    model.copyDiagnostic(
                                        item,
                                        localizedReason: localizedSkillMessage(
                                            item.reason,
                                            localizer: localizer
                                        )
                                    )
                                }
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel(localizer.string("全局 Skills 列表"))
    }

    @ViewBuilder
    private func detail(for skill: GlobalSkill?) -> some View {
        if let skill {
            SkillDetailView(
                skill: skill,
                update: model.update(for: skill),
                localizer: localizer,
                reveal: model.reveal,
                reviewUpdate: { updateToReview = $0 },
                uninstall: { skillToUninstall = skill }
            )
        } else {
            ContentUnavailableView(
                localizer.string("选择一个 Skill"),
                systemImage: "sparkles",
                description: Text(localizer.string("查看说明、文件、来源和 Agent 副本"))
            )
        }
    }

    private var selectedSkill: GlobalSkill? {
        model.filteredSkills.first { $0.id == selectedSkillID }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private func selectFirstVisibleSkillIfNeeded() {
        guard !model.filteredSkills.contains(where: { $0.id == selectedSkillID }) else {
            return
        }
        selectedSkillID = model.filteredSkills.first?.id
    }
}

private struct SkillListRow: View {
    let skill: GlobalSkill
    let localizer: ApplicationLocalizer

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(skill.name).font(.body.weight(.semibold))
                Spacer(minLength: 8)
                if skill.copies.contains(where: { $0.updateState == .updateAvailable }) {
                    Text(localizer.string("可更新"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                if skill.copies.contains(where: \.isLocallyModified) {
                    Text(localizer.string("本地已修改"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text(skill.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 4) {
                ForEach(skill.copies) { copy in
                    Text(copy.agentDisplayName)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Text(skill.sourceKinds.map { $0.displayName(localizer) }.sorted().joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skill.name), \(skill.description), \(skill.copies.map(\.agentDisplayName).joined(separator: ", "))")
    }
}

private struct SkillDetailView: View {
    let skill: GlobalSkill
    let update: SkillAvailableUpdate?
    let localizer: ApplicationLocalizer
    let reveal: (URL) -> Void
    let reviewUpdate: (SkillAvailableUpdate) -> Void
    let uninstall: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(skill.name).font(.largeTitle.weight(.semibold))
                        Text(skill.description)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if let update {
                        Button(localizer.string("查看更新…")) {
                            reviewUpdate(update)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button(localizer.string("卸载…"), role: .destructive, action: uninstall)
                }

                GroupBox(localizer.string("Agent 副本")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(skill.copies) { copy in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(copy.agentDisplayName).fontWeight(.medium)
                                    Text(copy.directory.path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Text(copyStatus(copy))
                                        .font(.caption)
                                        .foregroundStyle(copy.isLocallyModified ? .orange : .secondary)
                                    if let repository = copy.repository {
                                        Text([
                                            repository,
                                            copy.sourceRelativePath,
                                        ].compactMap { $0 }.filter { !$0.isEmpty }
                                            .joined(separator: " · "))
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    if let reference = copy.reference,
                                       let commit = copy.resolvedCommit
                                    {
                                        Text("\(reference.kind.rawValue):\(reference.value) · \(commit)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.tertiary)
                                            .textSelection(.enabled)
                                    }
                                }
                                Spacer()
                                Button(localizer.string("在 Finder 中显示")) {
                                    reveal(copy.directory)
                                }
                            }
                            if copy.id != skill.copies.last?.id { Divider() }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox(localizer.string("SKILL.md")) {
                    ScrollView(.horizontal) {
                        Text(skill.manifest)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180)
                }

                GroupBox(localizer.format("文件（%d）", skill.files.count)) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(skill.files) { file in
                            HStack {
                                Image(systemName: file.kind == .symbolicLink ? "link" : "doc")
                                    .foregroundStyle(.secondary)
                                Text(file.relativePath).font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .accessibilityLabel(localizer.string("Skill 详情"))
    }

    private func copyStatus(_ copy: InstalledSkillCopy) -> String {
        var values = [copy.source.displayName(localizer), copy.updateState.displayName(localizer)]
        if copy.isLocallyModified, copy.updateState != .locallyModified {
            values.append(localizer.string("本地已修改"))
        }
        if copy.isSymbolicLink { values.append(localizer.string("外部符号链接")) }
        return values.joined(separator: " · ")
    }
}

extension SkillSourceKind {
    func displayName(_ localizer: ApplicationLocalizer) -> String {
        switch self {
        case .zip: localizer.string("ZIP")
        case .github: "GitHub"
        case .skillsSh: "skills.sh"
        case .unknown: localizer.string("未知来源")
        }
    }
}

extension SkillUpdateState {
    static let allCasesForFiltering: [SkillUpdateState] = [
        .updateAvailable, .locallyModified, .current, .pinned, .unavailable, .failed,
    ]

    func displayName(_ localizer: ApplicationLocalizer) -> String {
        switch self {
        case .unavailable: localizer.string("不可更新")
        case .checking: localizer.string("正在检查")
        case .current: localizer.string("已是最新")
        case .updateAvailable: localizer.string("可更新")
        case .locallyModified: localizer.string("本地已修改")
        case .pinned: localizer.string("固定版本")
        case .failed: localizer.string("检查失败")
        }
    }
}

func localizedSkillMessage(
    _ message: String,
    localizer: ApplicationLocalizer
) -> String {
    if message.hasSuffix(" is not installed.") {
        let name = String(message.dropLast(" is not installed.".count))
        return localizer.format("%@ is not installed.", name)
    }
    if message.hasSuffix(" is installed, but its version could not be verified.") {
        let name = String(message.dropLast(
            " is installed, but its version could not be verified.".count
        ))
        return localizer.format(
            "%@ is installed, but its version could not be verified.",
            name
        )
    }
    let olderMarker = " is older than the supported "
    if let markerRange = message.range(of: olderMarker) {
        let nameAndVersion = String(message[..<markerRange.lowerBound])
        let supported = String(message[markerRange.upperBound...]).trimmingCharacters(
            in: CharacterSet(charactersIn: ".")
        )
        if let separator = nameAndVersion.lastIndex(of: " ") {
            return localizer.format(
                "%@ %@ is older than the supported %@.",
                String(nameAndVersion[..<separator]),
                String(nameAndVersion[nameAndVersion.index(after: separator)...]),
                supported
            )
        }
    }
    return localizer.string(message)
}
