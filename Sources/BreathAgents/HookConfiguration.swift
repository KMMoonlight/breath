import BreathCore
import Foundation

public struct AgentHookRegistration: Equatable, Sendable {
    public let eventName: String
    public let lifecycle: AgentLifecycle

    public init(eventName: String, lifecycle: AgentLifecycle) {
        self.eventName = eventName
        self.lifecycle = lifecycle
    }
}

public enum HookConfigurationError: Error, Equatable {
    case invalidRoot
    case invalidHooks
}

public struct JSONHookConfigurationEditor: Sendable {
    public init() {}

    public func install(
        in data: Data,
        registrations: [AgentHookRegistration],
        hookExecutable: String,
        agent: AgentKind
    ) throws -> Data {
        var root = try rootObject(from: data)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for registration in registrations {
            var entries = hooks[registration.eventName] as? [[String: Any]] ?? []
            let command = "\(shellQuote(hookExecutable)) --agent-hook \(agent.rawValue) \(registration.lifecycle.rawValue)"
            let exists = entries.contains { entry in
                isBreathEntry(entry, lifecycle: registration.lifecycle)
            }
            if !exists {
                entries.append([
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "name": "Breath",
                        "command": command,
                    ]],
                ])
            }
            hooks[registration.eventName] = entries
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    public func uninstall(from data: Data) throws -> Data {
        var root = try rootObject(from: data)
        guard var hooks = root["hooks"] as? [String: Any] else {
            return try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
        }

        for eventName in Array(hooks.keys) {
            guard let entries = hooks[eventName] as? [[String: Any]] else {
                continue
            }
            let remaining = entries.compactMap(removingBreathHandlers)
            if remaining.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = remaining
            }
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func removingBreathHandlers(
        from entry: [String: Any]
    ) -> [String: Any]? {
        guard let handlers = entry["hooks"] as? [[String: Any]] else {
            return entry
        }
        let remainingHandlers = handlers.filter { handler in
            !isBreathHandler(handler, lifecycle: nil)
        }
        guard !remainingHandlers.isEmpty else { return nil }
        var updated = entry
        updated["hooks"] = remainingHandlers
        return updated
    }

    private func rootObject(from data: Data) throws -> [String: Any] {
        if data.isEmpty {
            return [:]
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookConfigurationError.invalidRoot
        }
        if let hooks = root["hooks"], !(hooks is [String: Any]) {
            throw HookConfigurationError.invalidHooks
        }
        return root
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func isBreathEntry(
        _ entry: [String: Any],
        lifecycle: AgentLifecycle?
    ) -> Bool {
        guard let commands = entry["hooks"] as? [[String: Any]] else { return false }
        return commands.contains { isBreathHandler($0, lifecycle: lifecycle) }
    }

    private func isBreathHandler(
        _ command: [String: Any],
        lifecycle: AgentLifecycle?
    ) -> Bool {
        guard command["type"] as? String == "command",
              command["name"] as? String == "Breath",
              let value = command["command"] as? String,
              value.contains(" --agent-hook ")
        else {
            return false
        }
        guard let lifecycle else { return true }
        return value.hasSuffix(" \(lifecycle.rawValue)")
    }
}

public enum FlatJSONHookStyle: Equatable, Sendable {
    case copilotCLI
    case cursor
}

public struct FlatJSONHookConfigurationEditor: Sendable {
    public let style: FlatJSONHookStyle

    public init(style: FlatJSONHookStyle) {
        self.style = style
    }

    public func install(
        in data: Data,
        registrations: [AgentHookRegistration],
        hookExecutable: String,
        agent: AgentKind
    ) throws -> Data {
        var root = try rootObject(from: data)
        root["version"] = 1
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for registration in registrations {
            var entries = hooks[registration.eventName] as? [[String: Any]] ?? []
            let command = "\(shellQuote(hookExecutable)) --agent-hook \(agent.rawValue) \(registration.lifecycle.rawValue)"
            if !entries.contains(where: isBreathEntry) {
                entries.append(entry(command: command))
            }
            hooks[registration.eventName] = entries
        }

        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    public func uninstall(from data: Data) throws -> Data {
        var root = try rootObject(from: data)
        guard var hooks = root["hooks"] as? [String: Any] else {
            return try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
        }
        for eventName in Array(hooks.keys) {
            guard let entries = hooks[eventName] as? [[String: Any]] else { continue }
            let remaining = entries.filter { !isBreathEntry($0) }
            if remaining.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = remaining
            }
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func entry(command: String) -> [String: Any] {
        switch style {
        case .copilotCLI:
            [
                "type": "command",
                "bash": command,
                "timeoutSec": 5,
            ]
        case .cursor:
            ["command": command]
        }
    }

    private func isBreathEntry(_ entry: [String: Any]) -> Bool {
        let command = switch style {
        case .copilotCLI: entry["bash"] as? String
        case .cursor: entry["command"] as? String
        }
        let agent = switch style {
        case .copilotCLI: AgentKind.githubCopilotCLI.rawValue
        case .cursor: AgentKind.cursorAgent.rawValue
        }
        return command?.contains(" --agent-hook \(agent) ") == true
    }

    private func rootObject(from data: Data) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookConfigurationError.invalidRoot
        }
        if let hooks = root["hooks"], !(hooks is [String: Any]) {
            throw HookConfigurationError.invalidHooks
        }
        return root
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

public enum AgentIntegrationInstallationError: Error, Equatable {
    case unsupportedMechanism(AgentIntegrationMechanism)
    case pathOutsideHome(String)
}

public struct UserHookIntegrationInstaller: Sendable {
    private let editor = JSONHookConfigurationEditor()

    public init() {}

    public func install(
        adapter: AgentAdapterDescriptor,
        hookExecutable: String,
        homeDirectory: URL
    ) throws {
        guard adapter.integrationMechanism == .userHooks else {
            throw AgentIntegrationInstallationError.unsupportedMechanism(
                adapter.integrationMechanism
            )
        }
        let configURL = try resolve(adapter.userConfigurationPath, homeDirectory: homeDirectory)
        let directoryURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let existed = FileManager.default.fileExists(atPath: configURL.path)
        let original = existed ? try Data(contentsOf: configURL) : Data("{}".utf8)
        let backupURL = backupURL(for: configURL)
        if existed && !FileManager.default.fileExists(atPath: backupURL.path) {
            try original.write(to: backupURL, options: .atomic)
            try setPrivatePermissions(on: backupURL)
        }

        let installed = try install(
            in: original,
            adapter: adapter,
            hookExecutable: hookExecutable
        )
        try installed.write(to: configURL, options: .atomic)
        try setPrivatePermissions(on: configURL)
    }

    public func uninstall(
        adapter: AgentAdapterDescriptor,
        homeDirectory: URL
    ) throws {
        guard adapter.integrationMechanism == .userHooks else {
            throw AgentIntegrationInstallationError.unsupportedMechanism(
                adapter.integrationMechanism
            )
        }
        let configURL = try resolve(adapter.userConfigurationPath, homeDirectory: homeDirectory)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }
        let backupURL = backupURL(for: configURL)
        let existedBeforeBreath = FileManager.default.fileExists(atPath: backupURL.path)
        let updated = try uninstall(
            from: Data(contentsOf: configURL),
            adapter: adapter
        )
        let root = try JSONSerialization.jsonObject(with: updated) as? [String: Any]
        let hooksAreEmpty = (root?["hooks"] as? [String: Any])?.isEmpty == true
        let rootKeys = root.map { Set($0.keys) } ?? Set<String>()
        let onlyGeneratedStructure = rootKeys.isSubset(of: ["hooks", "version"])
        if !existedBeforeBreath && hooksAreEmpty && onlyGeneratedStructure {
            try FileManager.default.removeItem(at: configURL)
        } else {
            try updated.write(to: configURL, options: .atomic)
            try setPrivatePermissions(on: configURL)
        }

        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
    }

    private func resolve(_ path: String, homeDirectory: URL) throws -> URL {
        guard path.hasPrefix("~/") else {
            throw AgentIntegrationInstallationError.pathOutsideHome(path)
        }
        return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
    }

    private func install(
        in data: Data,
        adapter: AgentAdapterDescriptor,
        hookExecutable: String
    ) throws -> Data {
        switch adapter.kind {
        case .githubCopilotCLI:
            return try FlatJSONHookConfigurationEditor(style: .copilotCLI).install(
                in: data,
                registrations: adapter.hookRegistrations,
                hookExecutable: hookExecutable,
                agent: adapter.kind
            )
        case .cursorAgent:
            return try FlatJSONHookConfigurationEditor(style: .cursor).install(
                in: data,
                registrations: adapter.hookRegistrations,
                hookExecutable: hookExecutable,
                agent: adapter.kind
            )
        default:
            return try editor.install(
                in: data,
                registrations: adapter.hookRegistrations,
                hookExecutable: hookExecutable,
                agent: adapter.kind
            )
        }
    }

    private func uninstall(
        from data: Data,
        adapter: AgentAdapterDescriptor
    ) throws -> Data {
        switch adapter.kind {
        case .githubCopilotCLI:
            try FlatJSONHookConfigurationEditor(style: .copilotCLI).uninstall(from: data)
        case .cursorAgent:
            try FlatJSONHookConfigurationEditor(style: .cursor).uninstall(from: data)
        default:
            try editor.uninstall(from: data)
        }
    }

    private func backupURL(for configURL: URL) -> URL {
        URL(fileURLWithPath: configURL.path + ".breath-backup")
    }

    private func setPrivatePermissions(on url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
