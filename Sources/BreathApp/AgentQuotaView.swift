import BreathCore
import SwiftUI

private enum AgentQuotaLayout {
    static let cardWidth: CGFloat = 360
    static let cardHeight: CGFloat = 188
    static let quotaWindowWidth: CGFloat = 161
    static let quotaWindowHeight: CGFloat = 110
    static let cardSpacing: CGFloat = 12
    static let quotaWindowSpacing: CGFloat = 10
    static let contentPadding: CGFloat = 16
}

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
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(
                                        minimum: AgentQuotaLayout.cardWidth,
                                        maximum: AgentQuotaLayout.cardWidth
                                    ),
                                    spacing: AgentQuotaLayout.cardSpacing,
                                    alignment: .top
                                ),
                            ],
                            alignment: .leading,
                            spacing: AgentQuotaLayout.cardSpacing
                        ) {
                            ForEach(model.cards) { card in
                                AgentQuotaCardView(
                                    card: card,
                                    refresh: {
                                        Task { await model.refresh(card.kind) }
                                    }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AgentQuotaLayout.contentPadding)
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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        AgentBrandIcon(agent: card.kind, color: agentStatusColor)
                            .accessibilityHidden(true)
                        Text(card.displayName)
                            .font(.headline)
                            .foregroundStyle(agentStatusColor)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(card.displayName)
                    .accessibilityValue(localizer.string(accessibleStatus))
                    if hasIdentityDetails {
                        HStack(spacing: 6) {
                            if let providerName = displayedProviderName {
                                Text(providerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let maskedAccount = displayedMaskedAccount {
                                Text(maskedAccount)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                .fixedSize(horizontal: true, vertical: false)
            }

            statusContent
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
        .padding(14)
        .frame(
            width: AgentQuotaLayout.cardWidth,
            height: AgentQuotaLayout.cardHeight,
            alignment: .topLeading
        )
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
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .fixed(AgentQuotaLayout.quotaWindowWidth),
                            spacing: AgentQuotaLayout.quotaWindowSpacing
                        ),
                        GridItem(
                            .fixed(AgentQuotaLayout.quotaWindowWidth),
                            spacing: AgentQuotaLayout.quotaWindowSpacing
                        ),
                    ],
                    alignment: .leading,
                    spacing: AgentQuotaLayout.quotaWindowSpacing
                ) {
                    ForEach(snapshot.windows) { window in
                        AgentQuotaWindowView(window: window)
                    }
                }
            }
            .scrollIndicators(.automatic)
        case .notLoggedIn:
            Color.clear
        case .unsupported:
            Text(localizer.string("当前 Auth 暂不支持"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text(localizer.string(reason))
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    private var agentStatusColor: Color {
        switch card.status {
        case .checking: .secondary
        case .available: .green
        case .notLoggedIn, .unsupported: .secondary
        case .failed: .orange
        }
    }

    private var accessibleStatus: String {
        switch card.status {
        case .checking: "查询中"
        case .available: "可用"
        case .notLoggedIn: "未登录"
        case .unsupported: "当前 Auth 暂不支持"
        case .failed: "查询失败"
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

    private var displayedMaskedAccount: String? {
        if case .available(let snapshot) = card.status {
            return snapshot.maskedAccount
        }
        return nil
    }

    private var hasIdentityDetails: Bool {
        displayedProviderName != nil || displayedMaskedAccount != nil
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
                let displayedValue = unit == "Credits" ? integerAmount(value) : value
                Text([displayedValue, unit].compactMap { $0 }.joined(separator: " "))
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
        .frame(
            width: AgentQuotaLayout.quotaWindowWidth,
            height: AgentQuotaLayout.quotaWindowHeight,
            alignment: .topLeading
        )
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

    private func integerAmount(_ value: String) -> String {
        AgentQuotaAmountFormatter.integer(value, locale: localizer.locale)
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

enum AgentQuotaAmountFormatter {
    static func integer(_ value: String, locale: Locale) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.range(
            of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$"#,
            options: .regularExpression
        ) != nil else {
            return value
        }
        guard let decimal = Decimal(
            string: trimmedValue,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            return value
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? value
    }
}
