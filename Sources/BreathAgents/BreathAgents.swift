import BreathCore
import Foundation

public enum AgentEventDecodingError: Error, Equatable, Sendable {
    case invalidTopLevel
    case unexpectedFields([String])
}

public struct StrictAgentEventDecoder: Sendable {
    private static let allowedFields: Set<String> = [
        "applicationInstanceID",
        "agent",
        "version",
        "lifecycle",
        "occurredAt",
        "workspaceID",
        "workSessionID",
        "paneID",
        "noteLibraryID",
        "noteAgentConversationID",
        "noteAgentTerminalID",
        "sessionID",
        "nativeTitle",
        "workingDirectory",
    ]

    public init() {}

    public func decode(_ data: Data) throws -> AgentEvent {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentEventDecodingError.invalidTopLevel
        }

        let unexpectedFields = Set(object.keys)
            .subtracting(Self.allowedFields)
            .sorted()
        guard unexpectedFields.isEmpty else {
            throw AgentEventDecodingError.unexpectedFields(unexpectedFields)
        }

        return try JSONDecoder().decode(AgentEvent.self, from: data)
    }
}

public struct BuiltInAgentResumeCommands: AgentResumeCommandProviding, Sendable {
    public init() {}

    public func resumeCommand(for binding: AgentBinding) -> AgentResumeCommand? {
        guard let sessionID = binding.sessionID, !sessionID.isEmpty else {
            return nil
        }
        let executable = binding.agent.cliExecutableName
        switch binding.agent {
        case .codex:
            return AgentResumeCommand(executable: executable, arguments: ["resume", sessionID])
        case .claudeCode:
            return AgentResumeCommand(executable: executable, arguments: ["--resume", sessionID])
        case .antigravityCLI:
            return AgentResumeCommand(
                executable: executable,
                arguments: ["--conversation", sessionID]
            )
        case .githubCopilotCLI:
            return AgentResumeCommand(executable: executable, arguments: ["--resume", sessionID])
        case .qwenCode:
            return AgentResumeCommand(executable: executable, arguments: ["--resume", sessionID])
        case .cursorAgent:
            return AgentResumeCommand(executable: executable, arguments: ["--resume", sessionID])
        case .factoryDroid:
            return AgentResumeCommand(executable: executable, arguments: ["--resume", sessionID])
        case .openCode:
            return AgentResumeCommand(executable: executable, arguments: ["--session", sessionID])
        case .pi:
            return AgentResumeCommand(executable: executable, arguments: ["--session", sessionID])
        case .kimiCode:
            return AgentResumeCommand(executable: executable, arguments: ["--session", sessionID])
        }
    }
}

public extension AgentKind {
    var cliExecutableName: String {
        switch self {
        case .codex: "codex"
        case .claudeCode: "claude"
        case .antigravityCLI: "agy"
        case .githubCopilotCLI: "copilot"
        case .qwenCode: "qwen"
        case .cursorAgent: "cursor-agent"
        case .factoryDroid: "droid"
        case .openCode: "opencode"
        case .pi: "pi"
        case .kimiCode: "kimi"
        }
    }
}

public enum AgentIntegrationMechanism: String, Equatable, Sendable {
    case userHooks
    case plugin
    case `extension`
    case terminalParsing
}

public struct AgentGlobalSkillsCapability: Equatable, Sendable {
    public let configurationRootEnvironmentVariable: String?
    public let defaultConfigurationRootRelativePath: String
    public let skillsRelativePath: String
    public let additionalDiscoveryRootRelativePaths: [String]
    public let activationHint: String

    public init(
        configurationRootEnvironmentVariable: String? = nil,
        defaultConfigurationRootRelativePath: String,
        skillsRelativePath: String = "skills",
        additionalDiscoveryRootRelativePaths: [String] = [],
        activationHint: String
    ) {
        self.configurationRootEnvironmentVariable = configurationRootEnvironmentVariable
        self.defaultConfigurationRootRelativePath = defaultConfigurationRootRelativePath
        self.skillsRelativePath = skillsRelativePath
        self.additionalDiscoveryRootRelativePaths = additionalDiscoveryRootRelativePaths
        self.activationHint = activationHint
    }

