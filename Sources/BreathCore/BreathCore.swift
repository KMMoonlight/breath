import Foundation

public struct ApplicationInstanceID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct WorkspaceID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct WorkSessionID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct TerminalPaneID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct Workspace: Equatable, Codable, Sendable, Identifiable {
    public let id: WorkspaceID
    public let path: String
    public let displayName: String

    public init(id: WorkspaceID, path: String, displayName: String) {
        self.id = id
        self.path = path
        self.displayName = displayName
    }
}

public enum TerminalState: String, Equatable, Codable, Sendable {
    case idle
    case running
    case needsAttention
    case turnCompleted
}

public enum AgentKind: String, CaseIterable, Equatable, Hashable, Codable, Sendable {
    case codex
    case claudeCode
    case geminiCLI
    case githubCopilotCLI
    case qwenCode
    case cursorAgent
    case factoryDroid
    case openCode
    case pi
}

public enum AgentLifecycle: String, Equatable, Codable, Sendable {
    case turnStarted
    case needsAttention
    case attentionResolved
    case turnCompleted
    case sessionEnded
    case metadataUpdated
}

public struct AgentBinding: Equatable, Codable, Sendable {
    public let agent: AgentKind
    public var version: String?
    public var sessionID: String?
    public var nativeTitle: String?
    public var isActive: Bool?
    public var lastEventAt: Date?

    public init(
        agent: AgentKind,
        version: String? = nil,
        sessionID: String? = nil,
        nativeTitle: String? = nil,
        isActive: Bool? = nil,
        lastEventAt: Date? = nil
    ) {
        self.agent = agent
        self.version = version
        self.sessionID = sessionID
        self.nativeTitle = nativeTitle
        self.isActive = isActive
        self.lastEventAt = lastEventAt
    }
}

public struct AgentEvent: Equatable, Codable, Sendable {
    public let applicationInstanceID: ApplicationInstanceID
    public let agent: AgentKind
    public let version: String?
    public let lifecycle: AgentLifecycle
    public let occurredAt: Date
    public let workspaceID: WorkspaceID
    public let workSessionID: WorkSessionID
    public let paneID: TerminalPaneID
    public let sessionID: String?
    public let nativeTitle: String?
    public let workingDirectory: String

    public init(
        applicationInstanceID: ApplicationInstanceID,
        agent: AgentKind,
        version: String? = nil,
        lifecycle: AgentLifecycle,
        occurredAt: Date,
        workspaceID: WorkspaceID,
        workSessionID: WorkSessionID,
        paneID: TerminalPaneID,
        sessionID: String? = nil,
        nativeTitle: String? = nil,
        workingDirectory: String
    ) {
        self.applicationInstanceID = applicationInstanceID
        self.agent = agent
        self.version = version
        self.lifecycle = lifecycle
        self.occurredAt = occurredAt
        self.workspaceID = workspaceID
        self.workSessionID = workSessionID
        self.paneID = paneID
        self.sessionID = sessionID
        self.nativeTitle = nativeTitle
        self.workingDirectory = workingDirectory
    }
}

public struct TerminalPane: Equatable, Codable, Sendable, Identifiable {
    public let id: TerminalPaneID
    public var state: TerminalState
    public var agentBinding: AgentBinding?

    public init(
        id: TerminalPaneID,
        state: TerminalState = .idle,
        agentBinding: AgentBinding? = nil
    ) {
        self.id = id
        self.state = state
        self.agentBinding = agentBinding
    }
}

public enum SplitOrientation: String, Equatable, Codable, Sendable {
    case horizontal
    case vertical
}

public enum SplitBranch: String, Equatable, Hashable, Codable, Sendable {
    case first
    case second
}

public indirect enum PaneLayout: Equatable, Codable, Sendable {
    case pane(TerminalPane)
    case split(
        orientation: SplitOrientation,
        fraction: Double,
        first: PaneLayout,
        second: PaneLayout
    )

    public var paneIDs: [TerminalPaneID] {
        switch self {
        case .pane(let pane):
            return [pane.id]
        case .split(_, _, let first, let second):
            return first.paneIDs + second.paneIDs
        }
    }

    public var panes: [TerminalPane] {
        switch self {
        case .pane(let pane):
            return [pane]
        case .split(_, _, let first, let second):
            return first.panes + second.panes
        }
    }

    public func previousPaneID(from paneID: TerminalPaneID) -> TerminalPaneID? {
        adjacentPaneID(from: paneID, offset: -1)
    }

    public func nextPaneID(from paneID: TerminalPaneID) -> TerminalPaneID? {
        adjacentPaneID(from: paneID, offset: 1)
    }

    private func adjacentPaneID(
        from paneID: TerminalPaneID,
        offset: Int
    ) -> TerminalPaneID? {
        let paneIDs = paneIDs
        guard paneIDs.count > 1,
              let currentIndex = paneIDs.firstIndex(of: paneID)
        else {
            return nil
        }
        let adjacentIndex = (currentIndex + offset + paneIDs.count) % paneIDs.count
        return paneIDs[adjacentIndex]
    }

    fileprivate func splitting(
        paneID: TerminalPaneID,
        orientation: SplitOrientation,
        newPane: TerminalPane
    ) -> PaneLayout? {
        switch self {
        case .pane(let pane) where pane.id == paneID:
            return .split(
                orientation: orientation,
                fraction: 0.5,
                first: .pane(pane),
                second: .pane(newPane)
            )
        case .pane:
            return nil
        case .split(let currentOrientation, let fraction, let first, let second):
            if let replacement = first.splitting(
                paneID: paneID,
                orientation: orientation,
                newPane: newPane
            ) {
                return .split(
                    orientation: currentOrientation,
                    fraction: fraction,
                    first: replacement,
                    second: second
                )
            }
            if let replacement = second.splitting(
                paneID: paneID,
                orientation: orientation,
                newPane: newPane
            ) {
                return .split(
                    orientation: currentOrientation,
                    fraction: fraction,
                    first: first,
                    second: replacement
                )
            }
            return nil
        }
    }

    fileprivate func updatingPane(
        id paneID: TerminalPaneID,
        transform: (inout TerminalPane) -> Void
    ) -> PaneLayout? {
        switch self {
        case .pane(var pane) where pane.id == paneID:
            transform(&pane)
            return .pane(pane)
        case .pane:
            return nil
        case .split(let orientation, let fraction, let first, let second):
            if let replacement = first.updatingPane(id: paneID, transform: transform) {
                return .split(
                    orientation: orientation,
                    fraction: fraction,
                    first: replacement,
                    second: second
                )
            }
            if let replacement = second.updatingPane(id: paneID, transform: transform) {
                return .split(
                    orientation: orientation,
                    fraction: fraction,
                    first: first,
                    second: replacement
                )
            }
            return nil
        }
    }

    fileprivate func resizingSplit(
        containing paneID: TerminalPaneID,
        fraction: Double
    ) -> PaneLayout? {
        guard case .split(let orientation, _, let first, let second) = self,
              paneIDs.contains(paneID)
        else {
            return nil
        }
        return .split(
            orientation: orientation,
            fraction: min(max(fraction, 0.1), 0.9),
            first: first,
            second: second
        )
    }

    fileprivate func resizingSplit(
        at path: ArraySlice<SplitBranch>,
        fraction: Double
    ) -> PaneLayout? {
        guard case .split(let orientation, let currentFraction, let first, let second) = self else {
            return nil
        }
        guard let branch = path.first else {
            return .split(
                orientation: orientation,
                fraction: min(max(fraction, 0.1), 0.9),
                first: first,
                second: second
            )
        }
        switch branch {
        case .first:
            guard let replacement = first.resizingSplit(
                at: path.dropFirst(),
                fraction: fraction
            ) else { return nil }
            return .split(
                orientation: orientation,
                fraction: currentFraction,
                first: replacement,
                second: second
            )
        case .second:
            guard let replacement = second.resizingSplit(
                at: path.dropFirst(),
                fraction: fraction
            ) else { return nil }
            return .split(
                orientation: orientation,
                fraction: currentFraction,
                first: first,
                second: replacement
            )
        }
    }

    fileprivate func removingPane(id paneID: TerminalPaneID) -> PaneLayout? {
        switch self {
        case .pane:
            return nil
        case .split(let orientation, let fraction, let first, let second):
            if first.paneIDs == [paneID] {
                return second
            }
            if second.paneIDs == [paneID] {
                return first
            }
            if first.paneIDs.contains(paneID),
               let replacement = first.removingPane(id: paneID)
            {
                return .split(
                    orientation: orientation,
                    fraction: fraction,
                    first: replacement,
                    second: second
                )
            }
            if second.paneIDs.contains(paneID),
               let replacement = second.removingPane(id: paneID)
            {
                return .split(
                    orientation: orientation,
                    fraction: fraction,
                    first: first,
                    second: replacement
                )
            }
            return nil
        }
    }
}

