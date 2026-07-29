import BreathAgents
import Foundation
import Testing

@Suite("Agent hook output")
struct AgentHookOutputTests {
    @Test("Antigravity hook helper returns the event-specific JSON contract")
    func antigravityStandardOutput() {
        let command = AgentHookCommand()

        #expect(
            command.standardOutput(
                arguments: [
                    "Breath",
                    "--agent-hook",
                    "antigravityCLI",
                    "turnStarted",
                ]
            ) == Data("{}\n".utf8)
        )
        #expect(
            command.standardOutput(
                arguments: [
                    "Breath",
                    "--agent-hook",
                    "antigravityCLI",
                    "turnCompleted",
                ]
            ) == Data("{\"decision\":\"stop\"}\n".utf8)
        )
        #expect(
            command.standardOutput(
                arguments: [
                    "Breath",
                    "--agent-hook",
                    "kimiCode",
                    "turnCompleted",
                ]
            ) == nil
        )
    }
}