    public func resolveDirectory(
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        reliablyResolveDirectory(
            homeDirectory: homeDirectory,
            environment: environment
        ) ?? homeDirectory.appendingPathComponent(
            defaultConfigurationRootRelativePath,
            isDirectory: true
        ).appendingPathComponent(skillsRelativePath, isDirectory: true)
            .standardizedFileURL
    }

    public func reliablyResolveDirectory(
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let configurationRoot: URL
        if let configurationRootEnvironmentVariable,
           let rawRoot = environment[configurationRootEnvironmentVariable],
           !rawRoot.isEmpty
        {
            guard NSString(string: rawRoot).isAbsolutePath else { return nil }
            configurationRoot = URL(fileURLWithPath: rawRoot, isDirectory: true)
        } else {
            configurationRoot = homeDirectory.appendingPathComponent(
                defaultConfigurationRootRelativePath,
                isDirectory: true
            )
        }
        return configurationRoot
            .appendingPathComponent(skillsRelativePath, isDirectory: true)
            .standardizedFileURL
    }

    public func resolveDiscoveryDirectories(
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        var directories = reliablyResolveDirectory(
            homeDirectory: homeDirectory,
            environment: environment
        ).map { [$0] } ?? []
        directories.append(contentsOf: additionalDiscoveryRootRelativePaths.map {
            homeDirectory.appendingPathComponent($0, isDirectory: true).standardizedFileURL
        })
        var seen: Set<String> = []
        return directories.filter { seen.insert($0.path).inserted }
    }
}

public struct AgentAdapterDescriptor: Equatable, Sendable {
    public let kind: AgentKind
    public let displayName: String
    public let minimumVersion: String
    public let integrationMechanism: AgentIntegrationMechanism
    public let userConfigurationPath: String
    public let hookRegistrations: [AgentHookRegistration]
    public let globalSkills: AgentGlobalSkillsCapability?
    public let automation: AgentAutomationCapability?

    public init(
        kind: AgentKind,
        displayName: String,
        minimumVersion: String,
        integrationMechanism: AgentIntegrationMechanism,
        userConfigurationPath: String,
        hookRegistrations: [AgentHookRegistration],
        globalSkills: AgentGlobalSkillsCapability? = nil,
        automation: AgentAutomationCapability? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.minimumVersion = minimumVersion
        self.integrationMechanism = integrationMechanism
        self.userConfigurationPath = userConfigurationPath
        self.hookRegistrations = hookRegistrations
        self.globalSkills = globalSkills
        self.automation = automation
    }
}

public enum AgentAutomationInvocation: String, Equatable, Sendable {
    case codex
    case claudeCode
    case githubCopilotCLI
    case qwenCode
    case cursorAgent
    case factoryDroid
    case openCode
    case pi
    case kimiCode
}

public struct AgentAutomationCapability: Equatable, Sendable {
    public let minimumVersion: String
    public let invocation: AgentAutomationInvocation

    public init(
        minimumVersion: String,
        invocation: AgentAutomationInvocation
    ) {
        self.minimumVersion = minimumVersion
        self.invocation = invocation
    }

    public var usesFinalOutputFile: Bool {
        invocation == .codex
    }

    public func arguments(
        prompt: String,
        finalOutputPath: String
    ) -> [String] {
        switch invocation {
        case .codex:
            [
                "exec",
                // Breath supplies the outer sandbox and fixed approval policy.
                // A nested Codex sandbox fails with sandbox_apply on macOS.
                "--dangerously-bypass-approvals-and-sandbox",
                "--ephemeral",
                "--skip-git-repo-check",
                "--color", "never",
                "--output-last-message", finalOutputPath,
                prompt,
            ]
        case .claudeCode:
            [
                "-p", prompt,
                "--output-format", "json",
                "--permission-mode", "dontAsk",
                "--no-session-persistence",
            ]
        case .githubCopilotCLI:
            [
                "-p", prompt,
                "--output-format", "json",
                "--allow-all-tools",
                "--no-ask-user",
            ]
        case .qwenCode:
            [
                "-p", prompt,
                "--output-format", "json",
                "--approval-mode", "plan",
            ]
        case .cursorAgent:
            [
                "-p", prompt,
                "--output-format", "json",
            ]
        case .factoryDroid:
            [
                "exec", prompt,
                "--output-format", "json",
            ]
        case .openCode:
            [
                "run",
                "--format", "json",
                prompt,
            ]
        case .pi:
            [
                "-p", prompt,
                "--mode", "json",
                "--no-session",
            ]
        case .kimiCode:
            [
                "-p", prompt,
                "--output-format", "text",
            ]
        }
    }
}

