import BreathCore
import Foundation

private func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
}

private func agentHookCommand(
    executable: String,
    agent: AgentKind,
    lifecycle: AgentLifecycle
) -> String {
    "\(shellQuoted(executable)) --agent-hook \(agent.rawValue) \(lifecycle.rawValue)"
}

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
    case invalidEncoding
    case invalidManagedBlock
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
        var changed = false

        for registration in registrations {
            var entries = hooks[registration.eventName] as? [[String: Any]] ?? []
            let command = agentHookCommand(
                executable: hookExecutable,
                agent: agent,
                lifecycle: registration.lifecycle
            )
            var found = false
            for entryIndex in entries.indices {
                guard var handlers = entries[entryIndex]["hooks"] as? [[String: Any]] else {
                    continue
                }
                for handlerIndex in handlers.indices where isBreathHandler(
                    handlers[handlerIndex],
                    lifecycle: registration.lifecycle,
                    agent: agent
                ) {
                    if handlers[handlerIndex]["command"] as? String != command {
                        handlers[handlerIndex]["command"] = command
                        changed = true
                    }
                    found = true
                }
                entries[entryIndex]["hooks"] = handlers
            }
            if !found {
                entries.append([
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "name": "Breath",
                        "command": command,
                    ]],
                ])
                changed = true
            }
            hooks[registration.eventName] = entries
        }
        guard changed else { return data }
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

    private func isBreathHandler(
        _ command: [String: Any],
        lifecycle: AgentLifecycle?,
        agent: AgentKind? = nil
    ) -> Bool {
        guard command["type"] as? String == "command",
              command["name"] as? String == "Breath",
              let value = command["command"] as? String,
              value.contains(" --agent-hook ")
        else {
            return false
        }
        if let agent, !value.contains(" --agent-hook \(agent.rawValue) ") {
            return false
        }
        guard let lifecycle else { return true }
        return value.hasSuffix(" \(lifecycle.rawValue)")
    }
}

public struct AntigravityHookConfigurationEditor: Sendable {
    private static let integrationName = "breath-agent-integration"

    public init() {}

    public func install(
        in data: Data,
        registrations: [AgentHookRegistration],
        hookExecutable: String,
        agent: AgentKind
    ) throws -> Data {
        var root = try rootObject(from: data)
        guard root[Self.integrationName] == nil
                || root[Self.integrationName] is [String: Any]
        else {
            throw HookConfigurationError.invalidHooks
        }
        var integration = root[Self.integrationName] as? [String: Any] ?? [:]
        var changed = false

        for registration in registrations {
            var handlers = integration[registration.eventName] as? [[String: Any]] ?? []
            let command = agentHookCommand(
                executable: hookExecutable,
                agent: agent,
                lifecycle: registration.lifecycle
            )
            if let index = handlers.firstIndex(where: {
                isBreathHandler(
                    $0,
                    lifecycle: registration.lifecycle,
                    agent: agent
                )
            }) {
                if handlers[index]["command"] as? String != command {
                    handlers[index]["command"] = command
                    changed = true
                }
            } else {
                handlers.append([
                    "type": "command",
                    "command": command,
                    "timeout": 5,
                ])
                changed = true
            }
            integration[registration.eventName] = handlers
        }

        guard changed else { return data }
        root[Self.integrationName] = integration
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    public func uninstall(from data: Data) throws -> Data {
        var root = try rootObject(from: data)
        guard var integration = root[Self.integrationName] as? [String: Any] else {
            return data
        }

        for eventName in Array(integration.keys) {
            guard let handlers = integration[eventName] as? [[String: Any]] else {
                continue
            }
            let remaining = handlers.filter {
                !isBreathHandler($0, lifecycle: nil, agent: .antigravityCLI)
            }
            if remaining.isEmpty {
                integration.removeValue(forKey: eventName)
            } else {
                integration[eventName] = remaining
            }
        }

        if integration.isEmpty {
            root.removeValue(forKey: Self.integrationName)
        } else {
            root[Self.integrationName] = integration
        }
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func rootObject(from data: Data) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookConfigurationError.invalidRoot
        }
        return root
    }

    private func isBreathHandler(
        _ handler: [String: Any],
        lifecycle: AgentLifecycle?,
        agent: AgentKind
    ) -> Bool {
        guard handler["type"] as? String == "command",
              let command = handler["command"] as? String,
              command.contains(" --agent-hook \(agent.rawValue) ")
        else {
            return false
        }
        guard let lifecycle else { return true }
        return command.hasSuffix(" \(lifecycle.rawValue)")
    }
}

public struct KimiHookConfigurationEditor: Sendable {
    private static let beginMarker = "# BEGIN Breath Agent Integration"
    private static let endMarker = "# END Breath Agent Integration"

