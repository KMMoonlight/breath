import BreathAgents
import BreathCore
import Darwin
import Foundation
import IOKit.pwr_mgt

public enum AutomationRunnerError: Error, Equatable, Sendable {
    case timedOut
    case launchFailed(String)
    case processFailed(Int32, String)
    case outputLimitExceeded
    case unsupportedAgent
    case missingFinalOutput
    case invalidFinalOutput
}

extension AutomationRunnerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "Agent 运行超过最大时长。"
        case .launchFailed(let message):
            "无法启动 Agent：\(message)"
        case .processFailed(let status, let message):
            message.isEmpty
                ? "Agent 退出码：\(status)"
                : "Agent 退出码 \(status)：\(message)"
        case .outputLimitExceeded:
            "Agent 进程输出超过安全上限。"
        case .unsupportedAgent:
            "所选 Agent 未声明自动化运行能力。"
        case .missingFinalOutput:
            "Agent 未返回最终输出。"
        case .invalidFinalOutput:
            "无法解析 Agent 最终输出。"
        }
    }
}

public struct CLIAutomationRunner: AutomationRunning, Sendable {
    private let homeDirectory: URL
    private let runtimeRootDirectory: URL
    private let processEnvironment: @Sendable () -> [String: String]

    public init(
        homeDirectory: URL,
        runtimeRootDirectory: URL,
        processEnvironment: @escaping @Sendable () -> [String: String] = {
            ProcessInfo.processInfo.environment
        }
    ) {
        self.homeDirectory = homeDirectory
        self.runtimeRootDirectory = runtimeRootDirectory
        self.processEnvironment = processEnvironment
    }

