import BreathCore
import Foundation

public extension AgentHookCommand {
    func standardOutput(arguments: [String]) -> Data? {
        guard let invocation = AgentHookInvocation(arguments: arguments),
              invocation.agent == .antigravityCLI
        else {
            return nil
        }
        if invocation.lifecycle == .turnCompleted {
            return Data("{\"decision\":\"stop\"}\n".utf8)
        }
        return Data("{}\n".utf8)
    }
}