    public init() {}

    public func install(
        in data: Data,
        registrations: [AgentHookRegistration],
        hookExecutable: String,
        agent: AgentKind
    ) throws -> Data {
        guard let source = String(data: data, encoding: .utf8) else {
            throw HookConfigurationError.invalidEncoding
        }
        var result = try removingManagedBlock(from: source)
        if !result.isEmpty && !result.hasSuffix("\n") {
            result.append("\n")
        }
        result.append(Self.beginMarker)
        result.append("\n")
        for registration in registrations {
            let command = agentHookCommand(
                executable: hookExecutable,
                agent: agent,
                lifecycle: registration.lifecycle
            )
            result.append(
                """
                [[hooks]]
                event = "\(tomlString(registration.eventName))"
                command = "\(tomlString(command))"
                timeout = 5

                """
            )
        }
        result.append(Self.endMarker)
        result.append("\n")
        return Data(result.utf8)
    }

    public func uninstall(from data: Data) throws -> Data {
        guard let source = String(data: data, encoding: .utf8) else {
            throw HookConfigurationError.invalidEncoding
        }
        return Data(try removingManagedBlock(from: source).utf8)
    }

    private func removingManagedBlock(from source: String) throws -> String {
        let begin = source.range(of: Self.beginMarker)
        let end = source.range(of: Self.endMarker)
        guard (begin == nil) == (end == nil) else {
            throw HookConfigurationError.invalidManagedBlock
        }
        guard let begin, let end, begin.lowerBound < end.lowerBound else {
            if begin == nil && end == nil { return source }
            throw HookConfigurationError.invalidManagedBlock
        }
        var upperBound = end.upperBound
        if upperBound < source.endIndex, source[upperBound] == "\n" {
            upperBound = source.index(after: upperBound)
        }
        var result = source
        result.removeSubrange(begin.lowerBound..<upperBound)
        return result
    }

    private func tomlString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
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
        var changed = false
        if root["version"] as? Int != 1 {
            root["version"] = 1
            changed = true
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for registration in registrations {
            var entries = hooks[registration.eventName] as? [[String: Any]] ?? []
            let command = agentHookCommand(
                executable: hookExecutable,
                agent: agent,
                lifecycle: registration.lifecycle
            )
            var found = false
            for entryIndex in entries.indices where isBreathEntry(entries[entryIndex]) {
                switch style {
                case .copilotCLI:
                    if entries[entryIndex]["bash"] as? String != command {
                        entries[entryIndex]["bash"] = command
                        changed = true
                    }
                case .cursor:
                    if entries[entryIndex]["command"] as? String != command {
                        entries[entryIndex]["command"] = command
                        changed = true
                    }
                }
                found = true
            }
            if !found {
                entries.append(entry(command: command))
                changed = true
            }
            hooks[registration.eventName] = entries
        }

        guard changed else { return data }
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

}

public enum AgentIntegrationInstallationError: Error, Equatable {
    case unsupportedMechanism(AgentIntegrationMechanism)
    case pathOutsideHome(String)
}

public extension AgentAdapterDescriptor {
    func resolvedUserConfigurationURL(
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if kind == .kimiCode,
           let configuredRoot = environment["KIMI_CODE_HOME"],
           !configuredRoot.isEmpty
        {
            let rootURL: URL
            if configuredRoot.hasPrefix("/") {
                rootURL = URL(
                    fileURLWithPath: configuredRoot,
                    isDirectory: true
                )
            } else if configuredRoot == "~" {
                rootURL = homeDirectory
            } else if configuredRoot.hasPrefix("~/") {
                rootURL = homeDirectory.appendingPathComponent(
                    String(configuredRoot.dropFirst(2)),
                    isDirectory: true
                )
            } else {
                rootURL = homeDirectory.appendingPathComponent(
                    configuredRoot,
                    isDirectory: true
                )
            }
            return rootURL.standardizedFileURL.appendingPathComponent("config.toml")
        }
        guard userConfigurationPath.hasPrefix("~/") else {
            throw AgentIntegrationInstallationError.pathOutsideHome(
                userConfigurationPath
            )
        }
        return homeDirectory.appendingPathComponent(
            String(userConfigurationPath.dropFirst(2))
        )
    }
}

public struct UserHookIntegrationInstaller: Sendable {
    private let editor = JSONHookConfigurationEditor()

    public init() {}

