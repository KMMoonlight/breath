import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OnlineSkillSourceError: Error, Equatable, LocalizedError, Sendable {
    case invalidGitHubLocation
    case unsupportedGitHubHost
    case repositoryUnavailable
    case privateRepositoryUnsupported
    case responseTooLarge
    case serviceUnavailable
    case authenticationRequired
    case rateLimited
    case invalidResponse
    case unsupportedCatalogSource

    public var errorDescription: String? {
        switch self {
        case .invalidGitHubLocation: "Enter a GitHub repository URL or owner/repository."
        case .unsupportedGitHubHost: "Only public github.com repositories are supported."
        case .repositoryUnavailable: "The public GitHub repository could not be found."
        case .privateRepositoryUnsupported: "Private repositories are not supported; import a ZIP instead."
        case .responseTooLarge: "The remote Skill source exceeds the safe download limit."
        case .serviceUnavailable: "The online Skill service is temporarily unavailable."
        case .authenticationRequired: "The online catalog currently requires authentication that Breath does not collect."
        case .rateLimited: "The online service rate limit was reached. Try again later."
        case .invalidResponse: "The online service returned an invalid response."
        case .unsupportedCatalogSource: "This catalog result does not expose a supported public GitHub upstream."
        }
    }
}

public struct GitHubSkillLocator: Hashable, Sendable {
    public let repository: String
    public let subdirectory: String?
    public let reference: SkillSourceReference?

    public init(
        repository: String,
        subdirectory: String? = nil,
        reference: SkillSourceReference? = nil
    ) {
        self.repository = repository
        self.subdirectory = subdirectory
        self.reference = reference
    }

    public static func parse(_ input: String) throws -> GitHubSkillLocator {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OnlineSkillSourceError.invalidGitHubLocation }

        if trimmed.contains("://") {
            guard let components = URLComponents(string: trimmed),
                  components.scheme?.lowercased() == "https",
                  components.host?.lowercased() == "github.com"
            else {
                throw OnlineSkillSourceError.unsupportedGitHubHost
            }
            let path = components.path.split(separator: "/").map(String.init)
            guard path.count >= 2 else {
                throw OnlineSkillSourceError.invalidGitHubLocation
            }
            let repositoryName = stripGitSuffix(path[1])
            guard isValidRepositoryComponent(path[0]),
                  isValidRepositoryComponent(repositoryName)
            else {
                throw OnlineSkillSourceError.invalidGitHubLocation
            }
            let repository = "\(path[0])/\(repositoryName)"
            if path.count >= 4, path[2] == "tree" {
                return GitHubSkillLocator(
                    repository: repository,
                    subdirectory: path.count > 4 ? path.dropFirst(4).joined(separator: "/") : nil,
                    reference: SkillSourceReference(kind: .branch, value: path[3])
                )
            }
            if path.count >= 4, path[2] == "commit" {
                return GitHubSkillLocator(
                    repository: repository,
                    reference: SkillSourceReference(kind: .commit, value: path[3])
                )
            }
            if path.count >= 5, path[2] == "releases", path[3] == "tag" {
                return GitHubSkillLocator(
                    repository: repository,
                    reference: SkillSourceReference(kind: .tag, value: path[4])
                )
            }
            return GitHubSkillLocator(repository: repository)
        }

        let explicitParts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        let repositoryAndReference = explicitParts[0]
        let subdirectory = explicitParts.count == 2 ? explicitParts[1] : nil
        let referenceParts = repositoryAndReference.split(
            separator: "@",
            maxSplits: 1
        ).map(String.init)
        let repository = stripGitSuffix(referenceParts[0])
        let repositoryParts = repository.split(separator: "/")
        guard repositoryParts.count == 2,
              repositoryParts.allSatisfy({ isValidRepositoryComponent(String($0)) })
        else {
            throw OnlineSkillSourceError.invalidGitHubLocation
        }
        let reference: SkillSourceReference?
        if referenceParts.count == 2 {
            let rawReference = referenceParts[1]
            if rawReference.hasPrefix("tag=") {
                reference = SkillSourceReference(
                    kind: .tag,
                    value: String(rawReference.dropFirst(4))
                )
            } else if rawReference.hasPrefix("commit=") {
                reference = SkillSourceReference(
                    kind: .commit,
                    value: String(rawReference.dropFirst(7))
                )
            } else {
                reference = SkillSourceReference(kind: .branch, value: rawReference)
            }
        } else {
            reference = nil
        }
        return GitHubSkillLocator(
            repository: repository,
            subdirectory: subdirectory,
            reference: reference
        )
    }

    private static func stripGitSuffix(_ value: String) -> String {
        value.lowercased().hasSuffix(".git")
            ? String(value.dropLast(4))
            : value
    }

    private static func isValidRepositoryComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && value.range(
                of: "^[A-Za-z0-9_.-]+$",
                options: .regularExpression
            ) != nil
    }
}

