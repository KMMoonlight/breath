import BreathAgents
import Foundation

struct AgentQuotaSecret: CustomDebugStringConvertible, CustomStringConvertible, Sendable {
    fileprivate let value: String

    init(_ value: String) {
        self.value = value
    }

    var description: String { "<redacted>" }
    var debugDescription: String { "<redacted>" }
}

struct AgentQuotaCredential: CustomStringConvertible, Sendable {
    let bearerToken: AgentQuotaSecret
    let accountID: String?
    let maskedAccount: String?

    var description: String {
        "AgentQuotaCredential(bearerToken: <redacted>, accountID: <redacted>, maskedAccount: \(maskedAccount ?? "nil"))"
    }
}

struct AgentQuotaHTTPClient: Sendable {
    private let send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(
        send: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) {
        self.send = send
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(request)
    }

    static func live(
        sessionProvider: @escaping @Sendable () -> URLSession
    ) -> AgentQuotaHTTPClient {
        AgentQuotaHTTPClient { request in
            guard let allowedHost = request.url?.host else {
                throw AgentQuotaAdapterError.invalidResponse
            }
            let delegate = AgentQuotaRedirectDelegate(
                allowedHost: allowedHost
            )
            let (data, response) = try await sessionProvider().data(
                for: request,
                delegate: delegate
            )
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AgentQuotaAdapterError.invalidResponse
            }
            return (data, httpResponse)
        }
    }
}