    public func install(
        adapter: AgentAdapterDescriptor,
        hookExecutable: String,
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard adapter.integrationMechanism == .userHooks else {
            throw AgentIntegrationInstallationError.unsupportedMechanism(
                adapter.integrationMechanism
            )
        }
        let configURL = try adapter.resolvedUserConfigurationURL(
            homeDirectory: homeDirectory,
            environment: environment
        )
        let directoryURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let existed = FileManager.default.fileExists(atPath: configURL.path)
        let original: Data
        if existed {
            original = try Data(contentsOf: configURL)
        } else {
            original = adapter.kind == .kimiCode ? Data() : Data("{}".utf8)
        }
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
        if installed != original {
            try installed.write(to: configURL, options: .atomic)
        }
        try setPrivatePermissions(on: configURL)
        if adapter.kind == .antigravityCLI {
            try migrateLegacyGeminiIntegration(homeDirectory: homeDirectory)
        }
    }

    public func uninstall(
        adapter: AgentAdapterDescriptor,
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard adapter.integrationMechanism == .userHooks else {
            throw AgentIntegrationInstallationError.unsupportedMechanism(
                adapter.integrationMechanism
            )
        }
        let configURL = try adapter.resolvedUserConfigurationURL(
            homeDirectory: homeDirectory,
            environment: environment
        )
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }
        let backupURL = backupURL(for: configURL)
        let existedBeforeBreath = FileManager.default.fileExists(atPath: backupURL.path)
        let updated = try uninstall(
            from: Data(contentsOf: configURL),
            adapter: adapter
        )
        if !existedBeforeBreath,
           try generatedConfigurationIsEmpty(updated, adapter: adapter)
        {
            try FileManager.default.removeItem(at: configURL)
        } else {
            try updated.write(to: configURL, options: .atomic)
            try setPrivatePermissions(on: configURL)
        }

        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
    }

    private func install(
        in data: Data,
        adapter: AgentAdapterDescriptor,
        hookExecutable: String
    ) throws -> Data {
        switch adapter.kind {
        case .antigravityCLI:
            return try AntigravityHookConfigurationEditor().install(
                in: data,
                registrations: adapter.hookRegistrations,
                hookExecutable: hookExecutable,
                agent: adapter.kind
            )
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
        case .kimiCode:
            return try KimiHookConfigurationEditor().install(
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
        case .antigravityCLI:
            try AntigravityHookConfigurationEditor().uninstall(from: data)
        case .githubCopilotCLI:
            try FlatJSONHookConfigurationEditor(style: .copilotCLI).uninstall(from: data)
        case .cursorAgent:
            try FlatJSONHookConfigurationEditor(style: .cursor).uninstall(from: data)
        case .kimiCode:
            try KimiHookConfigurationEditor().uninstall(from: data)
        default:
            try editor.uninstall(from: data)
        }
    }

    private func generatedConfigurationIsEmpty(
        _ data: Data,
        adapter: AgentAdapterDescriptor
    ) throws -> Bool {
        if adapter.kind == .kimiCode {
            guard let contents = String(data: data, encoding: .utf8) else {
                throw HookConfigurationError.invalidEncoding
            }
            return contents.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }

        guard let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            throw HookConfigurationError.invalidRoot
        }
        if adapter.kind == .antigravityCLI {
            return root.isEmpty
        }
        let hooksAreEmpty = (root["hooks"] as? [String: Any])?.isEmpty == true
        return hooksAreEmpty && Set(root.keys).isSubset(of: ["hooks", "version"])
    }

    private func backupURL(for configURL: URL) -> URL {
        URL(fileURLWithPath: configURL.path + ".breath-backup")
    }

    private func migrateLegacyGeminiIntegration(
        homeDirectory: URL
    ) throws {
        let configURL = homeDirectory.appendingPathComponent(
            ".gemini/settings.json"
        )
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }
        let original = try Data(contentsOf: configURL)
        guard let updated = try? editor.uninstall(from: original) else {
            return
        }
        let backupURL = backupURL(for: configURL)
        let existedBeforeBreath = FileManager.default.fileExists(
            atPath: backupURL.path
        )
        guard let root = try JSONSerialization.jsonObject(with: updated)
                as? [String: Any]
        else {
            throw HookConfigurationError.invalidRoot
        }
        let hooksAreEmpty = (root["hooks"] as? [String: Any])?.isEmpty == true
        let generatedConfigurationIsEmpty =
            hooksAreEmpty
                && Set(root.keys).isSubset(of: ["hooks", "version"])

        if !existedBeforeBreath && generatedConfigurationIsEmpty {
            try FileManager.default.removeItem(at: configURL)
        } else if updated != original {
            try updated.write(to: configURL, options: .atomic)
            try setPrivatePermissions(on: configURL)
        }
        if existedBeforeBreath {
            try FileManager.default.removeItem(at: backupURL)
        }
    }

    private func setPrivatePermissions(on url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let permissions = attributes[.posixPermissions] as? NSNumber,
           permissions.intValue & 0o777 == 0o600
        {
            return
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