public struct GitHubResolvedSkillArchive: Sendable {
    public let repository: String
    public let subdirectory: String?
    public let reference: SkillSourceReference
    public let resolvedCommit: String
    public let archiveData: Data

    public init(
        repository: String,
        subdirectory: String?,
        reference: SkillSourceReference,
        resolvedCommit: String,
        archiveData: Data
    ) {
        self.repository = repository
        self.subdirectory = subdirectory
        self.reference = reference
        self.resolvedCommit = resolvedCommit
        self.archiveData = archiveData
    }
}

public protocol GitHubSkillProviding: Sendable {
    func resolve(_ locator: GitHubSkillLocator) async throws -> GitHubResolvedSkillArchive
}

public struct GitHubHTTPSkillProvider: GitHubSkillProviding, Sendable {
    private let session: URLSession
    private let maximumDownloadBytes: Int

    public init(
        session: URLSession = .shared,
        maximumDownloadBytes: Int = 64 * 1_024 * 1_024
    ) {
        self.session = session
        self.maximumDownloadBytes = maximumDownloadBytes
    }

    public func resolve(_ locator: GitHubSkillLocator) async throws -> GitHubResolvedSkillArchive {
        let repositoryURL = try apiURL("repos/\(locator.repository)")
        let repositoryData = try await request(repositoryURL)
        let repository = try JSONDecoder().decode(RepositoryResponse.self, from: repositoryData)
        guard !repository.isPrivate else {
            throw OnlineSkillSourceError.privateRepositoryUnsupported
        }
        let reference = locator.reference ?? SkillSourceReference(
            kind: .defaultBranch,
            value: repository.defaultBranch
        )
        let encodedReference = reference.value.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? reference.value
        let commitURL = try apiURL("repos/\(locator.repository)/commits/\(encodedReference)")
        let commitData = try await request(commitURL)
        let commit = try JSONDecoder().decode(CommitResponse.self, from: commitData)
        let archiveURL = try apiURL("repos/\(locator.repository)/zipball/\(commit.sha)")
        let archiveData = try await request(archiveURL)
        guard archiveData.count <= maximumDownloadBytes else {
            throw OnlineSkillSourceError.responseTooLarge
        }
        return GitHubResolvedSkillArchive(
            repository: locator.repository,
            subdirectory: locator.subdirectory,
            reference: reference,
            resolvedCommit: commit.sha,
            archiveData: archiveData
        )
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Breath", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OnlineSkillSourceError.serviceUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw OnlineSkillSourceError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            guard data.count <= maximumDownloadBytes else {
                throw OnlineSkillSourceError.responseTooLarge
            }
            return data
        case 401, 403:
            if http.statusCode == 403,
               http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
            {
                throw OnlineSkillSourceError.rateLimited
            }
            throw OnlineSkillSourceError.privateRepositoryUnsupported
        case 404:
            throw OnlineSkillSourceError.repositoryUnavailable
        case 429:
            throw OnlineSkillSourceError.rateLimited
        default:
            throw OnlineSkillSourceError.serviceUnavailable
        }
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://api.github.com/\(path)") else {
            throw OnlineSkillSourceError.invalidResponse
        }
        return url
    }

    private struct RepositoryResponse: Decodable {
        let defaultBranch: String
        let isPrivate: Bool

        enum CodingKeys: String, CodingKey {
            case defaultBranch = "default_branch"
            case isPrivate = "private"
        }
    }

    private struct CommitResponse: Decodable {
        let sha: String
    }
}

public enum SkillRiskLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case unknown
    case none
    case low
    case medium
    case high
    case critical

    public var requiresExtraConfirmation: Bool {
        self == .high || self == .critical
    }
}

public struct SkillSecurityAudit: Codable, Hashable, Sendable {
    public let riskLevel: SkillRiskLevel
    public let summary: String
    public let checkedAt: Date?

    public init(riskLevel: SkillRiskLevel, summary: String, checkedAt: Date?) {
        self.riskLevel = riskLevel
        self.summary = summary
        self.checkedAt = checkedAt
    }

