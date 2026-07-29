import BreathAgents
import BreathCore
import BreathNotes
import BreathTerminal
import Foundation

enum NoteAgentApplicationError: LocalizedError, Equatable {
    case libraryUnavailable
    case agentUnavailable(String)
    case conversationAlreadyRunning
    case conversationEndedDuringLaunch
    case resumeUnsupported(String)
    case eventTargetMismatch

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            "笔记库当前不可访问。"
        case let .agentUnavailable(name):
            "未找到可用的 \(name) 命令行工具。"
        case .conversationAlreadyRunning:
            "已有一个笔记 Agent 对话正在运行。"
        case .conversationEndedDuringLaunch:
            "笔记 Agent 在启动完成前已经退出。"
        case let .resumeUnsupported(name):
            "\(name) 当前无法继续这条对话，请开始新对话。"
        case .eventTargetMismatch:
            "Agent 事件不属于当前笔记对话。"
        }
    }
}

@MainActor
final class NoteAgentApplicationModel: ObservableObject {
    @Published var isDrawerPresented = false
    @Published private(set) var status: NoteAgentConversationStatus = .idle
    @Published private(set) var terminalID: NoteAgentTerminalID?
    @Published private(set) var conversationID: NoteAgentConversationID?
    @Published private(set) var selectedAgent: AgentKind?
    @Published private(set) var availableAgents: [AgentAdapterDescriptor] = []
    @Published var lastError: String?

    let terminalEngine: any TerminalEngine & TerminalViewProviding

    private let notesModel: NotesApplicationModel
    private let applicationInstanceID: ApplicationInstanceID
    private let availableAdapters: @MainActor () -> [AgentAdapterDescriptor]
    private let executableURL: @MainActor (AgentKind) -> URL?
    private var started = false
    private var processExitHandlerInstalled = false

    init(
        terminalEngine: any TerminalEngine & TerminalViewProviding,
        notesModel: NotesApplicationModel,
        applicationInstanceID: ApplicationInstanceID,
        availableAdapters: @escaping @MainActor () -> [AgentAdapterDescriptor],
        executableURL: @escaping @MainActor (AgentKind) -> URL?
    ) {
        self.terminalEngine = terminalEngine
        self.notesModel = notesModel
        self.applicationInstanceID = applicationInstanceID
        self.availableAdapters = availableAdapters
        self.executableURL = executableURL
        self.availableAgents = availableAdapters()
        self.selectedAgent = self.availableAgents.first?.kind
    }

    var recoveryBinding: NoteAgentRecoveryBinding? {
        notesModel.snapshot.noteAgentRecoveryBinding
    }

    func start() async {
        guard !started else { return }
        started = true
        refreshAvailability()
        synchronizePersistence()
        await installProcessExitHandlerIfNeeded()
    }

    private func installProcessExitHandlerIfNeeded() async {
        guard !processExitHandlerInstalled else { return }
        processExitHandlerInstalled = true
        await terminalEngine.setNoteAgentProcessExitHandler {
            [weak self] terminalID in
            Task { @MainActor [weak self] in
                self?.terminalDidExit(terminalID)
            }
        }
    }

    func refreshAvailability() {
        availableAgents = availableAdapters()
        if let selectedAgent,
           !availableAgents.contains(where: { $0.kind == selectedAgent })
        {
            self.selectedAgent = nil
        }
    }

    func synchronizePersistence() {
        let persisted = notesModel.snapshot.lastSelectedAgent
        if availableAgents.contains(where: { $0.kind == persisted }) {
            selectedAgent = persisted
        } else {
            selectedAgent = availableAgents.first?.kind
        }
    }

