import Foundation

struct GitCommandResult: Sendable {
    let executableURL: URL
    let arguments: [String]
    let exitCode: Int32
    let standardOutputData: Data
    let standardErrorData: Data

    var standardOutput: String {
        String(decoding: standardOutputData, as: UTF8.self)
    }

    var standardError: String {
        String(decoding: standardErrorData, as: UTF8.self)
    }

    var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayCommand: String {
        ([executableURL.path] + arguments.map(Self.shellQuoted))
            .joined(separator: " ")
    }

    private static func shellQuoted(_ argument: String) -> String {
        guard argument.contains(where: { $0.isWhitespace || "'\"\\$`".contains($0) }) else {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum GitOperationContext {
    @TaskLocal static var recorder:
        (@Sendable (GitCommandResult) async -> Void)?
    @TaskLocal static var outputRecorder:
        (@Sendable (String) async -> Void)?
    @TaskLocal static var statusRecorder:
        (@Sendable (GitOperationStatus) async -> Void)?
}

enum GitCommandError: LocalizedError, Equatable {
    case failed(command: String, exitCode: Int32, output: String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .failed(let command, let exitCode, let output):
            let detail = output.isEmpty ? "No output." : output
            return GitSecretRedactor.redact(
                "\(command) exited with \(exitCode): \(detail)"
            )
        case .invalidOutput(let message):
            return message
        }
    }
}

struct GitCommandRunner: Sendable {
    let executableURL: URL

    func run(
        arguments: [String],
        environment: [String: String]? = nil,
        standardInput: Data? = nil
    ) async throws -> GitCommandResult {
        let executableURL = executableURL
        let outputRecorder = GitOperationContext.outputRecorder
        let processHandle = GitRunningProcessHandle()
        let task = Task.detached(priority: .userInitiated) {
            () throws -> GitCommandResult in
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = standardOutput
            process.standardError = standardError
            process.environment = environment ?? ProcessInfo.processInfo.environment
            let termination = GitProcessTermination()
            process.terminationHandler = { process in
                termination.finish(process.terminationStatus)
            }
            processHandle.install(process)
            defer { processHandle.clear(process) }
            try Task.checkCancellation()
            let input: Pipe?
            if standardInput != nil {
                input = Pipe()
                process.standardInput = input
            } else {
                input = nil
                process.standardInput = FileHandle.nullDevice
            }
            try process.run()
            async let standardOutputData = Self.read(
                standardOutput,
                recorder: outputRecorder
            )
            async let standardErrorData = Self.read(
                standardError,
                recorder: outputRecorder
            )
            if let standardInput, let input {
                try input.fileHandleForWriting.write(contentsOf: standardInput)
                try input.fileHandleForWriting.close()
            }
            let exitCode = await termination.wait()
            let (capturedOutput, capturedError) = await (
                standardOutputData,
                standardErrorData
            )
            try Task.checkCancellation()
            return GitCommandResult(
                executableURL: executableURL,
                arguments: arguments,
                exitCode: exitCode,
                standardOutputData: capturedOutput,
                standardErrorData: capturedError
            )
        }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
            processHandle.cancel()
        }
        if let recorder = GitOperationContext.recorder {
            await recorder(result)
        }
        return result
    }

    private static func read(
        _ pipe: Pipe,
        recorder: (@Sendable (String) async -> Void)?
    ) async -> Data {
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            data.append(chunk)
            if let recorder {
                await recorder(String(decoding: chunk, as: UTF8.self))
            }
        }
        return data
    }
}

final class GitProcessTermination: @unchecked Sendable {
    private let lock = NSLock()
    private var exitCode: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func finish(_ exitCode: Int32) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: exitCode)
        } else {
            self.exitCode = exitCode
            lock.unlock()
        }
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let exitCode {
                lock.unlock()
                continuation.resume(returning: exitCode)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

private final class GitRunningProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func install(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        if isCancelled, process.isRunning {
            process.terminate()
        }
    }

    func clear(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if self.process === process {
            self.process = nil
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
