import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Agent quota adapters")
struct AgentQuotaAdapterTests {
    @Test("Codex preserves official percentage windows and credit balance")
    func codexQuotaResponse() throws {
        let data = Data(
            """
            {
              "plan_type": "pro",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 25,
                  "limit_window_seconds": 18000,
                  "reset_at": 1800000000
                },
                "secondary_window": {
                  "used_percent": 18,
                  "limit_window_seconds": 604800,
                  "reset_at": 1800600000
                }
              },
              "credits": {
                "unlimited": false,
                "balance": "766.76"
              }
            }
            """.utf8
        )

        let snapshot = try CodexAgentQuotaAdapter.decode(
            data,
            maskedAccount: "sa***@example.com"
        )

        #expect(snapshot.providerName == "OpenAI")
        #expect(snapshot.maskedAccount == "sa***@example.com")
        #expect(
            snapshot.windows.map(\.value) == [
                .percentage(value: 25, direction: .used),
                .percentage(value: 18, direction: .used),
                .amount(value: "766.76", unit: "Credits"),
            ]
        )
        #expect(snapshot.windows.map(\.name) == ["5 小时", "每周", "Credits"])
        #expect(
            snapshot.windows.map(\.resetsAt) == [
                Date(timeIntervalSince1970: 1_800_000_000),
                Date(timeIntervalSince1970: 1_800_600_000),
                nil,
            ]
        )
    }

    @Test("Codex sends an in-memory credential only to the official usage endpoint")
    func codexQuotaRequest() async throws {
        let recorder = QuotaRequestRecorder()
        let responseData = Data(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 12,
                  "limit_window_seconds": 18000,
                  "reset_at": 1800000000
                }
              }
            }
            """.utf8
        )
        let client = AgentQuotaHTTPClient { request in
            await recorder.record(request)
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
            )
            return (responseData, response)
        }

        let status = await CodexAgentQuotaAdapter.query(
            credentialProvider: {
                AgentQuotaCredential(
                    bearerToken: AgentQuotaSecret("test-secret-token"),
                    accountID: "account-123",
                    maskedAccount: "sa***@example.com"
                )
            },
            httpClient: client
        )

        guard case .available(let snapshot) = status else {
            Issue.record("Expected available Codex quota, got \(status)")
            return
        }
        #expect(snapshot.windows.first?.value == .percentage(value: 12, direction: .used))
        let request = try #require(await recorder.request)
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-ID") == "account-123")
        #expect(!String(describing: status).contains("test-secret-token"))
    }

    @Test("Codex falls back to the official app-server protocol")
    func codexAppServerFallback() async {
        let client = AgentQuotaHTTPClient { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data(), response)
        }
        let fallbackSnapshot = AgentQuotaSnapshot(
            providerName: "OpenAI",
            maskedAccount: nil,
            windows: [
                AgentQuotaWindow(
                    name: "5 小时",
                    value: .percentage(value: 27, direction: .used),
                    resetsAt: nil,
                    warning: false
                ),
            ]
        )

        let status = await CodexAgentQuotaAdapter.query(
            credentialProvider: {
                AgentQuotaCredential(
                    bearerToken: AgentQuotaSecret("secret"),
                    accountID: nil,
                    maskedAccount: nil
                )
            },
            httpClient: client,
            fallback: { .available(fallbackSnapshot) }
        )

        #expect(status == .available(fallbackSnapshot))
    }

    @Test("Codex app-server response preserves all named limit buckets")
    func codexAppServerResponse() throws {
        let data = Data(
            """
            {"id":1,"result":{"userAgent":"Breath"}}
            {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":18,"windowDurationMins":10080,"resetsAt":1800600000},"rateLimitReachedType":null,"credits":{"hasCredits":true,"unlimited":false,"balance":"766.76"}},"rateLimitsByLimitId":{"code_review":{"limitName":"Code Review","primary":{"usedPercent":9,"windowDurationMins":10080,"resetsAt":1800600000},"rateLimitReachedType":"rate_limit_reached"}}}}
            """.utf8
        )

        let snapshot = try CodexAgentQuotaAppServer.decode(data)

        #expect(snapshot.providerName == "OpenAI")
        #expect(snapshot.windows.map(\.name) == [
            "5 小时",
            "每周",
            "Credits",
            "Code Review · 每周",
        ])
        #expect(snapshot.windows.last?.warning == true)
    }

    @Test("Codex credential stays in memory and does not infer an account from JWT")
    func codexCredential() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-codex-quota-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let payload = Data(#"{"email":"sai@example.com"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let auth = Data(
            """
            {
              "tokens": {
                "access_token": "file-secret-token",
                "id_token": "header.\(payload).signature",
                "account_id": "account-456"
              }
            }
            """.utf8
        )
        try auth.write(to: temporaryDirectory.appendingPathComponent("auth.json"))
        let store = AgentQuotaCredentialStore(
            homeDirectory: temporaryDirectory,
            environment: ["CODEX_HOME": temporaryDirectory.path]
        )

        let credential = try #require(store.codexCredential())

        #expect(credential.accountID == "account-456")
        #expect(credential.maskedAccount == nil)
        #expect(!String(describing: credential).contains("file-secret-token"))
    }

    @Test("Claude preserves every official utilization window and extra usage amount")
    func claudeQuotaResponse() throws {
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 32.5,
                "resets_at": "2026-07-24T12:00:00Z"
              },
              "seven_day": {
                "utilization": 41,
                "resets_at": "2026-07-28T12:00:00Z"
              },
              "seven_day_opus": {
                "utilization": 12,
                "resets_at": "2026-07-28T12:00:00Z"
              },
              "extra_usage": {
                "is_enabled": true,
                "monthly_limit": 1000,
                "used_credits": 250,
                "utilization": 25
              }
            }
            """.utf8
        )

        let snapshot = try ClaudeAgentQuotaAdapter.decode(data)

        #expect(snapshot.providerName == "Anthropic")
        #expect(snapshot.maskedAccount == nil)
        #expect(snapshot.windows.map(\.name) == [
            "5 小时",
            "每周",
            "每周 Opus",
            "Extra Usage",
        ])
        #expect(snapshot.windows.map(\.value) == [
            .percentage(value: 32.5, direction: .used),
            .percentage(value: 41, direction: .used),
            .percentage(value: 12, direction: .used),
            .amount(value: "250 / 1000", unit: "Credits"),
        ])
    }

    @Test("Claude sends its OAuth credential only to the official usage endpoint")
    func claudeQuotaRequest() async throws {
        let recorder = QuotaRequestRecorder()
        let responseData = Data(
            """
            {
              "five_hour": {
                "utilization": 10,
                "resets_at": "2026-07-24T12:00:00Z"
              }
            }
            """.utf8
        )
        let client = AgentQuotaHTTPClient { request in
            await recorder.record(request)
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
            )
            return (responseData, response)
        }

        let status = await ClaudeAgentQuotaAdapter.query(
            credentialProvider: { AgentQuotaSecret("claude-secret-token") },
            httpClient: client,
            fallback: { .unsupported }
        )

        guard case .available = status else {
            Issue.record("Expected available Claude quota, got \(status)")
            return
        }
        let request = try #require(await recorder.request)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer claude-secret-token")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(!String(describing: status).contains("claude-secret-token"))
    }

    @Test("Claude falls back after an official endpoint format change")
    func claudeFallback() async {
        let client = AgentQuotaHTTPClient { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data(#"{"changed":true}"#.utf8), response)
        }
        let fallbackSnapshot = AgentQuotaSnapshot(
            providerName: "Anthropic",
            maskedAccount: nil,
            windows: [
                AgentQuotaWindow(
                    name: "5 小时",
                    value: .percentage(value: 8, direction: .used),
                    resetsAt: nil,
                    warning: false
                ),
            ]
        )

        let status = await ClaudeAgentQuotaAdapter.query(
            credentialProvider: { AgentQuotaSecret("secret") },
            httpClient: client,
            fallback: { .available(fallbackSnapshot) }
        )

        #expect(status == .available(fallbackSnapshot))
    }

    @Test("OpenRouter keeps official purchased and used credit amounts")
    func openRouterCredits() async throws {
        let recorder = QuotaRequestRecorder()
        let client = AgentQuotaHTTPClient { request in
            await recorder.record(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (
                Data(
                    """
                    {
                      "data": {
                        "total_credits": 100.5,
                        "total_usage": 25.75
                      }
                    }
                    """.utf8
                ),
                response
            )
        }

        let status = await OpenRouterQuotaAdapter.query(
            credential: AgentQuotaSecret("openrouter-secret"),
            httpClient: client
        )

        guard case .available(let snapshot) = status else {
            Issue.record("Expected available OpenRouter credits, got \(status)")
            return
        }
        #expect(snapshot.providerName == "OpenRouter")
        #expect(snapshot.windows.map(\.value) == [
            .amount(value: "100.5", unit: "Credits"),
            .amount(value: "25.75", unit: "Credits"),
        ])
        let request = try #require(await recorder.request)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/credits")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openrouter-secret")
    }

    @Test("OpenRouter falls back to the official current-key endpoint for regular API keys")
    func openRouterCurrentKeyFallback() async throws {
        let recorder = QuotaRequestRecorder()
        let client = AgentQuotaHTTPClient { request in
            await recorder.record(request)
            let statusCode: Int
            let data: Data
            if request.url?.path == "/api/v1/credits" {
                statusCode = 403
                data = Data()
            } else {
                statusCode = 200
                data = Data(
                    """
                    {
                      "data": {
                        "limit_remaining": 74.5,
                        "usage": 25.5,
                        "usage_daily": 2.5,
                        "usage_weekly": 10.5,
                        "usage_monthly": 20.5
                      }
                    }
                    """.utf8
                )
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response)
        }

        let status = await OpenRouterQuotaAdapter.query(
            credential: AgentQuotaSecret("openrouter-secret"),
            httpClient: client
        )

        guard case .available(let snapshot) = status else {
            Issue.record("Expected current-key quota data, got \(status)")
            return
        }
        #expect(snapshot.windows.map(\.name) == [
            "Credits Remaining",
            "Total Usage",
            "Daily Usage",
            "Weekly Usage",
            "Monthly Usage",
        ])
        #expect(snapshot.windows.map(\.value) == [
            .amount(value: "74.5", unit: "Credits"),
            .amount(value: "25.5", unit: "Credits"),
            .amount(value: "2.5", unit: "Credits"),
            .amount(value: "10.5", unit: "Credits"),
            .amount(value: "20.5", unit: "Credits"),
        ])
        let request = try #require(await recorder.request)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openrouter-secret")
    }

    @Test("current-provider resolver reads only the selected provider credential")
    func currentProviderOnly() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-provider-quota-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let settingsURL = temporaryDirectory.appendingPathComponent("settings.json")
        let authURL = temporaryDirectory.appendingPathComponent("auth.json")
        try Data(
            #"{"defaultProvider":"openrouter","defaultModel":"anthropic/claude","backupProvider":"anthropic"}"#.utf8
        ).write(to: settingsURL)
        try Data(
            """
            {
              "openrouter": {"type":"api","key":"selected-secret"},
              "anthropic": {"type":"api","key":"backup-secret"}
            }
            """.utf8
        ).write(to: authURL)
        let resolver = CurrentQuotaProviderResolver(
            settingsURLs: [settingsURL],
            authURL: authURL,
            environment: [:]
        )

        let provider = try #require(resolver.resolve())

        #expect(provider.name == "OpenRouter")
        #expect(provider.credential?.description == "<redacted>")
        #expect(!String(describing: provider).contains("selected-secret"))
        #expect(!String(describing: provider).contains("backup-secret"))
    }

    @Test("Qwen model selection resolves its provider and selected settings credential")
    func qwenStyleCurrentProvider() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-qwen-provider-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let settingsURL = temporaryDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "model": {
                "name": "openrouter/deepseek/deepseek-chat",
                "baseUrl": "https://openrouter.ai/api/v1"
              },
              "env": {
                "OPENROUTER_API_KEY": "selected-secret",
                "ANTHROPIC_API_KEY": "backup-secret"
              }
            }
            """.utf8
        ).write(to: settingsURL)
        let resolver = CurrentQuotaProviderResolver(
            settingsURLs: [settingsURL],
            authURL: nil,
            environment: [:]
        )

        let provider = try #require(resolver.resolve())

        #expect(provider.name == "OpenRouter")
        #expect(provider.credential != nil)
        #expect(!String(describing: provider).contains("selected-secret"))
        #expect(!String(describing: provider).contains("backup-secret"))
    }

    @Test("official CLI text decoder keeps percentage direction and amount units")
    func officialCLIQuotaText() throws {
        let snapshot = try AgentQuotaCLITextDecoder.decode(
            """
            Standard Usage
            5-hour: 34% used
            Weekly: 72% remaining
            Monthly: 120 Credits remaining
            """,
            providerName: "Factory"
        )

        #expect(snapshot.windows.map(\.name) == [
            "5 小时",
            "每周",
            "每月",
        ])
        #expect(snapshot.windows.map(\.value) == [
            .percentage(value: 34, direction: .used),
            .percentage(value: 72, direction: .remaining),
            .amount(value: "120", unit: "Credits"),
        ])
    }

    @Test("official CLI fallback sends only the local quota command")
    func officialCLIUsesInformationalCommand() async throws {
        let recorder = QuotaCommandRecorder()
        let runner = AgentQuotaCommandRunner { agent, arguments, standardInput in
            await recorder.record(
                agent: agent,
                arguments: arguments,
                standardInput: standardInput
            )
            return AgentQuotaCommandOutput(
                data: Data("5-hour: 34% used\n".utf8),
                exitCode: 0
            )
        }

        let status = await AgentQuotaOfficialCLIAdapter.query(
            agent: .factoryDroid,
            providerName: "Factory",
            command: "/limits",
            commandRunner: runner
        )

        guard case .available = status else {
            Issue.record("Expected parsed Factory quota, got \(status)")
            return
        }
        let invocation = try #require(await recorder.invocation)
        #expect(invocation.agent == .factoryDroid)
        #expect(invocation.arguments.isEmpty)
        #expect(String(decoding: invocation.standardInput ?? Data(), as: UTF8.self)
            == "/limits\n/exit\n")
        let secretOutput = AgentQuotaCommandOutput(
            data: Data("raw-secret-output".utf8),
            exitCode: 1
        )
        #expect(!String(describing: secretOutput).contains("raw-secret-output"))
    }
}

private actor QuotaRequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}

private actor QuotaCommandRecorder {
    struct Invocation: Sendable {
        let agent: AgentKind
        let arguments: [String]
        let standardInput: Data?
    }

    private(set) var invocation: Invocation?

    func record(
        agent: AgentKind,
        arguments: [String],
        standardInput: Data?
    ) {
        invocation = Invocation(
            agent: agent,
            arguments: arguments,
            standardInput: standardInput
        )
    }
}
