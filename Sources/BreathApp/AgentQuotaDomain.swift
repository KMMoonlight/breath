import BreathAgents
import BreathCore
import Foundation

struct AgentQuotaAgent: Equatable, Identifiable, Sendable {
    let kind: AgentKind
    let displayName: String

    var id: AgentKind { kind }
}

enum AgentQuotaPercentageDirection: Equatable, Sendable {
    case used
    case remaining
}

enum AgentQuotaValue: Equatable, Sendable {
    case percentage(value: Double, direction: AgentQuotaPercentageDirection)
    case amount(value: String, unit: String?)
}

struct AgentQuotaWindow: Equatable, Identifiable, Sendable {
    let name: String
    let value: AgentQuotaValue
    let resetsAt: Date?
    let warning: Bool

    var id: String {
        "\(name)|\(value)"
    }
}

struct AgentQuotaSnapshot: Equatable, Sendable {
    let providerName: String?
    let maskedAccount: String?
    let windows: [AgentQuotaWindow]
}

enum AgentQuotaStatus: Equatable, Sendable {
    case checking
    case available(AgentQuotaSnapshot)
    case notLoggedIn
    case unsupported
    case failed(String)
}

typealias AgentQuotaQuery = @Sendable () async -> AgentQuotaStatus

actor AgentQuotaService {
    private let adapters: [AgentAdapterDescriptor]
    private let isInstalled: @Sendable (AgentKind) -> Bool
    private let queries: [AgentKind: AgentQuotaQuery]
    private let timeout: Duration

    init(
        adapters: [AgentAdapterDescriptor],
        isInstalled: @escaping @Sendable (AgentKind) -> Bool,
        queries: [AgentKind: AgentQuotaQuery],
        timeout: Duration = .seconds(15)
    ) {
        self.adapters = adapters
        self.isInstalled = isInstalled
        self.queries = queries
        self.timeout = timeout
    }

    func installedAgents() -> [AgentQuotaAgent] {
        adapters.compactMap { adapter in
            guard isInstalled(adapter.kind) else { return nil }
            return AgentQuotaAgent(
                kind: adapter.kind,
                displayName: adapter.displayName
            )
        }
    }

    func declaredAgentKinds() -> Set<AgentKind> {
        Set(queries.keys)
    }

    func query(_ kind: AgentKind) async -> AgentQuotaStatus {
        guard let query = queries[kind] else { return .unsupported }
        let timeout = self.timeout
        return await withTaskGroup(
            of: AgentQuotaStatus.self,
            returning: AgentQuotaStatus.self
        ) { group in
            group.addTask {
                await query()
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return .failed("额度查询已取消。")
                }
                return .failed("额度查询超时。")
            }
            let first = await group.next() ?? .failed("额度查询失败。")
            group.cancelAll()
            return first
        }
    }

    func queryAll() async -> [AgentKind: AgentQuotaStatus] {
        let installed = installedAgents()
        let registeredQueries = queries
        let timeout = self.timeout
        return await withTaskGroup(
            of: (AgentKind, AgentQuotaStatus).self,
            returning: [AgentKind: AgentQuotaStatus].self
        ) { group in
            for agent in installed {
                let query = registeredQueries[agent.kind]
                group.addTask {
                    guard let query else {
                        return (agent.kind, .unsupported)
                    }
                    let status = await withTaskGroup(
                        of: AgentQuotaStatus.self,
                        returning: AgentQuotaStatus.self
                    ) { race in
                        race.addTask { await query() }
                        race.addTask {
                            do {
                                try await Task.sleep(for: timeout)
                            } catch {
                                return .failed("额度查询已取消。")
                            }
                            return .failed("额度查询超时。")
                        }
                        let first = await race.next() ?? .failed("额度查询失败。")
                        race.cancelAll()
                        return first
                    }
                    return (agent.kind, status)
                }
            }
            var results: [AgentKind: AgentQuotaStatus] = [:]
            for await (kind, status) in group {
                results[kind] = status
            }
            return results
        }
    }
}
