import BreathCore
import Darwin
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
    private let executeInteractive:
        @Sendable (AgentKind, [String], String) async throws
            -> AgentQuotaCommandOutput

    init(
        execute: @escaping
            @Sendable (AgentKind, [String], Data?) async throws
                -> AgentQuotaCommandOutput
    ) {
        self.execute = execute
        executeInteractive = { agent, arguments, command in
            try await execute(
                agent,
                arguments,
                Data("\(command)\n/exit\n".utf8)
            )
        }
    }

    private init(
        execute: @escaping
            @Sendable (AgentKind, [String], Data?) async throws
                -> AgentQuotaCommandOutput,
        executeInteractive: @escaping
            @Sendable (AgentKind, [String], String) async throws
                -> AgentQuotaCommandOutput
    ) {
        self.execute = execute
        self.executeInteractive = executeInteractive
    }

    func run(
        _ agent: AgentKind,
        arguments: [String],
        standardInput: Data? = nil
    ) async throws -> AgentQuotaCommandOutput {
        try await execute(agent, arguments, standardInput)
    }

    func runInteractive(
        _ agent: AgentKind,
        arguments: [String] = [],
        command: String
    ) async throws -> AgentQuotaCommandOutput {
        try await executeInteractive(agent, arguments, command)
    }

    static func live(
        detector: InstalledAgentCLIDetector,
        baseEnvironment: [String: String],
        processEnvironment: @escaping
            @Sendable ([String: String]) -> [String: String]
    ) -> AgentQuotaCommandRunner {
        AgentQuotaCommandRunner(
            execute: { agent, arguments, standardInput in
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
            },
            executeInteractive: { agent, arguments, command in
                guard let executableURL = detector.executableURL(for: agent) else {
                    throw AgentQuotaCommandError.notInstalled
                }
                var environment = processEnvironment(baseEnvironment)
                environment["LANG"] = "en_US.UTF-8"
                environment["LC_ALL"] = "en_US.UTF-8"
                environment["NO_COLOR"] = "1"
                environment.removeValue(forKey: "CI")
                environment["TERM"] = "xterm-256color"
                return try await runInteractiveProcess(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: environment,
                    command: command
                )
            }
        )
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

    private static func runInteractiveProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        command: String
    ) async throws -> AgentQuotaCommandOutput {
        let handle = AgentQuotaRunningProcessHandle()
        let task = Task.detached(priority: .userInitiated) {
            let process = Process()
            let captured = AgentQuotaOutputBuffer()
            var masterDescriptor: Int32 = -1
            var slaveDescriptor: Int32 = -1
            var windowSize = winsize(
                ws_row: 40,
                ws_col: 160,
                ws_xpixel: 0,
                ws_ypixel: 0
            )
            guard openpty(
                &masterDescriptor,
                &slaveDescriptor,
                nil,
                nil,
                &windowSize
            ) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let ptyMaster = masterDescriptor
            let ptySlave = slaveDescriptor
            defer { Darwin.close(ptyMaster) }
            let slaveHandle = FileHandle(
                fileDescriptor: ptySlave,
                closeOnDealloc: false
            )
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.standardInput = slaveHandle
            process.standardOutput = slaveHandle
            process.standardError = slaveHandle
            handle.install(process)
            defer { handle.clear(process) }
            try Task.checkCancellation()
            do {
                try process.run()
            } catch {
                Darwin.close(ptySlave)
                throw error
            }
            Darwin.close(ptySlave)

            let writer = Task.detached(priority: .userInitiated) {
                var previousCount = 0
                var quietPollCount = 0
                var hasRenderedTerminal = false
                for poll in 0..<40 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, process.isRunning else { return }
                    let currentCount = captured.snapshot().count
                    if currentCount > 0 {
                        hasRenderedTerminal = true
                    }
                    if currentCount == previousCount {
                        quietPollCount += 1
                    } else {
                        previousCount = currentCount
                        quietPollCount = 0
                    }
                    if poll >= 2, hasRenderedTerminal, quietPollCount >= 2 {
                        break
                    }
                }

                guard !Task.isCancelled, process.isRunning else { return }
                try? write(
                    Data("\(command)\r".utf8),
                    to: ptyMaster
                )

                previousCount = captured.snapshot().count
                quietPollCount = 0
                for poll in 0..<60 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, process.isRunning else { return }
                    let snapshot = captured.snapshot()
                    if snapshot.count == previousCount {
                        quietPollCount += 1
                    } else {
                        previousCount = snapshot.count
                        quietPollCount = 0
                    }
                    let text = String(decoding: snapshot, as: UTF8.self)
                    let normalized = AgentQuotaCLITextDecoder
                        .plainText(text)
                        .lowercased()
                    let searchable = AgentQuotaCLITextDecoder
                        .searchableText(text)
                    let hasResult = normalized.contains("remaining")
                        || normalized.range(
                            of: #"%\s*used"#,
                            options: .regularExpression
                        ) != nil
                        || normalized.contains("credits")
                        || searchable.contains("apiusagebilling")
                        || searchable.contains(
                            "onlyavailableforsubscriptionplans"
                        )
                        || normalized.contains("not logged in")
                        || normalized.contains("login required")
                        || normalized.contains("unknown command")
                        || normalized.contains("unrecognized command")
                    if poll >= 9, hasResult, quietPollCount >= 4 {
                        break
                    }
                }

                guard !Task.isCancelled, process.isRunning else { return }
                try? write(Data([0x1B]), to: ptyMaster)
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, process.isRunning else { return }
                try? write(Data("/exit\r".utf8), to: ptyMaster)
                try? await Task.sleep(for: .milliseconds(250))
                if process.isRunning {
                    try? write(
                        Data([0x03, 0x03, 0x04]),
                        to: ptyMaster
                    )
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if process.isRunning {
                    process.terminate()
                }
            }

            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try Task.checkCancellation()
                var descriptor = pollfd(
                    fd: ptyMaster,
                    events: Int16(POLLIN | POLLHUP | POLLERR),
                    revents: 0
                )
                let pollResult = Darwin.poll(&descriptor, 1, 50)
                if pollResult == 0 {
                    if !process.isRunning { break }
                    continue
                }
                if pollResult < 0 {
                    if errno == EINTR { continue }
                    writer.cancel()
                    handle.cancel()
                    throw POSIXError(
                        POSIXErrorCode(rawValue: errno) ?? .EIO
                    )
                }
                let count = Darwin.read(
                    ptyMaster,
                    &bytes,
                    bytes.count
                )
                if count == 0 { break }
                if count < 0 {
                    if errno == EINTR { continue }
                    if errno == EIO { break }
                    writer.cancel()
                    handle.cancel()
                    throw POSIXError(
                        POSIXErrorCode(rawValue: errno) ?? .EIO
                    )
                }
                let chunk = Data(bytes.prefix(Int(count)))
                guard captured.append(chunk, maximumSize: 1024 * 1024) else {
                    writer.cancel()
                    handle.cancel()
                    throw AgentQuotaCommandError.outputTooLarge
                }
            }
            writer.cancel()
            _ = await writer.result
            try Task.checkCancellation()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            return AgentQuotaCommandOutput(
                data: captured.snapshot(),
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

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(
                        POSIXErrorCode(rawValue: errno) ?? .EIO
                    )
                }
                offset += count
            }
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
            if let process, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

