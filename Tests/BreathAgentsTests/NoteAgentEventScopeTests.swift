import BreathAgents
import BreathCore
import Foundation
import Testing

@Suite("Note Agent event scope")
struct NoteAgentEventScopeTests {
    @Test("note events encode without forged workspace session or pane ids")
    func noteEventScope() throws {
        let libraryID = UUID()
        let conversationID = NoteAgentConversationID(rawValue: UUID())
        let terminalID = NoteAgentTerminalID(rawValue: UUID())
        let event = AgentEvent(
            applicationInstanceID: ApplicationInstanceID(rawValue: UUID()),
            agent: .codex,
            lifecycle: .needsAttention,
            occurredAt: Date(timeIntervalSince1970: 100),
            noteLibraryID: libraryID,
            noteAgentConversationID: conversationID,
            noteAgentTerminalID: terminalID,
            sessionID: "official-session",
            workingDirectory: "/notes"
        )

        let data = try JSONEncoder().encode(event)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["workspaceID"] == nil)
        #expect(object["workSessionID"] == nil)
        #expect(object["paneID"] == nil)
        #expect(object["noteLibraryID"] as? String == libraryID.uuidString)

        let decoded = try StrictAgentEventDecoder().decode(data)
        #expect(decoded == event)
        #expect(
            decoded.scope == .noteLibrary(
                noteLibraryID: libraryID,
                conversationID: conversationID,
                terminalID: terminalID
            )
        )
    }

    @Test("hook factory prefers an explicit note scope without pane identities")
    func hookFactoryBuildsNoteScope() throws {
        let applicationID = ApplicationInstanceID(rawValue: UUID())
        let libraryID = UUID()
        let conversationID = NoteAgentConversationID(rawValue: UUID())
        let terminalID = NoteAgentTerminalID(rawValue: UUID())
        let builtEvent = try AgentHookEventFactory(
            now: { Date(timeIntervalSince1970: 42) }
        ).makeEvent(
                agent: .codex,
                lifecycle: .turnCompleted,
                rawPayload: Data(
                    """
                    {"session_id":"session-42","cwd":"/tmp/notes"}
                    """.utf8
                ),
                environment: [
                    "BREATH_APPLICATION_INSTANCE_ID":
                        applicationID.rawValue.uuidString,
                    "BREATH_NOTE_LIBRARY_ID": libraryID.uuidString,
                    "BREATH_NOTE_AGENT_CONVERSATION_ID":
                        conversationID.rawValue.uuidString,
                    "BREATH_NOTE_AGENT_TERMINAL_ID":
                        terminalID.rawValue.uuidString,
                    "BREATH_WORKSPACE_ID": UUID().uuidString,
                    "BREATH_WORK_SESSION_ID": UUID().uuidString,
                    "BREATH_TERMINAL_PANE_ID": UUID().uuidString,
                ]
            )
        let event = try #require(builtEvent)

        #expect(
            event.scope == .noteLibrary(
                noteLibraryID: libraryID,
                conversationID: conversationID,
                terminalID: terminalID
            )
        )
        #expect(event.workspaceID == nil)
        #expect(event.workSessionID == nil)
        #expect(event.paneID == nil)
        #expect(event.sessionID == "session-42")
        #expect(event.workingDirectory == "/tmp/notes")
    }
}