private final class AgentQuotaRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    private let allowedHost: String

    init(allowedHost: String) {
        self.allowedHost = allowedHost
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https",
              request.url?.host?.caseInsensitiveCompare(allowedHost)
                == .orderedSame
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

struct AgentQuotaCredentialStore: Sendable {
    let homeDirectory: URL
    let environment: [String: String]

    init(
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    func codexCredential() -> AgentQuotaCredential? {
        let configurationDirectory: URL
        if let configuredPath = environment["CODEX_HOME"],
           NSString(string: configuredPath).isAbsolutePath
        {
            configurationDirectory = URL(
                fileURLWithPath: configuredPath,
                isDirectory: true
            )
        } else {
            configurationDirectory = homeDirectory
                .appendingPathComponent(".codex", isDirectory: true)
        }
        let authURL = configurationDirectory.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONDecoder().decode(CodexAuth.self, from: data),
              let accessToken = auth.tokens?.accessToken,
              !accessToken.isEmpty
        else {
            return nil
        }
        return AgentQuotaCredential(
            bearerToken: AgentQuotaSecret(accessToken),
            accountID: auth.tokens?.accountID,
            maskedAccount: nil
        )
    }

    func claudeCredential(
        keychainReader: @Sendable (String) -> String? = AgentQuotaKeychainReader.read
    ) -> AgentQuotaSecret? {
        let configurationDirectory: URL
        if let configuredPath = environment["CLAUDE_CONFIG_DIR"],
           NSString(string: configuredPath).isAbsolutePath
        {
            configurationDirectory = URL(
                fileURLWithPath: configuredPath,
                isDirectory: true
            )
        } else {
            configurationDirectory = homeDirectory
                .appendingPathComponent(".claude", isDirectory: true)
        }
        let credentialsURL = configurationDirectory
            .appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: credentialsURL),
           let token = Self.claudeAccessToken(in: data)
        {
            return AgentQuotaSecret(token)
        }
        guard let keychainValue = keychainReader("Claude Code-credentials"),
              let token = Self.claudeAccessToken(in: Data(keychainValue.utf8))
        else {
            return nil
        }
        return AgentQuotaSecret(token)
    }

    private static func claudeAccessToken(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            return nil
        }
        let oauth = object["claudeAiOauth"] as? [String: Any]
        let token = oauth?["accessToken"] as? String
            ?? object["accessToken"] as? String
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    private struct CodexAuth: Decodable {
        let tokens: Tokens?
    }

    private struct Tokens: Decodable {
        let accessToken: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }
}

private enum AgentQuotaKeychainReader {
    static func read(service: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s",
            service,
            "-w",
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum AgentQuotaAdapterError: LocalizedError, Equatable, Sendable {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "额度响应格式无法识别。"
        }
    }
}

enum CodexAgentQuotaAdapter {
    static func query(
        credentialProvider: @escaping @Sendable () async -> AgentQuotaCredential?,
        httpClient: AgentQuotaHTTPClient,
        fallback: @escaping AgentQuotaQuery = { .unsupported }
    ) async -> AgentQuotaStatus {
        guard let credential = await credentialProvider() else {
            let fallbackStatus = await fallback()
            return fallbackStatus == .unsupported ? .notLoggedIn : fallbackStatus
        }
        guard let url = URL(
            string: "https://chatgpt.com/backend-api/wham/usage"
        ) else {
            return .failed("额度查询失败。")
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 8
        )
        request.setValue(
            "Bearer \(credential.bearerToken.value)",
            forHTTPHeaderField: "Authorization"
        )
        if let accountID = credential.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Breath", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await httpClient.data(for: request)
            if response.statusCode == 401 || response.statusCode == 403 {
                let fallbackStatus = await fallback()
                return fallbackStatus == .unsupported ? .notLoggedIn : fallbackStatus
            }
            guard (200..<300).contains(response.statusCode) else {
                return await fallbackOrFailure(
                    fallback,
                    reason: "额度查询失败。"
                )
            }
            do {
                return .available(
                    try decode(data, maskedAccount: credential.maskedAccount)
                )
            } catch {
                return await fallbackOrFailure(
                    fallback,
                    reason: "额度响应格式无法识别。"
                )
            }
        } catch is CancellationError {
            return .failed("额度查询已取消。")
        } catch {
            return await fallbackOrFailure(
                fallback,
                reason: "额度查询失败。"
            )
        }
    }

    static func decode(
        _ data: Data,
        maskedAccount: String?
    ) throws -> AgentQuotaSnapshot {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AgentQuotaAdapterError.invalidResponse
        }

        var windows: [AgentQuotaWindow] = []
        if let primary = response.rateLimit?.primaryWindow {
            windows.append(window(primary))
        }
        if let secondary = response.rateLimit?.secondaryWindow {
            windows.append(window(secondary))
        }
        if let credits = response.credits {
            if credits.unlimited == true {
                windows.append(
                    AgentQuotaWindow(
                        name: "Credits",
                        value: .amount(value: "无限", unit: nil),
                        resetsAt: nil,
                        warning: false
                    )
                )
            } else if let balance = credits.balance {
                windows.append(
                    AgentQuotaWindow(
                        name: "Credits",
                        value: .amount(value: balance, unit: "Credits"),
                        resetsAt: nil,
                        warning: false
                    )
                )
            }
        }
        guard !windows.isEmpty else {
            throw AgentQuotaAdapterError.invalidResponse
        }
        return AgentQuotaSnapshot(
            providerName: "OpenAI",
            maskedAccount: maskedAccount,
            windows: windows
        )
    }

    private static func window(_ source: RateLimitWindow) -> AgentQuotaWindow {
        AgentQuotaWindow(
            name: windowName(seconds: source.limitWindowSeconds),
            value: .percentage(value: source.usedPercent, direction: .used),
            resetsAt: source.resetAt.map(Date.init(timeIntervalSince1970:)),
            warning: source.limitReached ?? false
        )
    }

    private static func windowName(seconds: Int?) -> String {
        switch seconds {
        case 18_000:
            "5 小时"
        case 604_800:
            "每周"
        case let seconds?:
            "\(seconds) 秒"
        case nil:
            "额度"
        }
    }

    private static func fallbackOrFailure(
        _ fallback: AgentQuotaQuery,
        reason: String
    ) async -> AgentQuotaStatus {
        let fallbackStatus = await fallback()
        return fallbackStatus == .unsupported ? .failed(reason) : fallbackStatus
    }

    private struct Response: Decodable {
        let rateLimit: RateLimit?
        let credits: Credits?

        enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
            case credits
        }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: RateLimitWindow?
        let secondaryWindow: RateLimitWindow?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    private struct RateLimitWindow: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAt: TimeInterval?
        let limitReached: Bool?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
            case limitReached = "limit_reached"
        }
    }

    private struct Credits: Decodable {
        let unlimited: Bool?
        let balance: String?
    }
}