public struct AgentAdapterRegistry: Sendable {
    public let adapters: [AgentAdapterDescriptor]

    public init(adapters: [AgentAdapterDescriptor]) {
        self.adapters = adapters
    }

    public static let builtIn = AgentAdapterRegistry(adapters: [
        AgentAdapterDescriptor(
            kind: .codex,
            displayName: "Codex",
            minimumVersion: "0.144.3",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.codex/hooks.json",
            hookRegistrations: standardHooks,
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "CODEX_HOME",
                defaultConfigurationRootRelativePath: ".codex",
                additionalDiscoveryRootRelativePaths: [".agents/skills"],
                activationHint: "Start a new Codex session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "0.144.3",
                invocation: .codex
            )
        ),
        AgentAdapterDescriptor(
            kind: .claudeCode,
            displayName: "Claude Code",
            minimumVersion: "2.1.7",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.claude/settings.json",
            hookRegistrations: [
                AgentHookRegistration(eventName: "SessionStart", lifecycle: .turnStarted),
            ] + standardHooks,
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "CLAUDE_CONFIG_DIR",
                defaultConfigurationRootRelativePath: ".claude",
                activationHint: "Start a new Claude Code session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "2.1.7",
                invocation: .claudeCode
            )
        ),
        AgentAdapterDescriptor(
            kind: .antigravityCLI,
            displayName: "Antigravity CLI",
            minimumVersion: "1.1.8",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.gemini/config/hooks.json",
            hookRegistrations: [
                AgentHookRegistration(eventName: "PreInvocation", lifecycle: .turnStarted),
                AgentHookRegistration(eventName: "Stop", lifecycle: .turnCompleted),
            ],
            globalSkills: AgentGlobalSkillsCapability(
                defaultConfigurationRootRelativePath: ".gemini/antigravity-cli",
                activationHint: "Start a new Antigravity CLI session to load changed Skills."
            ),
            automation: nil
        ),
        AgentAdapterDescriptor(
            kind: .githubCopilotCLI,
            displayName: "GitHub Copilot CLI",
            minimumVersion: "1.0.45",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.copilot/hooks/breath.json",
            hookRegistrations: [
                AgentHookRegistration(eventName: "userPromptSubmitted", lifecycle: .turnStarted),
                AgentHookRegistration(eventName: "preToolUse", lifecycle: .attentionResolved),
                AgentHookRegistration(eventName: "permissionRequest", lifecycle: .needsAttention),
                AgentHookRegistration(eventName: "agentStop", lifecycle: .turnCompleted),
                AgentHookRegistration(eventName: "sessionEnd", lifecycle: .sessionEnded),
            ],
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "COPILOT_HOME",
                defaultConfigurationRootRelativePath: ".copilot",
                activationHint: "Start a new GitHub Copilot CLI session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "1.0.45",
                invocation: .githubCopilotCLI
            )
        ),
        AgentAdapterDescriptor(
            kind: .qwenCode,
            displayName: "Qwen Code",
            minimumVersion: "0.16.2",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.qwen/settings.json",
            hookRegistrations: standardHooks,
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "QWEN_CLI_HOME",
                defaultConfigurationRootRelativePath: ".qwen",
                activationHint: "Start a new Qwen Code session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "0.16.2",
                invocation: .qwenCode
            )
        ),
        AgentAdapterDescriptor(
            kind: .cursorAgent,
            displayName: "Cursor Agent",
            minimumVersion: "2026.01.16",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.cursor/hooks.json",
            hookRegistrations: [
                AgentHookRegistration(eventName: "beforeSubmitPrompt", lifecycle: .turnStarted),
                AgentHookRegistration(eventName: "afterAgentResponse", lifecycle: .turnCompleted),
                AgentHookRegistration(eventName: "stop", lifecycle: .turnCompleted),
                AgentHookRegistration(eventName: "sessionEnd", lifecycle: .sessionEnded),
            ],
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "CURSOR_AGENT_HOME",
                defaultConfigurationRootRelativePath: ".cursor",
                activationHint: "Start a new Cursor Agent session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "2026.01.16",
                invocation: .cursorAgent
            )
        ),
        AgentAdapterDescriptor(
            kind: .factoryDroid,
            displayName: "Factory Droid",
            minimumVersion: "未版本化（2026-07 Hooks 文档）",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.factory/settings.json",
            hookRegistrations: standardHooks,
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "FACTORY_HOME",
                defaultConfigurationRootRelativePath: ".factory",
                activationHint: "Start a new Factory Droid session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "未版本化（2026-07 Headless 文档）",
                invocation: .factoryDroid
            )
        ),
        AgentAdapterDescriptor(
            kind: .openCode,
            displayName: "OpenCode",
            minimumVersion: "1.15.11",
            integrationMechanism: .plugin,
            userConfigurationPath: "~/.config/opencode/plugins/breath.ts",
            hookRegistrations: [
                AgentHookRegistration(eventName: "session.status", lifecycle: .turnStarted),
                AgentHookRegistration(eventName: "session.updated", lifecycle: .metadataUpdated),
                AgentHookRegistration(eventName: "permission.asked", lifecycle: .needsAttention),
                AgentHookRegistration(eventName: "permission.replied", lifecycle: .attentionResolved),
                AgentHookRegistration(eventName: "session.idle", lifecycle: .turnCompleted),
            ],
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "XDG_CONFIG_HOME",
                defaultConfigurationRootRelativePath: ".config",
                skillsRelativePath: "opencode/skills",
                activationHint: "Start a new OpenCode session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "1.15.11",
                invocation: .openCode
            )
        ),
        AgentAdapterDescriptor(
            kind: .pi,
            displayName: "Pi",
            minimumVersion: "未版本化（2026-07 Extension 文档）",
            integrationMechanism: .extension,
            userConfigurationPath: "~/.pi/agent/extensions/breath.ts",
            hookRegistrations: [
                AgentHookRegistration(eventName: "agent_start", lifecycle: .turnStarted),
                AgentHookRegistration(eventName: "agent_end", lifecycle: .turnCompleted),
                AgentHookRegistration(eventName: "session_shutdown", lifecycle: .sessionEnded),
            ],
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "PI_CODING_AGENT_DIR",
                defaultConfigurationRootRelativePath: ".pi/agent",
                activationHint: "Start a new Pi session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "未版本化（2026-07 Headless 文档）",
                invocation: .pi
            )
        ),
        AgentAdapterDescriptor(
            kind: .kimiCode,
            displayName: "Kimi Code",
            minimumVersion: "0.29.2",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.kimi-code/config.toml",
            hookRegistrations: [
                AgentHookRegistration(
                    eventName: "UserPromptSubmit",
                    lifecycle: .turnStarted
                ),
                AgentHookRegistration(
                    eventName: "PermissionRequest",
                    lifecycle: .needsAttention
                ),
                AgentHookRegistration(
                    eventName: "PermissionResult",
                    lifecycle: .attentionResolved
                ),
                AgentHookRegistration(
                    eventName: "Stop",
                    lifecycle: .turnCompleted
                ),
                AgentHookRegistration(
                    eventName: "SessionEnd",
                    lifecycle: .sessionEnded
                ),
            ],
            globalSkills: AgentGlobalSkillsCapability(
                configurationRootEnvironmentVariable: "KIMI_CODE_HOME",
                defaultConfigurationRootRelativePath: ".kimi-code",
                additionalDiscoveryRootRelativePaths: [".agents/skills"],
                activationHint: "Start a new Kimi Code session to load changed Skills."
            ),
            automation: AgentAutomationCapability(
                minimumVersion: "0.29.2",
                invocation: .kimiCode
            )
        ),
    ])

    private static let standardHooks = [
        AgentHookRegistration(eventName: "UserPromptSubmit", lifecycle: .turnStarted),
        AgentHookRegistration(eventName: "PreToolUse", lifecycle: .attentionResolved),
        AgentHookRegistration(eventName: "PermissionRequest", lifecycle: .needsAttention),
        AgentHookRegistration(eventName: "Stop", lifecycle: .turnCompleted),
        AgentHookRegistration(eventName: "SessionEnd", lifecycle: .sessionEnded),
    ]
}