    func launch(
        _ adapter: AgentAdapterDescriptor,
        resumeSessionID: String?
    ) async throws {
        await installProcessExitHandlerIfNeeded()
        guard status == .idle, terminalID == nil else {
            throw NoteAgentApplicationError.conversationAlreadyRunning
        }
        guard notesModel.isLibraryAvailable,
              let library = notesModel.snapshot.library
        else {
            throw NoteAgentApplicationError.libraryUnavailable
        }
        guard availableAgents.contains(where: {
            $0.kind == adapter.kind
        }), let executable = executableURL(adapter.kind)
        else {
            throw NoteAgentApplicationError.agentUnavailable(
                adapter.displayName
            )
        }

        let root = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        ).standardizedFileURL
        let values = try root.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            throw NoteAgentApplicationError.libraryUnavailable
        }

        let terminalID = NoteAgentTerminalID(rawValue: UUID())
        let conversationID = NoteAgentConversationID(rawValue: UUID())
        let arguments: [String]
        if let resumeSessionID {
            let binding = AgentBinding(
                agent: adapter.kind,
                sessionID: resumeSessionID
            )
            guard let resumeCommand = BuiltInAgentResumeCommands()
                .resumeCommand(for: binding)
            else {
                throw NoteAgentApplicationError.resumeUnsupported(
                    adapter.displayName
                )
            }
            arguments = resumeCommand.arguments
        } else {
            arguments = []
        }
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "BREATH_WORKSPACE_ID")
        environment.removeValue(forKey: "BREATH_WORK_SESSION_ID")
        environment.removeValue(forKey: "BREATH_TERMINAL_PANE_ID")
        environment["BREATH_APPLICATION_INSTANCE_ID"] =
            applicationInstanceID.rawValue.uuidString
        environment["BREATH_NOTE_LIBRARY_ID"] =
            library.id.rawValue.uuidString
        environment["BREATH_NOTE_AGENT_CONVERSATION_ID"] =
            conversationID.rawValue.uuidString
        environment["BREATH_NOTE_AGENT_TERMINAL_ID"] =
            terminalID.rawValue.uuidString

        self.terminalID = terminalID
        self.conversationID = conversationID
        selectedAgent = adapter.kind
        status = .running
        do {
            try await terminalEngine.openNoteAgent(NoteAgentTerminalLaunch(
                terminalID: terminalID,
                workingDirectory: root.path,
                executable: executable.path,
                arguments: arguments,
                environment: environment
            ))
        } catch {
            if self.terminalID == terminalID {
                self.terminalID = nil
                self.conversationID = nil
                status = .idle
            }
            throw error
        }
        guard self.terminalID == terminalID else {
            throw NoteAgentApplicationError.conversationEndedDuringLaunch
        }
        let recovery = resumeSessionID.map {
            NoteAgentRecoveryBinding(agent: adapter.kind, sessionID: $0)
        }
        do {
            try await notesModel.updateNoteAgentPersistence(
                lastSelectedAgent: adapter.kind,
                recoveryBinding: recovery
            )
        } catch {
            await terminalEngine.closeNoteAgent(terminalID)
            self.terminalID = nil
            self.conversationID = nil
            status = .idle
            throw error
        }
        lastError = nil
    }

    func endConversation() async {
        if let terminalID {
            await terminalEngine.closeNoteAgent(terminalID)
        }
        terminalID = nil
        conversationID = nil
        status = .idle
        do {
            try await notesModel.updateNoteAgentPersistence(
                lastSelectedAgent: selectedAgent,
                recoveryBinding: nil
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopForApplicationTermination() async {
        if let terminalID {
            await terminalEngine.closeNoteAgent(terminalID)
        }
        terminalID = nil
        conversationID = nil
        status = .idle
    }

    func noteAgentEvent(
        agent: AgentKind,
        lifecycle: AgentLifecycle,
        sessionID: String?
    ) async {
        guard selectedAgent == agent, terminalID != nil else { return }
        switch lifecycle {
        case .needsAttention:
            status = .needsAttention
        case .sessionEnded:
            status = .idle
        default:
            status = .running
        }
        guard let sessionID, !sessionID.isEmpty else { return }
        do {
            try await notesModel.updateNoteAgentPersistence(
                lastSelectedAgent: agent,
                recoveryBinding: NoteAgentRecoveryBinding(
                    agent: agent,
                    sessionID: sessionID
                )
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func handleAgentEvent(_ event: AgentEvent) async throws {
        guard event.applicationInstanceID == applicationInstanceID,
              let library = notesModel.snapshot.library,
              case let .noteLibrary(
                  noteLibraryID,
                  eventConversationID,
                  eventTerminalID
              ) = event.scope,
              noteLibraryID == library.id.rawValue,
              eventConversationID == conversationID,
              eventTerminalID == terminalID,
              URL(fileURLWithPath: event.workingDirectory)
                .standardizedFileURL.path
                == URL(fileURLWithPath: library.rootPath)
                    .standardizedFileURL.path
        else {
            throw NoteAgentApplicationError.eventTargetMismatch
        }
        await noteAgentEvent(
            agent: event.agent,
            lifecycle: event.lifecycle,
            sessionID: event.sessionID
        )
    }

    private func terminalDidExit(_ id: NoteAgentTerminalID) {
        guard terminalID == id else { return }
        terminalID = nil
        conversationID = nil
        status = .idle
        Task {
            await terminalEngine.closeNoteAgent(id)
        }
    }
}
