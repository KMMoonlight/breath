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
        switch binding.agent {
        case .codex:
            return AgentResumeCommand(executable: "codex", arguments: ["resume", sessionID])
        case .claudeCode:
            return AgentResumeCommand(executable: "claude", arguments: ["--resume", sessionID])
        case .geminiCLI:
            return AgentResumeCommand(executable: "gemini", arguments: ["--resume", sessionID])
        case .githubCopilotCLI:
            return AgentResumeCommand(executable: "copilot", arguments: ["--resume", sessionID])
        case .qwenCode:
            return AgentResumeCommand(executable: "qwen", arguments: ["--resume", sessionID])
        case .cursorAgent:
            return AgentResumeCommand(executable: "cursor-agent", arguments: ["--resume", sessionID])
        case .factoryDroid:
            return AgentResumeCommand(executable: "droid", arguments: ["--resume", sessionID])
        case .openCode:
            return AgentResumeCommand(executable: "opencode", arguments: ["--session", sessionID])
        case .pi:
            return AgentResumeCommand(executable: "pi", arguments: ["--session", sessionID])
        }
    }
}

public enum AgentIntegrationMechanism: String, Equatable, Sendable {
    case userHooks
    case plugin
    case `extension`
    case terminalParsing
}

public struct AgentAdapterDescriptor: Equatable, Sendable {
    public let kind: AgentKind
    public let displayName: String
    public let minimumVersion: String
    public let integrationMechanism: AgentIntegrationMechanism
    public let userConfigurationPath: String
    public let hookRegistrations: [AgentHookRegistration]

    public init(
        kind: AgentKind,
        displayName: String,
        minimumVersion: String,
        integrationMechanism: AgentIntegrationMechanism,
        userConfigurationPath: String,
        hookRegistrations: [AgentHookRegistration]
    ) {
        self.kind = kind
        self.displayName = displayName
        self.minimumVersion = minimumVersion
        self.integrationMechanism = integrationMechanism
        self.userConfigurationPath = userConfigurationPath
        self.hookRegistrations = hookRegistrations
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
            hookRegistrations: standardHooks
        ),
        AgentAdapterDescriptor(
            kind: .claudeCode,
            displayName: "Claude Code",
            minimumVersion: "2.1.7",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.claude/settings.json",
            hookRegistrations: standardHooks
        ),
        AgentAdapterDescriptor(
            kind: .geminiCLI,
            displayName: "Gemini CLI",
            minimumVersion: "0.37.2",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.gemini/settings.json",
            hookRegistrations: [
                AgentHookRegistration(eventName: "BeforeAgent", lifecycle: .turnStarted),
                AgentHookRegistration(eventName: "AfterAgent", lifecycle: .turnCompleted),
                AgentHookRegistration(eventName: "Notification", lifecycle: .needsAttention),
                AgentHookRegistration(eventName: "SessionEnd", lifecycle: .sessionEnded),
            ]
        ),
        AgentAdapterDescriptor(
            kind: .githubCopilotCLI,
            displayName: "GitHub Copilot CLI",
            minimumVersion: "1.0.45",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.copilot/hooks/breath.json",
            hookRegistrations: [
                AgentHookRegistration(eventName: "userPromptSubmitted", lifecycle: .turnStarted),
                AgentHookRegistration(eventName: "permissionRequest", lifecycle: .needsAttention),
                AgentHookRegistration(eventName: "agentStop", lifecycle: .turnCompleted),
                AgentHookRegistration(eventName: "sessionEnd", lifecycle: .sessionEnded),
            ]
        ),
        AgentAdapterDescriptor(
            kind: .qwenCode,
            displayName: "Qwen Code",
            minimumVersion: "0.16.2",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.qwen/settings.json",
            hookRegistrations: standardHooks
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
            ]
        ),
        AgentAdapterDescriptor(
            kind: .factoryDroid,
            displayName: "Factory Droid",
            minimumVersion: "未版本化（2026-07 Hooks 文档）",
            integrationMechanism: .userHooks,
            userConfigurationPath: "~/.factory/settings.json",
            hookRegistrations: standardHooks
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
                AgentHookRegistration(eventName: "session.idle", lifecycle: .turnCompleted),
            ]
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
            ]
        ),
    ])

    private static let standardHooks = [
        AgentHookRegistration(eventName: "UserPromptSubmit", lifecycle: .turnStarted),
        AgentHookRegistration(eventName: "PermissionRequest", lifecycle: .needsAttention),
        AgentHookRegistration(eventName: "Stop", lifecycle: .turnCompleted),
        AgentHookRegistration(eventName: "SessionEnd", lifecycle: .sessionEnded),
    ]
}
