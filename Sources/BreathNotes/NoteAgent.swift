import BreathCore
import Foundation

public struct NoteAgentRecoveryBinding: Equatable, Codable, Sendable {
    public let agent: AgentKind
    public let sessionID: String

    public init(agent: AgentKind, sessionID: String) {
        self.agent = agent
        self.sessionID = sessionID
    }
}

public enum NoteAgentConversationStatus: Equatable, Sendable {
    case idle
    case running
    case needsAttention
}
