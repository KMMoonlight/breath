import BreathAgents
import BreathCore
import Dispatch
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
    let resetDescription: String?
    let warning: Bool

    init(
        name: String,
        value: AgentQuotaValue,
        resetsAt: Date?,
        resetDescription: String? = nil,
        warning: Bool
    ) {
        self.name = name
        self.value = value
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.warning = warning
    }

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
typealias AgentQuotaProviderNameQuery = @Sendable () -> String?

actor AgentQuotaService {
    private let adapters: [AgentAdapterDescriptor]
    private let isInstalled: @Sendable (AgentKind) -> Bool
    private let isSupported: @Sendable (AgentKind) -> Bool
    private let providerNames: [AgentKind: AgentQuotaProviderNameQuery]
    private let queries: [AgentKind: AgentQuotaQuery]
    private let timeout: Duration

    init(
        adapters: [AgentAdapterDescriptor],
        isInstalled: @escaping @Sendable (AgentKind) -> Bool,
        isSupported: @escaping @Sendable (AgentKind) -> Bool = { _ in true },
        providerNames: [AgentKind: AgentQuotaProviderNameQuery] = [:],
        queries: [AgentKind: AgentQuotaQuery],
        timeout: Duration = .seconds(15)
    ) {
        self.adapters = adapters
        self.isInstalled = isInstalled
        self.isSupported = isSupported
        self.providerNames = providerNames
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

    func providerName(for kind: AgentKind) -> String? {
        providerNames[kind]?()
    }

    func query(_ kind: AgentKind) async -> AgentQuotaStatus {
        guard isSupported(kind), let query = queries[kind] else {
            return .unsupported
        }
        return await queryAgentQuota(query, timeout: timeout)
    }

    func queryAll() async -> [AgentKind: AgentQuotaStatus] {
        let installed = installedAgents()
        let registeredQueries = queries
        let supportsAgent = isSupported
        let timeout = self.timeout
        return await withTaskGroup(
            of: (AgentKind, AgentQuotaStatus).self,
            returning: [AgentKind: AgentQuotaStatus].self
        ) { group in
            for agent in installed {
                let query = registeredQueries[agent.kind]
                group.addTask {
                    guard supportsAgent(agent.kind), let query else {
                        return (agent.kind, .unsupported)
                    }
                    let status = await queryAgentQuota(query, timeout: timeout)
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

private func queryAgentQuota(
    _ query: @escaping AgentQuotaQuery,
    timeout: Duration
) async -> AgentQuotaStatus {
    let race = AgentQuotaQueryRace()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            race.install(continuation)
            let timeoutWorkItem = DispatchWorkItem {
                race.resolve(.failed("额度查询超时。"))
            }
            race.install(timeoutWorkItem: timeoutWorkItem)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: quotaTimeoutDeadline(after: timeout),
                execute: timeoutWorkItem
            )
            let queryTask = Task.detached(priority: .userInitiated) {
                let status = await query()
                race.resolve(status)
            }
            race.install(queryTask: queryTask)
        }
    } onCancel: {
        race.resolve(.failed("额度查询已取消。"))
    }
}

private func quotaTimeoutDeadline(after timeout: Duration) -> DispatchTime {
    let components = timeout.components
    let seconds = Double(components.seconds)
        + Double(components.attoseconds) / 1_000_000_000_000_000_000
    let nanoseconds = Int(
        min(
            max(seconds * 1_000_000_000, 0),
            Double(Int.max)
        )
    )
    return .now() + .nanoseconds(nanoseconds)
}

private final class AgentQuotaQueryRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AgentQuotaStatus, Never>?
    private var pendingResult: AgentQuotaStatus?
    private var queryTask: Task<Void, Never>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var isResolved = false

    func install(
        _ continuation: CheckedContinuation<AgentQuotaStatus, Never>
    ) {
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            lock.unlock()
            continuation.resume(returning: pendingResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(queryTask: Task<Void, Never>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            queryTask.cancel()
            return
        }
        self.queryTask = queryTask
        lock.unlock()
    }

    func install(timeoutWorkItem: DispatchWorkItem) {
        lock.lock()
        if isResolved {
            lock.unlock()
            timeoutWorkItem.cancel()
            return
        }
        self.timeoutWorkItem = timeoutWorkItem
        lock.unlock()
    }

    func resolve(_ result: AgentQuotaStatus) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil {
            pendingResult = result
        }
        let queryTask = self.queryTask
        self.queryTask = nil
        let timeoutWorkItem = self.timeoutWorkItem
        self.timeoutWorkItem = nil
        lock.unlock()

        queryTask?.cancel()
        timeoutWorkItem?.cancel()
        continuation?.resume(returning: result)
    }
}
