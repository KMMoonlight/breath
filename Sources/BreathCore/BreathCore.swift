import Foundation

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

public enum AgentKind: String, Equatable, Hashable, Codable, Sendable {
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
}

public struct AgentBinding: Equatable, Codable, Sendable {
    public let agent: AgentKind
    public var version: String?
    public var sessionID: String?
    public var nativeTitle: String?

    public init(
        agent: AgentKind,
        version: String? = nil,
        sessionID: String? = nil,
        nativeTitle: String? = nil
    ) {
        self.agent = agent
        self.version = version
        self.sessionID = sessionID
        self.nativeTitle = nativeTitle
    }
}

public struct AgentEvent: Equatable, Codable, Sendable {
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
    private let repository: any WorkbenchRepository
    private let terminalRuntime: any TerminalRuntime
    private let agentResumeCommands: (any AgentResumeCommandProviding)?
    private let defaultShell: @Sendable () -> String
    private let workspaceAvailable: @Sendable (String) -> Bool
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private var currentSnapshot: WorkbenchSnapshot
    private var materializedWorkSessionIDs: Set<WorkSessionID>

    public init(
        repository: any WorkbenchRepository,
        terminalRuntime: any TerminalRuntime,
        agentResumeCommands: (any AgentResumeCommandProviding)? = nil,
        defaultShell: @escaping @Sendable () -> String,
        workspaceAvailable: @escaping @Sendable (String) -> Bool = { _ in true },
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.repository = repository
        self.terminalRuntime = terminalRuntime
        self.agentResumeCommands = agentResumeCommands
        self.defaultShell = defaultShell
        self.workspaceAvailable = workspaceAvailable
        self.now = now
        self.timeZone = timeZone
        currentSnapshot = .empty
        materializedWorkSessionIDs = []
    }

