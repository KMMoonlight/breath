import BreathAgents
import BreathCore
import BreathSkills
import Foundation
import Testing
@testable import BreathApp

@Suite("Agent integration preferences")
struct AgentIntegrationPreferenceStoreTests {
    @MainActor
    @Test("an open Skills page receives Agent target availability changes")
    func openSkillsPageReceivesTargetAvailability() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-skill-targets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let codex = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .codex }
        )
        let service = GlobalSkillsService(
            homeDirectory: temporaryDirectory,
            agentAdapters: [codex],
            environment: [:],
            targetAvailability: [
                .codex: .unavailable(reason: "Agent installation status is still being checked."),
            ]
        )
        let model = SkillsViewModel(service: service)
        model.activate()
        defer { model.deactivate() }
        for _ in 0..<100 where model.snapshot.targets.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.snapshot.targets.first?.availability.isSelectable == false)
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.snapshot.targets.first?.availability.isSelectable == false)

        await service.updateTargetAvailability([.codex: .available])
        for _ in 0..<100
            where model.snapshot.targets.first?.availability.isSelectable != true
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.snapshot.targets.first?.availability.isSelectable == true)
    }

    @Test("installed CLIs are enabled by default and explicit choices persist")
    func installedDefaultsAndExplicitChoices() throws {
        let suiteName = "BreathTests.AgentIntegrationPreferenceStore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AgentIntegrationPreferenceStore(defaults: defaults)

        #expect(preferences.shouldInstall(.codex, isInstalled: true))
        #expect(preferences.shouldInstall(.claudeCode, isInstalled: true))
        #expect(!preferences.shouldInstall(.geminiCLI, isInstalled: false))

        preferences.setEnabled(false, for: .codex)
        preferences.setEnabled(true, for: .claudeCode)

        #expect(!preferences.shouldInstall(.codex, isInstalled: true))
        #expect(preferences.shouldInstall(.claudeCode, isInstalled: true))
        #expect(!preferences.shouldInstall(.claudeCode, isInstalled: false))
    }

    @MainActor
    @Test("application startup installs hooks only for detected Agent CLIs")
    func applicationStartupInstallsDetectedAgentHooks() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-auto-hooks-\(UUID().uuidString)", isDirectory: true)
        let homeDirectory = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        let supportDirectory = temporaryDirectory.appendingPathComponent("support", isDirectory: true)
        let codexDirectory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
        let suiteName = "BreathTests.AgentIntegrationStartup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        for (executableName, version) in [("codex", "0.144.3"), ("claude", "2.1.7")] {
            let executableURL = binDirectory.appendingPathComponent(executableName)
            try Data("#!/bin/sh\necho '\(version)'\n".utf8).write(to: executableURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executableURL.path
            )
        }
        try Data("not executable\n".utf8).write(
            to: binDirectory.appendingPathComponent("gemini")
        )
        try Data(
            """
            {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"existing-tool"}]}]}}
            """.utf8
        ).write(to: hooksURL)

        let model = try BreathApplicationModel(
            homeDirectory: homeDirectory,
            supportDirectory: supportDirectory,
            terminalEngineOverride: AppShellTestingTerminalEngine(),
            integrationPreferences: AgentIntegrationPreferenceStore(defaults: defaults),
            installedAgentCLIDetector: InstalledAgentCLIDetector(
                searchDirectories: [binDirectory]
            )
        )
        model.start()

        for _ in 0..<100 where model.agentCLIStatuses[.codex] == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let skillTargets = await model.skillsService.scan().targets
        #expect(model.agentCLIStatuses[.codex] != nil)
        #expect(skillTargets.first { $0.agent == .codex }?.availability.isSelectable == true)

        let installed = try String(contentsOf: hooksURL, encoding: .utf8)
        let claudeSettingsURL = homeDirectory.appendingPathComponent(".claude/settings.json")
        let claudeSettings = try String(contentsOf: claudeSettingsURL, encoding: .utf8)
        let geminiSettingsURL = homeDirectory.appendingPathComponent(".gemini/settings.json")
        #expect(installed.contains("existing-tool"))
        #expect(installed.contains("--agent-hook codex"))
        #expect(installed.contains("PreToolUse"))
        #expect(installed.contains("--agent-hook codex attentionResolved"))
        #expect(claudeSettings.contains("--agent-hook claudeCode"))
        #expect(claudeSettings.contains("SessionStart"))
        #expect(claudeSettings.contains("--agent-hook claudeCode turnStarted"))
        #expect(claudeSettings.contains("PreToolUse"))
        #expect(claudeSettings.contains("--agent-hook claudeCode attentionResolved"))
        #expect(!FileManager.default.fileExists(atPath: geminiSettingsURL.path))

        try Data("{\"environmentVariables\":{}}".utf8).write(to: claudeSettingsURL)
        model.repairDetectedAgentIntegrations()
        let repairedClaudeSettings = try String(contentsOf: claudeSettingsURL, encoding: .utf8)
        #expect(repairedClaudeSettings.contains("SessionStart"))
        #expect(repairedClaudeSettings.contains("--agent-hook claudeCode turnStarted"))
        #expect(repairedClaudeSettings.contains("PreToolUse"))
        #expect(repairedClaudeSettings.contains("--agent-hook claudeCode attentionResolved"))
        #expect(await model.prepareForTermination())
    }

    @MainActor
    @Test("an uninstalled Agent cannot enable hooks")
    func uninstalledAgentCannotEnableHooks() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-missing-agent-hooks-\(UUID().uuidString)", isDirectory: true)
        let homeDirectory = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        let supportDirectory = temporaryDirectory.appendingPathComponent("support", isDirectory: true)
        let suiteName = "BreathTests.UninstalledAgentHooks.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )

        let model = try BreathApplicationModel(
            homeDirectory: homeDirectory,
            supportDirectory: supportDirectory,
            terminalEngineOverride: AppShellTestingTerminalEngine(),
            integrationPreferences: AgentIntegrationPreferenceStore(defaults: defaults),
            installedAgentCLIDetector: InstalledAgentCLIDetector(searchDirectories: [])
        )
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .codex }
        )

        model.setAgentIntegration(adapter, enabled: true)

        #expect(!model.canToggleAgentIntegration(adapter))
        #expect(!model.enabledAgents.contains(.codex))
        #expect(
            !FileManager.default.fileExists(
                atPath: homeDirectory.appendingPathComponent(".codex/hooks.json").path
            )
        )
    }
}
