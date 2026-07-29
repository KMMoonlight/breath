@testable import BreathAutomation
import BreathCore
import Darwin
import Foundation
import Testing

@Suite("Automation CLI runner")
struct AutomationRunnerTests {
    @Test("runner startup removes abandoned runtime directories")
    func startupCleansAbandonedRuntime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-stale-\(UUID().uuidString)",
            isDirectory: true
        )
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let stale = runtime.appendingPathComponent("stale-run", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stale,
            withIntermediateDirectories: true
        )
        try Data("partial".utf8).write(
            to: stale.appendingPathComponent("stdout.txt")
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )
        try await runner.prepareForStartup()

        #expect(
            try FileManager.default.contentsOfDirectory(
                at: runtime,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    @Test("Codex runner returns only the final answer and cannot write the Workspace")
    func codexRunnerUsesReadOnlySandbox() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: runtime,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let projectFile = workspace.appendingPathComponent("project.txt")
        try Data("original".utf8).write(to: projectFile)
        let nested = workspace.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        let nestedFile = nested.appendingPathComponent("value.txt")
        try Data("nested-original".utf8).write(to: nestedFile)
        let otherUserFile = root.appendingPathComponent("outside.txt")
        try Data("outside-original".utf8).write(to: otherUserFile)
        let globalSkill = home.appendingPathComponent(
            ".agents/skills/example/SKILL.md"
        )
        try FileManager.default.createDirectory(
            at: globalSkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("# Example".utf8).write(to: globalSkill)
        let keychainFile = home.appendingPathComponent(
            "Library/Keychains/test-secret.keychain-db"
        )
        try FileManager.default.createDirectory(
            at: keychainFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("secret".utf8).write(to: keychainFile)
        let executableDirectory = root.appendingPathComponent(
            "bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: executableDirectory,
            withIntermediateDirectories: true
        )
        let executable = executableDirectory.appendingPathComponent(
            "fake-codex"
        )
        try Data(
            """
            #!/bin/sh
            output=""
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "--output-last-message" ]; then
                shift
                output="$1"
              fi
              shift
            done
            temp_status=blocked
            workspace_status=blocked
            nested_status=blocked
            child_status=blocked
            outside_status=blocked
            skill_status=missing
            keychain_status=blocked
            apple_event_status=blocked
            /bin/echo "allowed" > "$HOME/allowed.txt" 2>/dev/null && temp_status=allowed
            /bin/echo "changed" > "$PWD/project.txt" 2>/dev/null && workspace_status=writable
            /bin/echo "changed" > "$PWD/nested/value.txt" 2>/dev/null && nested_status=writable
            /bin/sh -c '/bin/echo child > "$PWD/child-created.txt"' 2>/dev/null && child_status=writable
            /bin/echo "changed" > '\(otherUserFile.path)' 2>/dev/null && outside_status=writable
            test -r "$HOME/.agents/skills/example/SKILL.md" && skill_status=available
            /bin/cat '\(keychainFile.path)' > "$HOME/keychain-leak" 2>/dev/null && keychain_status=readable
            /usr/bin/osascript -e 'tell application "Finder" to get name' >/dev/null 2>&1 && apple_event_status=allowed
            printf "# Final\\n\\ntemp=%s workspace=%s nested=%s child=%s outside=%s skills=%s keychain=%s apple-events=%s" \
              "$temp_status" "$workspace_status" "$nested_status" "$child_status" "$outside_status" "$skill_status" "$keychain_status" "$apple_event_status" > "$output"
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )

        let result = try await runner.run(
            AutomationRunRequest(
                runID: AutomationRunID(rawValue: UUID()),
                automationID: AutomationID(rawValue: UUID()),
                agent: .codex,
                executablePath: executable.path,
                workspacePath: workspace.path,
                prompt: "Review",
                maximumDurationMinutes: 1
            )
        )

        #expect(
            result.finalOutput
                == "# Final\n\ntemp=allowed workspace=blocked nested=blocked child=blocked outside=blocked skills=available keychain=blocked apple-events=blocked"
        )
        #expect(try String(contentsOf: projectFile, encoding: .utf8) == "original")
        #expect(
            try String(contentsOf: nestedFile, encoding: .utf8)
                == "nested-original"
        )
        #expect(
            try String(contentsOf: otherUserFile, encoding: .utf8)
                == "outside-original"
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: workspace.appendingPathComponent(
                    "child-created.txt"
                ).path
            )
        )
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: runtime,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    @Test("runtime setup skips Unix sockets in Agent configuration")
    func runtimeSetupSkipsConfigurationSockets() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "breath-sock-\(UUID().uuidString.prefix(8))",
                isDirectory: true
            )
        let workspace = root.appendingPathComponent(
            "workspace",
            isDirectory: true
        )
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let codexHome = home.appendingPathComponent(
            ".codex",
            isDirectory: true
        )
        let socketDirectory = codexHome.appendingPathComponent(
            "ipc",
            isDirectory: true
        )
        for directory in [workspace, socketDirectory, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("model = \"test\"".utf8).write(
            to: codexHome.appendingPathComponent("config.toml")
        )
        let socketDescriptor = try bindTestUnixSocket(
            at: socketDirectory.appendingPathComponent("ipc.sock").path
        )
        defer { Darwin.close(socketDescriptor) }

        let executable = root.appendingPathComponent("fake-codex")
        try Data(
            """
            #!/bin/sh
            output=""
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "--output-last-message" ]; then
                shift
                output="$1"
              fi
              shift
            done
            printf 'configuration copied' > "$output"
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )

        let result = try await runner.run(
            AutomationRunRequest(
                runID: AutomationRunID(rawValue: UUID()),
                automationID: AutomationID(rawValue: UUID()),
                agent: .codex,
                executablePath: executable.path,
                workspacePath: workspace.path,
                prompt: "Review",
                maximumDurationMinutes: 1
            )
        )

        #expect(result.finalOutput == "configuration copied")
    }

    @Test("Codex relies on the outer sandbox instead of nesting sandbox-exec")
    func codexDoesNotAttemptNestedSandbox() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-codex-sandbox-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent(
            "workspace",
            isDirectory: true
        )
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        for directory in [workspace, home, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("workspace content".utf8).write(
            to: workspace.appendingPathComponent("project.txt")
        )

        let executable = root.appendingPathComponent("fake-codex")
        try Data(
            """
            #!/bin/sh
            output=""
            externally_sandboxed=false
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --output-last-message)
                  shift
                  output="$1"
                  ;;
                --dangerously-bypass-approvals-and-sandbox)
                  externally_sandboxed=true
                  ;;
              esac
              shift
            done
            if [ "$externally_sandboxed" = true ]; then
              result=$(/bin/cat "$PWD/project.txt" 2>&1)
            else
              result=$(/usr/bin/sandbox-exec -p '(version 1) (allow default)' \
                /bin/cat "$PWD/project.txt" 2>&1)
            fi
            printf '%s' "$result" > "$output"
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )

        let result = try await runner.run(
            AutomationRunRequest(
                runID: AutomationRunID(rawValue: UUID()),
                automationID: AutomationID(rawValue: UUID()),
                agent: .codex,
                executablePath: executable.path,
                workspacePath: workspace.path,
                prompt: "Read project.txt",
                maximumDurationMinutes: 1
            )
        )

        #expect(result.finalOutput == "workspace content")
    }

    @Test("every supported Agent adapter extracts one structured final answer")
    func supportedAgentFinalAnswers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-matrix-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        for directory in [workspace, home, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )
        let cases: [(AgentKind, String, String)] = [
            (.claudeCode, #"{"type":"result","result":"Claude final"}"#, "Claude final"),
            (
                .githubCopilotCLI,
                #"{"type":"result","result":"Copilot final"}"#,
                "Copilot final"
            ),
            (.qwenCode, #"{"response":"Qwen final"}"#, "Qwen final"),
            (.cursorAgent, #"{"type":"result","result":"Cursor final"}"#, "Cursor final"),
            (
                .factoryDroid,
                #"{"type":"result","result":"Droid final"}"#,
                "Droid final"
            ),
            (.openCode, #"{"type":"text","text":"OpenCode final"}"#, "OpenCode final"),
            (
                .pi,
                #"{"type":"message_end","message":{"content":[{"type":"text","text":"Pi final"}]}}"#,
                "Pi final"
            ),
            (.kimiCode, "Kimi final", "Kimi final"),
        ]

        for (agent, json, expected) in cases {
            let executable = root.appendingPathComponent("fake-\(agent.rawValue)")
            try Data(
                """
                #!/bin/sh
                /bin/echo '\(json)'
                """.utf8
            ).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executable.path
            )

            let result = try await runner.run(
                AutomationRunRequest(
                    runID: AutomationRunID(rawValue: UUID()),
                    automationID: AutomationID(rawValue: UUID()),
                    agent: agent,
                    executablePath: executable.path,
                    workspacePath: workspace.path,
                    prompt: "Review",
                    maximumDurationMinutes: 1
                )
            )

            #expect(result.finalOutput == expected, "Failed for \(agent)")
        }
    }

    @Test("Kimi automation copies configuration from KIMI_CODE_HOME")
    func kimiAutomationUsesCustomHome() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-kimi-home-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let kimiHome = root.appendingPathComponent("custom-kimi", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        for directory in [workspace, home, kimiHome, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("custom-kimi-config".utf8).write(
            to: kimiHome.appendingPathComponent("config.toml")
        )
        let executable = root.appendingPathComponent("fake-kimi")
        try Data(
            """
            #!/bin/sh
            /bin/cat "$KIMI_CODE_HOME/config.toml"
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime,
            processEnvironment: {
                [
                    "PATH": "/usr/bin:/bin",
                    "KIMI_CODE_HOME": kimiHome.path,
                ]
            }
        )

        let result = try await runner.run(
            AutomationRunRequest(
                runID: AutomationRunID(rawValue: UUID()),
                automationID: AutomationID(rawValue: UUID()),
                agent: .kimiCode,
                executablePath: executable.path,
                workspacePath: workspace.path,
                prompt: "Review",
                maximumDurationMinutes: 1
            )
        )

        #expect(result.finalOutput == "custom-kimi-config")
    }

    @Test("sandboxed Agent cannot signal a process outside its sandbox")
    func sandboxBlocksSignalsToUnrelatedProcesses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-signal-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        for directory in [workspace, home, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let sentinel = Process()
        sentinel.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sentinel.arguments = ["60"]
        try sentinel.run()
        defer {
            if sentinel.isRunning {
                sentinel.terminate()
            }
        }
        let executable = root.appendingPathComponent("fake-claude-signal")
        try Data(
            """
            #!/bin/sh
            status=blocked
            kill -TERM \(sentinel.processIdentifier) 2>/dev/null && status=allowed
            printf '{"type":"result","result":"signal=%s"}\\n' "$status"
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )

        let result = try await runner.run(
            AutomationRunRequest(
                runID: AutomationRunID(rawValue: UUID()),
                automationID: AutomationID(rawValue: UUID()),
                agent: .claudeCode,
                executablePath: executable.path,
                workspacePath: workspace.path,
                prompt: "Review",
                maximumDurationMinutes: 1
            )
        )

        #expect(result.finalOutput == "signal=blocked")
        #expect(sentinel.isRunning)
    }

    @Test("structured final output is extracted from the bounded stdout tail")
    func finalOutputUsesStdoutTail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-tail-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        for directory in [workspace, home, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-claude-tail")
        try Data(
            """
            #!/bin/sh
            /usr/bin/yes '{"type":"progress","text":"working"}' \
              | /usr/bin/head -c 2200000
            printf '\\n{"type":"result","result":"Tail final"}\\n'
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )

        let result = try await runner.run(
            AutomationRunRequest(
                runID: AutomationRunID(rawValue: UUID()),
                automationID: AutomationID(rawValue: UUID()),
                agent: .claudeCode,
                executablePath: executable.path,
                workspacePath: workspace.path,
                prompt: "Review",
                maximumDurationMinutes: 1
            )
        )

        #expect(result.finalOutput == "Tail final")
    }

    @Test("runaway process output is terminated at the spool limit")
    func processOutputIsBounded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-output-limit-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        for directory in [workspace, home, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-claude-overflow")
        try Data(
            """
            #!/bin/sh
            /usr/bin/yes 'unbounded output' | /usr/bin/head -c 40000000
            printf '\\n{"type":"result","result":"Too late"}\\n'
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )

        await #expect(throws: AutomationRunnerError.outputLimitExceeded) {
            _ = try await runner.run(
                AutomationRunRequest(
                    runID: AutomationRunID(rawValue: UUID()),
                    automationID: AutomationID(rawValue: UUID()),
                    agent: .claudeCode,
                    executablePath: executable.path,
                    workspacePath: workspace.path,
                    prompt: "Review",
                    maximumDurationMinutes: 1
                )
            )
        }
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: runtime,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    @Test("runner failure summaries do not expose stderr credentials or paths")
    func failureSummaryIsSanitized() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-error-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        for directory in [workspace, home, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-codex-failure")
        try Data(
            """
            #!/bin/sh
            /bin/echo 'API token sk-secret failed in /Users/alice/.config' >&2
            exit 23
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )

        do {
            _ = try await runner.run(
                AutomationRunRequest(
                    runID: AutomationRunID(rawValue: UUID()),
                    automationID: AutomationID(rawValue: UUID()),
                    agent: .codex,
                    executablePath: executable.path,
                    workspacePath: workspace.path,
                    prompt: "Review",
                    maximumDurationMinutes: 1
                )
            )
            Issue.record("Expected the fake Agent to fail")
        } catch let error as AutomationRunnerError {
            #expect(
                error.errorDescription
                    == "Agent 退出码 23：Agent 身份验证失败，请重新登录。"
            )
            #expect(!error.localizedDescription.contains("sk-secret"))
            #expect(!error.localizedDescription.contains("/Users/alice"))
        }
    }

    @Test("cancellation terminates the full process tree and removes the runtime")
    func cancellationCleansProcessTree() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-runner-cancel-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        for directory in [workspace, home, runtime] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-codex-cancel")
        try Data(
            """
            #!/bin/sh
            /bin/sh -c 'trap "" TERM; while :; do /bin/sleep 1; done' &
            child="$!"
            /bin/echo "$child" > "$HOME/child.pid"
            trap "" TERM
            wait "$child"
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let runID = AutomationRunID(rawValue: UUID())
        let runRoot = runtime.appendingPathComponent(
            runID.rawValue.uuidString,
            isDirectory: true
        )
        let childPIDFile = runRoot.appendingPathComponent("home/child.pid")
        let runner = CLIAutomationRunner(
            homeDirectory: home,
            runtimeRootDirectory: runtime
        )
        let task = Task {
            try await runner.run(
                AutomationRunRequest(
                    runID: runID,
                    automationID: AutomationID(rawValue: UUID()),
                    agent: .codex,
                    executablePath: executable.path,
                    workspacePath: workspace.path,
                    prompt: "Wait",
                    maximumDurationMinutes: 1
                )
            )
        }
        var childPID: Int32?
        for _ in 0..<500 {
            if let value = try? String(
                contentsOf: childPIDFile,
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines),
               let parsed = Int32(value)
            {
                childPID = parsed
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        let capturedPID = try #require(childPID)

        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        for _ in 0..<200 where kill(capturedPID, 0) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(kill(capturedPID, 0) != 0)
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: runtime,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }
}

private func bindTestUnixSocket(at path: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        Darwin.close(descriptor)
        throw CocoaError(.fileWriteInvalidFileName)
    }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        bytes.withUnsafeBufferPointer { source in
            UnsafeMutableRawPointer(pointer)
                .assumingMemoryBound(to: CChar.self)
                .update(from: source.baseAddress!, count: bytes.count)
        }
    }
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(
                descriptor,
                $0,
                socklen_t(MemoryLayout<sockaddr_un>.size)
            )
        }
    }
    guard result == 0 else {
        Darwin.close(descriptor)
        throw CocoaError(.fileWriteUnknown)
    }
    return descriptor
}
