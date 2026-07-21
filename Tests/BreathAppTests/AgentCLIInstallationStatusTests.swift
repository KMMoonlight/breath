import BreathAgents
import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Agent CLI installation status")
struct AgentCLIInstallationStatusTests {
    @Test("reports a missing Agent CLI as not installed")
    func missingCLI() throws {
        let detector = InstalledAgentCLIDetector(searchDirectories: [])
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .codex }
        )

        #expect(detector.installationStatus(for: adapter) == .notInstalled)
    }

    @Test("reads the installed version and flags versions below the integration minimum")
    func installedOutdatedCLI() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try writeExecutable(
            named: AgentKind.codex.cliExecutableName,
            in: temporaryDirectory,
            contents: "#!/bin/sh\necho 'codex-cli 0.120.0'\n"
        )
        let detector = InstalledAgentCLIDetector(searchDirectories: [temporaryDirectory])
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .codex }
        )

        #expect(
            detector.installationStatus(for: adapter)
                == .installed(version: "0.120.0", updateAvailable: true)
        )
    }

    @Test("keeps a newer installed version up to date")
    func installedCurrentCLI() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try writeExecutable(
            named: AgentKind.claudeCode.cliExecutableName,
            in: temporaryDirectory,
            contents: "#!/bin/sh\necho '2.1.202 (Claude Code)'\n"
        )
        let detector = InstalledAgentCLIDetector(searchDirectories: [temporaryDirectory])
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .claudeCode }
        )

        #expect(
            detector.installationStatus(for: adapter)
                == .installed(version: "2.1.202", updateAvailable: false)
        )
    }

    @Test("only a verified compatible Agent can be selected as a Skill target")
    func globalSkillTargetRequiresCompatibleVersion() throws {
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .codex }
        )

        #expect(
            SkillInstallationTargetAvailabilityResolver.resolve(
                adapter: adapter,
                status: .installed(version: "0.144.3", updateAvailable: false)
            ) == .available
        )
        #expect(
            SkillInstallationTargetAvailabilityResolver.resolve(
                adapter: adapter,
                status: .installed(version: "0.120.0", updateAvailable: true)
            ).isSelectable == false
        )
        #expect(
            SkillInstallationTargetAvailabilityResolver.resolve(
                adapter: adapter,
                status: .installed(version: nil, updateAvailable: false)
            ).isSelectable == false
        )
        #expect(
            SkillInstallationTargetAvailabilityResolver.resolve(
                adapter: adapter,
                status: .notInstalled
            ).isSelectable == false
        )
    }

    @Test("every supported Agent can be detected and selected as a Skill target")
    func everyGlobalSkillTargetHasInstallationDetection() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        for adapter in AgentAdapterRegistry.builtIn.adapters {
            try writeExecutable(
                named: adapter.kind.cliExecutableName,
                in: temporaryDirectory,
                contents: "#!/bin/sh\necho '\(adapter.minimumVersion)'\n"
            )
        }
        let detector = InstalledAgentCLIDetector(searchDirectories: [temporaryDirectory])

        for adapter in AgentAdapterRegistry.builtIn.adapters {
            let status = detector.installationStatus(for: adapter)
            #expect(
                SkillInstallationTargetAvailabilityResolver.resolve(
                    adapter: adapter,
                    status: status
                ) == .available,
                "\(adapter.displayName) must have working installation detection"
            )
        }
    }

    @Test("flags an update when the official release is newer than the compatible minimum")
    func officialReleaseIsNewer() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try writeExecutable(
            named: AgentKind.geminiCLI.cliExecutableName,
            in: temporaryDirectory,
            contents: "#!/bin/sh\necho '0.37.2'\n"
        )
        let detector = InstalledAgentCLIDetector(searchDirectories: [temporaryDirectory])
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .geminiCLI }
        )

        #expect(
            detector.installationStatus(for: adapter, latestVersion: "0.50.0")
                == .installed(version: "0.37.2", updateAvailable: true)
        )
        #expect(
            InstalledAgentCLIDetector.isVersion(
                "2026.07.09-a3815c0",
                olderThan: "2026.07.09-b4926d1"
            )
        )
    }

    @Test("parses official npm and installer release metadata")
    func officialReleaseMetadata() {
        let npmData = Data(#"{"version":"2.1.210"}"#.utf8)
        let cursorInstaller = Data(
            "DOWNLOAD_URL=\"https://downloads.cursor.com/lab/2026.07.09-a3815c0/darwin/arm64/agent-cli-package.tar.gz\""
                .utf8
        )
        let droidInstaller = Data("VER=\"0.172.0\"".utf8)

        #expect(
            AgentCLILatestVersionChecker.version(for: .claudeCode, in: npmData)
                == "2.1.210"
        )
        #expect(
            AgentCLILatestVersionChecker.version(for: .cursorAgent, in: cursorInstaller)
                == "2026.07.09-a3815c0"
        )
        #expect(
            AgentCLILatestVersionChecker.version(for: .factoryDroid, in: droidInstaller)
                == "0.172.0"
        )
        #expect(
            AgentCLILatestVersionChecker.releaseURL(
                for: .claudeCode,
                homebrewCask: "claude-code"
            )?.absoluteString
                == "https://formulae.brew.sh/api/cask/claude-code.json"
        )
        #expect(
            AgentCLILatestVersionChecker.releaseURL(
                for: .claudeCode,
                homebrewCask: "claude-code@latest"
            )?.absoluteString
                == "https://formulae.brew.sh/api/cask/claude-code@latest.json"
        )
    }

    @Test("runs the Agent updater and returns the refreshed version")
    func updateCLI() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let markerURL = temporaryDirectory.appendingPathComponent("updated")
        try writeExecutable(
            named: AgentKind.codex.cliExecutableName,
            in: temporaryDirectory,
            contents: """
                #!/bin/sh
                if [ "$1" = "update" ]; then
                  touch "\(markerURL.path)"
                  exit 0
                fi
                if [ -f "\(markerURL.path)" ]; then
                  echo 'codex-cli 0.144.4'
                else
                  echo 'codex-cli 0.120.0'
                fi
                """
        )
        let detector = InstalledAgentCLIDetector(searchDirectories: [temporaryDirectory])
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .codex }
        )

        let status = try detector.update(adapter)

        #expect(FileManager.default.fileExists(atPath: markerURL.path))
        #expect(status == .installed(version: "0.144.4", updateAvailable: false))
    }

    @Test("updates npm-managed Agents through their existing npm installation")
    func updateNPMManagedCLI() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
        let packageBinDirectory = temporaryDirectory
            .appendingPathComponent("lib/node_modules/@google/gemini-cli/bin", isDirectory: true)
        let markerURL = temporaryDirectory.appendingPathComponent("updated")
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: packageBinDirectory,
            withIntermediateDirectories: true
        )
        try writeExecutable(
            named: "gemini.js",
            in: packageBinDirectory,
            contents: """
                #!/bin/sh
                if [ -f "\(markerURL.path)" ]; then
                  echo '0.50.0'
                else
                  echo '0.37.2'
                fi
                """
        )
        try FileManager.default.createSymbolicLink(
            at: binDirectory.appendingPathComponent("gemini"),
            withDestinationURL: packageBinDirectory.appendingPathComponent("gemini.js")
        )
        try writeExecutable(
            named: "npm",
            in: binDirectory,
            contents: """
                #!/bin/sh
                if [ "$1" = "install" ] && [ "$2" = "-g" ] && [ "$3" = "@google/gemini-cli@latest" ]; then
                  touch "\(markerURL.path)"
                  exit 0
                fi
                exit 1
                """
        )
        let detector = InstalledAgentCLIDetector(searchDirectories: [binDirectory])
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .geminiCLI }
        )

        let status = try detector.update(adapter)

        #expect(FileManager.default.fileExists(atPath: markerURL.path))
        #expect(status == .installed(version: "0.50.0", updateAvailable: false))
    }

    @Test("updates Homebrew Cask Claude Code through its installed channel")
    func updateHomebrewCaskClaudeCode() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let binDirectory = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
        let caskDirectory = temporaryDirectory
            .appendingPathComponent("Caskroom/claude-code/2.1.202", isDirectory: true)
        let markerURL = temporaryDirectory.appendingPathComponent("updated")
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: caskDirectory,
            withIntermediateDirectories: true
        )
        try writeExecutable(
            named: "claude",
            in: caskDirectory,
            contents: """
                #!/bin/sh
                if [ "$1" = "--version" ]; then
                  if [ -f "\(markerURL.path)" ]; then
                    echo '2.1.210 (Claude Code)'
                  else
                    echo '2.1.202 (Claude Code)'
                  fi
                  exit 0
                fi
                exit 1
                """
        )
        try FileManager.default.createSymbolicLink(
            at: binDirectory.appendingPathComponent("claude"),
            withDestinationURL: caskDirectory.appendingPathComponent("claude")
        )
        try writeExecutable(
            named: "brew",
            in: binDirectory,
            contents: """
                #!/bin/sh
                if [ "$1" = "upgrade" ] && [ "$2" = "--cask" ] && [ "$3" = "claude-code" ]; then
                  touch "\(markerURL.path)"
                  exit 0
                fi
                exit 1
                """
        )
        let detector = InstalledAgentCLIDetector(searchDirectories: [binDirectory])
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .claudeCode }
        )

        let status = try detector.update(adapter)

        #expect(FileManager.default.fileExists(atPath: markerURL.path))
        #expect(status == .installed(version: "2.1.210", updateAvailable: false))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-agent-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func writeExecutable(
        named name: String,
        in directory: URL,
        contents: String
    ) throws {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