    @discardableResult
    public func addWorkspace(at url: URL) async throws -> WorkspaceID {
        let normalizedURL = url.standardizedFileURL
        guard !currentSnapshot.workspaces.contains(where: { $0.path == normalizedURL.path }) else {
            throw WorkbenchError.workspaceAlreadyExists(normalizedURL.path)
        }
        let workspace = Workspace(
            id: WorkspaceID(rawValue: UUID()),
            path: normalizedURL.path,
            displayName: normalizedURL.lastPathComponent
        )
        currentSnapshot.workspaces.append(workspace)
        try await repository.save(currentSnapshot)
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
                "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
                "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
                "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
            ]
        )

        try await terminalRuntime.launch(launch)
        currentSnapshot.workSessions.append(workSession)
        currentSnapshot.selectedWorkSessionID = workSessionID
        materializedWorkSessionIDs.insert(workSessionID)
        try await repository.save(currentSnapshot)
        return workSessionID
    }

    public func snapshot() -> WorkbenchSnapshot {
        currentSnapshot
    }

    public func selectWorkSession(_ workSessionID: WorkSessionID) async throws {
        guard currentSnapshot.workSessions.contains(where: {
            $0.id == workSessionID && $0.archivedAt == nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        if !materializedWorkSessionIDs.contains(workSessionID) {
            try await materializeWorkSession(workSessionID)
        }
        currentSnapshot.selectedWorkSessionID = workSessionID
        try await repository.save(currentSnapshot)
    }

    public func restoreFromRepository() async throws {
        currentSnapshot = try await repository.load()
        materializedWorkSessionIDs.removeAll()

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
        try await materializeWorkSession(selectedID)
    }

    public func prepareForCleanExit() async throws {
        try await repository.save(currentSnapshot)
        for workSession in currentSnapshot.workSessions {
            for paneID in workSession.layout.paneIDs {
                await terminalRuntime.stop(paneID: paneID)
            }
        }
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
                "BREATH_WORKSPACE_ID": workspace.id.rawValue.uuidString,
                "BREATH_WORK_SESSION_ID": workSession.id.rawValue.uuidString,
                "BREATH_TERMINAL_PANE_ID": newPane.id.rawValue.uuidString,
            ]
        )

        try await terminalRuntime.launch(launch)
        currentSnapshot.workSessions[sessionIndex].layout = layout
        try await repository.save(currentSnapshot)
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
        currentSnapshot.workSessions[sessionIndex].layout = layout
        try await repository.save(currentSnapshot)
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
        currentSnapshot.workSessions[sessionIndex].layout = layout
        try await repository.save(currentSnapshot)
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
        currentSnapshot.workSessions[sessionIndex].layout = layout
        try await repository.save(currentSnapshot)
        await terminalRuntime.stop(paneID: paneID)
    }

    public func archiveWorkSession(_ workSessionID: WorkSessionID) async throws {
        guard let index = currentSnapshot.workSessions.firstIndex(where: {
            $0.id == workSessionID && $0.archivedAt == nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        let paneIDs = currentSnapshot.workSessions[index].layout.paneIDs
        currentSnapshot.workSessions[index].archivedAt = now()
        if currentSnapshot.selectedWorkSessionID == workSessionID {
            currentSnapshot.selectedWorkSessionID = nil
        }
        try await repository.save(currentSnapshot)
        for paneID in paneIDs {
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
        currentSnapshot.workSessions[index].archivedAt = nil
        try await repository.save(currentSnapshot)
    }

    public func deleteArchivedWorkSession(_ workSessionID: WorkSessionID) async throws {
        guard currentSnapshot.workSessions.contains(where: {
            $0.id == workSessionID && $0.archivedAt != nil
        }) else {
            throw WorkbenchError.workSessionNotFound(workSessionID)
        }
        currentSnapshot.workSessions.removeAll { $0.id == workSessionID }
        materializedWorkSessionIDs.remove(workSessionID)
        try await repository.save(currentSnapshot)
    }

    public func removeWorkspace(_ workspaceID: WorkspaceID) async throws {
        guard currentSnapshot.workspaces.contains(where: { $0.id == workspaceID }) else {
            throw WorkbenchError.workspaceNotFound(workspaceID)
        }

        let removedSessions = currentSnapshot.workSessions.filter {
            $0.workspaceID == workspaceID
        }
        currentSnapshot.workspaces.removeAll { $0.id == workspaceID }
        currentSnapshot.workSessions.removeAll { $0.workspaceID == workspaceID }
        if let selectedID = currentSnapshot.selectedWorkSessionID,
           removedSessions.contains(where: { $0.id == selectedID })
        {
            currentSnapshot.selectedWorkSessionID = nil
        }
        try await repository.save(currentSnapshot)

        for workSession in removedSessions {
            materializedWorkSessionIDs.remove(workSession.id)
            for paneID in workSession.layout.paneIDs {
                await terminalRuntime.stop(paneID: paneID)
            }
        }
    }

    public func handleAgentEvent(_ event: AgentEvent) async throws {
        guard let sessionIndex = currentSnapshot.workSessions.firstIndex(where: {
            $0.id == event.workSessionID && $0.workspaceID == event.workspaceID
        }) else {
            throw WorkbenchError.agentEventTargetMismatch
        }

        let currentLayout = currentSnapshot.workSessions[sessionIndex].layout
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
            pane.agentBinding = binding
            switch event.lifecycle {
            case .turnStarted:
                pane.state = .running
            case .needsAttention:
                pane.state = .needsAttention
            case .turnCompleted:
                pane.state = .turnCompleted
            case .sessionEnded:
                pane.state = .idle
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
        try await repository.save(currentSnapshot)
    }

    private func placeholderTitle(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return "新会话 · \(formatter.string(from: date))"
    }

    private func materializeWorkSession(_ workSessionID: WorkSessionID) async throws {
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

        var snapshotChanged = false
        for pane in workSession.layout.panes {
            let command = pane.agentBinding.flatMap {
                agentResumeCommands?.resumeCommand(for: $0)
            }
            let environment = [
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
                } catch {
                    await terminalRuntime.stop(paneID: pane.id)
                    try await terminalRuntime.launch(shellLaunch)
                    snapshotChanged = markPaneIdle(
                        pane.id,
                        in: workSessionID
                    ) || snapshotChanged
                }
            } else {
                try await terminalRuntime.launch(shellLaunch)
                if pane.agentBinding != nil || pane.state != .idle {
                    snapshotChanged = markPaneIdle(
                        pane.id,
                        in: workSessionID
                    ) || snapshotChanged
                }
            }
        }
        materializedWorkSessionIDs.insert(workSessionID)
        if snapshotChanged {
            try await repository.save(currentSnapshot)
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
                transform: { $0.state = .idle }
            )
        else {
            return false
        }
        currentSnapshot.workSessions[sessionIndex].layout = layout
        return true
    }
}