enum CodexAgentQuotaAppServer {
    static func decode(_ data: Data) throws -> AgentQuotaSnapshot {
        let response = data
            .split(separator: 0x0A)
            .lazy
            .compactMap { line -> ResponseEnvelope? in
                try? JSONDecoder().decode(ResponseEnvelope.self, from: Data(line))
            }
            .first { $0.id == 2 && $0.result != nil }
        guard let result = response?.result else {
            throw AgentQuotaAdapterError.invalidResponse
        }
        var windows: [AgentQuotaWindow] = []
        if let limits = result.rateLimits {
            append(limits, prefix: nil, to: &windows)
        }
        for (identifier, limits) in result.rateLimitsByLimitID?.sorted(
            by: { $0.key < $1.key }
        ) ?? [] {
            guard identifier != "codex", identifier != "default" else {
                continue
            }
            append(
                limits,
                prefix: limits.limitName ?? identifier,
                to: &windows
            )
        }
        guard !windows.isEmpty else {
            throw AgentQuotaAdapterError.invalidResponse
        }
        return AgentQuotaSnapshot(
            providerName: "OpenAI",
            maskedAccount: nil,
            windows: windows
        )
    }

    private static func append(
        _ limits: RateLimits,
        prefix: String?,
        to windows: inout [AgentQuotaWindow]
    ) {
        let warning = limits.rateLimitReachedType?.isEmpty == false
        if let primary = limits.primary {
            windows.append(window(primary, prefix: prefix, warning: warning))
        }
        if let secondary = limits.secondary {
            windows.append(window(secondary, prefix: prefix, warning: warning))
        }
        if let credits = limits.credits {
            if credits.unlimited == true {
                windows.append(
                    AgentQuotaWindow(
                        name: prefixed("Credits", with: prefix),
                        value: .amount(value: "无限", unit: nil),
                        resetsAt: nil,
                        warning: warning
                    )
                )
            } else if let balance = credits.balance {
                windows.append(
                    AgentQuotaWindow(
                        name: prefixed("Credits", with: prefix),
                        value: .amount(value: balance, unit: "Credits"),
                        resetsAt: nil,
                        warning: warning
                    )
                )
            }
        }
    }

    private static func window(
        _ source: RateLimitWindow,
        prefix: String?,
        warning: Bool
    ) -> AgentQuotaWindow {
        AgentQuotaWindow(
            name: prefixed(
                windowName(minutes: source.windowDurationMins),
                with: prefix
            ),
            value: .percentage(
                value: source.usedPercent,
                direction: .used
            ),
            resetsAt: source.resetsAt.map(Date.init(timeIntervalSince1970:)),
            warning: warning
        )
    }

    private static func prefixed(_ name: String, with prefix: String?) -> String {
        guard let prefix, !prefix.isEmpty else { return name }
        return "\(prefix) · \(name)"
    }

    private static func windowName(minutes: Int?) -> String {
        switch minutes {
        case 300:
            "5 小时"
        case 10_080:
            "每周"
        case 43_200:
            "每月"
        case let minutes?:
            "\(minutes) 分钟"
        case nil:
            "额度"
        }
    }

    private struct ResponseEnvelope: Decodable {
        let id: Int?
        let result: Result?
    }

    private struct Result: Decodable {
        let rateLimits: RateLimits?
        let rateLimitsByLimitID: [String: RateLimits]?

        enum CodingKeys: String, CodingKey {
            case rateLimits
            case rateLimitsByLimitID = "rateLimitsByLimitId"
        }
    }

    private struct RateLimits: Decodable {
        let limitName: String?
        let primary: RateLimitWindow?
        let secondary: RateLimitWindow?
        let rateLimitReachedType: String?
        let credits: Credits?
    }

    private struct RateLimitWindow: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: TimeInterval?
    }

    private struct Credits: Decodable {
        let unlimited: Bool?
        let balance: String?
    }
}

