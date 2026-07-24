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

    @Test("refresh all does not duplicate an Agent query already in flight")
    func refreshAllSkipsCheckingAgent() async {
        let probe = AgentQuotaRefreshProbe()
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { [.codex, .claudeCode].contains($0) },
            queries: [
                .codex: { await probe.query(.codex) },
                .claudeCode: { await probe.query(.claudeCode) },
            ]
        )
        let model = AgentQuotaViewModel(service: service)
        await model.load()

        let singleRefresh = Task { await model.refresh(.codex) }
        await probe.waitUntilCodexRefreshStarts()
        await model.refreshAll()
        await probe.releaseCodexRefresh()
        await singleRefresh.value

        #expect(await probe.count(for: .codex) == 2)
        #expect(await probe.count(for: .claudeCode) == 2)
    }

    @Test("multi-provider cards retain their selected provider when quota is unsupported")
    func providerNameSurvivesUnsupportedStatus() async {
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { $0 == .qwenCode },
            providerNames: [
                .qwenCode: { "OpenRouter" },
            ],
            queries: [
                .qwenCode: { .unsupported },
            ]
        )
        let model = AgentQuotaViewModel(service: service)

        await model.load()

        #expect(model.cards.first?.providerName == "OpenRouter")
        #expect(model.cards.first?.status == .unsupported)
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

private actor AgentQuotaRefreshProbe {
    private var counts: [AgentKind: Int] = [:]
    private var blockedCodexContinuation: CheckedContinuation<Void, Never>?

    func query(_ kind: AgentKind) async -> AgentQuotaStatus {
        counts[kind, default: 0] += 1
        if kind == .codex, counts[kind] == 2 {
            await withCheckedContinuation { continuation in
                blockedCodexContinuation = continuation
            }
        }
        return .unsupported
    }

    func waitUntilCodexRefreshStarts() async {
        while counts[.codex, default: 0] < 2 {
            await Task.yield()
        }
    }

    func releaseCodexRefresh() {
        blockedCodexContinuation?.resume()
        blockedCodexContinuation = nil
    }

    func count(for kind: AgentKind) -> Int {
        counts[kind, default: 0]
    }
}

private extension AgentQuotaStatus {
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}
