import AppKit
import BreathAgents
import BreathCore
import BreathPersistence
import BreathSkills
import BreathTerminal
import Foundation

@MainActor
final class BreathApplicationModel: ObservableObject {
    @Published private(set) var snapshot: WorkbenchSnapshot = .empty
    @Published var settings: SettingsSnapshot = .default
    @Published private(set) var effectiveTerminalColorTheme: TerminalColorTheme = .dark
    @Published private(set) var enabledAgents: Set<AgentKind> = []
    @Published private(set) var agentCLIStatuses: [AgentKind: AgentCLIInstallationStatus] = [:]
    @Published private(set) var updatingAgents: Set<AgentKind> = []
    @Published private(set) var networkProxyPassword = ""
    @Published private(set) var creatingWorktreeWorkspaceIDs: Set<WorkspaceID> = []
    @Published private(set) var managedWorktreeInventory:
        [ManagedWorktreeInventoryItem] = []
    @Published private(set) var isRefreshingManagedWorktreeInventory = false
    @Published private(set) var managedWorktreeInventoryError: String?
    @Published private(set) var deletingManagedWorktreeInventoryItemIDs:
        Set<String> = []
    @Published private(set) var isReady = false
    @Published private(set) var isRestoringSelectedSession = false
    @Published private(set) var isPreparingForTermination = false
    @Published private(set) var shortcutPriority = BreathShortcutPriority()
    @Published var lastError: String?

    let terminalEngine: any TerminalEngine & TerminalViewProviding
    let skillsService: GlobalSkillsService
    let adapters = AgentAdapterRegistry.builtIn.adapters

    private let repository: SQLiteWorkbenchRepository
    private let runtime: TerminalEngineRuntime
    private let workbench: Workbench
    private let managedWorktreeService: ManagedWorktreeService
    private let eventServer: UnixAgentEventServer
    private let eventSink: AgentEventSink
    private let userHookInstaller = UserHookIntegrationInstaller()
    private let scriptInstaller = ScriptIntegrationInstaller()
    private let integrationPreferences: AgentIntegrationPreferenceStore
    private let installedAgentCLIDetector: InstalledAgentCLIDetector
    private let networkSessionManager: NetworkSessionManager
    private let networkProxyPasswordStore: any NetworkProxyPasswordStoring
    private let agentCLILatestVersionChecker: AgentCLILatestVersionChecker
    private let homeDirectory: URL
    private var started = false
    private var startupSucceeded = false
    private var startupError: String?
    private var startupTask: Task<Void, Never>?
    private var networkProxyPasswordSaveTask: Task<Void, Never>?
    private var resolvedAppearance: ResolvedApplicationAppearance = .dark

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

    init(
        homeDirectory: URL,
        supportDirectory: URL,
        terminalEngineOverride: (any TerminalEngine & TerminalViewProviding)? = nil,
        integrationPreferences: AgentIntegrationPreferenceStore = AgentIntegrationPreferenceStore(),
        installedAgentCLIDetector: InstalledAgentCLIDetector? = nil,
        networkSessionManager: NetworkSessionManager = .shared,
        networkProxyPasswordStore: any NetworkProxyPasswordStoring =
            KeychainNetworkProxyPasswordStore()
    ) throws {
        self.homeDirectory = homeDirectory
        self.integrationPreferences = integrationPreferences
        self.installedAgentCLIDetector = installedAgentCLIDetector
            ?? InstalledAgentCLIDetector(homeDirectory: homeDirectory)
        self.networkSessionManager = networkSessionManager
        self.networkProxyPasswordStore = networkProxyPasswordStore
        agentCLILatestVersionChecker = AgentCLILatestVersionChecker(
            sessionProvider: { networkSessionManager.session }
        )
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
        skillsService = GlobalSkillsService(
            homeDirectory: homeDirectory,
            agentAdapters: AgentAdapterRegistry.builtIn.adapters,
            targetAvailability: Dictionary(uniqueKeysWithValues:
                AgentAdapterRegistry.builtIn.adapters.map {
                    (
                        $0.kind,
                        SkillInstallationTargetAvailability.unavailable(
                            reason: "Agent installation status is still being checked."
                        )
                    )
                }
            ),
            recordRepository: repository,
            githubProvider: GitHubHTTPSkillProvider(
                sessionProvider: { networkSessionManager.session }
            ),
            skillsShProvider: SkillsShHTTPProvider(
                sessionProvider: { networkSessionManager.session }
            )
        )
        if let terminalEngineOverride {
            terminalEngine = terminalEngineOverride
        } else {
            terminalEngine = try GhosttyTerminalEngine(
                configurationDirectory: supportDirectory.appendingPathComponent("terminal", isDirectory: true),
                agentSocketURL: socketURL
            )
        }
        runtime = TerminalEngineRuntime(engine: terminalEngine)
        managedWorktreeService = ManagedWorktreeService(
            managedRootURL: supportDirectory.appendingPathComponent(
                "worktrees",
                isDirectory: true
            )
        )
        workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            managedWorktreeManager: managedWorktreeService,
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
    }

#if DEBUG
    func prepareForAppShellTesting(snapshot: WorkbenchSnapshot) {
        self.snapshot = snapshot
        isReady = true
        isRestoringSelectedSession = false
        startupSucceeded = true
        started = true
    }
#endif