enum AgentQuotaCLITextDecoder {
    static func decode(
        _ output: String,
        providerName: String
    ) throws -> AgentQuotaSnapshot {
        var windows: [AgentQuotaWindow] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let name = windowName(in: line) else { continue }
            let reset = resetDetails(in: line)
            let warning = line.range(
                of: #"limit\s+reached|exhausted|depleted"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            if let percentage = firstMatch(
                #"([0-9]+(?:\.[0-9]+)?)\s*%\s*(used|remaining)"#,
                in: line
            ), let value = Double(percentage[0]) {
                windows.append(
                    AgentQuotaWindow(
                        name: name,
                        value: .percentage(
                            value: value,
                            direction: percentage[1].lowercased() == "remaining"
                                ? .remaining
                                : .used
                        ),
                        resetsAt: reset.date,
                        resetDescription: reset.description,
                        warning: warning
                    )
                )
                continue
            }
            if let percentage = firstMatch(
                #"(used|remaining)[^0-9]*([0-9]+(?:\.[0-9]+)?)\s*%"#,
                in: line
            ), let value = Double(percentage[1]) {
                windows.append(
                    AgentQuotaWindow(
                        name: name,
                        value: .percentage(
                            value: value,
                            direction: percentage[0].lowercased() == "remaining"
                                ? .remaining
                                : .used
                        ),
                        resetsAt: reset.date,
                        resetDescription: reset.description,
                        warning: warning
                    )
                )
                continue
            }
            if let amount = firstMatch(
                #"([0-9]+(?:\.[0-9]+)?)\s*(Credits?|requests?|tokens?|USD)"#,
                in: line
            ) {
                windows.append(
                    AgentQuotaWindow(
                        name: name,
                        value: .amount(
                            value: amount[0],
                            unit: amount[1]
                        ),
                        resetsAt: reset.date,
                        resetDescription: reset.description,
                        warning: warning
                    )
                )
            }
        }
        guard !windows.isEmpty else {
            throw AgentQuotaAdapterError.invalidResponse
        }
        return AgentQuotaSnapshot(
            providerName: providerName,
            maskedAccount: nil,
            windows: windows
        )
    }

    private static func windowName(in line: String) -> String? {
        let lowercased = line.lowercased()
        if lowercased.range(
            of: #"\b5(?:-| )?(?:hour|hours|hr|hrs)\b|\b5h\b"#,
            options: .regularExpression
        ) != nil {
            return "5 小时"
        }
        if lowercased.contains("weekly")
            || lowercased.range(
                of: #"\b7(?:-| )?day\b"#,
                options: .regularExpression
            ) != nil
        {
            return "每周"
        }
        if lowercased.contains("monthly")
            || lowercased.range(
                of: #"\b30(?:-| )?day\b"#,
                options: .regularExpression
            ) != nil
        {
            return "每月"
        }
        if lowercased.contains("credit") {
            return "Credits"
        }
        if lowercased.contains("request") {
            return "Requests"
        }
        return nil
    }

    private static func resetDetails(
        in line: String
    ) -> (date: Date?, description: String?) {
        if let timestamp = firstMatch(
            #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))"#,
            in: line
        )?.first {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]
            let date = formatter.date(from: timestamp) ?? {
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: timestamp)
            }()
            if let date {
                return (date, nil)
            }
        }
        let description = firstMatch(
            #"((?:resets?|resetting)\b[^,;]*)$"#,
            in: line
        )?.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            nil,
            description.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func firstMatch(
        _ pattern: String,
        in string: String
    ) -> [String]? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = expression.firstMatch(
            in: string,
            options: [],
            range: range
        ) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: string) else {
                return nil
            }
            return String(string[range])
        }
    }
}

enum ClaudeAgentQuotaAdapter {
    static func query(
        credentialProvider: @escaping @Sendable () async -> AgentQuotaSecret?,
        httpClient: AgentQuotaHTTPClient,
        fallback: @escaping AgentQuotaQuery
    ) async -> AgentQuotaStatus {
        guard let credential = await credentialProvider() else {
            let fallbackStatus = await fallback()
            return fallbackStatus == .unsupported ? .notLoggedIn : fallbackStatus
        }
        guard let url = URL(
            string: "https://api.anthropic.com/api/oauth/usage"
        ) else {
            return .failed("额度查询失败。")
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 8
        )
        request.setValue(
            "Bearer \(credential.value)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "oauth-2025-04-20",
            forHTTPHeaderField: "anthropic-beta"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Breath", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await httpClient.data(for: request)
            if response.statusCode == 401 || response.statusCode == 403 {
                let fallbackStatus = await fallback()
                return fallbackStatus == .unsupported ? .notLoggedIn : fallbackStatus
            }
            guard (200..<300).contains(response.statusCode) else {
                return await fallbackOrFailure(
                    fallback,
                    reason: "额度查询失败。"
                )
            }
            do {
                return .available(try decode(data))
            } catch {
                return await fallbackOrFailure(
                    fallback,
                    reason: "额度响应格式无法识别。"
                )
            }
        } catch is CancellationError {
            return .failed("额度查询已取消。")
        } catch {
            return await fallbackOrFailure(
                fallback,
                reason: "额度查询失败。"
            )
        }
    }

