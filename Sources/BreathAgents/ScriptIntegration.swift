import Foundation

public struct ScriptIntegrationInstaller: Sendable {
    public init() {}

    public func install(
        adapter: AgentAdapterDescriptor,
        hookExecutable: String,
        homeDirectory: URL
    ) throws {
        guard adapter.integrationMechanism == .plugin
                || adapter.integrationMechanism == .extension
        else {
            throw AgentIntegrationInstallationError.unsupportedMechanism(
                adapter.integrationMechanism
            )
        }
        let url = try resolve(adapter.userConfigurationPath, homeDirectory: homeDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let backupURL = URL(fileURLWithPath: url.path + ".breath-backup")
        if FileManager.default.fileExists(atPath: url.path),
           !FileManager.default.fileExists(atPath: backupURL.path)
        {
            try FileManager.default.copyItem(at: url, to: backupURL)
            try makePrivate(backupURL)
        }
        let source = switch adapter.integrationMechanism {
        case .plugin:
            openCodeSource(adapter: adapter, executable: hookExecutable)
        case .extension:
            piSource(adapter: adapter, executable: hookExecutable)
        case .userHooks, .terminalParsing:
            ""
        }
        try Data(source.utf8).write(to: url, options: .atomic)
        try makePrivate(url)
    }

    public func uninstall(
        adapter: AgentAdapterDescriptor,
        homeDirectory: URL
    ) throws {
        let url = try resolve(adapter.userConfigurationPath, homeDirectory: homeDirectory)
        let backupURL = URL(fileURLWithPath: url.path + ".breath-backup")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: backupURL, to: url)
            try makePrivate(url)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func openCodeSource(
        adapter: AgentAdapterDescriptor,
        executable: String
    ) -> String {
        let events = adapter.hookRegistrations.map {
            "  \(jsString($0.eventName)): \(jsString($0.lifecycle.rawValue))"
        }.joined(separator: ",\n")
        return """
        import type { Plugin } from "@opencode-ai/plugin"
        import { spawn } from "node:child_process"

        const executable = \(jsString(executable))
        const agent = \(jsString(adapter.kind.rawValue))
        const lifecycleByEvent: Record<string, string> = {
        \(events)
        }

        function send(lifecycle: string, metadata: Record<string, unknown>) {
          const child = spawn(executable, ["--agent-hook", agent, lifecycle], {
            env: process.env,
            stdio: ["pipe", "ignore", "ignore"]
          })
          child.stdin.end(JSON.stringify(metadata))
        }

        export const Breath: Plugin = async ({ directory }) => ({
          event: async ({ event }) => {
            const lifecycle = lifecycleByEvent[event.type]
            if (!lifecycle) return
            const properties = "properties" in event ? event.properties as Record<string, any> : {}
            if (event.type === "session.status" && properties.status?.type !== "busy") return
            const info = properties.info ?? properties.session ?? {}
            send(lifecycle, {
              session_id: info.id ?? properties.sessionID,
              title: info.title,
              cwd: directory
            })
          }
        })
        """
    }

    private func piSource(
        adapter: AgentAdapterDescriptor,
        executable: String
    ) -> String {
        let registrations = adapter.hookRegistrations.map { registration in
            """
              pi.on(\(jsString(registration.eventName)), async (_event, ctx) => {
                send(\(jsString(registration.lifecycle.rawValue)), ctx)
              })
            """
        }.joined(separator: "\n")
        return """
        import type { ExtensionAPI } from "@mariozechner/pi-coding-agent"
        import { spawn } from "node:child_process"

        const executable = \(jsString(executable))
        const agent = \(jsString(adapter.kind.rawValue))

        export default function breath(pi: ExtensionAPI) {
          function send(lifecycle: string, ctx: any) {
            const child = spawn(executable, ["--agent-hook", agent, lifecycle], {
              env: process.env,
              stdio: ["pipe", "ignore", "ignore"]
            })
            child.stdin.end(JSON.stringify({
              session_id: ctx.sessionManager.getSessionId?.(),
              title: ctx.sessionManager.getSessionName?.(),
              cwd: process.cwd()
            }))
          }

        \(registrations)
        }
        """
    }

    private func jsString(_ value: String) -> String {
        let data = try! JSONSerialization.data(
            withJSONObject: [value],
            options: [.withoutEscapingSlashes]
        )
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    private func resolve(_ path: String, homeDirectory: URL) throws -> URL {
        guard path.hasPrefix("~/") else {
            throw AgentIntegrationInstallationError.pathOutsideHome(path)
        }
        return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
    }

    private func makePrivate(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
