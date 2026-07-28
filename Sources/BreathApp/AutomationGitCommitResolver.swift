import Foundation

enum AutomationGitCommitResolver {
    static func resolve(workspacePath: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C", workspacePath,
            "rev-parse", "--verify", "HEAD",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let value = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.range(
                of: #"^[0-9a-fA-F]{40,64}$"#,
                options: .regularExpression
            ) != nil else {
                return nil
            }
            return value
        } catch {
            return nil
        }
    }
}