    static func decode(_ data: Data) throws -> AgentQuotaSnapshot {
        let response: Response
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            response = try decoder.decode(Response.self, from: data)
        } catch {
            throw AgentQuotaAdapterError.invalidResponse
        }
        var windows: [AgentQuotaWindow] = []
        append(response.fiveHour, named: "5 小时", to: &windows)
        append(response.sevenDay, named: "每周", to: &windows)
        append(response.sevenDayOpus, named: "每周 Opus", to: &windows)
        append(response.sevenDaySonnet, named: "每周 Sonnet", to: &windows)
        if let extraUsage = response.extraUsage, extraUsage.isEnabled != false {
            if let used = extraUsage.usedCredits,
               let limit = extraUsage.monthlyLimit
            {
                windows.append(
                    AgentQuotaWindow(
                        name: "Extra Usage",
                        value: .amount(
                            value: "\(quotaNumber(used)) / \(quotaNumber(limit))",
                            unit: "Credits"
                        ),
                        resetsAt: nil,
                        warning: false
                    )
                )
            } else if let utilization = extraUsage.utilization {
                windows.append(
                    AgentQuotaWindow(
                        name: "Extra Usage",
                        value: .percentage(
                            value: utilization,
                            direction: .used
                        ),
                        resetsAt: nil,
                        warning: false
                    )
                )
            }
        }
        guard !windows.isEmpty else {
            throw AgentQuotaAdapterError.invalidResponse
        }
        return AgentQuotaSnapshot(
            providerName: "Anthropic",
            maskedAccount: nil,
            windows: windows
        )
    }

    private static func append(
        _ source: UsageWindow?,
        named name: String,
        to windows: inout [AgentQuotaWindow]
    ) {
        guard let utilization = source?.utilization else { return }
        windows.append(
            AgentQuotaWindow(
                name: name,
                value: .percentage(value: utilization, direction: .used),
                resetsAt: source?.resetsAt,
                warning: false
            )
        )
    }

    private static func fallbackOrFailure(
        _ fallback: AgentQuotaQuery,
        reason: String
    ) async -> AgentQuotaStatus {
        let fallbackStatus = await fallback()
        return fallbackStatus == .unsupported ? .failed(reason) : fallbackStatus
    }

    private struct Response: Decodable {
        let fiveHour: UsageWindow?
        let sevenDay: UsageWindow?
        let sevenDayOpus: UsageWindow?
        let sevenDaySonnet: UsageWindow?
        let extraUsage: ExtraUsage?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
            case extraUsage = "extra_usage"
        }
    }

    private struct UsageWindow: Decodable {
        let utilization: Double?
        let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    private struct ExtraUsage: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case utilization
        }
    }
}

enum OpenRouterQuotaAdapter {
    static func query(
        credential: AgentQuotaSecret,
        httpClient: AgentQuotaHTTPClient
    ) async -> AgentQuotaStatus {
        guard let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits"),
              let currentKeyURL = URL(string: "https://openrouter.ai/api/v1/key")
        else {
            return .failed("额度查询失败。")
        }
        do {
            let creditsResponse = try await httpClient.data(
                for: request(url: creditsURL, credential: credential)
            )
            if creditsResponse.1.statusCode == 401 {
                return .notLoggedIn
            }
            if (200..<300).contains(creditsResponse.1.statusCode) {
                return .available(try decode(creditsResponse.0))
            }
            guard creditsResponse.1.statusCode == 403 else {
                return .failed("额度查询失败。")
            }

            let keyResponse = try await httpClient.data(
                for: request(url: currentKeyURL, credential: credential)
            )
            if keyResponse.1.statusCode == 401 || keyResponse.1.statusCode == 403 {
                return .notLoggedIn
            }
            guard (200..<300).contains(keyResponse.1.statusCode) else {
                return .failed("额度查询失败。")
            }
            return .available(try decodeCurrentKey(keyResponse.0))
        } catch is CancellationError {
            return .failed("额度查询已取消。")
        } catch let error as AgentQuotaAdapterError {
            return .failed(error.localizedDescription)
        } catch {
            return .failed("额度查询失败。")
        }
    }

