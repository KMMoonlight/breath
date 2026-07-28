import BreathAgents
import BreathAutomation
import Testing
@testable import BreathApp

@Suite("Automation editor logic")
struct AutomationEditorLogicTests {
    @Test("an available selected Agent does not show an unavailable warning")
    func availableAgentHasNoWarning() throws {
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first {
                $0.kind == .codex
            }
        )
        let option = AutomationAgentOption(
            adapter: adapter,
            availability: .available(
                executablePath: "/usr/local/bin/codex",
                currentVersion: adapter.automation?.minimumVersion
            )
        )

        #expect(
            automationAgentUnavailableReason(
                selectedAgent: .codex,
                options: [option],
                missingAgentReason: "missing"
            ) == nil
        )
    }

    @Test("a genuinely unavailable selected Agent keeps its concrete reason")
    func unavailableAgentKeepsReason() throws {
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first {
                $0.kind == .codex
            }
        )
        let option = AutomationAgentOption(
            adapter: adapter,
            availability: .unavailable(
                reason: "version too old",
                isInstalled: true,
                currentVersion: "0.1.0"
            )
        )

        #expect(
            automationAgentUnavailableReason(
                selectedAgent: .codex,
                options: [option],
                missingAgentReason: "missing"
            ) == "version too old"
        )
    }
}