private final class AgentQuotaOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data, maximumSize: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard data.count + chunk.count <= maximumSize else { return false }
        data.append(chunk)
        return true
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
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
        do {
            let output = try await commandRunner.runInteractive(
                agent,
                arguments: [],
                command: command
            )
            let text = String(decoding: output.data, as: UTF8.self)
            let normalized = AgentQuotaCLITextDecoder
                .plainText(text)
                .lowercased()
            let searchable = AgentQuotaCLITextDecoder.searchableText(text)
            if normalized.contains("not logged in")
                || normalized.contains("login required")
                || normalized.contains("please log in")
                || normalized.contains("authentication required")
            {
                return .notLoggedIn
            }
            if agent == .claudeCode,
               searchable.contains("apiusagebilling")
                || searchable.contains(
                    "usageisonlyavailableforsubscriptionplans"
                )
            {
                return .unsupported
            }
            if let snapshot = try? AgentQuotaCLITextDecoder.decode(
                text,
                providerName: providerName
            ) {
                return .available(snapshot)
            }
            if normalized.contains("unknown command")
                || normalized.contains("unrecognized command")
                || normalized.contains("command not found")
            {
                return .unsupported
            }
            guard output.exitCode == 0 else {
                return .failed("额度查询失败。")
            }
            return .failed("额度响应格式无法识别。")
        } catch is CancellationError {
            return .failed("额度查询已取消。")
        } catch AgentQuotaCommandError.notInstalled {
            return .unsupported
        } catch {
            return .failed("额度查询失败。")
        }
    }
}
