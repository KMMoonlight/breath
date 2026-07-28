import BreathAutomation
import Foundation

struct AutomationTriggerCommand {
    static func socketURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(
                "Library/Application Support/Breath",
                isDirectory: true
            )
            .appendingPathComponent("automation.sock")
    }

    func run(
        arguments: [String],
        homeDirectory: URL,
        standardOutput: (String) -> Void,
        standardError: (String) -> Void
    ) -> Int32 {
        guard arguments.count == 2,
              arguments[0] == "trigger",
              !arguments[1].isEmpty
        else {
            standardError("Usage: breath trigger <shortcode>")
            return 64
        }
        do {
            let response = try UnixAutomationTriggerClient().trigger(
                shortcode: arguments[1],
                at: Self.socketURL(homeDirectory: homeDirectory)
            )
            switch response.status {
            case .accepted, .queued:
                standardOutput(response.message)
                return 0
            case .rejected:
                standardError(response.message)
                return 1
            }
        } catch {
            standardError("Breath is not running")
            return 1
        }
    }
}
