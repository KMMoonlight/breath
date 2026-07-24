import BreathCore
import SwiftUI

struct AgentQuotaCard: Equatable, Identifiable, Sendable {
    let kind: AgentKind
    let displayName: String
    var providerName: String?
    var status: AgentQuotaStatus

    var id: AgentKind { kind }
}

@MainActor
final class AgentQuotaViewModel: ObservableObject {
    @Published private(set) var cards: [AgentQuotaCard] = []
    @Published private(set) var isRefreshingAll = false

    private let service: AgentQuotaService

    init(service: AgentQuotaService) {
        self.service = service
    }

    func load() async {
        let agents = await service.installedAgents()
        cards = []
        for agent in agents {
            cards.append(
                AgentQuotaCard(
                    kind: agent.kind,
                    displayName: agent.displayName,
                    providerName: await service.providerName(for: agent.kind),
                    status: .checking
                )
            )
        }
        await refresh(
            kinds: cards.map(\.kind),
            tracksRefreshAll: true
        )
    }

    func refreshAll() async {
        guard !isRefreshingAll else { return }
        let kinds = cards.compactMap { card in
            card.status == .checking ? nil : card.kind
        }
        await refresh(kinds: kinds, tracksRefreshAll: true)
    }

    private func refresh(
        kinds: [AgentKind],
        tracksRefreshAll: Bool
    ) async {
        guard !kinds.isEmpty else { return }
        if tracksRefreshAll {
            isRefreshingAll = true
        }
        defer {
            if tracksRefreshAll {
                isRefreshingAll = false
            }
        }
        for index in cards.indices where kinds.contains(cards[index].kind) {
            cards[index].providerName = await service.providerName(
                for: cards[index].kind
            )
            cards[index].status = .checking
        }
        await withTaskGroup(of: (AgentKind, AgentQuotaStatus).self) { group in
            for kind in kinds {
                let service = self.service
                group.addTask {
                    (kind, await service.query(kind))
                }
            }
            for await (kind, status) in group {
                guard let index = cards.firstIndex(where: { $0.kind == kind }) else {
                    continue
                }
                cards[index].status = status
            }
        }
    }

    func refresh(_ kind: AgentKind) async {
        guard let index = cards.firstIndex(where: { $0.kind == kind }),
              cards[index].status != .checking
        else {
            return
        }
        cards[index].providerName = await service.providerName(for: kind)
        cards[index].status = .checking
        let status = await service.query(kind)
        guard let refreshedIndex = cards.firstIndex(where: { $0.kind == kind }) else {
            return
        }
        cards[refreshedIndex].status = status
    }
}

struct AgentQuotaView: View {
    @StateObject private var model: AgentQuotaViewModel
    @Environment(\.applicationLanguage) private var applicationLanguage

    init(service: AgentQuotaService) {
        _model = StateObject(
            wrappedValue: AgentQuotaViewModel(service: service)
        )
    }

    var body: some View {
        Group {
            if model.cards.isEmpty {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text(localizer.string("额度"))
                            .font(.headline)
                        Spacer()
                        Button {
                            Task { await model.refreshAll() }
                        } label: {
                            Label(
                                localizer.string("全部刷新"),
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isRefreshingAll)
                        .accessibilityLabel(localizer.string("全部刷新"))
                        .help(localizer.string("全部刷新"))
                    }
                    .pageToolbarLeadingPadding()
                    .padding(.trailing, WorkbenchLayout.pageToolbarTrailingInset)
                    .frame(height: WorkbenchLayout.pageToolbarHeight)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(model.cards) { card in
                                AgentQuotaCardView(
                                    card: card,
                                    refresh: {
                                        Task { await model.refresh(card.kind) }
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .task {
            await model.load()
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private struct AgentQuotaCardView: View {
    let card: AgentQuotaCard
    let refresh: () -> Void

    @Environment(\.applicationLanguage) private var applicationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(card.displayName)
                    .font(.headline)
                if let providerName = displayedProviderName {
                    Text(providerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if case .available(let snapshot) = card.status {
                    if let maskedAccount = snapshot.maskedAccount {
                        Text(maskedAccount)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                statusBadge
                Button(action: refresh) {
                    Label(
                        localizer.string("刷新"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderless)
                .disabled(card.status == .checking)
                .accessibilityLabel(
                    localizer.format("刷新 %@ 额度", card.displayName)
                )
                .help(localizer.format("刷新 %@ 额度", card.displayName))
            }

            statusContent
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch card.status {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .available(let snapshot):
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 180), spacing: 10),
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(snapshot.windows) { window in
                    AgentQuotaWindowView(window: window)
                }
            }
        case .notLoggedIn:
            Text(localizer.string("未登录"))
                .foregroundStyle(.secondary)
        case .unsupported:
            Text(localizer.string("不支持查询"))
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text(localizer.string(reason))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var statusBadge: some View {
        let presentation = statusPresentation
        return Label(
            localizer.string(presentation.title),
            systemImage: presentation.systemImage
        )
        .font(.caption)
        .foregroundStyle(presentation.color)
        .accessibilityElement(children: .combine)
    }

    private var statusPresentation: (
        title: String,
        systemImage: String,
        color: Color
    ) {
        switch card.status {
        case .checking:
            ("查询中", "arrow.triangle.2.circlepath", .secondary)
        case .available(let snapshot):
            snapshot.windows.contains(where: \.warning)
                ? ("警告", "exclamationmark.triangle", .orange)
                : ("可用", "checkmark.circle", .secondary)
        case .notLoggedIn:
            ("未登录", "person.crop.circle.badge.questionmark", .secondary)
        case .unsupported:
            ("不支持查询", "questionmark.circle", .secondary)
        case .failed:
            ("查询失败", "xmark.circle", .red)
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }

    private var displayedProviderName: String? {
        if case .available(let snapshot) = card.status {
            return snapshot.providerName ?? card.providerName
        }
        return card.providerName
    }
}

private struct AgentQuotaWindowView: View {
    let window: AgentQuotaWindow

    @Environment(\.applicationLanguage) private var applicationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let resetsAt = window.resetsAt {
                ExplanationLabel(exactResetTime(resetsAt)) {
                    Text(localizer.string(window.name))
                        .font(.subheadline.weight(.medium))
                }
            } else {
                Text(localizer.string(window.name))
                    .font(.subheadline.weight(.medium))
            }

            switch window.value {
            case .percentage(let value, let direction):
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        localizer.format(
                            direction == .used ? "已使用 %@" : "剩余 %@",
                            formattedPercentage(value)
                        )
                    )
                    .font(.title3.monospacedDigit())
                    ProgressView(value: min(max(value, 0), 100), total: 100)
                        .tint(window.warning ? .orange : .accentColor)
                }
            case .amount(let value, let unit):
                Text([value, unit].compactMap { $0 }.joined(separator: " "))
                    .font(.title3.monospacedDigit())
                    .textSelection(.enabled)
            }

            if let resetsAt = window.resetsAt {
                Text(relativeResetTime(resetsAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let resetDescription = window.resetDescription {
                Text(resetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func relativeResetTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = localizer.locale
        formatter.unitsStyle = .full
        return localizer.format(
            "%@重置",
            formatter.localizedString(for: date, relativeTo: Date())
        )
    }

    private func exactResetTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localizer.locale
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formattedPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = localizer.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(value))%"
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}
