import BreathCore
import Foundation
import GRDB

public struct AgentHookEventFactory: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func makeEvent(
        agent: AgentKind,
        lifecycle: AgentLifecycle,
        rawPayload: Data,
        environment: [String: String]
    ) throws -> AgentEvent? {
        guard try shouldEmitEvent(
            agent: agent,
            lifecycle: lifecycle,
            rawPayload: rawPayload
        ) else {
            return nil
        }
        guard let applicationInstanceID = identifier(
            ApplicationInstanceID.init(rawValue:),
            value: environment["BREATH_APPLICATION_INSTANCE_ID"]
        ),
            let workspaceID = identifier(
            WorkspaceID.init(rawValue:),
            value: environment["BREATH_WORKSPACE_ID"]
        ),
            let workSessionID = identifier(
                WorkSessionID.init(rawValue:),
                value: environment["BREATH_WORK_SESSION_ID"]
            ),
            let paneID = identifier(
                TerminalPaneID.init(rawValue:),
                value: environment["BREATH_TERMINAL_PANE_ID"]
            )
        else {
            return nil
        }

        let metadata = try metadata(from: rawPayload)
        let nativeTitle = metadata.title ?? codexThreadTitle(
            agent: agent,
            sessionID: metadata.sessionID,
            environment: environment
        )
        return AgentEvent(
            applicationInstanceID: applicationInstanceID,
            agent: agent,
            version: environment["BREATH_AGENT_VERSION"],
            lifecycle: lifecycle,
            occurredAt: now(),
            workspaceID: workspaceID,
            workSessionID: workSessionID,
            paneID: paneID,
            sessionID: metadata.sessionID,
            nativeTitle: nativeTitle,
            workingDirectory: metadata.workingDirectory
                ?? environment["PWD"]
                ?? ""
        )
    }

    private func shouldEmitEvent(
        agent: AgentKind,
        lifecycle: AgentLifecycle,
        rawPayload: Data
    ) throws -> Bool {
        guard agent == .antigravityCLI,
              lifecycle == .turnCompleted,
              !rawPayload.isEmpty,
              let root = try JSONSerialization.jsonObject(with: rawPayload)
                as? [String: Any],
              let fullyIdle = root["fullyIdle"] as? Bool
        else {
            return true
        }
        return fullyIdle
    }

    private func identifier<ID>(
        _ make: (UUID) -> ID,
        value: String?
    ) -> ID? {
        guard let value, let uuid = UUID(uuidString: value) else {
            return nil
        }
        return make(uuid)
    }

    private func metadata(from data: Data) throws -> Metadata {
        guard !data.isEmpty else { return Metadata() }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Metadata()
        }
        let session = root["session"] as? [String: Any]
        let properties = root["properties"] as? [String: Any]
        let info = properties?["info"] as? [String: Any]
        return Metadata(
            sessionID: firstString(
                root["session_id"],
                root["sessionId"],
                root["conversation_id"],
                root["conversationId"],
                root["thread_id"],
                session?["id"],
                info?["id"]
            ),
            title: firstString(
                root["title"],
                root["session_title"],
                root["thread_title"],
                session?["title"],
                info?["title"]
            ),
            workingDirectory: firstString(
                root["cwd"],
                root["working_directory"],
                (root["workspace_roots"] as? [String])?.first,
                (root["workspacePaths"] as? [String])?.first,
                session?["cwd"],
                info?["directory"]
            )
        )
    }

    private func firstString(_ values: Any?...) -> String? {
        values.lazy.compactMap { value in
            guard let string = value as? String, !string.isEmpty else { return nil }
            return string
        }.first
    }

    private func codexThreadTitle(
        agent: AgentKind,
        sessionID: String?,
        environment: [String: String]
    ) -> String? {
        guard agent == .codex, let sessionID, !sessionID.isEmpty else { return nil }
        let codexDirectory: URL
        if let path = environment["CODEX_HOME"], !path.isEmpty {
            codexDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let home = environment["HOME"] ?? NSHomeDirectory()
            codexDirectory = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".codex", isDirectory: true)
        }

        if let title = codexStateDatabaseThreadTitle(
            sessionID: sessionID,
            codexDirectory: codexDirectory
        ) {
            return title
        }

        return codexSessionIndexThreadTitle(
            sessionID: sessionID,
            codexDirectory: codexDirectory
        )
    }

    private func codexStateDatabaseThreadTitle(
        sessionID: String,
        codexDirectory: URL
    ) -> String? {
        let databaseURL = codexDirectory.appendingPathComponent("state_5.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(0.25)

        do {
            let database = try DatabaseQueue(
                path: databaseURL.path,
                configuration: configuration
            )
            let title = try database.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT title FROM threads WHERE id = ?",
                    arguments: [sessionID]
                )
            }
            return normalizedTitle(title)
        } catch {
            return nil
        }
    }

    private func codexSessionIndexThreadTitle(
        sessionID: String,
        codexDirectory: URL
    ) -> String? {
        let indexURL = codexDirectory.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: indexURL) else { return nil }

        for line in data.split(separator: 0x0A).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line))
                    as? [String: Any],
                  object["id"] as? String == sessionID,
                  let title = object["thread_name"] as? String
            else {
                continue
            }
            return normalizedTitle(title)
        }
        return nil
    }

    private func normalizedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let normalized = title
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(80))
    }

    private struct Metadata {
        var sessionID: String?
        var title: String?
        var workingDirectory: String?
    }
}
