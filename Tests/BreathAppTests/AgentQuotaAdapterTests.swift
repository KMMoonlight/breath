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

    @Test("Claude preserves an unsupported CLI result without an OAuth credential")
    func claudeWithoutOAuthPreservesUnsupportedFallback() async {
        let client = AgentQuotaHTTPClient { _ in
            Issue.record("HTTP must not run without a Claude OAuth credential")
            throw CancellationError()
        }

        let status = await ClaudeAgentQuotaAdapter.query(
            credentialProvider: { nil },
            httpClient: client,
            fallback: { .unsupported }
        )

        #expect(status == .unsupported)
    }

    @Test("Kimi preserves its official weekly, rolling, and extra-usage limits")
    func kimiQuotaResponse() throws {
        let snapshot = try KimiAgentQuotaAdapter.decode(
            Data(
                """
                {
                  "usage": {
                    "used": "40",
                    "limit": "1000",
                    "resetTime": "2030-01-01T00:00:00Z"
                  },
                  "limits": [
                    {
                      "window": {
                        "duration": 300,
                        "timeUnit": "TIME_UNIT_MINUTE"
                      },
                      "detail": {
                        "used": "25",
                        "limit": "100",
                        "resetTime": "2030-01-02T00:00:00Z"
                      }
                    }
                  ],
                  "boosterWallet": {
                    "balance": {
                      "type": "BOOSTER",
                      "amount": "20000000000",
                      "amountLeft": "10000000000"
                    },
                    "monthlyChargeLimitEnabled": true,
                    "monthlyChargeLimit": {
                      "currency": "USD",
                      "priceInCents": "20000"
                    },
                    "monthlyUsed": {
                      "currency": "USD",
                      "priceInCents": "5000"
                    }
                  }
                }
                """.utf8
            )
        )

        #expect(snapshot.providerName == "Kimi Code")
        #expect(snapshot.windows.map(\.name) == [
            "每周",
            "5 小时",
            "Extra Usage",
        ])
        #expect(snapshot.windows.map(\.value) == [
            .percentage(value: 4, direction: .used),
            .percentage(value: 25, direction: .used),
            .amount(value: "50 / 200", unit: "USD"),
        ])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test("Kimi sends its in-memory OAuth token only to the official usage endpoint")
    func kimiQuotaRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-kimi-adapter-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeKimiCredential(
            homeDirectory: directory,
            accessToken: "kimi-test-access",
            refreshToken: "kimi-test-refresh"
        )
        let recorder = QuotaRequestRecorder()
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
            return (
                Data(#"{"usage":{"used":"20","limit":"100"}}"#.utf8),
                response
            )
        }

        let status = await KimiAgentQuotaAdapter.query(
            credentialStore: AgentQuotaCredentialStore(
                homeDirectory: directory
            ),
            httpClient: client
        )

        guard case .available = status else {
            Issue.record("Expected available Kimi quota, got \(status)")
            return
        }
        let request = try #require(await recorder.request)
        #expect(
            request.url?.absoluteString
                == "https://api.kimi.com/coding/v1/usages"
        )
        #expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Bearer kimi-test-access"
        )
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(!String(describing: status).contains("kimi-test-access"))
        #expect(!String(describing: status).contains("kimi-test-refresh"))
    }

    @Test("Kimi refreshes an expired OAuth token with the official flow and persists the rotation")
    func kimiRefreshesExpiredCredential() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-kimi-refresh-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeKimiCredential(
            homeDirectory: directory,
            accessToken: "expired-access",
            refreshToken: "old-refresh"
        )
        let recorder = QuotaRequestSequenceRecorder()
        let client = AgentQuotaHTTPClient { request in
            let index = await recorder.record(request)
            let statusCode: Int
            let data: Data
            switch index {
            case 0:
                statusCode = 401
                data = Data()
            case 1:
                statusCode = 200
                data = Data(
                    """
                    {
                      "access_token": "rotated-access",
                      "refresh_token": "rotated-refresh",
                      "expires_in": 900,
                      "scope": "kimi-code",
                      "token_type": "Bearer"
                    }
                    """.utf8
                )
            default:
                statusCode = 200
                data = Data(
                    #"{"usage":{"used":"10","limit":"100"}}"#.utf8
                )
            }
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
            )
            return (data, response)
        }

        let status = await KimiAgentQuotaAdapter.query(
            credentialStore: AgentQuotaCredentialStore(
                homeDirectory: directory
            ),
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        guard case .available = status else {
            Issue.record("Expected refreshed Kimi quota, got \(status)")
            return
        }
        let requests = await recorder.requests
        #expect(requests.map { $0.url?.absoluteString } == [
            "https://api.kimi.com/coding/v1/usages",
            "https://auth.kimi.com/api/oauth/token",
            "https://api.kimi.com/coding/v1/usages",
        ])
        #expect(
            String(decoding: requests[1].httpBody ?? Data(), as: UTF8.self)
                == "client_id=17e5f671-d194-4dfb-9706-5516cb48c098&grant_type=refresh_token&refresh_token=old-refresh"
        )
        let credentialURL = directory
            .appendingPathComponent(".kimi-code/credentials/kimi-code.json")
        let stored = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: credentialURL)
            ) as? [String: Any]
        )
        #expect(stored["access_token"] as? String == "rotated-access")
        #expect(stored["refresh_token"] as? String == "rotated-refresh")
        #expect(stored["expires_at"] as? Double == 1_800_000_900)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: credentialURL.path
        )[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
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

    @Test("Qwen current settings schema resolves OpenRouter from the selected model endpoint")
    func qwenCurrentSettingsProvider() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-qwen-current-provider-\(UUID())",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let settingsURL = temporaryDirectory.appendingPathComponent("settings.json")
        try Data(
            """
            {
              "security": {
                "auth": {
                  "selectedType": "openai"
                }
              },
              "model": {
                "name": "deepseek/deepseek-chat",
                "baseUrl": "https://openrouter.ai/api/v1"
              },
              "modelProviders": {
                "openai": [
                  {
                    "id": "deepseek/deepseek-chat",
                    "baseUrl": "https://openrouter.ai/api/v1",
                    "envKey": "OPENROUTER_API_KEY"
                  }
                ]
              }
            }
            """.utf8
        ).write(to: settingsURL)
        let resolver = CurrentQuotaProviderResolver(
            settingsURLs: [settingsURL],
            authURL: nil,
            environment: [
                "OPENROUTER_API_KEY": "selected-secret",
            ]
        )

        let provider = try #require(resolver.resolve())

        #expect(provider.id == "openrouter")
        #expect(provider.name == "OpenRouter")
        #expect(provider.credential != nil)
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

    @Test("official CLI decoder preserves reset text it cannot safely convert")
    func officialCLIResetText() throws {
        let snapshot = try AgentQuotaCLITextDecoder.decode(
            "5-hour: 34% used; resets in 2 hours",
            providerName: "Factory"
        )

        #expect(snapshot.windows.first?.resetsAt == nil)
        #expect(snapshot.windows.first?.resetDescription == "resets in 2 hours")
    }

    @Test("official CLI decoder reads Claude subscription usage screen")
    func officialCLIReadsClaudeUsageScreen() throws {
        let snapshot = try AgentQuotaCLITextDecoder.decode(
            """
            Current session
            [=================                                 ] 34% used
            Resets in 2 hours

            Current week (all models)
            [====================================              ] 72% used
            Resets Aug 1 at 9:00 AM
            """,
            providerName: "Anthropic"
        )

        #expect(snapshot.windows.map(\.name) == ["5 小时", "每周"])
        #expect(snapshot.windows.map(\.value) == [
            .percentage(value: 34, direction: .used),
            .percentage(value: 72, direction: .used),
        ])
        #expect(snapshot.windows.map(\.resetDescription) == [
            "Resets in 2 hours",
            "Resets Aug 1 at 9:00 AM",
        ])
    }

    @Test("official CLI decoder reads multiline TUI quota groups")
    func officialCLIMultilineQuotaGroups() throws {
        let snapshot = try AgentQuotaCLITextDecoder.decode(
            """
            \u{001B}[32mGEMINI MODELS\u{001B}[0m
            Weekly Limit
            [====================] 93.79%
            94% remaining · Refreshes in 155h 41m

            CLAUDE AND GPT MODELS
            Weekly Limit
            [===============     ] 73.41%
            73% remaining · Refreshes in 46h 38m
            """,
            providerName: "Google Antigravity"
        )

        #expect(snapshot.windows.map(\.name) == [
            "Gemini · 每周",
            "Claude / GPT · 每周",
        ])
        #expect(snapshot.windows.map(\.value) == [
            .percentage(value: 94, direction: .remaining),
            .percentage(value: 73, direction: .remaining),
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

    @Test("official CLI format failures are reported as failures")
    func officialCLIFormatFailure() async {
        let runner = AgentQuotaCommandRunner { _, _, _ in
            AgentQuotaCommandOutput(
                data: Data("format changed".utf8),
                exitCode: 0
            )
        }

        let status = await AgentQuotaOfficialCLIAdapter.query(
            agent: .factoryDroid,
            providerName: "Factory",
            command: "/limits",
            commandRunner: runner
        )

        #expect(status == .failed("额度响应格式无法识别。"))
    }

    @Test("Claude API-billing sessions report unsupported account quota")
    func claudeAPIBillingIsUnsupported() async {
        let runner = AgentQuotaCommandRunner { _, _, _ in
            AgentQuotaCommandOutput(
                data: Data(
                    """
                    Welcome back!
                    deepseek-v4-pro · API Usage Billing
                    Settings  Status  Config  Usage  Stats
                    Session
                    Total cost: $0.0000
                    """.utf8
                ),
                exitCode: 0
            )
        }

        let status = await AgentQuotaOfficialCLIAdapter.query(
            agent: .claudeCode,
            providerName: "Anthropic",
            command: "/usage",
            commandRunner: runner
        )

        #expect(status == .unsupported)
    }

    @Test("a cleanup command error does not discard an already parsed quota")
    func officialCLICleanupErrorAfterQuota() async {
        let runner = AgentQuotaCommandRunner { _, _, _ in
            AgentQuotaCommandOutput(
                data: Data(
                    """
                    5-hour: 34% used
                    unknown command: /exit
                    """.utf8
                ),
                exitCode: 1
            )
        }

        let status = await AgentQuotaOfficialCLIAdapter.query(
            agent: .factoryDroid,
            providerName: "Factory",
            command: "/limits",
            commandRunner: runner
        )

        guard case let .available(snapshot) = status else {
            Issue.record("Expected parsed quota, got \(status)")
            return
        }
        #expect(snapshot.windows.first?.value == .percentage(
            value: 34,
            direction: .used
        ))
    }

    @Test("Claude does not infer warning state from percentage values")
    func claudeDoesNotInferWarningThreshold() throws {
        let snapshot = try ClaudeAgentQuotaAdapter.decode(
            Data(
                """
                {
                  "five_hour": {
                    "utilization": 100
                  }
                }
                """.utf8
            )
        )

        #expect(snapshot.windows.first?.warning == false)
    }
}

private func writeKimiCredential(
    homeDirectory: URL,
    accessToken: String,
    refreshToken: String
) throws {
    let directory = homeDirectory
        .appendingPathComponent(".kimi-code/credentials", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let url = directory.appendingPathComponent("kimi-code.json")
    try Data(
        """
        {
          "access_token": "\(accessToken)",
          "refresh_token": "\(refreshToken)",
          "expires_at": 1,
          "expires_in": 900,
          "scope": "kimi-code",
          "token_type": "Bearer"
        }
        """.utf8
    ).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
    )
}

private actor QuotaRequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}

private actor QuotaRequestSequenceRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) -> Int {
        let index = requests.count
        requests.append(request)
        return index
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
