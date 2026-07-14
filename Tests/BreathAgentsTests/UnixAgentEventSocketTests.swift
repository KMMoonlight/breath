import BreathAgents
import BreathCore
import Darwin
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
            applicationInstanceID: ApplicationInstanceID(rawValue: UUID()),
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
        for _ in 0..<100 {
            if !(await recorder.events).isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await recorder.events == [event])
        let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber).intValue
        #expect(mode & 0o777 == 0o600)
    }

    @Test("a stalled client cannot block later Agent events")
    func stalledClientIsolation() async throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-\(UUID().uuidString).sock")
        let recorder = AgentEventRecorder()
        let server = UnixAgentEventServer(socketURL: socketURL) { event in
            Task { await recorder.append(event) }
        }
        defer { server.stop() }
        try server.start()
        let stalled = try connectTestSocket(to: socketURL.path)
        defer { Darwin.close(stalled) }
        var partialHeader: UInt8 = 0
        _ = Darwin.write(stalled, &partialHeader, 1)

        let event = AgentEvent(
            applicationInstanceID: ApplicationInstanceID(rawValue: UUID()),
            agent: .codex,
            lifecycle: .turnStarted,
            occurredAt: Date(timeIntervalSince1970: 60),
            workspaceID: WorkspaceID(rawValue: UUID()),
            workSessionID: WorkSessionID(rawValue: UUID()),
            paneID: TerminalPaneID(rawValue: UUID()),
            sessionID: "thread-2",
            workingDirectory: "/tmp/project"
        )
        try UnixAgentEventClient().send(event, to: socketURL)
        for _ in 0..<100 {
            if await recorder.events == [event] { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await recorder.events == [event])
    }
}

private func connectTestSocket(to path: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8CString)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        bytes.withUnsafeBufferPointer { source in
            UnsafeMutableRawPointer(pointer)
                .assumingMemoryBound(to: CChar.self)
                .update(from: source.baseAddress!, count: bytes.count)
        }
    }
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        Darwin.close(descriptor)
        throw CocoaError(.fileReadUnknown)
    }
    return descriptor
}

private actor AgentEventRecorder {
    private(set) var events: [AgentEvent] = []

    func append(_ event: AgentEvent) {
        events.append(event)
    }
}
