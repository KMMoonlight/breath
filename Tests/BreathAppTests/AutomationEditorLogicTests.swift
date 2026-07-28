import BreathAgents
import BreathAutomation
import Foundation
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

    @Test("a failed run shows a fixed completion time")
    func failedRunTimeStopsUpdating() {
        let queuedAt = Date(timeIntervalSince1970: 100)
        let endedAt = Date(timeIntervalSince1970: 110)
        let run = AutomationRun(
            id: AutomationRunID(rawValue: UUID()),
            automationID: AutomationID(rawValue: UUID()),
            status: .failed,
            triggerSource: .manual,
            queuedAt: queuedAt,
            startedAt: queuedAt,
            endedAt: endedAt,
            effectiveDuration: 10,
            agent: .codex
        )

        #expect(
            automationRunTimePresentation(for: run)
                == .fixed(endedAt)
        )
    }

    @Test("an active run keeps showing relative elapsed time")
    func activeRunTimeKeepsUpdating() {
        let queuedAt = Date(timeIntervalSince1970: 100)
        let run = AutomationRun(
            id: AutomationRunID(rawValue: UUID()),
            automationID: AutomationID(rawValue: UUID()),
            status: .running,
            triggerSource: .manual,
            queuedAt: queuedAt,
            startedAt: queuedAt,
            agent: .codex
        )

        #expect(
            automationRunTimePresentation(for: run)
                == .relative(queuedAt)
        )
    }
}
