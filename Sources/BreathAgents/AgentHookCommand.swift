import BreathCore
import Foundation

public enum AgentHookCommandResult: Equatable, Sendable {
    case sent
    case ignored
}

public struct AgentHookInvocation: Equatable, Sendable {
    public let agent: AgentKind
    public let lifecycle: AgentLifecycle

    public init?(arguments: [String]) {
        guard arguments.count >= 4,
              arguments[1] == "--agent-hook",
              let agent = AgentKind(rawValue: arguments[2]),
              let lifecycle = AgentLifecycle(rawValue: arguments[3])
        else {
            return nil
        }
        self.agent = agent
        self.lifecycle = lifecycle
    }
}

public struct AgentHookCommand: Sendable {
    private let factory: AgentHookEventFactory
    private let sender: any AgentEventSending

    public init(
        factory: AgentHookEventFactory = AgentHookEventFactory(),
        sender: any AgentEventSending = UnixAgentEventClient()
    ) {
        self.factory = factory
        self.sender = sender
    }

    public func run(
        arguments: [String],
        environment: [String: String],
        standardInput: Data
    ) -> AgentHookCommandResult {
        guard let invocation = AgentHookInvocation(arguments: arguments),
              let event = try? factory.makeEvent(
                  agent: invocation.agent,
                  lifecycle: invocation.lifecycle,
                  rawPayload: standardInput,
                  environment: environment
              )
        else {
            return .ignored
        }

        let socketURL: URL
        if let path = environment["BREATH_AGENT_SOCKET"], !path.isEmpty {
            socketURL = URL(fileURLWithPath: path)
        } else {
            let home = environment["HOME"] ?? NSHomeDirectory()
            socketURL = URL(fileURLWithPath: home)
                .appendingPathComponent("Library/Application Support/Breath/agent-events.sock")
        }

        do {
            try sender.send(event, to: socketURL)
            return .sent
        } catch {
            return .ignored
        }
    }
}
