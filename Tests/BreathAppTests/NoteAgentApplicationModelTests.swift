@testable import BreathApp
import AppKit
import BreathAgents
import BreathCore
import BreathNotes
import BreathPersistence
import BreathTerminal
import Foundation
import Testing

@MainActor
@Suite("Note Agent application model")
struct NoteAgentApplicationModelTests {
    @Test("launches in the note library without workspace or pane identity")
    func launchesWithNoteIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-note-agent-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: root.appendingPathComponent("breath.sqlite")
        )
        let notesModel = NotesApplicationModel(
            service: NotesService(repository: repository)
        )
        notesModel.selectLibrary(library)
        await waitUntil { notesModel.snapshot.library != nil }
        let terminal = RecordingNoteAgentTerminalEngine()
        let codex = try #require(
            AgentAdapterRegistry.builtIn.adapters.first {
                $0.kind == .codex
            }
        )
        let model = NoteAgentApplicationModel(
            terminalEngine: terminal,
            notesModel: notesModel,
            applicationInstanceID: ApplicationInstanceID(rawValue: UUID()),
            availableAdapters: { [codex] },
            executableURL: { _ in URL(fileURLWithPath: "/usr/local/bin/codex") }
        )

        try await model.launch(codex, resumeSessionID: nil)
        let launch = try #require(terminal.noteAgentLaunches.first)
        #expect(launch.workingDirectory == library.path)
        #expect(launch.executable == "/usr/local/bin/codex")
        #expect(launch.environment["BREATH_NOTE_LIBRARY_ID"] != nil)
        #expect(launch.environment["BREATH_NOTE_AGENT_TERMINAL_ID"] != nil)
        #expect(launch.environment["BREATH_WORKSPACE_ID"] == nil)
        #expect(launch.environment["BREATH_WORK_SESSION_ID"] == nil)
        #expect(launch.environment["BREATH_TERMINAL_PANE_ID"] == nil)

        model.isDrawerPresented = false
        #expect(terminal.closedNoteAgentIDs.isEmpty)

        await model.endConversation()
        #expect(terminal.closedNoteAgentIDs == [launch.terminalID])
        #expect(model.status == .idle)
    }

    @Test("a persistence failure closes an otherwise untracked Note Agent")
    func persistenceFailureRollsBackTerminal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-note-agent-rollback-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        let repository = FailingNoteAgentPersistenceRepository()
        let notesModel = NotesApplicationModel(
            service: NotesService(repository: repository)
        )
        notesModel.selectLibrary(library)
        await waitUntil { notesModel.snapshot.library != nil }
        await repository.rejectWrites()
        let terminal = RecordingNoteAgentTerminalEngine()
        let codex = try #require(
            AgentAdapterRegistry.builtIn.adapters.first {
                $0.kind == .codex
            }
        )
        let model = NoteAgentApplicationModel(
            terminalEngine: terminal,
            notesModel: notesModel,
            applicationInstanceID: ApplicationInstanceID(rawValue: UUID()),
            availableAdapters: { [codex] },
            executableURL: { _ in URL(fileURLWithPath: "/usr/local/bin/codex") }
        )

        await #expect(throws: PersistenceFailure.self) {
            try await model.launch(codex, resumeSessionID: nil)
        }
        #expect(terminal.noteAgentLaunches.count == 1)
        #expect(
            terminal.closedNoteAgentIDs
                == terminal.noteAgentLaunches.map(\.terminalID)
        )
        #expect(model.terminalID == nil)
        #expect(model.conversationID == nil)
        #expect(model.status == .idle)
    }

    @Test("an Agent that exits during launch cannot leave a ghost conversation")
    func earlyExitDuringLaunchIsObserved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-note-agent-early-exit-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: root.appendingPathComponent("breath.sqlite")
        )
        let notesModel = NotesApplicationModel(
            service: NotesService(repository: repository)
        )
        notesModel.selectLibrary(library)
        await waitUntil { notesModel.snapshot.library != nil }
        let terminal = RecordingNoteAgentTerminalEngine()
        terminal.exitsDuringOpen = true
        let codex = try #require(
            AgentAdapterRegistry.builtIn.adapters.first {
                $0.kind == .codex
            }
        )
        let model = NoteAgentApplicationModel(
            terminalEngine: terminal,
            notesModel: notesModel,
            applicationInstanceID: ApplicationInstanceID(rawValue: UUID()),
            availableAdapters: { [codex] },
            executableURL: { _ in URL(fileURLWithPath: "/usr/local/bin/codex") }
        )

        await #expect(
            throws: NoteAgentApplicationError.conversationEndedDuringLaunch
        ) {
            try await model.launch(codex, resumeSessionID: nil)
        }
        #expect(model.terminalID == nil)
        #expect(model.conversationID == nil)
        #expect(model.status == .idle)
        await waitUntil { !terminal.closedNoteAgentIDs.isEmpty }
        #expect(
            terminal.closedNoteAgentIDs
                == terminal.noteAgentLaunches.map(\.terminalID)
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct PersistenceFailure: Error {}

private actor FailingNoteAgentPersistenceRepository: NotesRepository {
    private var state = NotesPersistedState.empty
    private var rejectsWrites = false

    func rejectWrites() {
        rejectsWrites = true
    }

    func loadNotesState() async throws -> NotesPersistedState {
        state
    }

    func saveNotesState(_ state: NotesPersistedState) async throws {
        if rejectsWrites {
            throw PersistenceFailure()
        }
        self.state = state
    }

    func replaceNoteSearchIndex(
        libraryID: NoteLibraryID,
        documents: [NoteSearchDocument]
    ) async throws {}

    func searchNotes(
        libraryID: NoteLibraryID,
        query: String,
        limit: Int
    ) async throws -> [NoteSearchResult] {
        []
    }
}

@MainActor
private final class RecordingNoteAgentTerminalEngine:
    TerminalEngine,
    TerminalViewProviding,
    @unchecked Sendable
{
    var noteAgentLaunches: [NoteAgentTerminalLaunch] = []
    var closedNoteAgentIDs: [NoteAgentTerminalID] = []
    var exitsDuringOpen = false
    var noteAgentExitHandler: (@Sendable (NoteAgentTerminalID) -> Void)?

    func open(_ launch: TerminalLaunch) async throws {}
    func close(_ paneID: TerminalPaneID) async {}
    func apply(settings: TerminalSettings) async {}
    func view(for paneID: TerminalPaneID) -> NSView? { nil }

    func openNoteAgent(_ launch: NoteAgentTerminalLaunch) async throws {
        noteAgentLaunches.append(launch)
        if exitsDuringOpen {
            noteAgentExitHandler?(launch.terminalID)
            await Task.yield()
        }
    }

    func closeNoteAgent(_ terminalID: NoteAgentTerminalID) async {
        closedNoteAgentIDs.append(terminalID)
    }

    func setNoteAgentProcessExitHandler(
        _ handler: @escaping @Sendable (NoteAgentTerminalID) -> Void
    ) async {
        noteAgentExitHandler = handler
    }
}
