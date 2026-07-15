import AppKit
import BreathAgents
import BreathCore
import BreathPersistence
import BreathTerminal
import Foundation

@MainActor
final class BreathApplicationModel: ObservableObject {
    @Published private(set) var snapshot: WorkbenchSnapshot = .empty
    @Published var settings: SettingsSnapshot = .default
    @Published private(set) var enabledAgents: Set<AgentKind> = []
    @Published private(set) var isReady = false
    @Published var lastError: String?

    let terminalEngine: any TerminalEngine & TerminalViewProviding
    let adapters = AgentAdapterRegistry.builtIn.adapters

    private let repository: SQLiteWorkbenchRepository
    private let runtime: TerminalEngineRuntime
    private let workbench: Workbench
    private let eventServer: UnixAgentEventServer
    private let eventSink: AgentEventSink
    private let snapshotRefreshSink = SnapshotRefreshSink()
    private let userHookInstaller = UserHookIntegrationInstaller()
    private let scriptInstaller = ScriptIntegrationInstaller()
    private let homeDirectory: URL
    private var started = false
    private var startupSucceeded = false
    private var startupTask: Task<Void, Never>?

    static func makeDefault() -> BreathApplicationModel {
        do {
            return try BreathApplicationModel()
        } catch {
            fatalError("Breath initialization failed: \(error)")
        }
    }

    private convenience init() throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let supportDirectory = homeDirectory
            .appendingPathComponent("Library/Application Support/Breath", isDirectory: true)
        try self.init(
            homeDirectory: homeDirectory,
            supportDirectory: supportDirectory
        )
    }

    private init(
        homeDirectory: URL,
        supportDirectory: URL,
        testingSnapshot: WorkbenchSnapshot? = nil,
        injectedTerminalEngine: (any TerminalEngine & TerminalViewProviding)? = nil
    ) throws {
        self.homeDirectory = homeDirectory
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let socketURL = supportDirectory.appendingPathComponent("agent-events.sock")
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        repository = try SQLiteWorkbenchRepository(
            databaseURL: supportDirectory.appendingPathComponent("breath.sqlite")
        )
        if let injectedTerminalEngine {
            terminalEngine = injectedTerminalEngine
        } else {
            terminalEngine = try GhosttyTerminalEngine(
                configurationDirectory: supportDirectory.appendingPathComponent("terminal", isDirectory: true),
                agentSocketURL: socketURL
            )
        }
        runtime = TerminalEngineRuntime(engine: terminalEngine)
        workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            agentResumeCommands: BuiltInAgentResumeCommands(),
            applicationInstanceID: applicationInstanceID,
            defaultShell: {
                ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            },
            workspaceAvailable: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ) && isDirectory.boolValue
            }
        )
        eventSink = AgentEventSink()
        eventServer = UnixAgentEventServer(socketURL: socketURL) { [eventSink] event in
            eventSink.receive(event)
        }
        eventSink.handler = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.workbench.handleAgentEvent(event)
                    await self.refreshSnapshot()
                } catch {
                    self.lastError = error.localizedDescription
                }
            }
        }
        snapshotRefreshSink.handler = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshSnapshot()
            }
        }
        if let testingSnapshot {
            snapshot = testingSnapshot
            isReady = true
            startupSucceeded = true
            started = true
        }
    }

#if DEBUG
    static func makeTesting(
        snapshot: WorkbenchSnapshot,
        supportDirectory: URL
    ) throws -> BreathApplicationModel {
        try BreathApplicationModel(
            homeDirectory: supportDirectory,
            supportDirectory: supportDirectory,
            testingSnapshot: snapshot,
            injectedTerminalEngine: TestingTerminalEngine()
        )
    }

    func replaceTestingSnapshot(_ snapshot: WorkbenchSnapshot) {
        self.snapshot = snapshot
    }
