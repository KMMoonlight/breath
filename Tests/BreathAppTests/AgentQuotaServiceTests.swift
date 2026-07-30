import BreathAgents
import BreathCore
import Dispatch
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

    @Test("timeout does not wait for an Agent query that ignores cancellation")
    func queryTimeoutDoesNotWaitForNonCooperativeAdapter() async {
        let service = AgentQuotaService(
            adapters: AgentAdapterRegistry.builtIn.adapters,
            isInstalled: { $0 == .claudeCode },
            queries: [
                .claudeCode: {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(
                            deadline: .now() + 10
                        ) {
                            continuation.resume()
                        }
                    }
                    return .unsupported
                },
            ],
            timeout: .milliseconds(10)
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        let status = await service.query(.claudeCode)
        let elapsed = startedAt.duration(to: clock.now)

        #expect(status == .failed("额度查询超时。"))
        #expect(
            elapsed < .seconds(5),
            "A 10ms timeout waited \(elapsed) for the 10s blocked adapter"
        )
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

    @Test("live service queries Kimi 0.29.1 through its official usage endpoint")
    func liveServiceQueriesKimiUsage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-kimi-quota-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("kimi")
        try Data(
            """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "0.29.1"
              exit 0
            fi
            exit 2
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let credentialsDirectory = directory
            .appendingPathComponent(".kimi-code/credentials", isDirectory: true)
        try FileManager.default.createDirectory(
            at: credentialsDirectory,
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "access_token": "kimi-access-token",
              "refresh_token": "kimi-refresh-token",
              "expires_at": 1800000000,
              "expires_in": 900,
              "scope": "kimi-code",
              "token_type": "Bearer"
            }
            """.utf8
        ).write(
            to: credentialsDirectory.appendingPathComponent("kimi-code.json")
        )
        let httpClient = AgentQuotaHTTPClient { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
            )
            return (
                Data(
                    """
                    {
                      "usage": {
                        "used": "28",
                        "limit": "100",
                        "resetTime": "2030-01-01T00:00:00Z"
                      }
                    }
                    """.utf8
                ),
                response
            )
        }
        let service = AgentQuotaService.live(
            homeDirectory: directory,
            detector: InstalledAgentCLIDetector(
                searchDirectories: [directory]
            ),
            sessionProvider: { URLSession(configuration: .ephemeral) },
            httpClient: httpClient,
            environment: ["PATH": directory.path]
        )

        let status = await service.query(.kimiCode)

        guard case let .available(snapshot) = status else {
            Issue.record("Expected available Kimi quota, got \(status)")
            return
        }
        #expect(snapshot.providerName == "Kimi Code")
        #expect(snapshot.windows.map(\.name) == ["每周"])
        #expect(snapshot.windows.map(\.value) == [
            .percentage(value: 28, direction: .used),
        ])
    }

    @Test("live service queries Antigravity quota through a terminal independently of the global integration version")
    func liveServiceQueriesAntigravityUsageInTerminal() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-antigravity-quota-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("agy")
        try Data(
            """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "agy 0.1.0"
              exit 0
            fi
            if [ ! -t 0 ]; then
              echo "interactive terminal required"
              exit 4
            fi
            IFS= read -r command
            if [ "$command" != "/usage" ]; then
              echo "unknown command"
              exit 5
            fi
            printf '\\033[32mGEMINI MODELS\\033[0m\\r\\n'
            printf 'Weekly Limit\\r\\n'
            printf '94%% remaining · Refreshes in 155h 41m\\r\\n'
            sleep 5
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let detector = InstalledAgentCLIDetector(
            searchDirectories: [directory]
        )
        #expect(detector.isInstalled(.antigravityCLI))
        #expect(detector.executableURL(for: .antigravityCLI) == executable)
        let service = AgentQuotaService.live(
            homeDirectory: directory,
            detector: detector,
            sessionProvider: { URLSession(configuration: .ephemeral) },
            processEnvironment: { $0 },
            environment: [
                "PATH": "\(directory.path):/bin:/usr/bin",
            ]
        )

        let status = await service.query(.antigravityCLI)

        guard case let .available(snapshot) = status else {
            Issue.record("Expected available Antigravity quota, got \(status)")
            return
        }
        #expect(snapshot.providerName == "Google Antigravity")
        #expect(snapshot.windows.map(\.value) == [
            .percentage(value: 94, direction: .remaining),
        ])
    }

    @Test("interactive quota waits until the Agent terminal is ready")
    func interactiveQuotaWaitsForTerminalReadiness() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-claude-ready-quota-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        try Data(
            """
            #!/bin/bash
            if [ "$1" = "--version" ]; then
              echo "2.1.204 (Claude Code)"
              exit 0
            fi
            if IFS= read -r -t 1 early_command; then
              printf 'Ignored input before terminal readiness\\r\\n'
            fi
            printf 'Welcome to Claude Code\\r\\n'
            printf '> '
            IFS= read -r command
            if [ "$command" != "/usage" ]; then
              printf 'unknown command\\r\\n'
              exit 5
            fi
            printf '5-hour: 34%% used\\r\\n'
            sleep 5
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let detector = InstalledAgentCLIDetector(
            searchDirectories: [directory]
        )
        let runner = AgentQuotaCommandRunner.live(
            detector: detector,
            baseEnvironment: [
                "PATH": "\(directory.path):/bin:/usr/bin",
            ],
            processEnvironment: { $0 }
        )

        let status = await AgentQuotaOfficialCLIAdapter.query(
            agent: .claudeCode,
            providerName: "Anthropic",
            command: "/usage",
            commandRunner: runner
        )

        guard case let .available(snapshot) = status else {
            Issue.record("Expected parsed Claude quota, got \(status)")
            return
        }
        #expect(snapshot.windows.first?.value == .percentage(
            value: 34,
            direction: .used
        ))
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