    public func prepareForStartup() async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: runtimeRootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        for child in try fileManager.contentsOfDirectory(
            at: runtimeRootDirectory,
            includingPropertiesForKeys: nil
        ) {
            try fileManager.removeItem(at: child)
        }
    }

    public func run(
        _ request: AutomationRunRequest
    ) async throws -> AutomationAgentResult {
        let fileManager = FileManager.default
        let runRoot = runtimeRootDirectory.appendingPathComponent(
            request.runID.rawValue.uuidString,
            isDirectory: true
        )
        let temporaryHome = runRoot.appendingPathComponent("home", isDirectory: true)
        let temporaryDirectory = runRoot.appendingPathComponent("tmp", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: runRoot)
        }

        do {
            try fileManager.createDirectory(
                at: temporaryHome,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try copyRuntimeConfiguration(
                for: request.agent,
                to: temporaryHome
            )
        } catch {
            throw AutomationRunnerError.launchFailed(
                "无法准备临时运行环境。"
            )
        }
        let finalOutputURL = runRoot.appendingPathComponent("final-output.txt")
        let standardOutputURL = runRoot.appendingPathComponent("stdout.txt")
        let standardErrorURL = runRoot.appendingPathComponent("stderr.txt")
        let command = try command(
            for: request,
            finalOutputURL: finalOutputURL
        )
        let environment = runtimeEnvironment(
            for: request.agent,
            temporaryHome: temporaryHome,
            temporaryDirectory: temporaryDirectory
        )
        let profile = sandboxProfile(
            writableRoot: runRoot,
            workspaceRoot: URL(
                fileURLWithPath: request.workspacePath,
                isDirectory: true
            ),
            executablePath: request.executablePath,
            environment: environment
        )
        let assertion = AutomationPowerAssertion()
        assertion.acquire()
        defer { assertion.release() }

        let outcome: ProcessOutcome
        do {
            outcome = try await withThrowingTaskGroup(
                of: ProcessOutcome.self
            ) { group in
                group.addTask {
                    try await SandboxedProcess.execute(
                        executablePath: request.executablePath,
                        arguments: command.arguments,
                        environment: environment,
                        workingDirectory: URL(
                            fileURLWithPath: request.workspacePath,
                            isDirectory: true
                        ),
                        sandboxProfile: profile,
                        standardOutputURL: standardOutputURL,
                        standardErrorURL: standardErrorURL
                    )
                }
                group.addTask {
                    try await SuspendingClock().sleep(
                        for: .seconds(
                            Int64(request.maximumDurationMinutes) * 60
                        )
                    )
                    throw AutomationRunnerError.timedOut
                }
                do {
                    guard let first = try await group.next() else {
                        throw AutomationRunnerError.launchFailed(
                            "Agent 进程没有返回状态。"
                        )
                    }
                    group.cancelAll()
                    return first
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AutomationRunnerError {
            throw error
        } catch {
            throw AutomationRunnerError.launchFailed(
                "无法准备或启动沙盒 Agent。"
            )
        }

        let standardError = Self.readLimitedText(
            at: standardErrorURL,
            limit: 16 * 1_024
        )
        guard outcome.terminationStatus == 0 else {
            throw AutomationRunnerError.processFailed(
                outcome.terminationStatus,
                Self.safeFailureSummary(from: standardError)
            )
        }
        let standardOutput = Self.readHeadAndTailText(
            at: standardOutputURL,
            limit: 2 * 1_024 * 1_024
        )
        let parsed = try parseFinalResult(
            agent: request.agent,
            finalOutputURL: command.usesFinalOutputFile
                ? finalOutputURL
                : nil,
            standardOutput: standardOutput
        )
        guard !parsed.output.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw AutomationRunnerError.missingFinalOutput
        }
        return AutomationAgentResult(
            finalOutput: parsed.output,
            model: parsed.model
        )
    }

    private func command(
        for request: AutomationRunRequest,
        finalOutputURL: URL
    ) throws -> AgentCommand {
        guard let capability = AgentAdapterRegistry.builtIn.adapters
            .first(where: { $0.kind == request.agent })?
            .automation
        else {
            throw AutomationRunnerError.unsupportedAgent
        }
        return AgentCommand(
            arguments: capability.arguments(
                prompt: request.prompt,
                finalOutputPath: finalOutputURL.path
            ),
            usesFinalOutputFile: capability.usesFinalOutputFile
        )
    }

    private func runtimeEnvironment(
        for agent: AgentKind,
        temporaryHome: URL,
        temporaryDirectory: URL
    ) -> [String: String] {
        let inheritedEnvironment = processEnvironment()
        let retainedKeys: Set<String> = [
            "PATH", "LANG", "LC_ALL", "LC_CTYPE", "TERM",
            "SSL_CERT_FILE", "SSL_CERT_DIR",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
            "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY",
            "GOOGLE_API_KEY", "GITHUB_TOKEN", "COPILOT_GITHUB_TOKEN",
            "QWEN_API_KEY", "DASHSCOPE_API_KEY", "CURSOR_API_KEY",
            "FACTORY_API_KEY", "OPENROUTER_API_KEY", "AZURE_OPENAI_API_KEY",
            "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
        ]
        var environment = inheritedEnvironment.filter {
            retainedKeys.contains($0.key) || $0.key.hasPrefix("LC_")
        }
        environment["HOME"] = temporaryHome.path
        environment["TMPDIR"] = temporaryDirectory.path
        environment["XDG_CACHE_HOME"] = temporaryHome
            .appendingPathComponent(".cache", isDirectory: true).path
        switch agent {
        case .codex:
            environment["CODEX_HOME"] = temporaryHome
                .appendingPathComponent(".codex", isDirectory: true).path
        case .claudeCode:
            environment["CLAUDE_CONFIG_DIR"] = temporaryHome
                .appendingPathComponent(".claude", isDirectory: true).path
        case .geminiCLI:
            environment["GEMINI_CLI_HOME"] = temporaryHome
                .appendingPathComponent(".gemini", isDirectory: true).path
        case .githubCopilotCLI:
            environment["COPILOT_HOME"] = temporaryHome
                .appendingPathComponent(".copilot", isDirectory: true).path
        case .qwenCode:
            environment["QWEN_CLI_HOME"] = temporaryHome
                .appendingPathComponent(".qwen", isDirectory: true).path
        case .cursorAgent:
            environment["CURSOR_AGENT_HOME"] = temporaryHome
                .appendingPathComponent(".cursor", isDirectory: true).path
        case .factoryDroid:
            environment["FACTORY_HOME"] = temporaryHome
                .appendingPathComponent(".factory", isDirectory: true).path
        case .openCode:
            environment["XDG_CONFIG_HOME"] = temporaryHome
                .appendingPathComponent(".config", isDirectory: true).path
        case .pi:
            environment["PI_CODING_AGENT_DIR"] = temporaryHome
                .appendingPathComponent(".pi/agent", isDirectory: true).path
        }
        return environment
    }

    private func copyRuntimeConfiguration(
        for agent: AgentKind,
        to temporaryHome: URL
    ) throws {
        let fileManager = FileManager.default
        let relativePaths: [String]
        switch agent {
        case .codex:
            relativePaths = [".codex", ".agents/skills"]
        case .claudeCode:
            relativePaths = [".claude"]
        case .geminiCLI:
            relativePaths = [".gemini"]
        case .githubCopilotCLI:
            relativePaths = [".copilot"]
        case .qwenCode:
            relativePaths = [".qwen"]
        case .cursorAgent:
            relativePaths = [".cursor"]
        case .factoryDroid:
            relativePaths = [".factory"]
        case .openCode:
            relativePaths = [".config/opencode"]
        case .pi:
            relativePaths = [".pi/agent"]
        }
        for relativePath in relativePaths {
            let source = homeDirectory.appendingPathComponent(
                relativePath,
                isDirectory: true
            )
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = temporaryHome.appendingPathComponent(
                relativePath,
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try copyConfigurationTree(from: source, to: destination)
        }
    }

    private func copyConfigurationTree(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let ignoredNames: Set<String> = [
            "backups", "cache", "debug", "history", "logs", "projects",
            "sessions", "stats-cache", "telemetry", "tmp", "todos",
        ]
        let values = try source.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        if values.isSymbolicLink == true {
            return
        }
        if values.isDirectory != true {
            try fileManager.copyItem(at: source, to: destination)
            return
        }
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        for child in try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) where !ignoredNames.contains(child.lastPathComponent.lowercased()) {
            try copyConfigurationTree(
                from: child,
                to: destination.appendingPathComponent(child.lastPathComponent)
            )
        }
    }

    private func sandboxProfile(
        writableRoot: URL,
        workspaceRoot: URL,
        executablePath: String,
        environment: [String: String]
    ) -> String {
        var writablePaths = Set([
            writableRoot.path,
            writableRoot.resolvingSymlinksInPath().path,
        ])
        if writableRoot.path.hasPrefix("/var/") {
            writablePaths.insert("/private\(writableRoot.path)")
        }
        let writableRules: String = writablePaths.sorted().map { path -> String in
            let escapedPath = path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "(subpath \"\(escapedPath)\")"
        }.joined(separator: "\n            ")
        var readablePaths = Set([
            writableRoot.path,
            writableRoot.resolvingSymlinksInPath().path,
            workspaceRoot.path,
            workspaceRoot.resolvingSymlinksInPath().path,
            "/System",
            "/usr",
            "/bin",
            "/sbin",
            "/Library",
            "/etc",
            "/private/etc",
            "/dev",
            "/tmp",
            "/private/tmp",
            "/private/var/db/timezone",
            "/private/var/run",
            "/opt/homebrew",
        ])
        let executableURL = URL(fileURLWithPath: executablePath)
            .resolvingSymlinksInPath()
        readablePaths.insert(executableURL.path)
        readablePaths.insert(
            executableURL.deletingLastPathComponent().path
        )
        for pathEntry in (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            where pathEntry.hasPrefix("/")
                && pathEntry != homeDirectory.path
                && pathEntry != homeDirectory.resolvingSymlinksInPath().path
        {
            readablePaths.insert(pathEntry)
            readablePaths.insert(
                URL(fileURLWithPath: pathEntry, isDirectory: true)
                    .resolvingSymlinksInPath().path
            )
        }
        for path in Array(readablePaths) where path.hasPrefix("/var/") {
            readablePaths.insert("/private\(path)")
        }
        let readableRules = readablePaths.sorted().map { path -> String in
            let escapedPath = sandboxEscapedPath(path)
            if path == executableURL.path {
                return "(literal \"\(escapedPath)\")"
            }
            return "(subpath \"\(escapedPath)\")"
        }.joined(separator: "\n            ")
        var protectedHomePaths = Set([
            homeDirectory.path,
            homeDirectory.resolvingSymlinksInPath().path,
        ])
        for path in Array(protectedHomePaths) where path.hasPrefix("/var/") {
            protectedHomePaths.insert("/private\(path)")
        }
        let protectedHomeRules = protectedHomePaths.sorted().map {
            "(require-not (subpath \"\(sandboxEscapedPath($0))\"))"
        }.joined(separator: "\n                ")
        return """
        (version 1)
        (deny default)
        (allow process-exec
            (require-all
                (require-not (literal "/usr/bin/osascript"))
                (require-not (literal "/usr/bin/open"))
                (require-not (literal "/usr/bin/security"))
                (require-not (subpath "/Applications"))
                (require-not (subpath "/System/Applications"))))
        (allow process-fork)
        (allow process-info* (target self))
        (allow signal (target same-sandbox))
        (allow file-read-metadata)
        (allow file-read*
            (require-all
                \(protectedHomeRules)))
        (allow file-read*
            \(readableRules))
        (allow file-write*
            \(writableRules)
            (literal "/dev/null")
            (literal "/dev/tty"))
        (allow network-outbound)
        (allow sysctl-read)
        (allow mach-lookup
            (require-all
                (require-not (global-name "com.apple.securityd"))
                (require-not (global-name "com.apple.security.agent"))
                (require-not (global-name "com.apple.cfprefsd.agent"))
                (require-not (global-name "com.apple.cfprefsd.daemon"))
                (require-not (global-name "com.apple.tccd"))
                (require-not (global-name "com.apple.appleevents"))
                (require-not (global-name "com.apple.accessibility.api"))))
        """
    }

    private func sandboxEscapedPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func parseFinalResult(
        agent: AgentKind,
        finalOutputURL: URL?,
        standardOutput: String
    ) throws -> (output: String, model: String?) {
        if let finalOutputURL {
            let output = Self.readHeadAndTailText(
                at: finalOutputURL,
                limit: 2 * 1_024 * 1_024
            )
            return (output, nil)
        }
        let lines = standardOutput.split(
            whereSeparator: \.isNewline
        ).map(String.init)
        var lastOutput: String?
        var lastModel: String?
        for candidate in lines + [standardOutput] {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else {
                continue
            }
            if let output = Self.extractFinalText(from: object, agent: agent) {
                lastOutput = output
            }
            if let model = Self.extractStringRecursively(
                keys: ["model", "model_name", "modelName"],
                from: object
            ) {
                lastModel = model
            }
        }
        guard let lastOutput else {
            throw AutomationRunnerError.invalidFinalOutput
        }
        return (lastOutput, lastModel)
    }

    private static func extractFinalText(
        from object: Any,
        agent: AgentKind
    ) -> String? {
        if let dictionary = object as? [String: Any] {
            let type = (dictionary["type"] as? String)?.lowercased()
            let isFinalEvent = type == nil
                || type == "result"
                || type == "final"
                || type == "message_end"
                || type == "agent_message"
                || type == "text"
                || (agent == .openCode && type == "step_finish")
            if isFinalEvent,
               let value = extractString(
                   keys: [
                       "result", "response", "final_output", "finalOutput",
                       "text", "content",
                   ],
                   from: dictionary
               )
            {
                return value
            }
            for key in ["message", "data", "item", "output"] {
                if let nested = dictionary[key],
                   let value = extractFinalText(from: nested, agent: agent)
                {
                    return value
                }
            }
        } else if let array = object as? [Any] {
            return array.compactMap {
                extractFinalText(from: $0, agent: agent)
            }.last
        } else if let string = object as? String {
            return string
        }
        return nil
    }

    private static func extractString(
        keys: [String],
        from object: Any
    ) -> String? {
        guard let dictionary = object as? [String: Any] else { return nil }
        for key in keys {
            if let string = dictionary[key] as? String,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return string
            }
            if let array = dictionary[key] as? [Any] {
                let text = array.compactMap { element -> String? in
                    if let string = element as? String { return string }
                    return extractString(keys: ["text", "content"], from: element)
                }.joined()
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private static func extractStringRecursively(
        keys: [String],
        from object: Any
    ) -> String? {
        if let value = extractString(keys: keys, from: object) {
            return value
        }
        if let dictionary = object as? [String: Any] {
            for value in dictionary.values {
                if let result = extractStringRecursively(
                    keys: keys,
                    from: value
                ) {
                    return result
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let result = extractStringRecursively(
                    keys: keys,
                    from: value
                ) {
                    return result
                }
            }
        }
        return nil
    }

    private static func readLimitedText(at url: URL, limit: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: limit)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func readHeadAndTailText(
        at url: URL,
        limit: Int
    ) -> String {
        guard limit > 0,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return ""
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size <= UInt64(limit) {
            try? handle.seek(toOffset: 0)
            let data = (try? handle.read(upToCount: limit)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
        let marker = "\n… Breath omitted bounded process output …\n"
        let available = max(0, limit - marker.utf8.count)
        let headSize = available / 2
        let tailSize = available - headSize
        try? handle.seek(toOffset: 0)
        let head = (try? handle.read(upToCount: headSize)) ?? Data()
        try? handle.seek(toOffset: size - UInt64(tailSize))
        let tail = (try? handle.read(upToCount: tailSize)) ?? Data()
        return String(decoding: head, as: UTF8.self)
            + marker
            + String(decoding: tail, as: UTF8.self)
    }

    private static func firstLine(of value: String) -> String {
        String(
            value.split(whereSeparator: \.isNewline).first?.prefix(512) ?? ""
        )
    }

    private static func safeFailureSummary(from standardError: String) -> String {
        let line = firstLine(of: standardError).lowercased()
        if ["auth", "login", "token", "credential"].contains(where: line.contains) {
            return "Agent 身份验证失败，请重新登录。"
        }
        if ["sandbox", "operation not permitted", "permission denied"].contains(
            where: line.contains
        ) {
            return "Agent 被沙盒或权限策略阻止。"
        }
        return "Agent 运行失败。"
    }
}

private struct AgentCommand {
    let arguments: [String]
    let usesFinalOutputFile: Bool

    init(arguments: [String], usesFinalOutputFile: Bool = false) {
        self.arguments = arguments
        self.usesFinalOutputFile = usesFinalOutputFile
    }
}

private struct ProcessOutcome: Sendable {
    let terminationStatus: Int32
}

private enum SandboxedProcess {
    static func execute(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL,
        sandboxProfile: String,
        standardOutputURL: URL,
        standardErrorURL: URL
    ) async throws -> ProcessOutcome {
        FileManager.default.createFile(
            atPath: standardOutputURL.path,
            contents: nil
        )
        FileManager.default.createFile(
            atPath: standardErrorURL.path,
            contents: nil
        )
        let outputHandle = try FileHandle(forWritingTo: standardOutputURL)
        let errorHandle = try FileHandle(forWritingTo: standardErrorURL)
        let inputDescriptor = Darwin.open("/dev/null", O_RDONLY)
        guard inputDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            Darwin.close(inputDescriptor)
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let launchArguments = [
            "/usr/bin/sandbox-exec",
            "-p", sandboxProfile,
            executablePath,
        ] + arguments
        let controller = ProcessTerminationController()

        return try await withTaskCancellationHandler {
            let processIdentifier = try spawnProcessGroup(
                executablePath: "/usr/bin/sandbox-exec",
                arguments: launchArguments,
                environment: environment,
                workingDirectory: workingDirectory.path,
                standardInput: inputDescriptor,
                standardOutput: outputHandle.fileDescriptor,
                standardError: errorHandle.fileDescriptor
            )
            controller.install(processIdentifier)
            let rawStatus = await Task.detached(priority: .utility) {
                waitForProcess(
                    processIdentifier,
                    monitoredFiles: [
                        standardOutputURL,
                        standardErrorURL,
                    ],
                    maximumCombinedBytes: 32 * 1_024 * 1_024
                )
            }.value
            await controller.finishProcessGroup()
            try Task.checkCancellation()
            guard rawStatus.waitError == nil else {
                throw rawStatus.waitError!
            }
            if rawStatus.outputLimitExceeded {
                throw AutomationRunnerError.outputLimitExceeded
            }
            return ProcessOutcome(
                terminationStatus: terminationStatus(
                    from: rawStatus.status
                )
            )
        } onCancel: {
            controller.requestTermination()
        }
    }

    private static func spawnProcessGroup(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String,
        standardInput: Int32,
        standardOutput: Int32,
        standardError: Int32
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0,
              posix_spawnattr_init(&attributes) == 0
        else {
            throw POSIXError(.ENOMEM)
        }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attributes)
        }
        guard posix_spawn_file_actions_adddup2(
            &fileActions,
            standardInput,
            STDIN_FILENO
        ) == 0 else {
            throw NSError(domain: "spawn.stdin", code: Int(EINVAL))
        }
        guard posix_spawn_file_actions_adddup2(
            &fileActions,
            standardOutput,
            STDOUT_FILENO
        ) == 0 else {
            throw NSError(domain: "spawn.stdout", code: Int(EINVAL))
        }
        guard posix_spawn_file_actions_adddup2(
            &fileActions,
            standardError,
            STDERR_FILENO
        ) == 0 else {
            throw NSError(domain: "spawn.stderr", code: Int(EINVAL))
        }
        guard posix_spawn_file_actions_addchdir_np(
            &fileActions,
            workingDirectory
        ) == 0
        else {
            throw NSError(domain: "spawn.chdir", code: Int(EINVAL))
        }

        let flags = Int16(POSIX_SPAWN_SETPGROUP)
        guard posix_spawnattr_setflags(&attributes, flags) == 0 else {
            throw NSError(domain: "spawn.flags", code: Int(EINVAL))
        }
        guard posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            throw NSError(domain: "spawn.pgroup", code: Int(EINVAL))
        }

        let environmentEntries = environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()
        var processIdentifier = pid_t(0)
        let result = withMutableCStringArray(arguments) { argumentVector in
            withMutableCStringArray(
                environmentEntries
            ) { environmentVector in
                posix_spawn(
                    &processIdentifier,
                    executablePath,
                    &fileActions,
                    &attributes,
                    argumentVector,
                    environmentVector
                )
            }
        }
        guard result == 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: result) ?? .EINVAL
            )
        }
        return processIdentifier
    }

    private static func withMutableCStringArray<Result>(
        _ strings: [String],
        _ body: (
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        ) throws -> Result
    ) rethrows -> Result {
        var pointers = strings.map { strdup($0) }
        pointers.append(nil)
        defer {
            for pointer in pointers where pointer != nil {
                free(pointer)
            }
        }
        return try pointers.withUnsafeMutableBufferPointer {
            try body($0.baseAddress!)
        }
    }

    private static func waitForProcess(
        _ processIdentifier: pid_t,
        monitoredFiles: [URL],
        maximumCombinedBytes: UInt64
    ) -> (
        status: Int32,
        waitError: POSIXError?,
        outputLimitExceeded: Bool
    ) {
        var status = Int32(0)
        var exceeded = false
        while true {
            let result = waitpid(processIdentifier, &status, WNOHANG)
            if result == processIdentifier {
                if !exceeded {
                    exceeded = combinedFileSize(monitoredFiles)
                        > maximumCombinedBytes
                }
                return (status, nil, exceeded)
            }
            if result == -1 {
                if errno == EINTR { continue }
                return (
                    status,
                    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO),
                    exceeded
                )
            }
            if !exceeded {
                let combinedSize = combinedFileSize(monitoredFiles)
                if combinedSize > maximumCombinedBytes {
                    exceeded = true
                    _ = kill(-processIdentifier, SIGKILL)
                }
            }
            usleep(50_000)
        }
    }

    private static func combinedFileSize(_ files: [URL]) -> UInt64 {
        files.reduce(UInt64(0)) { partial, url in
            var information = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return lstat(path, &information)
            }
            guard result == 0 else {
                return partial
            }
            return partial + UInt64(max(0, information.st_size))
        }
    }

    private static func terminationStatus(from rawStatus: Int32) -> Int32 {
        let signal = rawStatus & 0x7f
        if signal == 0 {
            return (rawStatus >> 8) & 0xff
        }
        return 128 + signal
    }
}