    private static func request(
        url: URL,
        credential: AgentQuotaSecret
    ) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.setValue(
            "Bearer \(credential.value)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Breath", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func decode(_ data: Data) throws -> AgentQuotaSnapshot {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AgentQuotaAdapterError.invalidResponse
        }
        return AgentQuotaSnapshot(
            providerName: "OpenRouter",
            maskedAccount: nil,
            windows: [
                AgentQuotaWindow(
                    name: "Total Credits",
                    value: .amount(
                        value: quotaNumber(response.data.totalCredits),
                        unit: "Credits"
                    ),
                    resetsAt: nil,
                    warning: false
                ),
                AgentQuotaWindow(
                    name: "Total Usage",
                    value: .amount(
                        value: quotaNumber(response.data.totalUsage),
                        unit: "Credits"
                    ),
                    resetsAt: nil,
                    warning: false
                ),
            ]
        )
    }

    static func decodeCurrentKey(_ data: Data) throws -> AgentQuotaSnapshot {
        let response: CurrentKeyResponse
        do {
            response = try JSONDecoder().decode(CurrentKeyResponse.self, from: data)
        } catch {
            throw AgentQuotaAdapterError.invalidResponse
        }
        let values: [(String, Double?)] = [
            ("Credits Remaining", response.data.limitRemaining),
            ("Total Usage", response.data.usage),
            ("Daily Usage", response.data.usageDaily),
            ("Weekly Usage", response.data.usageWeekly),
            ("Monthly Usage", response.data.usageMonthly),
        ]
        return AgentQuotaSnapshot(
            providerName: "OpenRouter",
            maskedAccount: nil,
            windows: values.compactMap { name, value in
                guard let value else { return nil }
                return AgentQuotaWindow(
                    name: name,
                    value: .amount(
                        value: quotaNumber(value),
                        unit: "Credits"
                    ),
                    resetsAt: nil,
                    warning: false
                )
            }
        )
    }

    private struct Response: Decodable {
        let data: Credits
    }

    private struct Credits: Decodable {
        let totalCredits: Double
        let totalUsage: Double

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }

    private struct CurrentKeyResponse: Decodable {
        let data: CurrentKey
    }

    private struct CurrentKey: Decodable {
        let limitRemaining: Double?
        let usage: Double?
        let usageDaily: Double?
        let usageWeekly: Double?
        let usageMonthly: Double?

        enum CodingKeys: String, CodingKey {
            case limitRemaining = "limit_remaining"
            case usage
            case usageDaily = "usage_daily"
            case usageWeekly = "usage_weekly"
            case usageMonthly = "usage_monthly"
        }
    }
}

struct ResolvedQuotaProvider: CustomStringConvertible, Sendable {
    let id: String
    let name: String
    let credential: AgentQuotaSecret?

    var description: String {
        "ResolvedQuotaProvider(id: \(id), name: \(name), credential: <redacted>)"
    }
}

struct CurrentQuotaProviderResolver: Sendable {
    let settingsURLs: [URL]
    let authURL: URL?
    let environment: [String: String]

    func resolve() -> ResolvedQuotaProvider? {
        guard let providerID = selectedProviderID() else { return nil }
        return ResolvedQuotaProvider(
            id: providerID,
            name: Self.displayName(for: providerID),
            credential: credential(for: providerID)
        )
    }

    func providerName() -> String? {
        selectedProviderID().map(Self.displayName(for:))
    }

