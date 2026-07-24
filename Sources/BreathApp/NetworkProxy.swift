import BreathCore
import Foundation
import Network
import Security

enum NetworkProxyConfigurationError: Error, Equatable, Sendable {
    case emptyURL
    case invalidURL
    case unsupportedScheme
    case missingHost
    case invalidPort
    case credentialsInURL
}

enum NetworkProxySessionConfiguration {
    static func make(
        settings: NetworkProxySettings,
        password: String
    ) throws -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        switch settings.mode {
        case .none:
            configuration.connectionProxyDictionary = [:]
            configuration.proxyConfigurations = []
        case .system:
            configuration.connectionProxyDictionary = nil
            configuration.proxyConfigurations = []
        case .manual:
            let endpoint = try manualEndpoint(from: settings.manualURL)
            let proxy = endpoint.scheme.makeProxy(
                endpoint: endpoint.networkEndpoint
            )
            let username = settings.username.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !username.isEmpty || !password.isEmpty {
                proxy.applyCredential(username: username, password: password)
            }
            configuration.connectionProxyDictionary = [:]
            configuration.proxyConfigurations = [proxy]
        }
        return configuration
    }

    static func validate(_ settings: NetworkProxySettings) throws {
        guard settings.mode == .manual else { return }
        _ = try manualEndpoint(from: settings.manualURL)
    }

    static func manualProxyURL(
        settings: NetworkProxySettings,
        password: String
    ) throws -> URL {
        let endpoint = try manualEndpoint(from: settings.manualURL)
        var components = URLComponents()
        components.scheme = endpoint.scheme.processScheme
        components.host = endpoint.host
        components.port = Int(endpoint.port.rawValue)
        let username = settings.username.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !username.isEmpty || !password.isEmpty {
            components.user = username
            components.password = password
        }
        guard let url = components.url else {
            throw NetworkProxyConfigurationError.invalidURL
        }
        return url
    }

    private static func manualEndpoint(
        from rawURL: String
    ) throws -> ManualProxyEndpoint {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NetworkProxyConfigurationError.emptyURL
        }
        guard let components = URLComponents(string: trimmed),
              let rawScheme = components.scheme?.lowercased()
        else {
            throw NetworkProxyConfigurationError.invalidURL
        }
        guard let scheme = ManualProxyScheme(rawValue: rawScheme) else {
            throw NetworkProxyConfigurationError.unsupportedScheme
        }
        guard components.user == nil, components.password == nil else {
            throw NetworkProxyConfigurationError.credentialsInURL
        }
        guard let host = components.host, !host.isEmpty else {
            throw NetworkProxyConfigurationError.missingHost
        }
        guard components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            throw NetworkProxyConfigurationError.invalidURL
        }
        let portNumber = components.port ?? scheme.defaultPort
        guard let port = NWEndpoint.Port(rawValue: UInt16(exactly: portNumber) ?? 0),
              port.rawValue != 0
        else {
            throw NetworkProxyConfigurationError.invalidPort
        }
        return ManualProxyEndpoint(
            scheme: scheme,
            host: host,
            port: port,
            networkEndpoint: .hostPort(host: NWEndpoint.Host(host), port: port)
        )
    }
}

private enum ManualProxyScheme: String {
    case http
    case https
    case socks
    case socks5

    var defaultPort: Int {
        switch self {
        case .http: 80
        case .https: 443
        case .socks, .socks5: 1_080
        }
    }

    var processScheme: String {
        switch self {
        case .socks, .socks5: "socks5h"
        case .http, .https: rawValue
        }
    }

    func makeProxy(endpoint: NWEndpoint) -> ProxyConfiguration {
        switch self {
        case .http:
            ProxyConfiguration(
                httpCONNECTProxy: endpoint,
                tlsOptions: nil
            )
        case .https:
            ProxyConfiguration(
                httpCONNECTProxy: endpoint,
                tlsOptions: NWProtocolTLS.Options()
            )
        case .socks, .socks5:
            ProxyConfiguration(socksv5Proxy: endpoint)
        }
    }
}

private struct ManualProxyEndpoint {
    let scheme: ManualProxyScheme
    let host: String
    let port: NWEndpoint.Port
    let networkEndpoint: NWEndpoint
}

final class NetworkSessionManager: @unchecked Sendable {
    static let shared = NetworkSessionManager()

    private let lock = NSLock()
    private var activeSession: URLSession
    private var activeSettings: NetworkProxySettings
    private var activePassword: String

    init(
        settings: NetworkProxySettings = NetworkProxySettings(),
        password: String = ""
    ) {
        activeSettings = settings
        activePassword = password
        activeSession = URLSession(
            configuration: Self.configuration(
                settings: settings,
                password: password
            )
        )
    }

    var session: URLSession {
        lock.lock()
        defer { lock.unlock() }
        return activeSession
    }

    func update(settings: NetworkProxySettings, password: String) {
        let nextSession = URLSession(
            configuration: Self.configuration(
                settings: settings,
                password: password
            )
        )
        lock.lock()
        let previousSession = activeSession
        activeSession = nextSession
        activeSettings = settings
        activePassword = password
        lock.unlock()
        previousSession.finishTasksAndInvalidate()
    }

