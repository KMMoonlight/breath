import BreathAgents
import BreathCore
import Testing
@testable import BreathApp

@MainActor
@Suite("Agent quota page")
struct AgentQuotaViewModelTests {
    @Test("loads only installed Agent cards and their independent status")
    func loadsInstalledCards() async {
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { $0 == .codex },
            queries: [
                .codex: {
                    .available(
                        AgentQuotaSnapshot(
                            providerName: "OpenAI",
                            maskedAccount: nil,
                            windows: [
                                AgentQuotaWindow(
                                    name: "5 小时",
                                    value: .percentage(value: 10, direction: .used),
                                    resetsAt: nil,
                                    warning: false
                                ),
                            ]
                        )
                    )
                },
            ]
        )
        let model = AgentQuotaViewModel(service: service)

        await model.load()

        #expect(model.cards.map(\.kind) == [.codex])
        #expect(model.cards.first?.status == .available(
            AgentQuotaSnapshot(
                providerName: "OpenAI",
                maskedAccount: nil,
                windows: [
                    AgentQuotaWindow(
                        name: "5 小时",
                        value: .percentage(value: 10, direction: .used),
                        resetsAt: nil,
                        warning: false
                    ),
                ]
            )
        ))
    }

    @Test("a failed refresh replaces the previous available quota")
    func failedRefreshReplacesPreviousResult() async {
        let probe = AgentQuotaSequenceProbe()
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { $0 == .codex },
            queries: [
                .codex: {
                    await probe.next()
                },
            ]
        )
        let model = AgentQuotaViewModel(service: service)

        await model.load()
        #expect(model.cards.first?.status.isAvailable == true)

        await model.refresh(.codex)

        #expect(model.cards.first?.status == .failed("脱敏失败"))
    }
}

private actor AgentQuotaSequenceProbe {
    private var count = 0

    func next() -> AgentQuotaStatus {
        count += 1
        if count == 1 {
            return .available(
                AgentQuotaSnapshot(
                    providerName: "OpenAI",
                    maskedAccount: nil,
                    windows: [
                        AgentQuotaWindow(
                            name: "5 小时",
                            value: .percentage(value: 10, direction: .used),
                            resetsAt: nil,
                            warning: false
                        ),
                    ]
                )
            )
        }
        return .failed("脱敏失败")
    }
}

private extension AgentQuotaStatus {
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}
