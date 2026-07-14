import BreathAgents
import BreathCore
import Foundation
import Testing

@Suite("Local Agent event socket")
struct UnixAgentEventSocketTests {
    @Test("a strict event crosses a current-user-only Unix socket")
    func roundTrip() async throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-\(UUID().uuidString).sock")
        let recorder = AgentEventRecorder()
        let server = UnixAgentEventServer(socketURL: socketURL) { event in
            Task { await recorder.append(event) }
        }
        defer { server.stop() }
        try server.start()
        let event = AgentEvent(
            agent: .codex,
            lifecycle: .turnCompleted,
            occurredAt: Date(timeIntervalSince1970: 50),
            workspaceID: WorkspaceID(rawValue: UUID()),
            workSessionID: WorkSessionID(rawValue: UUID()),
            paneID: TerminalPaneID(rawValue: UUID()),
            sessionID: "thread-1",
            nativeTitle: "Socket test",
            workingDirectory: "/tmp/project"
        )

        try UnixAgentEventClient().send(event, to: socketURL)
        for _ in 0..<1_000 {
            if !(await recorder.events).isEmpty { break }
            await Task.yield()
        }

        #expect(await recorder.events == [event])
        let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber).intValue
        #expect(mode & 0o777 == 0o600)
    }
}

private actor AgentEventRecorder {
    private(set) var events: [AgentEvent] = []

    func append(_ event: AgentEvent) {
        events.append(event)
    }
}