    private func selectedProviderID() -> String? {
        for url in settingsURLs {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else {
                continue
            }
            if let provider = firstString(
                in: object,
                keys: ["defaultProvider", "selectedProvider", "provider"]
            ) {
                return provider.lowercased()
            }
            if let model = object["model"] as? [String: Any],
               let provider = firstString(
                   in: model,
                   keys: ["provider", "providerID", "providerId"]
               )
            {
                return provider.lowercased()
            }
            if let model = object["model"] as? [String: Any],
               let modelName = firstString(in: model, keys: ["name"]),
               let separator = modelName.firstIndex(of: "/"),
               separator != modelName.startIndex
            {
                return String(modelName[..<separator]).lowercased()
            }
            if let model = firstString(
                in: object,
                keys: ["defaultModel", "selectedModel", "model"]
            ),
               let separator = model.firstIndex(of: "/"),
               separator != model.startIndex
            {
                return String(model[..<separator]).lowercased()
            }
        }
        return nil
    }

    private func credential(for providerID: String) -> AgentQuotaSecret? {
        if let environmentKey = Self.environmentKey(for: providerID),
           let value = environment[environmentKey],
           !value.isEmpty
        {
            return AgentQuotaSecret(value)
        }
        if let environmentKey = Self.environmentKey(for: providerID) {
            for url in settingsURLs {
                guard let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                      let settingsEnvironment = object["env"] as? [String: Any],
                      let value = settingsEnvironment[environmentKey] as? String,
                      !value.isEmpty
                else {
                    continue
                }
                return AgentQuotaSecret(value)
            }
        }
        guard let authURL,
              let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let selected = object[providerID] as? [String: Any],
              let value = firstString(
                  in: selected,
                  keys: ["key", "apiKey", "accessToken", "token"]
              )
        else {
            return nil
        }
        return AgentQuotaSecret(value)
    }