    var canPerformCommands: Bool {
        isReady && !isRestoringSelectedSession && !isPreparingForTermination
    }

    func updateTerminalInputFocus(
        paneID: TerminalPaneID,
        workSessionID: WorkSessionID,
        isFocused: Bool
    ) {
        var priority = shortcutPriority
        priority.updateTerminalFocus(
            paneID: paneID,
            workSessionID: workSessionID,
            isFocused: isFocused
        )
        shortcutPriority = priority
    }

    func start() {
        guard !started else { return }
        started = true
        do {
            try eventServer.start()
        } catch {
            lastError = "Agent 事件服务启动失败：\(error.localizedDescription)"
        }
        do {
            try installDetectedAgentIntegrations()
        } catch {
            lastError = "自动安装 Agent 集成失败：\(error.localizedDescription)"
        }
        refreshEnabledAgents()
        isRestoringSelectedSession = true
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isReady = true
                isRestoringSelectedSession = false
            }
            do {
                await workbench.setSnapshotChangeHandler { [weak self] in
                    await self?.refreshSnapshot()
                }
                settings = try await repository.loadSettings()
                do {
                    networkProxyPassword = try await networkProxyPasswordStore
                        .loadPassword()
                } catch {
                    networkProxyPassword = ""
                    lastError = "读取代理密码失败：\(error.localizedDescription)"
                }
                networkSessionManager.update(
                    settings: settings.networkProxy,
                    password: networkProxyPassword
                )
                refreshAgentCLIStatuses()
                let terminalSettings = resolveTerminalSettings()
                await runtime.apply(settings: terminalSettings)
                try await workbench.restoreSnapshotFromRepository()
                await refreshSnapshot()
                isReady = true
                await Task.yield()
                try await workbench.materializeSelectedWorkSession()
                await refreshSnapshot()
                startupSucceeded = true
                startupError = nil
            } catch {
                startupError = error.localizedDescription
                lastError = startupError
            }
        }
    }

    func addWorkspace(_ url: URL) {
        perform {
            _ = try await self.workbench.addWorkspace(at: url)
        }
    }

    var currentWorkspaceID: WorkspaceID? {
        guard let selectedWorkSessionID = snapshot.selectedWorkSessionID else {
            return nil
        }
        return snapshot.activeWorkSessions.first(where: {
            $0.id == selectedWorkSessionID
        })?.workspaceID
    }

    func canSelectWorkSessionTab(at index: Int) -> Bool {
        guard let currentWorkspaceID else { return false }
        return snapshot.activeWorkSessionID(at: index, in: currentWorkspaceID) != nil
    }

    var canNavigateSplitPanes: Bool {
        guard let selectedWorkSessionID = snapshot.selectedWorkSessionID,
              let session = snapshot.activeWorkSessions.first(where: {
                  $0.id == selectedWorkSessionID
              })
        else {
            return false
        }
        return session.layout.paneIDs.count > 1
    }

    func createWorkSession(in workspaceID: WorkspaceID) {
        perform {
            _ = try await self.workbench.createWorkSession(in: workspaceID)
        }
    }

    func createManagedWorktreeSession(
        in workspaceID: WorkspaceID,
        startBranch: ManagedWorktreeStartBranch,
        completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        guard !creatingWorktreeWorkspaceIDs.contains(workspaceID) else {
            completion(false)
            return
        }
        creatingWorktreeWorkspaceIDs.insert(workspaceID)
        perform(completion: { [weak self] succeeded in
            self?.creatingWorktreeWorkspaceIDs.remove(workspaceID)
            completion(succeeded)
        }) {
            _ = try await self.workbench.createManagedWorktreeSession(
                in: workspaceID,
                startBranch: startBranch
            )
        }
    }

    func managedWorktreeStartBranches(
        in workspaceID: WorkspaceID
    ) async throws -> [ManagedWorktreeStartBranch] {
        try await workbench.managedWorktreeStartBranches(in: workspaceID)
    }

    func managedWorktreeMergeTargets(
        for workSessionID: WorkSessionID
    ) async throws -> [ManagedWorktreeStartBranch] {
        try await workbench.managedWorktreeMergeTargets(
            for: workSessionID
        )
    }

    func refreshManagedWorktreeInventory() {
        guard !isRefreshingManagedWorktreeInventory else { return }
        isRefreshingManagedWorktreeInventory = true
        managedWorktreeInventoryError = nil
        let workspaces = snapshot.workspaces
        let knownWorktrees = snapshot.workSessions.compactMap(
            \.managedWorktree
        )
        Task {
            defer { isRefreshingManagedWorktreeInventory = false }
            let inventory = await managedWorktreeService.inventory(
                workspaces: workspaces,
                knownWorktrees: knownWorktrees
            )
            managedWorktreeInventory = inventory.items
            managedWorktreeInventoryError = inventory.warnings.isEmpty
                ? nil
                : inventory.warnings.joined(separator: "\n")
        }
    }

    func deleteManagedWorktreeInventoryBranch(
        _ item: ManagedWorktreeInventoryItem
    ) {
        guard !isRefreshingManagedWorktreeInventory,
              deletingManagedWorktreeInventoryItemIDs.insert(item.id).inserted
        else {
            return
        }
        Task {
            defer {
                deletingManagedWorktreeInventoryItemIDs.remove(item.id)
            }
            do {
                try await managedWorktreeService.deleteInventoryBranch(item)
                managedWorktreeInventoryError = nil
                refreshManagedWorktreeInventory()
            } catch {
                managedWorktreeInventoryError =
                    managedWorktreeInventoryErrorDescription(error)
            }
        }
    }

    func deleteManagedWorktreeInventoryDirectory(
        _ item: ManagedWorktreeInventoryItem
    ) {
        guard !isRefreshingManagedWorktreeInventory,
              deletingManagedWorktreeInventoryItemIDs.insert(item.id).inserted
        else {
            return
        }
        Task {
            defer {
                deletingManagedWorktreeInventoryItemIDs.remove(item.id)
            }
            do {
                try await managedWorktreeService.deleteInventoryDirectory(
                    item,
                    knownWorktrees: snapshot.workSessions.compactMap(
                        \.managedWorktree
                    )
                )
                managedWorktreeInventoryError = nil
                refreshManagedWorktreeInventory()
            } catch {
                managedWorktreeInventoryError =
                    managedWorktreeInventoryErrorDescription(error)
            }
        }
    }

    private func managedWorktreeInventoryErrorDescription(
        _ error: Error
    ) -> String {
        if let worktreeError = error as? ManagedWorktreeServiceError {
            return worktreeError.inventoryErrorDescription
        }
        return error.localizedDescription
    }

    func mergeManagedWorktreeSession(
        _ workSessionID: WorkSessionID,
        into targetBranch: ManagedWorktreeStartBranch,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        perform(completion: completion) {
            try await self.workbench.mergeManagedWorktreeSession(
                workSessionID,
                into: targetBranch
            )
        }
    }

    func deleteManagedWorktreeSession(
        _ workSessionID: WorkSessionID,
        selecting fallbackID: WorkSessionID?,
        completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        perform(completion: completion) {
            try await self.workbench.deleteManagedWorktreeSession(
                workSessionID,
                selecting: fallbackID
            )
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

    func closePane(
        _ paneID: TerminalPaneID,
        completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        perform(completion: completion) {
            try await self.workbench.closePane(paneID)
        }
    }

    func archive(
        _ id: WorkSessionID,
        selecting fallbackID: WorkSessionID? = nil
    ) {
        perform {
            try await self.workbench.archiveWorkSession(id)
            if let fallbackID {
                try await self.workbench.selectWorkSession(fallbackID)
            }
        }
    }

    func restoreArchive(_ id: WorkSessionID) {
        perform { try await self.workbench.restoreArchivedWorkSession(id) }
    }

    func deleteArchive(_ id: WorkSessionID) {
        perform { try await self.workbench.deleteArchivedWorkSession(id) }
    }

    func removeWorkspace(_ id: WorkspaceID) {
        let workspace = snapshot.workspaces.first { $0.id == id }
        let knownWorktrees = snapshot.workSessions
            .filter { $0.workspaceID == id }
            .compactMap(\.managedWorktree)
        perform {
            if let workspace {
                _ = try await self.managedWorktreeService
                    .preserveInventoryRepository(
                        for: workspace,
                        knownWorktrees: knownWorktrees
                    )
            }
            try await self.workbench.removeWorkspace(id)
        }
    }

    func saveApplicationSettings(_ application: ApplicationSettings) {
        settings.application = application
        switch application.appearance {
        case .system:
            break
        case .light:
            synchronizeTerminalAppearance(.light)
        case .dark:
            synchronizeTerminalAppearance(.dark)
        }
        persistSettings()
    }

    func saveTerminalSettings(_ terminal: TerminalSettings) {
        settings.terminal = terminal
        let terminalSettings = resolveTerminalSettings()
        Task {
            await runtime.apply(settings: terminalSettings)
            do {
                try await repository.saveSettings(settings)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func saveTerminalShortcutPolicy(_ policy: TerminalShortcutPolicy) {
        settings.terminalShortcutPolicy = policy
        persistSettings()
    }

    func saveNetworkProxySettings(_ networkProxy: NetworkProxySettings) {
        settings.networkProxy = networkProxy
        networkSessionManager.update(
            settings: networkProxy,
            password: networkProxyPassword
        )
        persistSettings()
    }

    func saveNetworkProxyPassword(_ password: String) {
        networkProxyPassword = password
        networkSessionManager.update(
            settings: settings.networkProxy,
            password: password
        )
        let previousSave = networkProxyPasswordSaveTask
        let passwordStore = networkProxyPasswordStore
        networkProxyPasswordSaveTask = Task { [weak self] in
            await previousSave?.value
            do {
                try await passwordStore.savePassword(password)
            } catch {
                self?.lastError = "保存代理密码失败：\(error.localizedDescription)"
            }
        }
    }

    var networkProxyConfigurationError: NetworkProxyConfigurationError? {
        do {
            try NetworkProxySessionConfiguration.validate(settings.networkProxy)
            return nil
        } catch let error as NetworkProxyConfigurationError {
            return error
        } catch {
            return .invalidURL
        }
    }

    func testNetworkProxy(address: String) async -> NetworkProxyTestResult {
        if let networkProxyConfigurationError {
            return .failure(
                .invalidProxyConfiguration(networkProxyConfigurationError)
            )
        }
        return await NetworkProxyTester(
            sessionProvider: { [networkSessionManager] in
                networkSessionManager.session
            }
        ).test(address)
    }

    func synchronizeTerminalAppearance(_ appearance: ResolvedApplicationAppearance) {
        let previousTheme = effectiveTerminalColorTheme
        resolvedAppearance = appearance
        let terminalSettings = resolveTerminalSettings()
        guard terminalSettings.colorTheme != previousTheme else { return }
        Task {
            await runtime.apply(settings: terminalSettings)
        }
    }

    func setAgentIntegration(_ adapter: AgentAdapterDescriptor, enabled: Bool) {
        guard !enabled || installedAgentCLIDetector.isInstalled(adapter.kind) else {
            lastError = "未安装 \(adapter.displayName)，无法安装 Hooks。"
            refreshAgentCLIStatuses()
            return
        }
        do {
            try applyAgentIntegration(adapter, enabled: enabled)
            integrationPreferences.setEnabled(enabled, for: adapter.kind)
            refreshEnabledAgents()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func canToggleAgentIntegration(_ adapter: AgentAdapterDescriptor) -> Bool {
        enabledAgents.contains(adapter.kind)
            || installedAgentCLIDetector.isInstalled(adapter.kind)
    }

    func refreshAgentCLIStatuses() {
        let detector = installedAgentCLIDetector
        let latestVersionChecker = agentCLILatestVersionChecker
        let adapters = self.adapters
        Task { [weak self] in
            let localStatuses = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(
                    of: (AgentKind, AgentCLIInstallationStatus).self,
                    returning: [AgentKind: AgentCLIInstallationStatus].self
                ) { group in
                    for adapter in adapters {
                        group.addTask {
                            (adapter.kind, detector.installationStatus(for: adapter))
                        }
                    }
                    var statuses: [AgentKind: AgentCLIInstallationStatus] = [:]
                    for await (kind, status) in group {
                        statuses[kind] = status
                    }
                    return statuses
                }
            }.value
            guard let self else { return }
            agentCLIStatuses = localStatuses
            await skillsService.updateTargetAvailability(
                Dictionary(uniqueKeysWithValues: adapters.map { adapter in
                    (
                        adapter.kind,
                        SkillInstallationTargetAvailabilityResolver.resolve(
                            adapter: adapter,
                            status: localStatuses[adapter.kind]
                        )
                    )
                })
            )

            await withTaskGroup(of: (AgentKind, String, String?).self) { group in
                for adapter in adapters {
                    guard case let .installed(version?, _) = localStatuses[adapter.kind] else {
                        continue
                    }
                    let homebrewCask = detector.homebrewCaskToken(for: adapter.kind)
                    group.addTask {
                        let latestVersion = await latestVersionChecker.latestVersion(
                            for: adapter.kind,
                            homebrewCask: homebrewCask
                        )
                        return (adapter.kind, version, latestVersion)
                    }
                }
                for await (kind, detectedVersion, latestVersion) in group {
                    guard let latestVersion,
                          case let .installed(currentVersion?, _) = agentCLIStatuses[kind],
                          currentVersion == detectedVersion
                    else {
                        continue
                    }
                    agentCLIStatuses[kind] = .installed(
                        version: currentVersion,
                        updateAvailable: InstalledAgentCLIDetector.isVersion(
                            currentVersion,
                            olderThan: latestVersion
                        )
                    )
                }
            }
        }
    }

    func updateAgentCLI(_ adapter: AgentAdapterDescriptor) {
        guard !updatingAgents.contains(adapter.kind) else { return }
        updatingAgents.insert(adapter.kind)
        let detector = installedAgentCLIDetector
        Task { [weak self] in
            defer { self?.updatingAgents.remove(adapter.kind) }
            do {
                let status = try await Task.detached(priority: .userInitiated) {
                    try detector.update(adapter)
                }.value
                self?.agentCLIStatuses[adapter.kind] = status
                self?.refreshAgentCLIStatuses()
            } catch {
                self?.lastError = "自动更新 \(adapter.displayName) 失败：\(error.localizedDescription)"
                self?.refreshAgentCLIStatuses()
            }
        }
    }

    func repairDetectedAgentIntegrations() {
        refreshEnabledAgents()
        var failures: [String] = []
        for adapter in adapters where !enabledAgents.contains(adapter.kind)
            && integrationPreferences.shouldInstall(
                adapter.kind,
                isInstalled: installedAgentCLIDetector.isInstalled(adapter.kind)
            )
        {
            do {
                try applyAgentIntegration(adapter, enabled: true)
            } catch {
                failures.append("\(adapter.displayName)：\(error.localizedDescription)")
            }
        }
        refreshEnabledAgents()
        if !failures.isEmpty {
            lastError = "修复 Agent 集成失败：\(failures.joined(separator: "；"))"
        }
    }

    func prepareForTermination() async -> Bool {
        guard !isPreparingForTermination else { return false }
        isPreparingForTermination = true
        await networkProxyPasswordSaveTask?.value
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
            isPreparingForTermination = false
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

    func workingDirectory(for session: WorkSession) -> String {
        let workspacePath = snapshot.workspaces.first(where: {
            $0.id == session.workspaceID
        })?.path ?? ""
        return session.workingDirectory(workspacePath: workspacePath)
    }

    func gitWorkspace(for workspaceID: WorkspaceID) -> Workspace? {
        guard let workspace = snapshot.workspaces.first(where: {
            $0.id == workspaceID
        }) else {
            return nil
        }
        guard let selectedID = snapshot.selectedWorkSessionID,
              let selectedSession = snapshot.activeWorkSessions.first(where: {
                  $0.id == selectedID && $0.workspaceID == workspaceID
              })
        else {
            return workspace
        }
        return Workspace(
            id: workspace.id,
            path: workingDirectory(for: selectedSession),
            displayName: workspace.displayName
        )
    }

    private func perform(
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil,
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        guard isReady else {
            completion?(false)
            return
        }
        Task { @MainActor in
            if isRestoringSelectedSession {
                await startupTask?.value
            }
            guard startupSucceeded else {
                lastError = startupError
                    ?? "启动恢复未完成。请退出 Breath 后重试；现有会话数据不会被覆盖。"
                completion?(false)
                return
            }
            do {
                try await operation()
                await refreshSnapshot()
                completion?(true)
            } catch {
                lastError = error.localizedDescription
                completion?(false)
            }
        }
    }

    private func refreshSnapshot() async {
        snapshot = await workbench.snapshot()
    }

    @discardableResult
    private func resolveTerminalSettings() -> TerminalSettings {
        var terminal = settings.terminal
        terminal.colorTheme = terminal.colorTheme.resolved(for: resolvedAppearance)
        effectiveTerminalColorTheme = terminal.colorTheme
        return terminal
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

    private func installDetectedAgentIntegrations() throws {
        for adapter in adapters where integrationPreferences.shouldInstall(
            adapter.kind,
            isInstalled: installedAgentCLIDetector.isInstalled(adapter.kind)
        ) {
            try applyAgentIntegration(adapter, enabled: true)
        }
    }

    private func applyAgentIntegration(
        _ adapter: AgentAdapterDescriptor,
        enabled: Bool
    ) throws {
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

struct AgentIntegrationPreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldInstall(_ agent: AgentKind, isInstalled: Bool) -> Bool {
        guard isInstalled else { return false }
        let preferenceKey = key(for: agent)
        guard defaults.object(forKey: preferenceKey) != nil else {
            return true
        }
        return defaults.bool(forKey: preferenceKey)
    }

    func setEnabled(_ enabled: Bool, for agent: AgentKind) {
        defaults.set(enabled, forKey: key(for: agent))
    }

    private func key(for agent: AgentKind) -> String {
        "Breath.agentIntegration.\(agent.rawValue).enabled"
    }
}

enum AgentCLIInstallationStatus: Equatable, Sendable {
    case notInstalled
    case installed(version: String?, updateAvailable: Bool)
}

enum SkillInstallationTargetAvailabilityResolver {
    static func resolve(
        adapter: AgentAdapterDescriptor,
        status: AgentCLIInstallationStatus?
    ) -> SkillInstallationTargetAvailability {
        switch status {
        case .installed(let version?, _):
            guard !InstalledAgentCLIDetector.isVersion(
                version,
                olderThan: adapter.minimumVersion
            ) else {
                return .unavailable(
                    reason: "\(adapter.displayName) \(version) is older than the supported \(adapter.minimumVersion)."
                )
            }
            return .available
        case .installed(version: nil, updateAvailable: _):
            guard InstalledAgentCLIDetector.hasSemanticVersion(adapter.minimumVersion) else {
                return .available
            }
            return .unavailable(
                reason: "\(adapter.displayName) is installed, but its version could not be verified."
            )
        case .notInstalled, nil:
            return .unavailable(reason: "\(adapter.displayName) is not installed.")
        }
    }
}

enum AgentCLIInstallationError: LocalizedError {
    case notInstalled(String)
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case let .notInstalled(name):
            "未找到 \(name) 的本地可执行文件。"
        case let .updateFailed(message):
            "更新失败：\(message)"
        }
    }
}

struct AgentCLILatestVersionChecker: Sendable {
    private let sessionProvider: @Sendable () -> URLSession

    init(
        sessionProvider: @escaping @Sendable () -> URLSession = {
            URLSession.shared
        }
    ) {
        self.sessionProvider = sessionProvider
    }

    func latestVersion(
        for agent: AgentKind,
        homebrewCask: String? = nil
    ) async -> String? {
        guard let url = Self.releaseURL(for: agent, homebrewCask: homebrewCask) else {
            return nil
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 5
        )
        request.setValue("Breath", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await sessionProvider().data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              data.count <= 1_000_000
        else {
            return nil
        }
        return Self.version(for: agent, in: data)
    }

    static func version(for agent: AgentKind, in data: Data) -> String? {
        switch agent {
        case .cursorAgent:
            guard let contents = String(data: data, encoding: .utf8) else { return nil }
            return value(
                after: "downloads.cursor.com/lab/",
                before: "/",
                in: contents
            )
        case .factoryDroid:
            guard let contents = String(data: data, encoding: .utf8) else { return nil }
            return value(after: "VER=\"", before: "\"", in: contents)
        case .codex,
             .claudeCode,
             .geminiCLI,
             .githubCopilotCLI,
             .qwenCode,
             .openCode,
             .pi:
            return (try? JSONDecoder().decode(NPMRelease.self, from: data))?.version
        }
    }

    static func releaseURL(
        for agent: AgentKind,
        homebrewCask: String? = nil
    ) -> URL? {
        if let homebrewCask {
            return URL(string: "https://formulae.brew.sh/api/cask/\(homebrewCask).json")
        }
        let url: String
        switch agent {
        case .codex:
            url = "https://registry.npmjs.org/%40openai%2Fcodex/latest"
        case .claudeCode:
            url = "https://registry.npmjs.org/%40anthropic-ai%2Fclaude-code/latest"
        case .geminiCLI:
            url = "https://registry.npmjs.org/%40google%2Fgemini-cli/latest"
        case .githubCopilotCLI:
            url = "https://registry.npmjs.org/%40github%2Fcopilot/latest"
        case .qwenCode:
            url = "https://registry.npmjs.org/%40qwen-code%2Fqwen-code/latest"
        case .cursorAgent:
            url = "https://cursor.com/install"
        case .factoryDroid:
            url = "https://app.factory.ai/cli"
        case .openCode:
            url = "https://registry.npmjs.org/opencode-ai/latest"
        case .pi:
            url = "https://registry.npmjs.org/%40mariozechner%2Fpi-coding-agent/latest"
        }
        return URL(string: url)
    }

    private static func value(
        after prefix: String,
        before suffix: Character,
        in contents: String
    ) -> String? {
        guard let prefixRange = contents.range(of: prefix) else { return nil }
        let remainder = contents[prefixRange.upperBound...]
        guard let suffixIndex = remainder.firstIndex(of: suffix) else { return nil }
        let value = remainder[..<suffixIndex]
        return value.isEmpty ? nil : String(value)
    }

    private struct NPMRelease: Decodable {
        let version: String
    }
}

struct InstalledAgentCLIDetector: Sendable {
    private let searchDirectories: [URL]

    init(searchDirectories: [URL]) {
        var seenPaths = Set<String>()
        self.searchDirectories = searchDirectories.compactMap { directory in
            let standardized = directory.standardizedFileURL
            return seenPaths.insert(standardized.path).inserted ? standardized : nil
        }
    }

    init(
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.init(searchDirectories: Self.defaultSearchDirectories(
            homeDirectory: homeDirectory,
            environment: environment
        ))
    }

    func isInstalled(_ agent: AgentKind) -> Bool {
        executableURL(for: agent) != nil
    }

    func homebrewCaskToken(for agent: AgentKind) -> String? {
        guard let executableURL = executableURL(for: agent) else { return nil }
        return homebrewCaskToken(for: agent, executableURL: executableURL)
    }

    func installationStatus(
        for adapter: AgentAdapterDescriptor,
        latestVersion: String? = nil
    ) -> AgentCLIInstallationStatus {
        guard let executableURL = executableURL(for: adapter.kind) else {
            return .notInstalled
        }
        guard let output = try? run(executableURL, arguments: ["--version"]),
              let version = Self.version(in: output)
        else {
            return .installed(version: nil, updateAvailable: false)
        }
        return .installed(
            version: version,
            updateAvailable: Self.isVersion(
                version,
                olderThan: latestVersion ?? adapter.minimumVersion
            )
        )
    }

    func update(
        _ adapter: AgentAdapterDescriptor
    ) throws -> AgentCLIInstallationStatus {
        guard let executableURL = executableURL(for: adapter.kind) else {
            throw AgentCLIInstallationError.notInstalled(adapter.displayName)
        }
        let command = updateCommand(for: adapter.kind, executableURL: executableURL)
        _ = try run(command.executableURL, arguments: command.arguments)
        return installationStatus(for: adapter)
    }

    private func updateCommand(
        for agent: AgentKind,
        executableURL: URL
    ) -> (executableURL: URL, arguments: [String]) {
        if let caskToken = homebrewCaskToken(for: agent, executableURL: executableURL) {
            let brewURL = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("brew")
            if FileManager.default.isExecutableFile(atPath: brewURL.path) {
                return (brewURL, ["upgrade", "--cask", caskToken])
            }
        }
        let resolvedPath = executableURL.resolvingSymlinksInPath().path
        let npmURL = executableURL.deletingLastPathComponent().appendingPathComponent("npm")
        if resolvedPath.contains("/node_modules/"),
           let packageName = agent.npmPackageName,
           FileManager.default.isExecutableFile(atPath: npmURL.path)
        {
            return (npmURL, ["install", "-g", "\(packageName)@latest"])
        }
        return (executableURL, agent.cliUpdateArguments)
    }

    private func homebrewCaskToken(
        for agent: AgentKind,
        executableURL: URL
    ) -> String? {
        guard agent == .claudeCode else { return nil }
        let components = executableURL.resolvingSymlinksInPath().pathComponents
        guard let caskroomIndex = components.firstIndex(of: "Caskroom"),
              components.indices.contains(caskroomIndex + 1)
        else {
            return nil
        }
        let token = components[caskroomIndex + 1]
        return ["claude-code", "claude-code@latest"].contains(token) ? token : nil
    }

    private func executableURL(for agent: AgentKind) -> URL? {
        searchDirectories
            .map { $0.appendingPathComponent(agent.cliExecutableName) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func run(_ executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        let detectedPath = searchDirectories.map(\.path).joined(separator: ":")
        let inheritedPath = environment["PATH", default: ""]
        environment["PATH"] = [detectedPath, inheritedPath]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        process.environment = environment
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let contents = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw AgentCLIInstallationError.updateFailed(
                contents.isEmpty ? "进程退出码 \(process.terminationStatus)" : contents
            )
        }
        return contents
    }

    private static func version(in output: String) -> String? {
        output
            .split(whereSeparator: \Character.isWhitespace)
            .lazy
            .compactMap { rawToken -> String? in
                var token = String(rawToken)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}<>,;:"))
                if token.first == "v" || token.first == "V" {
                    token.removeFirst()
                }
                let components = token.split(separator: ".", omittingEmptySubsequences: false)
                guard components.count >= 2,
                      components.allSatisfy({ component in
                          component.first?.isNumber == true
                      })
                else {
                    return nil
                }
                return token
            }
            .first
    }

    static func isVersion(_ version: String, olderThan minimumVersion: String) -> Bool {
        guard let minimum = Self.version(in: minimumVersion) else { return false }
        let currentComponents = numericComponents(of: version)
        let minimumComponents = numericComponents(of: minimum)
        let componentCount = max(currentComponents.count, minimumComponents.count)
        for index in 0..<componentCount {
            let current = index < currentComponents.count ? currentComponents[index] : 0
            let required = index < minimumComponents.count ? minimumComponents[index] : 0
            if current != required { return current < required }
        }
        return version != minimum
    }

    static func hasSemanticVersion(_ value: String) -> Bool {
        version(in: value) != nil
    }

    private static func numericComponents(of version: String) -> [Int] {
        version.split(separator: ".").map { component in
            let digits = component.prefix(while: \Character.isNumber)
            return Int(digits) ?? 0
        }
    }

    private static func defaultSearchDirectories(
        homeDirectory: URL,
        environment: [String: String]
    ) -> [URL] {
        var directories = environment["PATH", default: ""]
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }

        directories.append(contentsOf: [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent("bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".bun/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".volta/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".asdf/shims", isDirectory: true),
            homeDirectory.appendingPathComponent(".local/share/mise/shims", isDirectory: true),
            homeDirectory.appendingPathComponent(".local/share/fnm/aliases/default/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true),
        ])

        for variable in ["NVM_BIN", "FNM_MULTISHELL_PATH"] {
            if let path = environment[variable], !path.isEmpty {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                directories.append(variable == "FNM_MULTISHELL_PATH"
                    ? directory.appendingPathComponent("bin", isDirectory: true)
                    : directory)
            }
        }

        for variable in ["VOLTA_HOME", "BUN_INSTALL"] {
            if let path = environment[variable], !path.isEmpty {
                directories.append(
                    URL(fileURLWithPath: path, isDirectory: true)
                        .appendingPathComponent("bin", isDirectory: true)
                )
            }
        }

        var nvmRoots = [homeDirectory.appendingPathComponent(".nvm", isDirectory: true)]
        if let path = environment["NVM_DIR"], !path.isEmpty {
            nvmRoots.append(URL(fileURLWithPath: path, isDirectory: true))
        }
        nvmRoots.append(contentsOf: Self.childDirectories(
            of: URL(fileURLWithPath: "/opt/homebrew/Cellar/nvm", isDirectory: true)
        ))
        nvmRoots.append(contentsOf: Self.childDirectories(
            of: URL(fileURLWithPath: "/usr/local/Cellar/nvm", isDirectory: true)
        ))
        for root in nvmRoots {
            let versionsDirectory = root.appendingPathComponent("versions/node", isDirectory: true)
            directories.append(contentsOf: Self.childDirectories(of: versionsDirectory).map {
                $0.appendingPathComponent("bin", isDirectory: true)
            })
        }

        return directories
    }

    private static func childDirectories(of directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}

private extension AgentKind {
    var npmPackageName: String? {
        switch self {
        case .codex: "@openai/codex"
        case .claudeCode: "@anthropic-ai/claude-code"
        case .geminiCLI: "@google/gemini-cli"
        case .githubCopilotCLI: "@github/copilot"
        case .qwenCode: "@qwen-code/qwen-code"
        case .openCode: "opencode-ai"
        case .pi: "@mariozechner/pi-coding-agent"
        case .cursorAgent, .factoryDroid: nil
        }
    }

    var cliUpdateArguments: [String] {
        switch self {
        case .openCode:
            ["upgrade"]
        case .pi:
            ["update", "--self"]
        case .codex,
             .claudeCode,
             .geminiCLI,
             .githubCopilotCLI,
             .qwenCode,
             .cursorAgent,
             .factoryDroid:
            ["update"]
        }
    }
}

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
