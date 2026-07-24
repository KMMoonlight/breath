import BreathAgents
import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Agent quota service")
struct AgentQuotaServiceTests {
    @Test("lists only installed Agents in registry order")
    func installedAgentsFollowRegistryOrder() async {
        let installedKinds: Set<AgentKind> = [.claudeCode, .codex, .pi]
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { installedKinds.contains($0) },
            queries: [:]
        )

        let agents = await service.installedAgents()

        #expect(agents.map(\.kind) == [.codex, .claudeCode, .pi])
        #expect(agents.map(\.displayName) == ["Codex", "Claude Code", "Pi"])
    }

    @Test("returns an official quota snapshot or unsupported status")
    func queryUsesRegisteredAdapter() async {
        let snapshot = AgentQuotaSnapshot(
            providerName: "OpenAI",
            maskedAccount: "sa***@example.com",
            windows: [
                AgentQuotaWindow(
                    name: "5 小时",
                    value: .percentage(value: 42, direction: .used),
                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                    warning: false
                ),
            ]
        )
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { _ in true },
            queries: [
                .codex: { .available(snapshot) },
            ]
        )

        #expect(await service.query(.codex) == .available(snapshot))
        #expect(await service.query(.pi) == .unsupported)
    }

    @Test("an installed Agent below the supported version does not run its quota query")
    func incompatibleAgentDoesNotQuery() async {
        let probe = AgentQuotaInvocationProbe()
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { _ in true },
            isSupported: { $0 != .codex },
            queries: [
                .codex: {
                    await probe.record()
                    return .failed("should not run")
                },
            ]
        )

        #expect(await service.query(.codex) == .unsupported)
        #expect(await probe.count == 0)
    }

    @Test("queries installed Agents concurrently")
    func queryAllRunsConcurrently() async {
        let probe = AgentQuotaConcurrencyProbe()
        let query: AgentQuotaQuery = {
            await probe.begin()
            try? await Task.sleep(for: .milliseconds(40))
            await probe.end()
            return .unsupported
        }
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { [.codex, .claudeCode].contains($0) },
            queries: [
                .codex: query,
                .claudeCode: query,
            ]
        )

        let results = await service.queryAll()

        #expect(results.count == 2)
        #expect(await probe.maximumConcurrentCount == 2)
    }

    @Test("times out one Agent without blocking its result")
    func queryTimeout() async {
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { $0 == .codex },
            queries: [
                .codex: {
                    try? await Task.sleep(for: .seconds(1))
                    return .unsupported
                },
            ],
            timeout: .milliseconds(10)
        )

        #expect(await service.query(.codex) == .failed("额度查询超时。"))
    }

    @Test("live service declares an explicit quota capability for every built-in Agent")
    func liveServiceCoversRegistry() async {
        let service = AgentQuotaService.live(
            homeDirectory: FileManager.default.temporaryDirectory,
            detector: InstalledAgentCLIDetector(searchDirectories: []),
            sessionProvider: { URLSession(configuration: .ephemeral) },
            environment: [:]
        )

        #expect(await service.declaredAgentKinds() == Set(AgentKind.allCases))
    }
}

private actor AgentQuotaConcurrencyProbe {
    private var activeCount = 0
    private(set) var maximumConcurrentCount = 0

    func begin() {
        activeCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, activeCount)
    }

    func end() {
        activeCount -= 1
    }
}

private actor AgentQuotaInvocationProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
