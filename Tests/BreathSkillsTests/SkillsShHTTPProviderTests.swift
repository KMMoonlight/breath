import BreathSkills
import Foundation
import Testing

@Suite("skills.sh HTTP provider", .serialized)
struct SkillsShHTTPProviderTests {
    @Test("uses the public CLI search endpoint and maps GitHub results")
    func searchesPublicCatalog() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SkillsShURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            SkillsShURLProtocol.handler = nil
        }

        SkillsShURLProtocol.handler = { request in
            let url = try #require(request.url)
            #expect(url.path == "/api/search")
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == "browser")
            #expect(components.queryItems?.first(where: { $0.name == "limit" })?.value == "3")

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            let data = Data(
                """
                {
                  "query": "browser",
                  "searchType": "fuzzy",
                  "skills": [
                    {
                      "id": "vercel-labs/agent-browser/agent-browser",
                      "skillId": "agent-browser",
                      "name": "agent-browser",
                      "installs": 563823,
                      "source": "vercel-labs/agent-browser"
                    },
                    {
                      "id": "open.feishu.cn/lark-doc",
                      "skillId": "lark-doc",
                      "name": "lark-doc",
                      "installs": 444100,
                      "source": "open.feishu.cn"
                    }
                  ],
                  "count": 2,
                  "duration_ms": 12
                }
                """.utf8
            )
            return (response, data)
        }

        let provider = SkillsShHTTPProvider(sessionProvider: { session })
        let results = try await provider.search(query: "browser", limit: 3)

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.id == "vercel-labs/agent-browser/agent-browser")
        #expect(result.slug == "agent-browser")
        #expect(result.source == "vercel-labs/agent-browser")
        #expect(result.sourceType == "github")
        #expect(result.installURL?.absoluteString == "https://github.com/vercel-labs/agent-browser")
        #expect(result.pageURL.absoluteString == "https://skills.sh/vercel-labs/agent-browser/agent-browser")
    }
}

private final class SkillsShURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
