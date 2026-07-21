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
        titleSource: WorkSessionTitleSource? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.layout = .pane(pane)
        self.archivedAt = archivedAt
        self.titleSource = titleSource
    }

    public init(
        id: WorkSessionID,
        workspaceID: WorkspaceID,
        title: String,
        layout: PaneLayout,
        archivedAt: Date? = nil,
        titleSource: WorkSessionTitleSource? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.layout = layout
        self.archivedAt = archivedAt
        self.titleSource = titleSource
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
}

public extension TerminalRuntime {
    func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
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
}

public actor Workbench {
    private struct RecoveryFallback: Sendable {
        let token: UUID
        let workSessionID: WorkSessionID
        let shellLaunch: TerminalLaunch
    }

    private let repository: any WorkbenchRepository
    private let terminalRuntime: any TerminalRuntime
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
    private var snapshotChangeHandler: (@Sendable () async -> Void)?

    public init(
        repository: any WorkbenchRepository,
        terminalRuntime: any TerminalRuntime,
        agentResumeCommands: (any AgentResumeCommandProviding)? = nil,
        applicationInstanceID: ApplicationInstanceID = ApplicationInstanceID(rawValue: UUID()),
        defaultShell: @escaping @Sendable () -> String,
        workspaceAvailable: @escaping @Sendable (String) -> Bool = { _ in true },
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.repository = repository
        self.terminalRuntime = terminalRuntime
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

    public func snapshot() -> WorkbenchSnapshot {
        currentSnapshot
    }

    public func setSnapshotChangeHandler(
        _ handler: @escaping @Sendable () async -> Void
    ) {
        snapshotChangeHandler = handler
    }

    public func selectWorkSession(_ workSessionID: WorkSessionID) async throws {
        let previousSelection = currentSnapshot.selectedWorkSessionID
        guard currentSnapshot.workSessions.contains(where: {
            $0.id == workSessionID && $0.archivedAt == nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        if !materializedWorkSessionIDs.contains(workSessionID) {
            try await materializeWorkSession(workSessionID)
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

        guard let selectedID = currentSnapshot.selectedWorkSessionID,
              let selectedSession = currentSnapshot.workSessions.first(where: {
                  $0.id == selectedID && $0.archivedAt == nil
              }),
              let selectedWorkspace = currentSnapshot.workspaces.first(where: {
                  $0.id == selectedSession.workspaceID
              }),
              workspaceAvailable(selectedWorkspace.path)
        else {
            currentSnapshot.selectedWorkSessionID = nil
            return
        }
    }

    public func materializeSelectedWorkSession() async throws {
        guard let selectedID = currentSnapshot.selectedWorkSessionID,
              !materializedWorkSessionIDs.contains(selectedID)
        else {
            return
        }
        try await materializeWorkSession(selectedID)
    }

    public func prepareForCleanExit() async throws {
        try await repository.save(currentSnapshot)
        recoveryFallbacks.removeAll()
        for workSession in currentSnapshot.workSessions {
            for paneID in workSession.layout.paneIDs {
                await terminalRuntime.stop(paneID: paneID)
            }
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
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(where: {
            $0.layout.paneIDs.contains(paneID)
        }) else {
            throw WorkbenchError.terminalPaneNotFound(paneID)
        }
        let workSession = currentSnapshot.workSessions[sessionIndex]
        guard let workspace = currentSnapshot.workspaces.first(where: {
            $0.id == workSession.workspaceID
        }) else {
            throw WorkbenchError.workspaceNotFound(workSession.workspaceID)
        }
        guard workspaceAvailable(workspace.path) else {
            throw WorkbenchError.workspaceUnavailable(workspace.id)
        }

        let newPane = TerminalPane(id: TerminalPaneID(rawValue: UUID()))
        guard let layout = workSession.layout.splitting(
            paneID: paneID,
            orientation: orientation,
            newPane: newPane
        ) else {
            throw WorkbenchError.terminalPaneNotFound(paneID)
        }
        let launch = TerminalLaunch(
            paneID: newPane.id,
            workingDirectory: workspace.path,
            executable: defaultShell(),
            arguments: ["-l"],
            environment: [
                "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
                "BREATH_WORKSPACE_ID": workspace.id.rawValue.uuidString,
                "BREATH_WORK_SESSION_ID": workSession.id.rawValue.uuidString,
                "BREATH_TERMINAL_PANE_ID": newPane.id.rawValue.uuidString,
            ]
        )

        let previousSnapshot = currentSnapshot
        try await terminalRuntime.launch(launch)
        currentSnapshot.workSessions[sessionIndex].layout = layout
        do {
            try await persistSnapshot(rollingBackTo: previousSnapshot)
        } catch {
            await terminalRuntime.stop(paneID: newPane.id)
            throw error
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
        guard currentSnapshot.workSessions.contains(where: {
            $0.id == workSessionID && $0.archivedAt != nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workSessions.removeAll { $0.id == workSessionID }
        try await persistSnapshot(rollingBackTo: previousSnapshot)
        materializedWorkSessionIDs.remove(workSessionID)
    }

    public func removeWorkspace(_ workspaceID: WorkspaceID) async throws {
        guard currentSnapshot.workspaces.contains(where: { $0.id == workspaceID }) else {
            throw WorkbenchError.workspaceNotFound(workspaceID)
        }

        let removedSessions = currentSnapshot.workSessions.filter {
            $0.workspaceID == workspaceID
        }
        let previousSnapshot = currentSnapshot
        currentSnapshot.workspaces.removeAll { $0.id == workspaceID }
        currentSnapshot.workSessions.removeAll { $0.workspaceID == workspaceID }
        if let selectedID = currentSnapshot.selectedWorkSessionID,
           removedSessions.contains(where: { $0.id == selectedID })
        {
            currentSnapshot.selectedWorkSessionID = nil
        }
        try await persistSnapshot(rollingBackTo: previousSnapshot)

        for workSession in removedSessions {
            materializedWorkSessionIDs.remove(workSession.id)
            for paneID in workSession.layout.paneIDs {
                recoveryFallbacks.removeValue(forKey: paneID)
                await terminalRuntime.stop(paneID: paneID)
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

    private func materializeWorkSession(_ workSessionID: WorkSessionID) async throws {
        await ensureProcessExitMonitoring()
        guard let workSession = currentSnapshot.workSessions.first(where: {
            $0.id == workSessionID
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        guard let workspace = currentSnapshot.workspaces.first(where: {
            $0.id == workSession.workspaceID
        }) else {
            throw WorkbenchError.workspaceNotFound(workSession.workspaceID)
        }
        guard workspaceAvailable(workspace.path) else {
            throw WorkbenchError.workspaceUnavailable(workspace.id)
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
                    workingDirectory: workspace.path,
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
                        try await terminalRuntime.launch(
                            TerminalLaunch(
                                paneID: pane.id,
                                workingDirectory: workspace.path,
                                executable: command.executable,
                                arguments: command.arguments,
                                environment: environment
                            )
                        )
                        launchedPaneIDs.append(pane.id)
                    } catch {
                        removeRecoveryFallback(pane.id, token: fallback.token)
                        await terminalRuntime.stop(paneID: pane.id)
                        try await terminalRuntime.launch(shellLaunch)
                        launchedPaneIDs.append(pane.id)
                        snapshotChanged = markPaneIdle(
                            pane.id,
                            in: workSessionID
                        ) || snapshotChanged
                        latestOwnedSnapshot = currentSnapshot
                    }
                } else {
                    try await terminalRuntime.launch(shellLaunch)
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