    private func firstString(
        in object: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func environmentKey(for providerID: String) -> String? {
        switch providerID {
        case "openrouter":
            "OPENROUTER_API_KEY"
        default:
            nil
        }
    }

    private static func displayName(for providerID: String) -> String {
        switch providerID {
        case "openrouter":
            "OpenRouter"
        case "anthropic":
            "Anthropic"
        case "openai":
            "OpenAI"
        case "google", "gemini":
            "Google"
        default:
            providerID
        }
    }
}

enum CurrentProviderQuotaAdapter {
    static func query(
        resolver: CurrentQuotaProviderResolver,
        httpClient: AgentQuotaHTTPClient
    ) async -> AgentQuotaStatus {
        guard let provider = resolver.resolve() else {
            return .unsupported
        }
        switch provider.id {
        case "openrouter":
            guard let credential = provider.credential else {
                return .notLoggedIn
            }
            return await OpenRouterQuotaAdapter.query(
                credential: credential,
                httpClient: httpClient
            )
        default:
            return .unsupported
        }
    }
}

private func quotaNumber(_ value: Double) -> String {
    if value.isFinite, value.rounded() == value,
       value >= Double(Int64.min), value <= Double(Int64.max)
    {
        return String(Int64(value))
    }
    return String(value)
}

extension AgentQuotaService {
    static func live(
        homeDirectory: URL,
        detector: InstalledAgentCLIDetector,
        sessionProvider: @escaping @Sendable () -> URLSession,
        processEnvironment: @escaping
            @Sendable ([String: String]) -> [String: String] = {
                NetworkSessionManager.shared.processEnvironment(basedOn: $0)
            },
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AgentQuotaService {
        let credentialStore = AgentQuotaCredentialStore(
            homeDirectory: homeDirectory,
            environment: environment
        )
        let httpClient = AgentQuotaHTTPClient.live(sessionProvider: sessionProvider)
        let commandRunner = AgentQuotaCommandRunner.live(
            detector: detector,
            baseEnvironment: environment,
            processEnvironment: processEnvironment
        )
        let qwenDirectory = resolvedDirectory(
            environment["QWEN_HOME"],
            fallback: homeDirectory.appendingPathComponent(
                ".qwen",
                isDirectory: true
            )
        )
        let openCodeConfigRoot = resolvedDirectory(
            environment["XDG_CONFIG_HOME"],
            fallback: homeDirectory.appendingPathComponent(
                ".config",
                isDirectory: true
            )
        )
        let openCodeDataRoot = resolvedDirectory(
            environment["XDG_DATA_HOME"],
            fallback: homeDirectory.appendingPathComponent(
                ".local/share",
                isDirectory: true
            )
        )
        let openCodeConfigDirectory = openCodeConfigRoot
            .appendingPathComponent("opencode", isDirectory: true)
        let openCodeDataDirectory = openCodeDataRoot
            .appendingPathComponent("opencode", isDirectory: true)
        let piDirectory = resolvedDirectory(
            environment["PI_CODING_AGENT_DIR"],
            fallback: homeDirectory.appendingPathComponent(
                ".pi/agent",
                isDirectory: true
            )
        )
        let qwenProvider = CurrentQuotaProviderResolver(
            settingsURLs: [
                qwenDirectory.appendingPathComponent("settings.json"),
            ],
            authURL: qwenDirectory.appendingPathComponent("auth.json"),
            environment: environment
        )
        let openCodeProvider = CurrentQuotaProviderResolver(
            settingsURLs: [
                openCodeConfigDirectory.appendingPathComponent("opencode.json"),
                homeDirectory.appendingPathComponent("opencode.json"),
            ],
            authURL: openCodeDataDirectory.appendingPathComponent("auth.json"),
            environment: environment
        )
        let piProvider = CurrentQuotaProviderResolver(
            settingsURLs: [
                piDirectory.appendingPathComponent("settings.json"),
            ],
            authURL: piDirectory.appendingPathComponent("auth.json"),
            environment: environment
        )
        let adapters = AgentAdapterRegistry.builtIn.adapters
        let adaptersByKind = Dictionary(
            uniqueKeysWithValues: adapters.map { ($0.kind, $0) }
        )
        return AgentQuotaService(
            adapters: adapters,
            isInstalled: { detector.isInstalled($0) },
            isSupported: { kind in
                guard let adapter = adaptersByKind[kind] else { return false }
                return detector.supportsMinimumVersion(of: adapter)
            },
            providerNames: [
                .qwenCode: { qwenProvider.providerName() },
                .openCode: { openCodeProvider.providerName() },
                .pi: { piProvider.providerName() },
            ],
            queries: [
                .codex: {
                    let protocolStatus = await CodexAgentQuotaAppServer.query(
                        commandRunner: commandRunner
                    )
                    switch protocolStatus {
                    case .available, .notLoggedIn:
                        return protocolStatus
                    case .checking, .unsupported, .failed:
                        break
                    }
                    return await CodexAgentQuotaAdapter.query(
                        credentialProvider: {
                            credentialStore.codexCredential()
                        },
                        httpClient: httpClient,
                        fallback: { .unsupported }
                    )
                },
                .claudeCode: {
                    await ClaudeAgentQuotaAdapter.query(
                        credentialProvider: {
                            credentialStore.claudeCredential()
                        },
                        httpClient: httpClient,
                        fallback: {
                            await AgentQuotaOfficialCLIAdapter.query(
                                agent: .claudeCode,
                                providerName: "Anthropic",
                                command: "/status",
                                commandRunner: commandRunner
                            )
                        }
                    )
                },
                .antigravityCLI: { .unsupported },
                .githubCopilotCLI: {
                    await AgentQuotaOfficialCLIAdapter.query(
                        agent: .githubCopilotCLI,
                        providerName: "GitHub Copilot",
                        command: "/clikit quota",
                        commandRunner: commandRunner
                    )
                },
                .qwenCode: {
                    await CurrentProviderQuotaAdapter.query(
                        resolver: qwenProvider,
                        httpClient: httpClient
                    )
                },
                .cursorAgent: { .unsupported },
                .factoryDroid: {
                    await AgentQuotaOfficialCLIAdapter.query(
                        agent: .factoryDroid,
                        providerName: "Factory",
                        command: "/limits",
                        commandRunner: commandRunner
                    )
                },
                .openCode: {
                    await CurrentProviderQuotaAdapter.query(
                        resolver: openCodeProvider,
                        httpClient: httpClient
                    )
                },
                .pi: {
                    await CurrentProviderQuotaAdapter.query(
                        resolver: piProvider,
                        httpClient: httpClient
                    )
                },
                .kimiCode: { .unsupported },
            ]
        )
    }
}

private func resolvedDirectory(_ path: String?, fallback: URL) -> URL {
    guard let path, NSString(string: path).isAbsolutePath else {
        return fallback
    }
    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
}
