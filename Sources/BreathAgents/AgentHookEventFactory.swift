import BreathCore
import Foundation

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
            nativeTitle: metadata.title,
            workingDirectory: metadata.workingDirectory
                ?? environment["PWD"]
                ?? ""
        )
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

    private struct Metadata {
        var sessionID: String?
        var title: String?
        var workingDirectory: String?
    }
}
