import BreathAutomation
import Foundation
import Testing

@Suite("Automation trigger socket")
struct AutomationTriggerSocketTests {
    @Test("same-user CLI request receives an acknowledgement without HTTP")
    func triggerRoundTrip() async throws {
        let directory = URL(
            fileURLWithPath: "/tmp",
            isDirectory: true
        ).appendingPathComponent(
            "breath-trigger-socket-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketURL = directory.appendingPathComponent("automation.sock")
        let server = UnixAutomationTriggerServer(socketURL: socketURL) { shortcode in
            AutomationTriggerResponse(
                status: .accepted,
                message: "Accepted \(shortcode)"
            )
        }
        try server.start()
        defer { server.stop() }

        let response = try UnixAutomationTriggerClient().trigger(
            shortcode: "K7mQ2xR8v4Np",
            at: socketURL
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: socketURL.path
        )

        #expect(response.status == .accepted)
        #expect(response.message == "Accepted K7mQ2xR8v4Np")
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