    public static let unknown = SkillSecurityAudit(
        riskLevel: .unknown,
        summary: "No security audit is available.",
        checkedAt: nil
    )
}

public struct SkillsShSearchResult: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let slug: String
    public let name: String
    public let description: String?
    public let source: String
    public let installs: Int
    public let sourceType: String
    public let installURL: URL?
    public let pageURL: URL
    public let securityAudit: SkillSecurityAudit

    public init(
        id: String,
        slug: String,
        name: String,
        description: String?,
        source: String,
        installs: Int,
        sourceType: String,
        installURL: URL?,
        pageURL: URL,
        securityAudit: SkillSecurityAudit = .unknown
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.source = source
        self.installs = installs
        self.sourceType = sourceType
        self.installURL = installURL
        self.pageURL = pageURL
        self.securityAudit = securityAudit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            slug: try container.decode(String.self, forKey: .slug),
            name: try container.decode(String.self, forKey: .name),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            source: try container.decode(String.self, forKey: .source),
            installs: try container.decode(Int.self, forKey: .installs),
            sourceType: try container.decode(String.self, forKey: .sourceType),
            installURL: try container.decodeIfPresent(URL.self, forKey: .installURL),
            pageURL: try container.decode(URL.self, forKey: .pageURL)
        )
    }

    public func withSecurityAudit(_ audit: SkillSecurityAudit) -> SkillsShSearchResult {
        SkillsShSearchResult(
            id: id,
            slug: slug,
            name: name,
            description: description,
            source: source,
            installs: installs,
            sourceType: sourceType,
            installURL: installURL,
            pageURL: pageURL,
            securityAudit: audit
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case description
        case source
        case installs
        case sourceType
        case installURL = "installUrl"
        case pageURL = "url"
    }
}

public protocol SkillsShProviding: Sendable {
    func search(query: String, limit: Int) async throws -> [SkillsShSearchResult]
    func audit(skillID: String) async throws -> SkillSecurityAudit
}

public struct SkillsShHTTPProvider: SkillsShProviding, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(query: String, limit: Int = 50) async throws -> [SkillsShSearchResult] {
        guard var components = URLComponents(string: "https://skills.sh/api/v1/skills/search") else {
            throw OnlineSkillSourceError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))),
        ]
        guard let url = components.url else { throw OnlineSkillSourceError.invalidResponse }
        let data = try await request(url)
        return try Self.makeDecoder().decode(SearchResponse.self, from: data).data
    }

    public func audit(skillID: String) async throws -> SkillSecurityAudit {
        let encodedID = skillID.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        guard let url = URL(string: "https://skills.sh/api/v1/skills/audit/\(encodedID)") else {
            throw OnlineSkillSourceError.invalidResponse
        }
        do {
            let data = try await request(url)
            let response = try Self.makeDecoder().decode(AuditResponse.self, from: data)
            guard !response.audits.isEmpty else { return .unknown }
            let highest = response.audits.max {
                riskRank($0.riskLevel) < riskRank($1.riskLevel)
            }
            return SkillSecurityAudit(
                riskLevel: Self.riskLevel(highest?.riskLevel),
                summary: highest?.summary ?? "Security audit available.",
                checkedAt: highest?.auditedAt
            )
        } catch OnlineSkillSourceError.repositoryUnavailable {
            return .unknown
        }
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Breath", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OnlineSkillSourceError.serviceUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw OnlineSkillSourceError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw OnlineSkillSourceError.authenticationRequired
        case 404: throw OnlineSkillSourceError.repositoryUnavailable
        case 429: throw OnlineSkillSourceError.rateLimited
        default: throw OnlineSkillSourceError.serviceUnavailable
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func riskRank(_ raw: String?) -> Int {
        switch Self.riskLevel(raw) {
        case .unknown: 0
        case .none: 1
        case .low: 2
        case .medium: 3
        case .high: 4
        case .critical: 5
        }
    }

    private static func riskLevel(_ raw: String?) -> SkillRiskLevel {
        guard let raw else { return .unknown }
        return SkillRiskLevel(rawValue: raw.lowercased()) ?? .unknown
    }

    private struct SearchResponse: Decodable {
        let data: [SkillsShSearchResult]
    }

    private struct AuditResponse: Decodable {
        let audits: [AuditEntry]
    }

    private struct AuditEntry: Decodable {
        let summary: String
        let auditedAt: Date?
        let riskLevel: String?
    }
}