private final class ProcessTerminationController: @unchecked Sendable {
    private let lock = NSLock()
    private var processGroup: pid_t?
    private var cancellationRequested = false

    func install(_ processIdentifier: pid_t) {
        let shouldTerminate = lock.withLock {
            processGroup = processIdentifier
            return cancellationRequested
        }
        if shouldTerminate {
            signalProcessGroup(SIGTERM)
        }
    }

    func requestTermination() {
        let processGroup = lock.withLock { () -> pid_t? in
            cancellationRequested = true
            return self.processGroup
        }
        guard let processGroup else { return }
        _ = kill(-processGroup, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 2
        ) {
            if processGroupExists(processGroup) {
                _ = kill(-processGroup, SIGKILL)
            }
        }
    }

    func finishProcessGroup() async {
        guard let processGroup = lock.withLock({ self.processGroup }) else {
            return
        }
        await Task.detached(priority: .utility) {
            guard processGroupExists(processGroup) else { return }
            _ = kill(-processGroup, SIGTERM)
            for _ in 0..<20 {
                usleep(100_000)
                guard processGroupExists(processGroup) else { return }
            }
            _ = kill(-processGroup, SIGKILL)
            for _ in 0..<10 {
                usleep(50_000)
                guard processGroupExists(processGroup) else { return }
            }
        }.value
    }

    private func signalProcessGroup(_ signal: Int32) {
        guard let processGroup = lock.withLock({ self.processGroup }) else {
            return
        }
        _ = kill(-processGroup, signal)
    }
}

private func processGroupExists(_ processGroup: pid_t) -> Bool {
    if kill(-processGroup, 0) == 0 {
        return true
    }
    return errno == EPERM
}

private final class AutomationPowerAssertion {
    private var identifier = IOPMAssertionID(0)

    func acquire() {
        guard identifier == 0 else { return }
        _ = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Breath Automation Run" as CFString,
            &identifier
        )
    }

    func release() {
        guard identifier != 0 else { return }
        IOPMAssertionRelease(identifier)
        identifier = 0
    }
}
