import BreathAgents
import BreathCore
import Foundation
import Testing

@Suite("Agent hook helper command")
struct AgentHookCommandTests {
    @Test("the hook helper sends sanitized metadata and silently ignores unassociated shells")
    func sendOrIgnore() throws {
        let sender = RecordingAgentEventSender()
        let socketURL = URL(fileURLWithPath: "/tmp/breath.sock")
        let workspaceID = WorkspaceID(rawValue: UUID())
        let workSessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let command = AgentHookCommand(
            factory: AgentHookEventFactory(now: { Date(timeIntervalSince1970: 3) }),
            sender: sender
        )
        let payload = Data("{\"session_id\":\"agent-1\",\"prompt\":\"private\"}".utf8)

        let result = command.run(
            arguments: ["Breath", "--agent-hook", "codex", "turnStarted"],
            environment: [
                "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
                "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
                "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
                "BREATH_AGENT_SOCKET": socketURL.path,
                "PWD": "/tmp/project",
            ],
            standardInput: payload
        )
        #expect(result == .sent)
        #expect(sender.events.first?.0.sessionID == "agent-1")
        #expect(sender.events.first?.1 == socketURL)

        let ignored = command.run(
            arguments: ["Breath", "--agent-hook", "codex", "turnStarted"],
            environment: [:],
            standardInput: payload
        )
        #expect(ignored == .ignored)
        #expect(sender.events.count == 1)
    }
}

private final class RecordingAgentEventSender: AgentEventSending, @unchecked Sendable {
    private(set) var events: [(AgentEvent, URL)] = []

    func send(_ event: AgentEvent, to socketURL: URL) throws {
        events.append((event, socketURL))
    }
}
