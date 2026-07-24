import BreathCore
import Foundation

struct AgentQuotaCommandOutput: CustomStringConvertible, Sendable {
    let data: Data
    let exitCode: Int32

    var description: String {
        "AgentQuotaCommandOutput(data: <redacted>, exitCode: \(exitCode))"
    }
}

struct AgentQuotaCommandRunner: Sendable {
    private let execute:
        @Sendable (AgentKind, [String], Data?) async throws
            -> AgentQuotaCommandOutput

    init(
        execute: @escaping
            @Sendable (AgentKind, [String], Data?) async throws
                -> AgentQuotaCommandOutput
    ) {
        self.execute = execute
    }

    func run(
        _ agent: AgentKind,
        arguments: [String],
        standardInput: Data? = nil
    ) async throws -> AgentQuotaCommandOutput {
        try await execute(agent, arguments, standardInput)
    }

    static func live(
        detector: InstalledAgentCLIDetector,
        baseEnvironment: [String: String],
        processEnvironment: @escaping
            @Sendable ([String: String]) -> [String: String]
    ) -> AgentQuotaCommandRunner {
        AgentQuotaCommandRunner { agent, arguments, standardInput in
            guard let executableURL = detector.executableURL(for: agent) else {
                throw AgentQuotaCommandError.notInstalled
            }
            var environment = processEnvironment(baseEnvironment)
            environment["LANG"] = "en_US.UTF-8"
            environment["LC_ALL"] = "en_US.UTF-8"
            environment["NO_COLOR"] = "1"
            environment["CI"] = "1"
            environment["TERM"] = "dumb"
            return try await runProcess(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                standardInput: standardInput
            )
        }
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Data?
    ) async throws -> AgentQuotaCommandOutput {
        let handle = AgentQuotaRunningProcessHandle()
        let task = Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = output
            process.standardError = output
            let input: Pipe?
            if standardInput != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                input = pipe
            } else {
                process.standardInput = FileHandle.nullDevice
                input = nil
            }
            handle.install(process)
            defer { handle.clear(process) }
            try Task.checkCancellation()
            try process.run()
            if let standardInput, let input {
                try input.fileHandleForWriting.write(contentsOf: standardInput)
                try input.fileHandleForWriting.close()
            }

            var captured = Data()
            while true {
                let chunk = try output.fileHandleForReading.read(
                    upToCount: 64 * 1024
                ) ?? Data()
                if chunk.isEmpty { break }
                captured.append(chunk)
                guard captured.count <= 1024 * 1024 else {
                    handle.cancel()
                    throw AgentQuotaCommandError.outputTooLarge
                }
            }
            process.waitUntilExit()
            try Task.checkCancellation()
            return AgentQuotaCommandOutput(
                data: captured,
                exitCode: process.terminationStatus
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
            handle.cancel()
        }
    }
}

enum AgentQuotaCommandError: Error, Equatable, Sendable {
    case notInstalled
    case outputTooLarge
}

private final class AgentQuotaRunningProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func install(_ process: Process) {
        lock.lock()
        if cancelled {
            lock.unlock()
            process.terminate()
            return
        }
        self.process = process
        lock.unlock()
    }

    func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

extension CodexAgentQuotaAppServer {
    static func query(
        commandRunner: AgentQuotaCommandRunner
    ) async -> AgentQuotaStatus {
        let input = Data(
            """
            {"id":1,"method":"initialize","params":{"clientInfo":{"name":"Breath","version":"1"},"capabilities":{}}}
            {"method":"initialized"}
            {"id":2,"method":"account/rateLimits/read"}

            """.utf8
        )
        do {
            let output = try await commandRunner.run(
                .codex,
                arguments: ["app-server", "--listen", "stdio://"],
                standardInput: input
            )
            if let snapshot = try? decode(output.data) {
                return .available(snapshot)
            }
            let text = String(decoding: output.data, as: UTF8.self)
                .lowercased()
            if text.contains("authentication required")
                || text.contains("not authenticated")
                || text.contains("login required")
            {
                return .notLoggedIn
            }
            return .unsupported
        } catch is CancellationError {
            return .failed("额度查询已取消。")
        } catch {
            return .unsupported
        }
    }
}

enum AgentQuotaOfficialCLIAdapter {
    static func query(
        agent: AgentKind,
        providerName: String,
        command: String,
        commandRunner: AgentQuotaCommandRunner
    ) async -> AgentQuotaStatus {
        let input = Data("\(command)\n/exit\n".utf8)
        do {
            let output = try await commandRunner.run(
                agent,
                arguments: [],
                standardInput: input
            )
            let text = String(decoding: output.data, as: UTF8.self)
            if let snapshot = try? AgentQuotaCLITextDecoder.decode(
                text,
                providerName: providerName
            ) {
                return .available(snapshot)
            }
            let normalized = text.lowercased()
            if normalized.contains("not logged in")
                || normalized.contains("login required")
                || normalized.contains("please log in")
                || normalized.contains("authentication required")
            {
                return .notLoggedIn
            }
            return .unsupported
        } catch is CancellationError {
            return .failed("额度查询已取消。")
        } catch {
            return .unsupported
        }
    }
}