#endif

    func start() {
        guard !started else { return }
        started = true
        do {
            try eventServer.start()
        } catch {
            lastError = "Agent 事件服务启动失败：\(error.localizedDescription)"
        }
        refreshEnabledAgents()
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer { isReady = true }
            do {
                await workbench.setSnapshotChangeHandler { [snapshotRefreshSink] in
                    snapshotRefreshSink.receive()
                }
                settings = try await repository.loadSettings()
                await runtime.apply(settings: settings.terminal)
                try await workbench.restoreFromRepository()
                await refreshSnapshot()
                startupSucceeded = true
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func addWorkspace(_ url: URL) {
        perform {
            let id = try await self.workbench.addWorkspace(at: url)
            _ = try await self.workbench.createWorkSession(in: id)
        }
    }

    func createWorkSession(in workspaceID: WorkspaceID) {
        perform {
            _ = try await self.workbench.createWorkSession(in: workspaceID)
        }
    }

    func selectWorkSession(_ id: WorkSessionID?) {
        guard let id else { return }
        perform { try await self.workbench.selectWorkSession(id) }
    }

    func split(_ paneID: TerminalPaneID, orientation: SplitOrientation) {
        perform { _ = try await self.workbench.splitPane(paneID, orientation: orientation) }
    }

    func resizeSplit(
        in workSessionID: WorkSessionID,
        path: [SplitBranch],
        fraction: Double
    ) {
        perform {
            try await self.workbench.resizeSplit(
                in: workSessionID,
                path: path,
                fraction: fraction
            )
        }
    }

    func closePane(_ paneID: TerminalPaneID) {
        perform { try await self.workbench.closePane(paneID) }
    }

    func archive(_ id: WorkSessionID) {
        perform { try await self.workbench.archiveWorkSession(id) }
    }

    func restoreArchive(_ id: WorkSessionID) {
        perform { try await self.workbench.restoreArchivedWorkSession(id) }
    }

    func deleteArchive(_ id: WorkSessionID) {
        perform { try await self.workbench.deleteArchivedWorkSession(id) }
    }

    func removeWorkspace(_ id: WorkspaceID) {
        perform { try await self.workbench.removeWorkspace(id) }
    }

    func saveApplicationSettings(_ application: ApplicationSettings) {
        settings.application = application
        persistSettings()
    }

    func saveTerminalSettings(_ terminal: TerminalSettings) {
        settings.terminal = terminal
        Task {
            await runtime.apply(settings: terminal)
            do {
                try await repository.saveSettings(settings)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func setAgentIntegration(_ adapter: AgentAdapterDescriptor, enabled: Bool) {
        do {
            let executable = Bundle.main.executableURL?.path
                ?? "/Applications/Breath.app/Contents/MacOS/Breath"
            switch adapter.integrationMechanism {
            case .userHooks:
                if enabled {
                    try userHookInstaller.install(
                        adapter: adapter,
                        hookExecutable: executable,
                        homeDirectory: homeDirectory
                    )
                } else {
                    try userHookInstaller.uninstall(
                        adapter: adapter,
                        homeDirectory: homeDirectory
                    )
                }
            case .plugin, .extension:
                if enabled {
                    try scriptInstaller.install(
                        adapter: adapter,
                        hookExecutable: executable,
                        homeDirectory: homeDirectory
                    )
                } else {
                    try scriptInstaller.uninstall(
                        adapter: adapter,
                        homeDirectory: homeDirectory
                    )
                }
            case .terminalParsing:
                return
            }
            refreshEnabledAgents()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func prepareForTermination() async -> Bool {
        if !started { start() }
        await startupTask?.value
        guard startupSucceeded else {
            await workbench.stopAllTerminalsWithoutSaving()
            return true
        }
        do {
            try await workbench.prepareForCleanExit()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func isWorkspaceAvailable(_ workspace: Workspace) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: workspace.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private func perform(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        guard isReady else { return }
        guard startupSucceeded else {
            lastError = "启动恢复未完成。请退出 Breath 后重试；现有会话数据不会被覆盖。"
            return
        }
        Task { @MainActor in
            do {
                try await operation()
                await refreshSnapshot()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func refreshSnapshot() async {
        snapshot = await workbench.snapshot()
    }

    private func persistSettings() {
        Task {
            do {
                try await repository.saveSettings(settings)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func refreshEnabledAgents() {
        enabledAgents = Set(adapters.compactMap { adapter in
            guard adapter.userConfigurationPath.hasPrefix("~/") else { return nil }
            let url = homeDirectory.appendingPathComponent(
                String(adapter.userConfigurationPath.dropFirst(2))
            )
            guard let data = try? Data(contentsOf: url),
                  let contents = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            switch adapter.integrationMechanism {
            case .userHooks, .plugin, .extension:
                return contents.contains("--agent-hook") ? adapter.kind : nil
            case .terminalParsing:
                return nil
            }
        })
    }
}

#if DEBUG
@MainActor
private final class TestingTerminalEngine: TerminalEngine, TerminalViewProviding, @unchecked Sendable {
    func open(_ launch: TerminalLaunch) async throws {}

    func close(_ paneID: TerminalPaneID) async {}

    func apply(settings: TerminalSettings) async {}

    func view(for paneID: TerminalPaneID) -> NSView? {
        nil
    }
}
#endif

private final class AgentEventSink: @unchecked Sendable {
    private let lock = NSLock()
    var handler: (@Sendable (AgentEvent) -> Void)?

    func receive(_ event: AgentEvent) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?(event)
    }
}

private final class SnapshotRefreshSink: @unchecked Sendable {
    private let lock = NSLock()
    var handler: (@Sendable () -> Void)?

    func receive() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?()
    }
}