    func processEnvironment(
        basedOn base: [String: String]
    ) -> [String: String] {
        lock.lock()
        let settings = activeSettings
        let password = activePassword
        lock.unlock()

        switch settings.mode {
        case .system:
            return base
        case .none:
            return Self.environment(
                basedOn: base,
                proxyURL: nil,
                bypassAll: true
            )
        case .manual:
            guard let proxyURL = try? NetworkProxySessionConfiguration
                .manualProxyURL(settings: settings, password: password)
            else {
                return Self.environment(
                    basedOn: base,
                    proxyURL: nil,
                    bypassAll: true
                )
            }
            return Self.environment(
                basedOn: base,
                proxyURL: proxyURL.absoluteString,
                bypassAll: false
            )
        }
    }

    private static func configuration(
        settings: NetworkProxySettings,
        password: String
    ) -> URLSessionConfiguration {
        if let configuration = try? NetworkProxySessionConfiguration.make(
            settings: settings,
            password: password
        ) {
            return configuration
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.proxyConfigurations = []
        configuration.protocolClasses = [InvalidNetworkProxyURLProtocol.self]
        return configuration
    }

    private static func environment(
        basedOn base: [String: String],
        proxyURL: String?,
        bypassAll: Bool
    ) -> [String: String] {
        var environment = base
        let proxyKeys = [
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
            "http_proxy", "https_proxy", "all_proxy",
        ]
        for key in proxyKeys {
            if let proxyURL {
                environment[key] = proxyURL
            } else {
                environment.removeValue(forKey: key)
            }
        }
        if bypassAll {
            environment["NO_PROXY"] = "*"
            environment["no_proxy"] = "*"
        } else {
            environment.removeValue(forKey: "NO_PROXY")
            environment.removeValue(forKey: "no_proxy")
        }
        let configCount = Int(environment["GIT_CONFIG_COUNT"] ?? "") ?? 0
        environment["GIT_CONFIG_COUNT"] = String(configCount + 2)
        environment["GIT_CONFIG_KEY_\(configCount)"] = "http.proxy"
        environment["GIT_CONFIG_VALUE_\(configCount)"] = proxyURL ?? ""
        environment["GIT_CONFIG_KEY_\(configCount + 1)"] = "https.proxy"
        environment["GIT_CONFIG_VALUE_\(configCount + 1)"] = proxyURL ?? ""
        return environment
    }
}

private final class InvalidNetworkProxyURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.badURL)
        )
    }

    override func stopLoading() {}
}

enum NetworkProxyTestFailure: Equatable, Sendable {
    case invalidAddress
    case invalidProxyConfiguration(NetworkProxyConfigurationError)
    case invalidResponse
    case httpStatus(Int)
    case requestFailed(String)
}

enum NetworkProxyTestResult: Equatable, Sendable {
    case success(statusCode: Int, elapsedMilliseconds: Int)
    case failure(NetworkProxyTestFailure)
}

struct NetworkProxyTester: Sendable {
    private let sessionProvider: @Sendable () -> URLSession

    init(
        sessionProvider: @escaping @Sendable () -> URLSession
    ) {
        self.sessionProvider = sessionProvider
    }

    func test(_ rawAddress: String) async -> NetworkProxyTestResult {
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil
        else {
            return .failure(.invalidAddress)
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.setValue("Breath", forHTTPHeaderField: "User-Agent")
        let startedAt = ContinuousClock.now
        do {
            let (_, response) = try await sessionProvider().bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            guard (200..<400).contains(response.statusCode) else {
                return .failure(.httpStatus(response.statusCode))
            }
            let elapsed = startedAt.duration(to: .now)
            return .success(
                statusCode: response.statusCode,
                elapsedMilliseconds: max(
                    0,
                    Int(elapsed.components.seconds * 1_000)
                        + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                )
            )
        } catch {
            return .failure(.requestFailed(error.localizedDescription))
        }
    }
}

protocol NetworkProxyPasswordStoring: Sendable {
    func loadPassword() async throws -> String
    func savePassword(_ password: String) async throws
}

struct KeychainNetworkProxyPasswordStore: NetworkProxyPasswordStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.breath.network-proxy",
        account: String = "manual-proxy-password"
    ) {
        self.service = service
        self.account = account
    }

    func loadPassword() async throws -> String {
        let service = service
        let account = account
        return try await Task.detached(priority: .utility) {
            try Self.loadPassword(service: service, account: account)
        }.value
    }

    func savePassword(_ password: String) async throws {
        let service = service
        let account = account
        try await Task.detached(priority: .utility) {
            try Self.savePassword(
                password,
                service: service,
                account: account
            )
        }.value
    }

    private static func loadPassword(
        service: String,
        account: String
    ) throws -> String {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return ""
        }
        guard status == errSecSuccess else {
            throw NetworkProxyPasswordStoreError.unhandled(status)
        }
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw NetworkProxyPasswordStoreError.invalidData
        }
        return password
    }

    private static func savePassword(
        _ password: String,
        service: String,
        account: String
    ) throws {
        let query = baseQuery(service: service, account: account)
        if password.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw NetworkProxyPasswordStoreError.unhandled(status)
            }
            return
        }
        let data = Data(password.utf8)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw NetworkProxyPasswordStoreError.unhandled(status)
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrLabel as String] = "Breath Network Proxy"
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NetworkProxyPasswordStoreError.unhandled(addStatus)
        }
    }

    private static func baseQuery(
        service: String,
        account: String
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum NetworkProxyPasswordStoreError: LocalizedError {
    case invalidData
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "The proxy password stored in Keychain is not valid UTF-8."
        case .unhandled(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}