public enum WorkSessionTitleSource: String, Equatable, Codable, Sendable {
    case agentNative
}

public struct WorkSession: Equatable, Codable, Sendable, Identifiable {
    public let id: WorkSessionID
    public let workspaceID: WorkspaceID
    public var title: String
    public var layout: PaneLayout
    public var archivedAt: Date?
    public var titleSource: WorkSessionTitleSource?
    public var managedWorktree: ManagedWorktree?

    public var pane: TerminalPane {
        switch layout {
        case .pane(let pane):
            return pane
        case .split(_, _, let first, _):
            return WorkSession(
                id: id,
                workspaceID: workspaceID,
                title: title,
                layout: first
            ).pane
        }
    }

    public init(
        id: WorkSessionID,
        workspaceID: WorkspaceID,
        title: String,
        pane: TerminalPane,
        archivedAt: Date? = nil,
        titleSource: WorkSessionTitleSource? = nil,
        managedWorktree: ManagedWorktree? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.layout = .pane(pane)
        self.archivedAt = archivedAt
        self.titleSource = titleSource
        self.managedWorktree = managedWorktree
    }

    public init(
        id: WorkSessionID,
        workspaceID: WorkspaceID,
        title: String,
        layout: PaneLayout,
        archivedAt: Date? = nil,
        titleSource: WorkSessionTitleSource? = nil,
        managedWorktree: ManagedWorktree? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.layout = layout
        self.archivedAt = archivedAt
        self.titleSource = titleSource
        self.managedWorktree = managedWorktree
    }

    public func workingDirectory(workspacePath: String) -> String {
        guard let managedWorktree,
              managedWorktree.workspaceID == workspaceID,
              managedWorktree.workSessionID == id
        else {
            return workspacePath
        }
        return managedWorktree.workingDirectory
    }
}

public struct WorkbenchSnapshot: Equatable, Codable, Sendable {
    public var workspaces: [Workspace]
    public var workSessions: [WorkSession]
    public var selectedWorkSessionID: WorkSessionID?

    public init(
        workspaces: [Workspace],
        workSessions: [WorkSession],
        selectedWorkSessionID: WorkSessionID?
    ) {
        self.workspaces = workspaces
        self.workSessions = workSessions
        self.selectedWorkSessionID = selectedWorkSessionID
    }

    public static let empty = WorkbenchSnapshot(
        workspaces: [],
        workSessions: [],
        selectedWorkSessionID: nil
    )

    public var activeWorkSessions: [WorkSession] {
        workSessions.filter { $0.archivedAt == nil }
    }

    public var archivedWorkSessions: [WorkSession] {
        workSessions.filter { $0.archivedAt != nil }
    }

    public func activeWorkSessionID(
        at index: Int,
        in workspaceID: WorkspaceID
    ) -> WorkSessionID? {
        let sessionIDs = activeWorkSessions
            .filter { $0.workspaceID == workspaceID }
            .map(\.id)
        guard sessionIDs.indices.contains(index) else { return nil }
        return sessionIDs[index]
    }

    public func archiveFallbackWorkSessionID(
        for workSessionID: WorkSessionID
    ) -> WorkSessionID? {
        guard selectedWorkSessionID == workSessionID,
              let session = activeWorkSessions.first(where: {
                  $0.id == workSessionID
              })
        else {
            return nil
        }
        let sessionIDs = activeWorkSessions
            .filter { $0.workspaceID == session.workspaceID }
            .map(\.id)
        guard sessionIDs.count > 1,
              let index = sessionIDs.firstIndex(of: workSessionID)
        else {
            return nil
        }
        let fallbackIndex = index + 1 < sessionIDs.count ? index + 1 : index - 1
        return sessionIDs[fallbackIndex]
    }
}

public struct TerminalLaunch: Equatable, Sendable {
    public let paneID: TerminalPaneID
    public let workingDirectory: String
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(
        paneID: TerminalPaneID,
        workingDirectory: String,
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) {
        self.paneID = paneID
        self.workingDirectory = workingDirectory
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

public protocol WorkbenchRepository: Sendable {
    func load() async throws -> WorkbenchSnapshot
    func save(_ snapshot: WorkbenchSnapshot) async throws
}

public protocol TerminalRuntime: Sendable {
    func launch(_ request: TerminalLaunch) async throws
    func stop(paneID: TerminalPaneID) async
    func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async
    func setInputSubmittedHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) async -> Void
    ) async
}

public extension TerminalRuntime {
    func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async {}

    func setInputSubmittedHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) async -> Void
    ) async {}
}

public struct AgentResumeCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public protocol AgentResumeCommandProviding: Sendable {
    func resumeCommand(for binding: AgentBinding) -> AgentResumeCommand?
}

public enum WorkbenchError: Error, Equatable {
    case workspaceNotFound(WorkspaceID)
    case workspaceAlreadyExists(String)
    case workspaceUnavailable(WorkspaceID)
    case workSessionNotFound(WorkSessionID)
    case terminalPaneNotFound(TerminalPaneID)
    case invalidSplitPath
    case cannotCloseLastPane
    case agentEventTargetMismatch
    case managedWorktreesUnavailable
    case managedWorktreeUnavailable(WorkSessionID)
    case managedWorktreeOwnershipMismatch(WorkSessionID)
    case managedWorktreeCreationRollbackFailed(
        worktreePath: String,
        creationError: String,
        cleanupError: String
    )
    case managedWorktreePersistenceRollbackFailed(
        worktreePath: String,
        persistenceError: String,
        rollbackError: String
    )
    case preparingForCleanExit
}

extension WorkbenchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .workspaceNotFound:
            return "找不到工作区。"
        case .workspaceAlreadyExists(let path):
            return "该工作区已经存在：\(path)"
        case .workspaceUnavailable:
            return "工作区目录当前不可用。"
        case .workSessionNotFound:
            return "找不到工作会话。"
        case .terminalPaneNotFound:
            return "找不到终端窗格。"
        case .invalidSplitPath:
            return "分屏布局已经发生变化，请重试。"
        case .cannotCloseLastPane:
            return "不能单独关闭工作会话中的最后一个终端。"
        case .agentEventTargetMismatch:
            return "Agent 事件不属于当前 Breath 会话。"
        case .managedWorktreesUnavailable:
            return "Worktree 服务当前不可用。"
        case .managedWorktreeUnavailable:
            return "该工作会话的 Worktree 已不可用。"
        case .managedWorktreeOwnershipMismatch:
            return "Worktree 所属信息与工作会话不一致，已拒绝操作。"
        case .managedWorktreeCreationRollbackFailed(
            let worktreePath,
            let creationError,
            let cleanupError
        ):
            return """
            Worktree 会话创建失败，且自动清理未完成：\(worktreePath)
            创建错误：\(creationError)
            清理错误：\(cleanupError)
            """
        case .managedWorktreePersistenceRollbackFailed(
            let worktreePath,
            let persistenceError,
            let rollbackError
        ):
            return """
            Worktree 会话持久化失败，且无法恢复之前的快照：\(worktreePath)
            持久化错误：\(persistenceError)
            恢复错误：\(rollbackError)
            """
        case .preparingForCleanExit:
            return "Breath 正在退出，无法开始新的 Worktree 操作。"
        }
    }
}

private actor ManagedWorktreeLifecycleGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

public actor Workbench {
    private struct RecoveryFallback: Sendable {
        let token: UUID
        let workSessionID: WorkSessionID
        let shellLaunch: TerminalLaunch
    }

    private let repository: any WorkbenchRepository
    private let terminalRuntime: any TerminalRuntime
    private let managedWorktreeManager: (any ManagedWorktreeManaging)?
    private let managedWorktreeLifecycleGate = ManagedWorktreeLifecycleGate()
    private let applicationInstanceID: ApplicationInstanceID
    private let agentResumeCommands: (any AgentResumeCommandProviding)?
    private let defaultShell: @Sendable () -> String
    private let workspaceAvailable: @Sendable (String) -> Bool
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private var currentSnapshot: WorkbenchSnapshot
    private var materializedWorkSessionIDs: Set<WorkSessionID>
    private var recoveryFallbacks: [TerminalPaneID: RecoveryFallback]
    private var monitorsProcessExits = false
    private var monitorsInputSubmissions = false
    private var isPreparingForCleanExit = false
    private var snapshotChangeHandler: (@Sendable () async -> Void)?

    public init(
        repository: any WorkbenchRepository,
        terminalRuntime: any TerminalRuntime,
        managedWorktreeManager: (any ManagedWorktreeManaging)? = nil,
        agentResumeCommands: (any AgentResumeCommandProviding)? = nil,
        applicationInstanceID: ApplicationInstanceID = ApplicationInstanceID(rawValue: UUID()),
        defaultShell: @escaping @Sendable () -> String,
        workspaceAvailable: @escaping @Sendable (String) -> Bool = { _ in true },
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.repository = repository
        self.terminalRuntime = terminalRuntime
        self.managedWorktreeManager = managedWorktreeManager
        self.agentResumeCommands = agentResumeCommands
        self.applicationInstanceID = applicationInstanceID
        self.defaultShell = defaultShell
        self.workspaceAvailable = workspaceAvailable
        self.now = now
        self.timeZone = timeZone
        currentSnapshot = .empty
        materializedWorkSessionIDs = []
        recoveryFallbacks = [:]
    }

    @discardableResult
    public func addWorkspace(at url: URL) async throws -> WorkspaceID {
        let previousSnapshot = currentSnapshot
        let normalizedURL = canonicalWorkspaceURL(url)
        let comparisonKey = workspaceComparisonKey(normalizedURL)
        guard !currentSnapshot.workspaces.contains(where: {
            workspaceComparisonKey(URL(fileURLWithPath: $0.path, isDirectory: true)) == comparisonKey
        }) else {
            throw WorkbenchError.workspaceAlreadyExists(normalizedURL.path)
        }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: normalizedURL.path,
            displayName: normalizedURL.lastPathComponent
        )
        currentSnapshot.workspaces.append(workspace)
        try await persistSnapshot(rollingBackTo: previousSnapshot)
        return workspace.id
    }

    @discardableResult
    public func createWorkSession(in workspaceID: WorkspaceID) async throws -> WorkSessionID {
        guard let workspace = currentSnapshot.workspaces.first(where: { $0.id == workspaceID }) else {
            throw WorkbenchError.workspaceNotFound(workspaceID)
        }
        guard workspaceAvailable(workspace.path) else {
            throw WorkbenchError.workspaceUnavailable(workspaceID)
        }

        let workSessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let workSession = WorkSession(
            id: workSessionID,
            workspaceID: workspaceID,
            title: placeholderTitle(at: now()),
            pane: TerminalPane(id: paneID)
        )
        let launch = TerminalLaunch(
            paneID: paneID,
            workingDirectory: workspace.path,
            executable: defaultShell(),
            arguments: ["-l"],
            environment: [
                "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
                "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
                "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
                "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
            ]
        )

        let previousSnapshot = currentSnapshot
        await ensureInputSubmissionMonitoring()
        try await terminalRuntime.launch(launch)
        currentSnapshot.workSessions.append(workSession)
        currentSnapshot.selectedWorkSessionID = workSessionID
        do {
            try await persistSnapshot(rollingBackTo: previousSnapshot)
        } catch {
            await terminalRuntime.stop(paneID: paneID)
            throw error
        }
        materializedWorkSessionIDs.insert(workSessionID)
        return workSessionID
    }

    @discardableResult
    public func createManagedWorktreeSession(
        in workspaceID: WorkspaceID,
        branchName: String
    ) async throws -> WorkSessionID {
        try await createManagedWorktreeSession(
            in: workspaceID,
            branchName: branchName,
            startBranch: nil
        )
    }

    public func managedWorktreeStartBranches(
        in workspaceID: WorkspaceID
    ) async throws -> [ManagedWorktreeStartBranch] {
        guard let workspace = currentSnapshot.workspaces.first(where: {
            $0.id == workspaceID
        }) else {
            throw WorkbenchError.workspaceNotFound(workspaceID)
        }
        guard workspaceAvailable(workspace.path) else {
            throw WorkbenchError.workspaceUnavailable(workspaceID)
        }
        guard let managedWorktreeManager else {
            throw WorkbenchError.managedWorktreesUnavailable
        }
        return try await managedWorktreeManager.startBranches(for: workspace)
    }

    @discardableResult
    public func createManagedWorktreeSession(
        in workspaceID: WorkspaceID,
        startBranch: ManagedWorktreeStartBranch
    ) async throws -> WorkSessionID {
        let workSessionID = WorkSessionID(rawValue: UUID())
        return try await createManagedWorktreeSession(
            in: workspaceID,
            branchName: ManagedWorktree.sessionBranchName(
                for: workSessionID
            ),
            startBranch: startBranch,
            workSessionID: workSessionID
        )
    }

    private func createManagedWorktreeSession(
        in workspaceID: WorkspaceID,
        branchName: String,
        startBranch: ManagedWorktreeStartBranch?,
        workSessionID: WorkSessionID? = nil
    ) async throws -> WorkSessionID {
        guard !isPreparingForCleanExit else {
            throw WorkbenchError.preparingForCleanExit
        }
        await managedWorktreeLifecycleGate.acquire()
        guard !isPreparingForCleanExit else {
            await managedWorktreeLifecycleGate.release()
            throw WorkbenchError.preparingForCleanExit
        }
        do {
            let workSessionID =
                try await createManagedWorktreeSessionWithoutAcquiringGate(
                    in: workspaceID,
                    branchName: branchName,
                    startBranch: startBranch,
                    workSessionID: workSessionID
                )
            await managedWorktreeLifecycleGate.release()
            return workSessionID
        } catch {
            await managedWorktreeLifecycleGate.release()
            throw error
        }
    }

    private func createManagedWorktreeSessionWithoutAcquiringGate(
        in workspaceID: WorkspaceID,
        branchName: String,
        startBranch: ManagedWorktreeStartBranch?,
        workSessionID requestedWorkSessionID: WorkSessionID? = nil
    ) async throws -> WorkSessionID {
        guard let workspace = currentSnapshot.workspaces.first(where: {
            $0.id == workspaceID
        }) else {
            throw WorkbenchError.workspaceNotFound(workspaceID)
        }
        guard workspaceAvailable(workspace.path) else {
            throw WorkbenchError.workspaceUnavailable(workspaceID)
        }
        guard let managedWorktreeManager else {
            throw WorkbenchError.managedWorktreesUnavailable
        }

        let workSessionID =
            requestedWorkSessionID ?? WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let managedWorktree = try await managedWorktreeManager.create(
            workspace: workspace,
            workSessionID: workSessionID,
            branchName: branchName,
            startBranch: startBranch
        )
        guard managedWorktree.workspaceID == workspaceID,
              managedWorktree.workSessionID == workSessionID
        else {
            let ownershipError =
                WorkbenchError.managedWorktreeOwnershipMismatch(
                workSessionID
            )
            try await rollbackManagedWorktreeCreation(
                managedWorktree,
                after: ownershipError,
                using: managedWorktreeManager
            )
            throw ownershipError
        }
        let workSession = WorkSession(
            id: workSessionID,
            workspaceID: workspaceID,
            title: placeholderTitle(at: now()),
            pane: TerminalPane(id: paneID),
            managedWorktree: managedWorktree
        )
        let launch = TerminalLaunch(
            paneID: paneID,
            workingDirectory: managedWorktree.workingDirectory,
            executable: defaultShell(),
            arguments: ["-l"],
            environment: terminalEnvironment(
                workspaceID: workspaceID,
                workSessionID: workSessionID,
                paneID: paneID
            )
        )

        do {
            await ensureInputSubmissionMonitoring()
            try await terminalRuntime.launch(launch)
        } catch let creationError {
            await terminalRuntime.stop(paneID: paneID)
            try await rollbackManagedWorktreeCreation(
                managedWorktree,
                after: creationError,
                using: managedWorktreeManager
            )
            throw creationError
        }

        do {
            try await persistAndPublishCreatedWorkSession(workSession)
        } catch let creationError {
            await terminalRuntime.stop(paneID: paneID)
            if let workbenchError = creationError as? WorkbenchError,
               case .managedWorktreePersistenceRollbackFailed =
                   workbenchError
            {
                throw creationError
            }
            try await rollbackManagedWorktreeCreation(
                managedWorktree,
                after: creationError,
                using: managedWorktreeManager
            )
            throw creationError
        }
        return workSessionID
    }

    private func persistAndPublishCreatedWorkSession(
        _ workSession: WorkSession
    ) async throws {
        var persistedUnpublishedSession = false
        do {
            while true {
                let baseSnapshot = currentSnapshot
                var completedSnapshot = baseSnapshot
                completedSnapshot.workSessions.append(workSession)
                completedSnapshot.selectedWorkSessionID = workSession.id

                try await repository.save(completedSnapshot)
                persistedUnpublishedSession = true
                guard currentSnapshot == baseSnapshot else {
                    continue
                }
                materializedWorkSessionIDs.insert(workSession.id)
                currentSnapshot = completedSnapshot
                await snapshotChangeHandler?()
                return
            }
        } catch let persistenceError {
            guard persistedUnpublishedSession else {
                throw persistenceError
            }
            do {
                try await restorePersistedPublishedSnapshot()
            } catch let rollbackError {
                throw WorkbenchError
                    .managedWorktreePersistenceRollbackFailed(
                        worktreePath:
                            workSession.managedWorktree?.rootPath ?? "",
                        persistenceError:
                            persistenceError.localizedDescription,
                        rollbackError: rollbackError.localizedDescription
                    )
            }
            throw persistenceError
        }
    }

    private func restorePersistedPublishedSnapshot() async throws {
        while true {
            let publishedSnapshot = currentSnapshot
            try await repository.save(publishedSnapshot)
            guard currentSnapshot == publishedSnapshot else {
                continue
            }
            return
        }
    }

    private func rollbackManagedWorktreeCreation(
        _ managedWorktree: ManagedWorktree,
        after creationError: any Error,
        using manager: any ManagedWorktreeManaging
    ) async throws {
        do {
            try await manager.rollbackCreation(managedWorktree)
        } catch let cleanupError {
            throw WorkbenchError.managedWorktreeCreationRollbackFailed(
                worktreePath: managedWorktree.rootPath,
                creationError: creationError.localizedDescription,
                cleanupError: cleanupError.localizedDescription
            )
        }
    }

    public func snapshot() -> WorkbenchSnapshot {
        currentSnapshot
    }

    public func setSnapshotChangeHandler(
        _ handler: @escaping @Sendable () async -> Void
    ) {
        snapshotChangeHandler = handler
    }

    public func selectWorkSession(_ workSessionID: WorkSessionID) async throws {
        try await withManagedWorktreeLifecycleGate {
            try await selectWorkSessionWithoutAcquiringGate(workSessionID)
        }
    }

    private func selectWorkSessionWithoutAcquiringGate(
        _ workSessionID: WorkSessionID
    ) async throws {
        let previousSelection = currentSnapshot.selectedWorkSessionID
        guard currentSnapshot.workSessions.contains(where: {
            $0.id == workSessionID && $0.archivedAt == nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        if !materializedWorkSessionIDs.contains(workSessionID) {
            try await materializeWorkSessionWithoutAcquiringGate(
                workSessionID
            )
        }
        guard currentSnapshot.workSessions.contains(where: {
            $0.id == workSessionID && $0.archivedAt == nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        currentSnapshot.selectedWorkSessionID = workSessionID
        do {
            try await repository.save(currentSnapshot)
        } catch {
            currentSnapshot.selectedWorkSessionID = previousSelection
            throw error
        }
    }

    public func restoreFromRepository() async throws {
        try await restoreSnapshotFromRepository()
        try await materializeSelectedWorkSession()
    }

    public func restoreSnapshotFromRepository() async throws {
        currentSnapshot = try await repository.load()
        materializedWorkSessionIDs.removeAll()
        recoveryFallbacks.removeAll()
        var reconciledWorktrees = false
        for index in currentSnapshot.workSessions.indices {
            guard var managedWorktree =
                currentSnapshot.workSessions[index].managedWorktree
            else {
                continue
            }
            let isAvailable: Bool
            let workSession = currentSnapshot.workSessions[index]
            if managedWorktree.workspaceID == workSession.workspaceID,
               managedWorktree.workSessionID == workSession.id,
               let managedWorktreeManager
            {
                isAvailable = await managedWorktreeManager.isAvailable(
                    managedWorktree
                )
            } else {
                isAvailable = false
            }
            let state: ManagedWorktreeState = isAvailable
                ? .available
                : .unavailable
            if managedWorktree.state != state {
                managedWorktree.state = state
                currentSnapshot.workSessions[index].managedWorktree =
                    managedWorktree
                reconciledWorktrees = true
            }
        }
        if reconciledWorktrees {
            try await repository.save(currentSnapshot)
        }

        guard let selectedID = currentSnapshot.selectedWorkSessionID,
              let selectedSession = currentSnapshot.workSessions.first(where: {
                  $0.id == selectedID && $0.archivedAt == nil
              }),
              let selectedWorkspace = currentSnapshot.workspaces.first(where: {
                  $0.id == selectedSession.workspaceID
              })
        else {
            currentSnapshot.selectedWorkSessionID = nil
            return
        }
        do {
            _ = try await workingDirectory(
                for: selectedSession,
                workspace: selectedWorkspace
            )
        } catch {
            currentSnapshot.selectedWorkSessionID = nil
        }
    }

    public func materializeSelectedWorkSession() async throws {
        try await withManagedWorktreeLifecycleGate {
            if let selectedID = currentSnapshot.selectedWorkSessionID,
               !materializedWorkSessionIDs.contains(selectedID)
            {
                try await materializeWorkSessionWithoutAcquiringGate(
                    selectedID
                )
            }
        }
    }

    public func prepareForCleanExit() async throws {
        guard !isPreparingForCleanExit else {
            throw WorkbenchError.preparingForCleanExit
        }
        isPreparingForCleanExit = true
        await managedWorktreeLifecycleGate.acquire()
        do {
            try await repository.save(currentSnapshot)
            recoveryFallbacks.removeAll()
            for workSession in currentSnapshot.workSessions {
                for paneID in workSession.layout.paneIDs {
                    await terminalRuntime.stop(paneID: paneID)
                }
            }
            await managedWorktreeLifecycleGate.release()
        } catch {
            isPreparingForCleanExit = false
            await managedWorktreeLifecycleGate.release()
            throw error
        }
    }

    public func stopAllTerminalsWithoutSaving() async {
        recoveryFallbacks.removeAll()
        for workSession in currentSnapshot.workSessions {
            for paneID in workSession.layout.paneIDs {
                await terminalRuntime.stop(paneID: paneID)
            }
        }
        materializedWorkSessionIDs.removeAll()
    }

    @discardableResult
    public func splitPane(
        _ paneID: TerminalPaneID,
        orientation: SplitOrientation
    ) async throws -> TerminalPaneID {
        try await withManagedWorktreeLifecycleGate {
            try await splitPaneWithoutAcquiringGate(
                paneID,
                orientation: orientation
            )
        }
    }

    private func splitPaneWithoutAcquiringGate(
        _ paneID: TerminalPaneID,
        orientation: SplitOrientation
    ) async throws -> TerminalPaneID {
        guard let workSession = currentSnapshot.workSessions.first(where: {
            $0.archivedAt == nil && $0.layout.paneIDs.contains(paneID)
        }) else {
            throw WorkbenchError.terminalPaneNotFound(paneID)
        }
        guard let workspace = currentSnapshot.workspaces.first(where: {
            $0.id == workSession.workspaceID
        }) else {
            throw WorkbenchError.workspaceNotFound(workSession.workspaceID)
        }
        let workingDirectory = try await workingDirectory(
            for: workSession,
            workspace: workspace
        )

        guard let refreshedSession = currentSnapshot.workSessions.first(
            where: {
                $0.id == workSession.id
                    && $0.workspaceID == workspace.id
                    && $0.archivedAt == nil
                    && $0.layout.paneIDs.contains(paneID)
            }
        ), currentSnapshot.workspaces.contains(where: {
            $0.id == workspace.id
        }) else {
            throw WorkbenchError.workSessionNotFound(workSession.id)
        }
        let newPane = TerminalPane(id: TerminalPaneID(rawValue: UUID()))
        guard refreshedSession.layout.splitting(
            paneID: paneID,
            orientation: orientation,
            newPane: newPane
        ) != nil else {
            throw WorkbenchError.terminalPaneNotFound(paneID)
        }
        let launch = TerminalLaunch(
            paneID: newPane.id,
            workingDirectory: workingDirectory,
            executable: defaultShell(),
            arguments: ["-l"],
            environment: [
                "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
                "BREATH_WORKSPACE_ID": workspace.id.rawValue.uuidString,
                "BREATH_WORK_SESSION_ID": workSession.id.rawValue.uuidString,
                "BREATH_TERMINAL_PANE_ID": newPane.id.rawValue.uuidString,
            ]
        )

        await ensureInputSubmissionMonitoring()
        guard ownsTerminalPane(
            paneID,
            workSessionID: workSession.id,
            workspaceID: workspace.id
        ) else {
            throw WorkbenchError.workSessionNotFound(workSession.id)
        }
        try await terminalRuntime.launch(launch)
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(
            where: {
                $0.id == workSession.id
                    && $0.workspaceID == workspace.id
                    && $0.archivedAt == nil
            }
        ) else {
            await terminalRuntime.stop(paneID: newPane.id)
            throw WorkbenchError.workSessionNotFound(workSession.id)
        }
        guard let layout = currentSnapshot.workSessions[sessionIndex]
            .layout.splitting(
                paneID: paneID,
                orientation: orientation,
                newPane: newPane
            )
        else {
            await terminalRuntime.stop(paneID: newPane.id)
            throw WorkbenchError.terminalPaneNotFound(paneID)
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions[sessionIndex].layout = layout
        do {
            try await persistSnapshot(rollingBackTo: previousSnapshot)
        } catch {
            await terminalRuntime.stop(paneID: newPane.id)
            throw error
        }
        guard currentSnapshot.workSessions.contains(where: {
            $0.id == workSession.id
                && $0.workspaceID == workspace.id
                && $0.archivedAt == nil
                && $0.layout.paneIDs.contains(newPane.id)
        }) else {
            await terminalRuntime.stop(paneID: newPane.id)
            throw WorkbenchError.workSessionNotFound(workSession.id)
        }
        return newPane.id
    }

    public func resizeSplit(
        containing paneID: TerminalPaneID,
        fraction: Double
    ) async throws {
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(where: {
            $0.layout.paneIDs.contains(paneID)
        }),
            let layout = currentSnapshot.workSessions[sessionIndex].layout.resizingSplit(
                containing: paneID,
                fraction: fraction
            )
        else {
            throw WorkbenchError.terminalPaneNotFound(paneID)
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions[sessionIndex].layout = layout
        try await persistSnapshot(rollingBackTo: previousSnapshot)
    }

    public func resizeSplit(
        in workSessionID: WorkSessionID,
        path: [SplitBranch],
        fraction: Double
    ) async throws {
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(where: {
            $0.id == workSessionID
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        guard let layout = currentSnapshot.workSessions[sessionIndex].layout.resizingSplit(
            at: path[...],
            fraction: fraction
        ) else {
            throw WorkbenchError.invalidSplitPath
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions[sessionIndex].layout = layout
        try await persistSnapshot(rollingBackTo: previousSnapshot)
    }

    public func closePane(_ paneID: TerminalPaneID) async throws {
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(where: {
            $0.layout.paneIDs.contains(paneID)
        }) else {
            throw WorkbenchError.terminalPaneNotFound(paneID)
        }
        guard currentSnapshot.workSessions[sessionIndex].layout.paneIDs.count > 1 else {
            throw WorkbenchError.cannotCloseLastPane
        }
        guard let layout = currentSnapshot.workSessions[sessionIndex].layout.removingPane(id: paneID) else {
            throw WorkbenchError.terminalPaneNotFound(paneID)
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions[sessionIndex].layout = layout
        try await persistSnapshot(rollingBackTo: previousSnapshot)
        recoveryFallbacks.removeValue(forKey: paneID)
        await terminalRuntime.stop(paneID: paneID)
    }

    public func archiveWorkSession(_ workSessionID: WorkSessionID) async throws {
        guard let index = currentSnapshot.workSessions.firstIndex(where: {
            $0.id == workSessionID && $0.archivedAt == nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        let paneIDs = currentSnapshot.workSessions[index].layout.paneIDs
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions[index].archivedAt = now()
        if currentSnapshot.selectedWorkSessionID == workSessionID {
            currentSnapshot.selectedWorkSessionID = nil
        }
        try await persistSnapshot(rollingBackTo: previousSnapshot)
        for paneID in paneIDs {
            recoveryFallbacks.removeValue(forKey: paneID)
            await terminalRuntime.stop(paneID: paneID)
        }
        materializedWorkSessionIDs.remove(workSessionID)
    }

    public func managedWorktreeMergeTargets(
        for workSessionID: WorkSessionID
    ) async throws -> [ManagedWorktreeStartBranch] {
        guard let workSession = currentSnapshot.workSessions.first(where: {
            $0.id == workSessionID && $0.archivedAt == nil
        }),
              let managedWorktree = workSession.managedWorktree
        else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        guard managedWorktree.workspaceID == workSession.workspaceID,
              managedWorktree.workSessionID == workSession.id
        else {
            throw WorkbenchError.managedWorktreeOwnershipMismatch(
                workSession.id
            )
        }
        guard let workspace = currentSnapshot.workspaces.first(where: {
            $0.id == workSession.workspaceID
        }) else {
            throw WorkbenchError.workspaceNotFound(workSession.workspaceID)
        }
        guard let managedWorktreeManager else {
            throw WorkbenchError.managedWorktreesUnavailable
        }
        return try await managedWorktreeManager.startBranches(for: workspace)
            .filter {
                $0.kind == .localBranch
                    && $0.name != managedWorktree.branchName
            }
    }

    public func mergeManagedWorktreeSession(
        _ workSessionID: WorkSessionID,
        into targetBranch: ManagedWorktreeStartBranch
    ) async throws {
        try await withManagedWorktreeLifecycleGate {
            guard let workSession = currentSnapshot.workSessions.first(where: {
                $0.id == workSessionID && $0.archivedAt == nil
            }),
                  let managedWorktree = workSession.managedWorktree
            else {
                throw WorkbenchError.workSessionNotFound(workSessionID)
            }
            guard managedWorktree.workspaceID == workSession.workspaceID,
                  managedWorktree.workSessionID == workSession.id
            else {
                throw WorkbenchError.managedWorktreeOwnershipMismatch(
                    workSession.id
                )
            }
            guard managedWorktree.state == .available else {
                throw WorkbenchError.managedWorktreeUnavailable(
                    workSession.id
                )
            }
            guard let managedWorktreeManager else {
                throw WorkbenchError.managedWorktreesUnavailable
            }
            try await managedWorktreeManager.merge(
                managedWorktree,
                into: targetBranch
            )
        }
    }

    public func deleteManagedWorktreeSession(
        _ workSessionID: WorkSessionID,
        selecting fallbackID: WorkSessionID? = nil
    ) async throws {
        guard !isPreparingForCleanExit else {
            throw WorkbenchError.preparingForCleanExit
        }
        await managedWorktreeLifecycleGate.acquire()
        guard !isPreparingForCleanExit else {
            await managedWorktreeLifecycleGate.release()
            throw WorkbenchError.preparingForCleanExit
        }
        do {
            try await deleteManagedWorktreeSessionWithoutAcquiringGate(
                workSessionID,
                selecting: fallbackID
            )
            await managedWorktreeLifecycleGate.release()
        } catch {
            await managedWorktreeLifecycleGate.release()
            throw error
        }
    }

    private func deleteManagedWorktreeSessionWithoutAcquiringGate(
        _ workSessionID: WorkSessionID,
        selecting fallbackID: WorkSessionID?
    ) async throws {
        guard let workSession = currentSnapshot.workSessions.first(where: {
            $0.id == workSessionID && $0.archivedAt == nil
        }),
              let managedWorktree = workSession.managedWorktree
        else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        guard managedWorktree.workspaceID == workSession.workspaceID,
              managedWorktree.workSessionID == workSession.id
        else {
            throw WorkbenchError.managedWorktreeOwnershipMismatch(
                workSession.id
            )
        }
        guard let managedWorktreeManager else {
            throw WorkbenchError.managedWorktreesUnavailable
        }

        try await managedWorktreeManager.validateRemoval(managedWorktree)
        for paneID in workSession.layout.paneIDs {
            recoveryFallbacks.removeValue(forKey: paneID)
            await terminalRuntime.stop(paneID: paneID)
        }
        materializedWorkSessionIDs.remove(workSessionID)
        try await managedWorktreeManager.remove(managedWorktree)

        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions.removeAll { $0.id == workSessionID }
        if currentSnapshot.selectedWorkSessionID == workSessionID {
            currentSnapshot.selectedWorkSessionID = fallbackID.flatMap {
                candidateID in
                currentSnapshot.activeWorkSessions.contains(where: {
                    $0.id == candidateID
                }) ? candidateID : nil
            }
        }
        do {
            try await persistSnapshot(rollingBackTo: previousSnapshot)
        } catch {
            markManagedWorktreesUnavailable(
                workSessionIDs: [workSessionID]
            )
            try? await repository.save(currentSnapshot)
            throw error
        }
    }

    public func restoreArchivedWorkSession(_ workSessionID: WorkSessionID) async throws {
        guard let index = currentSnapshot.workSessions.firstIndex(where: {
            $0.id == workSessionID && $0.archivedAt != nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions[index].archivedAt = nil
        try await persistSnapshot(rollingBackTo: previousSnapshot)
    }

    public func deleteArchivedWorkSession(_ workSessionID: WorkSessionID) async throws {
        guard !isPreparingForCleanExit else {
            throw WorkbenchError.preparingForCleanExit
        }
        await managedWorktreeLifecycleGate.acquire()
        guard !isPreparingForCleanExit else {
            await managedWorktreeLifecycleGate.release()
            throw WorkbenchError.preparingForCleanExit
        }
        do {
            try await deleteArchivedWorkSessionWithoutAcquiringGate(
                workSessionID
            )
            await managedWorktreeLifecycleGate.release()
        } catch {
            await managedWorktreeLifecycleGate.release()
            throw error
        }
    }

    private func deleteArchivedWorkSessionWithoutAcquiringGate(
        _ workSessionID: WorkSessionID
    ) async throws {
        guard let workSession = currentSnapshot.workSessions.first(where: {
            $0.id == workSessionID && $0.archivedAt != nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        if let managedWorktree = workSession.managedWorktree {
            guard managedWorktree.workspaceID == workSession.workspaceID,
                  managedWorktree.workSessionID == workSession.id
            else {
                throw WorkbenchError.managedWorktreeOwnershipMismatch(
                    workSession.id
                )
            }
            guard let managedWorktreeManager else {
                throw WorkbenchError.managedWorktreesUnavailable
            }
            try await managedWorktreeManager.remove(managedWorktree)
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions.removeAll { $0.id == workSessionID }
        do {
            try await persistSnapshot(rollingBackTo: previousSnapshot)
        } catch {
            if workSession.managedWorktree != nil {
                markManagedWorktreesUnavailable(
                    workSessionIDs: [workSessionID]
                )
                try? await repository.save(currentSnapshot)
            }
            throw error
        }
        materializedWorkSessionIDs.remove(workSessionID)
    }

    public func removeWorkspace(_ workspaceID: WorkspaceID) async throws {
        guard !isPreparingForCleanExit else {
            throw WorkbenchError.preparingForCleanExit
        }
        await managedWorktreeLifecycleGate.acquire()
        guard !isPreparingForCleanExit else {
            await managedWorktreeLifecycleGate.release()
            throw WorkbenchError.preparingForCleanExit
        }
        do {
            try await removeWorkspaceWithoutAcquiringGate(workspaceID)
            await managedWorktreeLifecycleGate.release()
        } catch {
            await managedWorktreeLifecycleGate.release()
            throw error
        }
    }

    private func removeWorkspaceWithoutAcquiringGate(
        _ workspaceID: WorkspaceID
    ) async throws {
        guard currentSnapshot.workspaces.contains(where: { $0.id == workspaceID }) else {
            throw WorkbenchError.workspaceNotFound(workspaceID)
        }

        let removedSessions = currentSnapshot.workSessions.filter {
            $0.workspaceID == workspaceID
        }
        let managedSessions = removedSessions.compactMap {
            session -> (WorkSession, ManagedWorktree)? in
            guard let managedWorktree = session.managedWorktree else {
                return nil
            }
            return (session, managedWorktree)
        }
        for (session, managedWorktree) in managedSessions {
            guard managedWorktree.workspaceID == session.workspaceID,
                  managedWorktree.workSessionID == session.id
            else {
                throw WorkbenchError.managedWorktreeOwnershipMismatch(
                    session.id
                )
            }
        }
        if !managedSessions.isEmpty {
            guard let managedWorktreeManager else {
                throw WorkbenchError.managedWorktreesUnavailable
            }
            for (_, managedWorktree) in managedSessions {
                try await managedWorktreeManager.validateRemoval(
                    managedWorktree
                )
            }
            for workSession in removedSessions {
                for paneID in workSession.layout.paneIDs {
                    recoveryFallbacks.removeValue(forKey: paneID)
                    await terminalRuntime.stop(paneID: paneID)
                }
                materializedWorkSessionIDs.remove(workSession.id)
            }
            var removedWorktreeSessionIDs: Set<WorkSessionID> = []
            do {
                for (session, managedWorktree) in managedSessions {
                    try await managedWorktreeManager.remove(managedWorktree)
                    removedWorktreeSessionIDs.insert(session.id)
                }
            } catch {
                markManagedWorktreesUnavailable(
                    workSessionIDs: removedWorktreeSessionIDs
                )
                try? await repository.save(currentSnapshot)
                throw error
            }
        }

        let previousSnapshot = currentSnapshot
        currentSnapshot.workspaces.removeAll { $0.id == workspaceID }
        currentSnapshot.workSessions.removeAll { $0.workspaceID == workspaceID }
        if let selectedID = currentSnapshot.selectedWorkSessionID,
           removedSessions.contains(where: { $0.id == selectedID })
        {
            currentSnapshot.selectedWorkSessionID = nil
        }
        do {
            try await persistSnapshot(rollingBackTo: previousSnapshot)
        } catch {
            if !managedSessions.isEmpty {
                markManagedWorktreesUnavailable(
                    workSessionIDs: Set(managedSessions.map(\.0.id))
                )
                try? await repository.save(currentSnapshot)
            }
            throw error
        }

        if managedSessions.isEmpty {
            for workSession in removedSessions {
                materializedWorkSessionIDs.remove(workSession.id)
                for paneID in workSession.layout.paneIDs {
                    recoveryFallbacks.removeValue(forKey: paneID)
                    await terminalRuntime.stop(paneID: paneID)
                }
            }
        }
    }

    public func handleAgentEvent(_ event: AgentEvent) async throws {
        guard event.applicationInstanceID == applicationInstanceID else {
            throw WorkbenchError.agentEventTargetMismatch
        }
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(where: {
            $0.id == event.workSessionID && $0.workspaceID == event.workspaceID
        }) else {
            throw WorkbenchError.agentEventTargetMismatch
        }

        let currentLayout = currentSnapshot.workSessions[sessionIndex].layout
        guard let currentPane = currentLayout.panes.first(where: { $0.id == event.paneID }) else {
            throw WorkbenchError.agentEventTargetMismatch
        }
        if let lastEventAt = currentPane.agentBinding?.lastEventAt,
           event.occurredAt < lastEventAt
        {
            return
        }
        if event.lifecycle != .turnStarted {
            guard let current = currentPane.agentBinding,
                  current.agent == event.agent,
                  current.sessionID == nil
                    || event.sessionID == nil
                    || current.sessionID == event.sessionID
            else {
                return
            }
        }

        let previousSnapshot = currentSnapshot
        guard let updatedLayout = currentLayout.updatingPane(id: event.paneID, transform: { pane in
            var binding: AgentBinding
            if let current = pane.agentBinding, current.agent == event.agent {
                binding = current
            } else {
                binding = AgentBinding(agent: event.agent)
            }
            if let version = event.version {
                binding.version = version
            }
            if let sessionID = event.sessionID {
                binding.sessionID = sessionID
            }
            if let nativeTitle = event.nativeTitle, !nativeTitle.isEmpty {
                binding.nativeTitle = nativeTitle
            }
            binding.lastEventAt = event.occurredAt
            pane.agentBinding = binding
            switch event.lifecycle {
            case .turnStarted:
                pane.state = .running
                pane.agentBinding?.isActive = true
            case .needsAttention:
                pane.state = .needsAttention
                pane.agentBinding?.isActive = true
            case .attentionResolved:
                if pane.state == .needsAttention {
                    pane.state = .running
                    pane.agentBinding?.isActive = true
                }
            case .turnCompleted:
                pane.state = .turnCompleted
                pane.agentBinding?.isActive = true
            case .sessionEnded:
                pane.state = .idle
                pane.agentBinding?.isActive = false
            case .metadataUpdated:
                break
            }
        }) else {
            throw WorkbenchError.agentEventTargetMismatch
        }

        currentSnapshot.workSessions[sessionIndex].layout = updatedLayout
        if currentSnapshot.workSessions[sessionIndex].titleSource == nil,
           let nativeTitle = event.nativeTitle,
           !nativeTitle.isEmpty
        {
            currentSnapshot.workSessions[sessionIndex].title = nativeTitle
            currentSnapshot.workSessions[sessionIndex].titleSource = .agentNative
        }
        try await persistSnapshot(rollingBackTo: previousSnapshot)
    }

    private func placeholderTitle(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "新会话 · \(formatter.string(from: date))"
    }

    private func workingDirectory(
        for workSession: WorkSession,
        workspace: Workspace
    ) async throws -> String {
        guard let managedWorktree = workSession.managedWorktree else {
            guard workspaceAvailable(workspace.path) else {
                throw WorkbenchError.workspaceUnavailable(workspace.id)
            }
            return workspace.path
        }
        guard managedWorktree.workspaceID == workSession.workspaceID,
              managedWorktree.workSessionID == workSession.id
        else {
            throw WorkbenchError.managedWorktreeOwnershipMismatch(
                workSession.id
            )
        }
        guard managedWorktree.state == .available else {
            throw WorkbenchError.managedWorktreeUnavailable(workSession.id)
        }
        guard let managedWorktreeManager,
              await managedWorktreeManager.isAvailable(managedWorktree)
        else {
            await markManagedWorktreeUnavailable(
                workSessionID: workSession.id
            )
            throw WorkbenchError.managedWorktreeUnavailable(workSession.id)
        }
        return managedWorktree.workingDirectory
    }

    private func terminalEnvironment(
        workspaceID: WorkspaceID,
        workSessionID: WorkSessionID,
        paneID: TerminalPaneID
    ) -> [String: String] {
        [
            "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
            "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
            "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
            "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
        ]
    }

    private func materializeWorkSessionWithoutAcquiringGate(
        _ workSessionID: WorkSessionID
    ) async throws {
        await ensureProcessExitMonitoring()
        await ensureInputSubmissionMonitoring()
        guard let initialWorkSession = currentSnapshot.workSessions.first(
            where: {
                $0.id == workSessionID && $0.archivedAt == nil
            }
        ) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        guard let initialWorkspace = currentSnapshot.workspaces.first(where: {
            $0.id == initialWorkSession.workspaceID
        }) else {
            throw WorkbenchError.workspaceNotFound(
                initialWorkSession.workspaceID
            )
        }
        let sessionWorkingDirectory = try await workingDirectory(
            for: initialWorkSession,
            workspace: initialWorkspace
        )

        guard let workSession = currentSnapshot.workSessions.first(where: {
            $0.id == workSessionID
                && $0.workspaceID == initialWorkspace.id
                && $0.archivedAt == nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        guard let workspace = currentSnapshot.workspaces.first(where: {
            $0.id == initialWorkspace.id
        }) else {
            throw WorkbenchError.workspaceNotFound(initialWorkspace.id)
        }

        let previousSnapshot = currentSnapshot
        var snapshotChanged = false
        var latestOwnedSnapshot = currentSnapshot
        var launchedPaneIDs: [TerminalPaneID] = []
        do {
            for pane in workSession.layout.panes {
                let command: AgentResumeCommand? = pane.agentBinding.flatMap {
                    guard $0.isActive == true else { return nil }
                    return agentResumeCommands?.resumeCommand(for: $0)
                }
                let environment = [
                    "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
                    "BREATH_WORKSPACE_ID": workspace.id.rawValue.uuidString,
                    "BREATH_WORK_SESSION_ID": workSession.id.rawValue.uuidString,
                    "BREATH_TERMINAL_PANE_ID": pane.id.rawValue.uuidString,
                ]
                let shellLaunch = TerminalLaunch(
                    paneID: pane.id,
                    workingDirectory: sessionWorkingDirectory,
                    executable: defaultShell(),
                    arguments: ["-l"],
                    environment: environment
                )

                if let command {
                    let fallback = RecoveryFallback(
                        token: UUID(),
                        workSessionID: workSessionID,
                        shellLaunch: shellLaunch
                    )
                    recoveryFallbacks[pane.id] = fallback
                    do {
                        try await launchTerminalVerifyingOwnership(
                            TerminalLaunch(
                                paneID: pane.id,
                                workingDirectory: sessionWorkingDirectory,
                                executable: command.executable,
                                arguments: command.arguments,
                                environment: environment
                            ),
                            workSessionID: workSessionID,
                            workspaceID: workspace.id
                        )
                        launchedPaneIDs.append(pane.id)
                    } catch {
                        removeRecoveryFallback(pane.id, token: fallback.token)
                        guard ownsTerminalPane(
                            pane.id,
                            workSessionID: workSessionID,
                            workspaceID: workspace.id
                        ) else {
                            throw WorkbenchError.workSessionNotFound(
                                workSessionID
                            )
                        }
                        await terminalRuntime.stop(paneID: pane.id)
                        try await launchTerminalVerifyingOwnership(
                            shellLaunch,
                            workSessionID: workSessionID,
                            workspaceID: workspace.id
                        )
                        launchedPaneIDs.append(pane.id)
                        snapshotChanged = markPaneIdle(
                            pane.id,
                            in: workSessionID
                        ) || snapshotChanged
                        latestOwnedSnapshot = currentSnapshot
                    }
                } else {
                    try await launchTerminalVerifyingOwnership(
                        shellLaunch,
                        workSessionID: workSessionID,
                        workspaceID: workspace.id
                    )
                    launchedPaneIDs.append(pane.id)
                    if pane.agentBinding != nil || pane.state != .idle {
                        snapshotChanged = markPaneIdle(
                            pane.id,
                            in: workSessionID
                        ) || snapshotChanged
                        latestOwnedSnapshot = currentSnapshot
                    }
                }
            }
            if snapshotChanged {
                try await persistSnapshot(rollingBackTo: previousSnapshot)
            }
            guard currentSnapshot.workSessions.contains(where: {
                $0.id == workSessionID
                    && $0.workspaceID == workspace.id
                    && $0.archivedAt == nil
            }), currentSnapshot.workspaces.contains(where: {
                $0.id == workspace.id
            }) else {
                throw WorkbenchError.workSessionNotFound(workSessionID)
            }
            materializedWorkSessionIDs.insert(workSessionID)
        } catch {
            for paneID in workSession.layout.paneIDs {
                recoveryFallbacks.removeValue(forKey: paneID)
            }
            for paneID in Set(launchedPaneIDs) {
                await terminalRuntime.stop(paneID: paneID)
            }
            if currentSnapshot == latestOwnedSnapshot,
               currentSnapshot != previousSnapshot
            {
                currentSnapshot = previousSnapshot
            }
            throw error
        }
    }

    private func launchTerminalVerifyingOwnership(
        _ launch: TerminalLaunch,
        workSessionID: WorkSessionID,
        workspaceID: WorkspaceID
    ) async throws {
        try await terminalRuntime.launch(launch)
        guard ownsTerminalPane(
            launch.paneID,
            workSessionID: workSessionID,
            workspaceID: workspaceID
        ) else {
            await terminalRuntime.stop(paneID: launch.paneID)
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
    }

    private func ownsTerminalPane(
        _ paneID: TerminalPaneID,
        workSessionID: WorkSessionID,
        workspaceID: WorkspaceID
    ) -> Bool {
        currentSnapshot.workspaces.contains(where: {
            $0.id == workspaceID
        }) && currentSnapshot.workSessions.contains(where: {
            $0.id == workSessionID
                && $0.workspaceID == workspaceID
                && $0.archivedAt == nil
                && $0.layout.paneIDs.contains(paneID)
        })
    }

    private func withManagedWorktreeLifecycleGate<Result>(
        _ operation: () async throws -> Result
    ) async rethrows -> Result {
        await managedWorktreeLifecycleGate.acquire()
        do {
            let result = try await operation()
            await managedWorktreeLifecycleGate.release()
            return result
        } catch {
            await managedWorktreeLifecycleGate.release()
            throw error
        }
    }

    private func persistSnapshot(
        rollingBackTo previousSnapshot: WorkbenchSnapshot
    ) async throws {
        let attemptedSnapshot = currentSnapshot
        do {
            try await repository.save(attemptedSnapshot)
            await snapshotChangeHandler?()
        } catch {
            if currentSnapshot == attemptedSnapshot {
                currentSnapshot = previousSnapshot
            }
            throw error
        }
    }

    private func markPaneIdle(
        _ paneID: TerminalPaneID,
        in workSessionID: WorkSessionID
    ) -> Bool {
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(where: {
            $0.id == workSessionID
        }),
            let layout = currentSnapshot.workSessions[sessionIndex].layout.updatingPane(
                id: paneID,
                transform: {
                    $0.state = .idle
                    $0.agentBinding?.isActive = false
                }
            )
        else {
            return false
        }
        currentSnapshot.workSessions[sessionIndex].layout = layout
        return true
    }

    private func markManagedWorktreesUnavailable(
        workSessionIDs: Set<WorkSessionID>
    ) {
        for index in currentSnapshot.workSessions.indices
            where workSessionIDs.contains(currentSnapshot.workSessions[index].id)
        {
            currentSnapshot.workSessions[index].managedWorktree?.state =
                .unavailable
        }
    }

    private func markManagedWorktreeUnavailable(
        workSessionID: WorkSessionID
    ) async {
        guard let index = currentSnapshot.workSessions.firstIndex(where: {
            $0.id == workSessionID
        }),
            currentSnapshot.workSessions[index].managedWorktree?.state
                != .unavailable
        else {
            return
        }
        currentSnapshot.workSessions[index].managedWorktree?.state =
            .unavailable
        try? await repository.save(currentSnapshot)
        await snapshotChangeHandler?()
    }

    private func canonicalWorkspaceURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func workspaceComparisonKey(_ url: URL) -> String {
        let canonical = canonicalWorkspaceURL(url)
        let isCaseSensitive = (try? canonical.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames) ?? true
        return isCaseSensitive ? canonical.path : canonical.path.lowercased()
    }

    private func ensureProcessExitMonitoring() async {
        guard !monitorsProcessExits else { return }
        monitorsProcessExits = true
        await terminalRuntime.setProcessExitHandler { [weak self] paneID in
            Task { await self?.handleTerminalProcessExit(paneID) }
        }
    }

    private func ensureInputSubmissionMonitoring() async {
        guard !monitorsInputSubmissions else { return }
        monitorsInputSubmissions = true
        await terminalRuntime.setInputSubmittedHandler { [weak self] paneID in
            await self?.handleTerminalInputSubmitted(paneID)
        }
    }

    private func handleTerminalInputSubmitted(_ paneID: TerminalPaneID) async {
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(where: {
            $0.layout.paneIDs.contains(paneID)
        }) else {
            return
        }
        let layout = currentSnapshot.workSessions[sessionIndex].layout
        guard let pane = layout.panes.first(where: { $0.id == paneID }),
              pane.state == .needsAttention,
              let updatedLayout = layout.updatingPane(id: paneID, transform: {
                  $0.state = .running
              })
        else {
            return
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions[sessionIndex].layout = updatedLayout
        try? await persistSnapshot(rollingBackTo: previousSnapshot)
    }

    private func handleTerminalProcessExit(_ paneID: TerminalPaneID) async {
        guard let fallback = recoveryFallbacks[paneID],
              isActivePane(paneID, in: fallback.workSessionID)
        else { return }
        await terminalRuntime.stop(paneID: paneID)
        guard recoveryFallbacks[paneID]?.token == fallback.token,
              isActivePane(paneID, in: fallback.workSessionID)
        else { return }
        do {
            try await terminalRuntime.launch(fallback.shellLaunch)
            guard recoveryFallbacks[paneID]?.token == fallback.token,
                  isActivePane(paneID, in: fallback.workSessionID)
            else {
                await terminalRuntime.stop(paneID: paneID)
                return
            }
            let previousSnapshot = currentSnapshot
            guard markPaneIdle(paneID, in: fallback.workSessionID) else {
                await terminalRuntime.stop(paneID: paneID)
                return
            }
            try await persistSnapshot(rollingBackTo: previousSnapshot)
            removeRecoveryFallback(paneID, token: fallback.token)
        } catch {
            await terminalRuntime.stop(paneID: paneID)
            removeRecoveryFallback(paneID, token: fallback.token)
            materializedWorkSessionIDs.remove(fallback.workSessionID)
            await snapshotChangeHandler?()
        }
    }

    private func removeRecoveryFallback(_ paneID: TerminalPaneID, token: UUID) {
        guard recoveryFallbacks[paneID]?.token == token else { return }
        recoveryFallbacks.removeValue(forKey: paneID)
    }

    private func isActivePane(
        _ paneID: TerminalPaneID,
        in workSessionID: WorkSessionID
    ) -> Bool {
        currentSnapshot.workSessions.contains {
            $0.id == workSessionID
                && $0.archivedAt == nil
                && $0.layout.paneIDs.contains(paneID)
        }
    }
}
