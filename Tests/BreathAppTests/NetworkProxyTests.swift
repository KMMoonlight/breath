import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Network proxy")
struct NetworkProxyTests {
    @Test("direct mode disables inherited proxy settings")
    func directMode() throws {
        let configuration = try NetworkProxySessionConfiguration.make(
            settings: NetworkProxySettings(mode: .none),
            password: ""
        )

        #expect(configuration.connectionProxyDictionary?.isEmpty == true)
        #expect(configuration.proxyConfigurations.isEmpty)
    }

    @Test("system mode leaves system proxy discovery enabled")
    func systemMode() throws {
        let configuration = try NetworkProxySessionConfiguration.make(
            settings: NetworkProxySettings(mode: .system),
            password: ""
        )

        #expect(configuration.connectionProxyDictionary == nil)
        #expect(configuration.proxyConfigurations.isEmpty)
    }

    @Test("manual mode creates one authenticated proxy configuration")
    func manualMode() throws {
        let configuration = try NetworkProxySessionConfiguration.make(
            settings: NetworkProxySettings(
                mode: .manual,
                manualURL: "http://127.0.0.1:7890",
                username: "breath"
            ),
            password: "secret"
        )

        // An empty legacy dictionary overrides proxyConfigurations and silently
        // sends requests directly, so manual mode must leave it unset.
        #expect(configuration.connectionProxyDictionary == nil)
        #expect(configuration.proxyConfigurations.count == 1)
    }

    @Test("manual mode rejects unsupported and credential-bearing URLs")
    func invalidManualURLs() {
        #expect(throws: NetworkProxyConfigurationError.unsupportedScheme) {
            try NetworkProxySessionConfiguration.make(
                settings: NetworkProxySettings(
                    mode: .manual,
                    manualURL: "ftp://proxy.example.com:21"
                ),
                password: ""
            )
        }
        #expect(throws: NetworkProxyConfigurationError.credentialsInURL) {
            try NetworkProxySessionConfiguration.make(
                settings: NetworkProxySettings(
                    mode: .manual,
                    manualURL: "http://user:secret@proxy.example.com:8080"
                ),
                password: ""
            )
        }
    }

    @Test("connection test reports an HTTP response")
    func connectionTest() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkProxyURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let tester = NetworkProxyTester(sessionProvider: { session })

        let result = await tester.test("https://www.google.com")

        guard case .success(let statusCode, let elapsedMilliseconds) = result else {
            Issue.record("Expected a successful proxy test, got \(result)")
            return
        }
        #expect(statusCode == 204)
        #expect(elapsedMilliseconds >= 0)
    }

    @Test("connection test rejects non-HTTP addresses")
    func invalidTestAddress() async {
        let tester = NetworkProxyTester(sessionProvider: { .shared })

        #expect(await tester.test("file:///tmp/test") == .failure(.invalidAddress))
    }

    @Test("connection test reports HTTP failures instead of success")
    func failedHTTPStatus() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkProxyURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let tester = NetworkProxyTester(sessionProvider: { session })

        #expect(
            await tester.test("https://www.google.com/auth")
                == .failure(.httpStatus(407))
        )
    }

    @Test("manual and direct modes configure Git subprocess environments")
    func processEnvironments() {
        let inherited = [
            "HTTP_PROXY": "http://old.example:8080",
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "credential.helper",
            "GIT_CONFIG_VALUE_0": "osxkeychain",
        ]
        let direct = NetworkSessionManager(
            settings: NetworkProxySettings(mode: .none)
        ).processEnvironment(basedOn: inherited)
        #expect(direct["HTTP_PROXY"] == nil)
        #expect(direct["NO_PROXY"] == "*")
        #expect(direct["GIT_CONFIG_COUNT"] == "3")
        #expect(direct["GIT_CONFIG_KEY_1"] == "http.proxy")
        #expect(direct["GIT_CONFIG_VALUE_1"] == "")

        let manual = NetworkSessionManager(
            settings: NetworkProxySettings(
                mode: .manual,
                manualURL: "http://proxy.example.com:7890",
                username: "breath user"
            ),
            password: "secret"
        ).processEnvironment(basedOn: [:])
        #expect(
            manual["HTTPS_PROXY"]
                == "http://breath%20user:secret@proxy.example.com:7890"
        )
        #expect(manual["GIT_CONFIG_VALUE_0"] == manual["HTTPS_PROXY"])
    }

    @Test("invalid manual settings never fall through to a direct connection")
    func invalidManualSettingsBlockRequests() async {
        let manager = NetworkSessionManager(
            settings: NetworkProxySettings(mode: .manual),
            password: ""
        )
        let tester = NetworkProxyTester(sessionProvider: { manager.session })

        guard case .failure(.requestFailed(_)) = await tester.test(
            "https://www.google.com"
        ) else {
            Issue.record("Invalid manual proxy settings should block the request")
            return
        }
    }
}

private final class NetworkProxyURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let statusCode = request.url?.path == "/auth" ? 407 : 204
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
