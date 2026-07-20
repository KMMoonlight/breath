import BreathAgents
import BreathCore
import Foundation
import GRDB
import Testing

@Suite("Supported Agent CLI registry")
struct AgentAdapterRegistryTests {
    @Test("v1 exposes the approved nine-agent compatibility matrix")
    func supportedMatrix() {
        let adapters = AgentAdapterRegistry.builtIn.adapters

        #expect(
            adapters.map(\.kind) == [
                .codex,
                .claudeCode,
                .geminiCLI,
                .githubCopilotCLI,
                .qwenCode,
                .cursorAgent,
                .factoryDroid,
                .openCode,
                .pi,
            ]
        )
        #expect(adapters.map(\.displayName) == [
            "Codex",
            "Claude Code",
            "Gemini CLI",
            "GitHub Copilot CLI",
            "Qwen Code",
            "Cursor Agent",
            "Factory Droid",
            "OpenCode",
            "Pi",
        ])
        #expect(adapters.allSatisfy { !$0.minimumVersion.isEmpty })
        #expect(adapters.allSatisfy { $0.integrationMechanism != .terminalParsing })
    }

    @Test("every adapter declares its user-level integration target and lifecycle events")
    func integrationPlans() {
        for adapter in AgentAdapterRegistry.builtIn.adapters {
            #expect(!adapter.userConfigurationPath.isEmpty)
            #expect(adapter.hookRegistrations.contains(where: { $0.lifecycle == .turnStarted }))
            #expect(adapter.hookRegistrations.contains(where: { $0.lifecycle == .turnCompleted }))
        }
    }

    @Test("every supported Agent declares a resolvable global Skills contract")
    func globalSkillContracts() throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let expected: [AgentKind: String] = [
            .codex: "/Users/tester/.codex/skills",
            .claudeCode: "/Users/tester/.claude/skills",
            .geminiCLI: "/Users/tester/.gemini/skills",
            .githubCopilotCLI: "/Users/tester/.copilot/skills",
            .qwenCode: "/Users/tester/.qwen/skills",
            .cursorAgent: "/Users/tester/.cursor/skills",
            .factoryDroid: "/Users/tester/.factory/skills",
            .openCode: "/Users/tester/.config/opencode/skills",
            .pi: "/Users/tester/.pi/agent/skills",
        ]

        for adapter in AgentAdapterRegistry.builtIn.adapters {
            let capability = try #require(adapter.globalSkills)
            #expect(
                capability.resolveDirectory(
                    homeDirectory: home,
                    environment: [:]
                ).path == expected[adapter.kind]
            )
            #expect(!capability.activationHint.isEmpty)
        }

        let openCode = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .openCode }
        )
        #expect(
            openCode.globalSkills?.resolveDirectory(
                homeDirectory: home,
                environment: ["XDG_CONFIG_HOME": "/Volumes/config" ]
            ).path == "/Volumes/config/opencode/skills"
        )
        #expect(
            openCode.globalSkills?.reliablyResolveDirectory(
                homeDirectory: home,
                environment: ["XDG_CONFIG_HOME": "relative/config"]
            ) == nil
        )
    }

    @Test("Claude, Gemini, and OpenCode map their official lifecycle events")
    func officialLifecycleMappings() throws {
        let claude = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .claudeCode }
        )
        #expect(claude.hookRegistrations.contains(
            AgentHookRegistration(eventName: "SessionStart", lifecycle: .turnStarted)
        ))

        let gemini = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .geminiCLI }
        )
        #expect(gemini.hookRegistrations.contains(
            AgentHookRegistration(eventName: "Notification", lifecycle: .needsAttention)
        ))
        #expect(gemini.hookRegistrations.contains(
            AgentHookRegistration(eventName: "SessionEnd", lifecycle: .sessionEnded)
        ))

        let openCode = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .openCode }
        )
        #expect(openCode.hookRegistrations.contains(
            AgentHookRegistration(eventName: "session.status", lifecycle: .turnStarted)
        ))
        #expect(openCode.hookRegistrations.contains(
            AgentHookRegistration(eventName: "session.updated", lifecycle: .metadataUpdated)
        ))
        #expect(!openCode.hookRegistrations.contains(
            AgentHookRegistration(eventName: "session.updated", lifecycle: .turnStarted)
        ))

        let cursor = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .cursorAgent }
        )
        #expect(cursor.hookRegistrations.contains(
            AgentHookRegistration(eventName: "sessionEnd", lifecycle: .sessionEnded)
        ))
    }

    @Test("agent event decoding rejects conversation content fields")
    func strictEventPayload() throws {
        let event = AgentEvent(
            applicationInstanceID: ApplicationInstanceID(rawValue: UUID()),
            agent: .claudeCode,
            version: "2.1.7",
            lifecycle: .turnStarted,
            occurredAt: Date(timeIntervalSince1970: 100),
            workspaceID: WorkspaceID(rawValue: UUID()),
            workSessionID: WorkSessionID(rawValue: UUID()),
            paneID: TerminalPaneID(rawValue: UUID()),
            sessionID: "session-1",
            nativeTitle: "Fix tests",
            workingDirectory: "/tmp/project"
        )
        let valid = try JSONEncoder().encode(event)
        #expect(try StrictAgentEventDecoder().decode(valid) == event)

        var object = try #require(
            JSONSerialization.jsonObject(with: valid) as? [String: Any]
        )
        object["prompt"] = "secret content"
        let forbidden = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: AgentEventDecodingError.unexpectedFields(["prompt"])) {
            try StrictAgentEventDecoder().decode(forbidden)
        }
    }

    @Test("built-in adapters resume through each CLI's supported session flag")
    func resumeCommands() {
        let provider = BuiltInAgentResumeCommands()
        let expected: [AgentKind: AgentResumeCommand] = [
            .codex: AgentResumeCommand(executable: "codex", arguments: ["resume", "session-1"]),
            .claudeCode: AgentResumeCommand(executable: "claude", arguments: ["--resume", "session-1"]),
            .geminiCLI: AgentResumeCommand(executable: "gemini", arguments: ["--resume", "session-1"]),
            .githubCopilotCLI: AgentResumeCommand(executable: "copilot", arguments: ["--resume", "session-1"]),
            .qwenCode: AgentResumeCommand(executable: "qwen", arguments: ["--resume", "session-1"]),
            .cursorAgent: AgentResumeCommand(executable: "cursor-agent", arguments: ["--resume", "session-1"]),
            .factoryDroid: AgentResumeCommand(executable: "droid", arguments: ["--resume", "session-1"]),
            .openCode: AgentResumeCommand(executable: "opencode", arguments: ["--session", "session-1"]),
            .pi: AgentResumeCommand(executable: "pi", arguments: ["--session", "session-1"]),
        ]

        for (agent, command) in expected {
            #expect(
                provider.resumeCommand(
                    for: AgentBinding(agent: agent, sessionID: "session-1")
                ) == command
            )
        }
        #expect(provider.resumeCommand(for: AgentBinding(agent: .codex)) == nil)
    }

    @Test("hook installation is idempotent and uninstall preserves user entries")
    func reversibleHookConfiguration() throws {
        let original = Data(
            """
            {"theme":"dark","hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"user-tool"}]}]}}
            """.utf8
        )
        let editor = JSONHookConfigurationEditor()
        let registrations = [
            AgentHookRegistration(eventName: "UserPromptSubmit", lifecycle: .turnStarted),
            AgentHookRegistration(eventName: "Stop", lifecycle: .turnCompleted),
        ]

        let installed = try editor.install(
            in: original,
            registrations: registrations,
            hookExecutable: "/Applications/Breath.app/Contents/MacOS/Breath",
            agent: .claudeCode
        )
        let installedAgain = try editor.install(
            in: installed,
            registrations: registrations,
            hookExecutable: "/Applications/Breath.app/Contents/MacOS/Breath",
            agent: .claudeCode
        )
        #expect(installedAgain == installed)
        let installedObject = try #require(
            JSONSerialization.jsonObject(with: installed) as? [String: Any]
        )
        let installedHooks = try #require(installedObject["hooks"] as? [String: Any])
        let breathEntries = try #require(installedHooks["UserPromptSubmit"] as? [[String: Any]])
        #expect(breathEntries.first?["breathManaged"] == nil)

        let uninstalled = try editor.uninstall(from: installed)
        let object = try #require(JSONSerialization.jsonObject(with: uninstalled) as? [String: Any])
        #expect(object["theme"] as? String == "dark")
        let hooks = try #require(object["hooks"] as? [String: Any])
        #expect((hooks["Stop"] as? [Any])?.count == 1)
        #expect(hooks["UserPromptSubmit"] == nil)
    }

    @Test("uninstall removes only Breath's nested hook handler")
    func uninstallPreservesSharedMatcherHandlers() throws {
        let source = Data(
            """
            {"hooks":{"Stop":[{"matcher":"","hooks":[
              {"type":"command","name":"Breath","command":"'/Applications/Breath.app/Contents/MacOS/Breath' --agent-hook claudeCode turnCompleted"},
              {"type":"command","name":"User Tool","command":"user-tool"}
            ]}]}}
            """.utf8
        )

        let result = try JSONHookConfigurationEditor().uninstall(from: source)
        let root = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: Any])
        let entries = try #require(hooks["Stop"] as? [[String: Any]])
        let handlers = try #require(entries.first?["hooks"] as? [[String: Any]])
        #expect(handlers.count == 1)
        #expect(handlers.first?["command"] as? String == "user-tool")
    }

    @Test("Copilot personal hooks use its versioned flat command schema")
    func copilotHookConfiguration() throws {
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first(where: { $0.kind == .githubCopilotCLI })
        )
        let editor = FlatJSONHookConfigurationEditor(style: .copilotCLI)
        let original = Data(
            """
            {"version":1,"hooks":{"sessionStart":[{"type":"command","bash":"user-tool"}],"agentStop":[{"type":"command","bash":"user-tool --agent-hook private status"}]}}
            """.utf8
        )

        let installed = try editor.install(
            in: original,
            registrations: adapter.hookRegistrations,
            hookExecutable: "/Applications/Breath.app/Contents/MacOS/Breath",
            agent: adapter.kind
        )
        #expect(try editor.install(
            in: installed,
            registrations: adapter.hookRegistrations,
            hookExecutable: "/Applications/Breath.app/Contents/MacOS/Breath",
            agent: adapter.kind
        ) == installed)

        let object = try #require(JSONSerialization.jsonObject(with: installed) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        let hooks = try #require(object["hooks"] as? [String: Any])
        let promptHooks = try #require(hooks["userPromptSubmitted"] as? [[String: Any]])
        #expect(promptHooks.count == 1)
        #expect(promptHooks[0]["type"] as? String == "command")
        #expect((promptHooks[0]["bash"] as? String)?.contains("--agent-hook githubCopilotCLI turnStarted") == true)
        #expect(promptHooks[0]["hooks"] == nil)
        #expect(promptHooks[0]["breathManaged"] == nil)

        let uninstalled = try editor.uninstall(from: installed)
        let uninstalledObject = try #require(
            JSONSerialization.jsonObject(with: uninstalled) as? [String: Any]
        )
        let remainingHooks = try #require(uninstalledObject["hooks"] as? [String: Any])
        #expect((remainingHooks["sessionStart"] as? [Any])?.count == 1)
        #expect((remainingHooks["agentStop"] as? [Any])?.count == 1)
        #expect(remainingHooks["userPromptSubmitted"] == nil)
    }

    @Test("Cursor hooks use versioned direct command entries")
    func cursorHookConfiguration() throws {
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first(where: { $0.kind == .cursorAgent })
        )
        let editor = FlatJSONHookConfigurationEditor(style: .cursor)

        let installed = try editor.install(
            in: Data("{}".utf8),
            registrations: adapter.hookRegistrations,
            hookExecutable: "/Applications/Breath.app/Contents/MacOS/Breath",
            agent: adapter.kind
        )
        let object = try #require(JSONSerialization.jsonObject(with: installed) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        let hooks = try #require(object["hooks"] as? [String: Any])
        let promptHooks = try #require(hooks["beforeSubmitPrompt"] as? [[String: Any]])
        #expect((promptHooks[0]["command"] as? String)?.contains("--agent-hook cursorAgent turnStarted") == true)
        #expect(promptHooks[0]["bash"] == nil)
        #expect(promptHooks[0]["hooks"] == nil)
    }

    @Test("user hook installation creates a private backup and can be fully removed")
    func userHookInstaller() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-agent-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let configURL = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("{\"theme\":\"dark\"}".utf8)
        try original.write(to: configURL)
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first(where: { $0.kind == .claudeCode })
        )
        let installer = UserHookIntegrationInstaller()

        try installer.install(
            adapter: adapter,
            hookExecutable: "/Applications/Breath.app/Contents/MacOS/Breath",
            homeDirectory: home
        )

        let backupURL = URL(fileURLWithPath: configURL.path + ".breath-backup")
        #expect(try Data(contentsOf: backupURL) == original)
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions]
                as? NSNumber
        ).intValue
        #expect(mode & 0o777 == 0o600)

        try installer.uninstall(adapter: adapter, homeDirectory: home)
        let current = try Data(contentsOf: configURL)
        let root = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        #expect(root["theme"] as? String == "dark")
        #expect((root["hooks"] as? [String: Any])?.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
    }

    @Test("uninstall removes hook config files that Breath created from scratch")
    func uninstallNewHookConfiguration() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-new-hook-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = UserHookIntegrationInstaller()

        for kind in [AgentKind.githubCopilotCLI, .cursorAgent] {
            let adapter = try #require(
                AgentAdapterRegistry.builtIn.adapters.first(where: { $0.kind == kind })
            )
            let relativePath = String(adapter.userConfigurationPath.dropFirst(2))
            let configURL = home.appendingPathComponent(relativePath)

            try installer.install(
                adapter: adapter,
                hookExecutable: "/Applications/Breath.app/Contents/MacOS/Breath",
                homeDirectory: home
            )
            #expect(FileManager.default.fileExists(atPath: configURL.path))

            try installer.uninstall(adapter: adapter, homeDirectory: home)
            #expect(!FileManager.default.fileExists(atPath: configURL.path))
        }
    }

    @Test("official hook payloads are reduced to metadata before entering Breath")
    func hookPayloadSanitization() throws {
        let raw = Data(
            """
            {
              "session_id":"agent-session-7",
              "cwd":"/tmp/project",
              "title":"Fix navigation",
              "prompt":"private prompt",
              "last_assistant_message":"private reply",
              "tool_input":{"command":"secret"},
              "transcript_path":"/tmp/private.jsonl"
            }
            """.utf8
        )
        let workspaceID = WorkspaceID(rawValue: UUID())
        let workSessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        let factory = AgentHookEventFactory(now: { Date(timeIntervalSince1970: 42) })

        let event = try #require(
            try factory.makeEvent(
                agent: .claudeCode,
                lifecycle: .turnStarted,
                rawPayload: raw,
                environment: [
                    "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
                    "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
                    "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
                    "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
                ]
            )
        )

        #expect(event.sessionID == "agent-session-7")
        #expect(event.applicationInstanceID == applicationInstanceID)
        #expect(event.nativeTitle == "Fix navigation")
        #expect(event.workingDirectory == "/tmp/project")
        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        #expect(!encoded.contains("private prompt"))
        #expect(!encoded.contains("private reply"))
        #expect(!encoded.contains("secret"))
        #expect(!encoded.contains("transcript"))

        #expect(
            try factory.makeEvent(
                agent: .claudeCode,
                lifecycle: .turnStarted,
                rawPayload: raw,
                environment: [:]
            ) == nil
        )
    }

    @Test("all nine official hook payload shapes reduce to resumable metadata")
    func supportedHookPayloadShapes() throws {
        struct Sample {
            let agent: AgentKind
            let object: [String: Any]
            let sessionID: String
            let title: String?
            let workingDirectory: String
        }

        let samples = [
            Sample(
                agent: .codex,
                object: ["thread_id": "codex-1", "thread_title": "Review patch", "cwd": "/tmp/codex"],
                sessionID: "codex-1",
                title: "Review patch",
                workingDirectory: "/tmp/codex"
            ),
            Sample(
                agent: .claudeCode,
                object: ["session_id": "claude-1", "cwd": "/tmp/claude", "transcript_path": "/private/transcript"],
                sessionID: "claude-1",
                title: nil,
                workingDirectory: "/tmp/claude"
            ),
            Sample(
                agent: .geminiCLI,
                object: ["session_id": "gemini-1", "cwd": "/tmp/gemini"],
                sessionID: "gemini-1",
                title: nil,
                workingDirectory: "/tmp/gemini"
            ),
            Sample(
                agent: .githubCopilotCLI,
                object: ["sessionId": "copilot-1", "cwd": "/tmp/copilot"],
                sessionID: "copilot-1",
                title: nil,
                workingDirectory: "/tmp/copilot"
            ),
            Sample(
                agent: .qwenCode,
                object: ["session_id": "qwen-1", "cwd": "/tmp/qwen"],
                sessionID: "qwen-1",
                title: nil,
                workingDirectory: "/tmp/qwen"
            ),
            Sample(
                agent: .cursorAgent,
                object: ["conversation_id": "cursor-1", "workspace_roots": ["/tmp/cursor"]],
                sessionID: "cursor-1",
                title: nil,
                workingDirectory: "/tmp/cursor"
            ),
            Sample(
                agent: .factoryDroid,
                object: ["session_id": "droid-1", "cwd": "/tmp/droid"],
                sessionID: "droid-1",
                title: nil,
                workingDirectory: "/tmp/droid"
            ),
            Sample(
                agent: .openCode,
                object: [
                    "properties": [
                        "info": ["id": "opencode-1", "title": "Refactor module", "directory": "/tmp/opencode"]
                    ]
                ],
                sessionID: "opencode-1",
                title: "Refactor module",
                workingDirectory: "/tmp/opencode"
            ),
            Sample(
                agent: .pi,
                object: ["session": ["id": "pi-1", "title": "Fix parser", "cwd": "/tmp/pi"]],
                sessionID: "pi-1",
                title: "Fix parser",
                workingDirectory: "/tmp/pi"
            ),
        ]
        let workspaceID = WorkspaceID(rawValue: UUID())
        let workSessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        let environment = [
            "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
            "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
            "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
            "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
        ]
        let factory = AgentHookEventFactory(now: { Date(timeIntervalSince1970: 42) })

        for sample in samples {
            let payload = try JSONSerialization.data(withJSONObject: sample.object)
            let event = try #require(
                try factory.makeEvent(
                    agent: sample.agent,
                    lifecycle: .turnStarted,
                    rawPayload: payload,
                    environment: environment
                )
            )
            #expect(event.agent == sample.agent)
            #expect(event.sessionID == sample.sessionID)
            #expect(event.nativeTitle == sample.title)
            #expect(event.workingDirectory == sample.workingDirectory)
        }
    }

    @Test("Codex hook events resolve the generated thread title from its session index")
    func codexSessionIndexTitle() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-codex-title-\(UUID().uuidString)", isDirectory: true)
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )
        try Data(
            """
            {"id":"another-session","thread_name":"Other title","updated_at":"2026-07-15T00:00:00Z"}
            {"id":"codex-session-1","thread_name":"修复会话标题","updated_at":"2026-07-15T00:01:00Z"}
            """.utf8
        ).write(to: codexDirectory.appendingPathComponent("session_index.jsonl"))

        let workspaceID = WorkspaceID(rawValue: UUID())
        let workSessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        let payload = Data(
            """
            {"session_id":"codex-session-1","cwd":"/tmp/project","prompt":"private prompt"}
            """.utf8
        )
        let event = try #require(
            try AgentHookEventFactory(now: { Date(timeIntervalSince1970: 42) }).makeEvent(
                agent: .codex,
                lifecycle: .turnCompleted,
                rawPayload: payload,
                environment: [
                    "HOME": home.path,
                    "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
                    "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
                    "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
                    "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
                ]
            )
        )

        #expect(event.nativeTitle == "修复会话标题")
        #expect(!String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
            .contains("private prompt"))
    }

    @Test("Codex hook events resolve current thread titles from its state database")
    func codexStateDatabaseTitle() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-codex-state-title-\(UUID().uuidString)", isDirectory: true)
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(
            at: codexDirectory,
            withIntermediateDirectories: true
        )

        let database = try DatabaseQueue(
            path: codexDirectory.appendingPathComponent("state_5.sqlite").path
        )
        try database.write { db in
            try db.create(table: "threads") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
            }
            try db.execute(
                sql: "INSERT INTO threads (id, title) VALUES (?, ?)",
                arguments: ["codex-session-2", "  总结   当前对话  "]
            )
        }

        let workspaceID = WorkspaceID(rawValue: UUID())
        let workSessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        let payload = Data(
            """
            {"session_id":"codex-session-2","cwd":"/tmp/project","prompt":"private prompt"}
            """.utf8
        )
        let event = try #require(
            try AgentHookEventFactory(now: { Date(timeIntervalSince1970: 42) }).makeEvent(
                agent: .codex,
                lifecycle: .turnCompleted,
                rawPayload: payload,
                environment: [
                    "HOME": home.path,
                    "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
                    "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
                    "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
                    "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
                ]
            )
        )

        #expect(event.nativeTitle == "总结 当前对话")
        #expect(!String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
            .contains("private prompt"))
    }

    @Test("OpenCode plugin and Pi extension installation are private and reversible")
    func scriptIntegrations() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-script-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = ScriptIntegrationInstaller()

        for kind in [AgentKind.openCode, .pi] {
            let adapter = try #require(
                AgentAdapterRegistry.builtIn.adapters.first(where: { $0.kind == kind })
            )
            try installer.install(
                adapter: adapter,
                hookExecutable: "/Applications/Breath.app/Contents/MacOS/Breath",
                homeDirectory: home
            )
            let relativePath = String(adapter.userConfigurationPath.dropFirst(2))
            let url = home.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(source.contains(adapter.kind.rawValue))
            #expect(source.contains("/Applications/Breath.app/Contents/MacOS/Breath"))
            #expect(!source.contains("transcript"))
            #expect(!source.contains("tool_input"))
            if kind == .pi {
                #expect(source.contains("getSessionId"))
                #expect(!source.contains("getSessionFile"))
            }
            if kind == .openCode {
                #expect(source.contains("properties.status?.type !== \"busy\""))
            }
            let mode = try #require(
                FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
                    as? NSNumber
            ).intValue
            #expect(mode & 0o777 == 0o600)

            try installer.uninstall(adapter: adapter, homeDirectory: home)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}
