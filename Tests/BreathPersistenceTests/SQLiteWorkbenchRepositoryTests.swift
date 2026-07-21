import BreathAgents
import BreathCore
import BreathPersistence
import BreathSkills
import Foundation
import Testing

@Suite("SQLite workbench repository")
struct SQLiteWorkbenchRepositoryTests {
    @Test("workbench snapshot survives a repository round trip")
    func roundTrip() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let repository = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let expected = WorkbenchSnapshot(
            workspaces: [
                Workspace(id: workspaceID, path: "/tmp/project", displayName: "project"),
            ],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "新会话 · 12:00",
                    pane: TerminalPane(id: paneID)
                ),
            ],
            selectedWorkSessionID: sessionID
        )

        try await repository.save(expected)

        let reopened = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        let actual = try await reopened.load()
        #expect(actual == expected)
    }

    @Test("application and terminal settings survive a repository round trip")
    func settingsRoundTrip() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-settings-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let repository = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        let expected = SettingsSnapshot(
            application: ApplicationSettings(
                appearance: .dark,
                sidebarDensity: .compact,
                fontSize: 14,
                language: .english
            ),
            terminal: TerminalSettings(
                fontFamily: "Berkeley Mono",
                fontSize: 14,
                colorTheme: .solarizedDark,
                cursorStyle: .underline
            )
        )

        try await repository.saveSettings(expected)

        let reopened = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        #expect(try await reopened.loadSettings() == expected)
    }

    @Test("database files are readable and writable only by the current user")
    func privateDatabasePermissions() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-private-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        _ = try SQLiteWorkbenchRepository(databaseURL: databaseURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber).intValue
        #expect(mode & 0o777 == 0o600)
    }

    @Test("agent hook content is discarded before workbench persistence")
    func agentEventPrivacyBoundary() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-privacy-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
        }
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-project-\(UUID().uuidString)", isDirectory: true)
        let repository = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        let runtime = PrivacyTerminalRuntime()
        let applicationInstanceID = ApplicationInstanceID(rawValue: UUID())
        let workbench = Workbench(
            repository: repository,
            terminalRuntime: runtime,
            applicationInstanceID: applicationInstanceID,
            defaultShell: { "/bin/zsh" }
        )
        let workspaceID = try await workbench.addWorkspace(at: workspaceURL)
        let workSessionID = try await workbench.createWorkSession(in: workspaceID)
        let paneID = try #require(
            await workbench.snapshot().workSessions.first?.layout.paneIDs.first
        )
        let rawPayload = Data(
            """
            {
              "session_id":"privacy-session",
              "title":"Official title",
              "cwd":"/tmp/project",
              "prompt":"BREATH_PRIVATE_PROMPT_7F45",
              "last_assistant_message":"BREATH_PRIVATE_REPLY_8C21",
              "tool_input":{"command":"BREATH_PRIVATE_TOOL_3A90"},
              "transcript_path":"BREATH_PRIVATE_TRANSCRIPT_1D63"
            }
            """.utf8
        )
        let event = try #require(
            try AgentHookEventFactory().makeEvent(
                agent: .claudeCode,
                lifecycle: .turnStarted,
                rawPayload: rawPayload,
                environment: [
                    "BREATH_APPLICATION_INSTANCE_ID": applicationInstanceID.rawValue.uuidString,
                    "BREATH_WORKSPACE_ID": workspaceID.rawValue.uuidString,
                    "BREATH_WORK_SESSION_ID": workSessionID.rawValue.uuidString,
                    "BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString,
                ]
            )
        )

        try await workbench.handleAgentEvent(event)
        let persisted = try await repository.load()
        #expect(persisted.workSessions.first?.pane.agentBinding?.sessionID == "privacy-session")
        #expect(persisted.workSessions.first?.title == "Official title")

        var databaseBytes = try Data(contentsOf: databaseURL)
        for suffix in ["-shm", "-wal"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if let data = try? Data(contentsOf: url) {
                databaseBytes.append(data)
            }
        }
        let rawDatabase = String(decoding: databaseBytes, as: UTF8.self)
        for secret in [
            "BREATH_PRIVATE_PROMPT_7F45",
            "BREATH_PRIVATE_REPLY_8C21",
            "BREATH_PRIVATE_TOOL_3A90",
            "BREATH_PRIVATE_TRANSCRIPT_1D63",
        ] {
            #expect(!rawDatabase.contains(secret))
        }
    }

    @Test("remote and ZIP Skill provenance survive a repository round trip")
    func skillInstallationRecordRoundTrip() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-skill-records-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let repository = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        let record = SkillInstallationRecord(
            agent: .codex,
            installationDirectory: URL(fileURLWithPath: "/Users/tester/.codex/skills/review"),
            skillName: "review",
            origin: .remote(SkillRemoteProvenance(
                source: .github,
                repository: "example/skills",
                sourceRelativePath: "skills/review",
                reference: SkillSourceReference(kind: .branch, value: "main"),
                resolvedCommit: "0123456789abcdef",
                catalogSkillID: "example/skills/review"
            )),
            installedContentDigest: "digest-v1",
            installedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let zipRecord = SkillInstallationRecord(
            agent: .claudeCode,
            installationDirectory: URL(fileURLWithPath: "/Users/tester/.claude/skills/local"),
            skillName: "local",
            origin: .zip,
            installedContentDigest: "digest-local",
            installedAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        try await repository.saveSkillInstallationRecord(record)
        try await repository.saveSkillInstallationRecord(zipRecord)

        let reopened = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        #expect(try await reopened.loadSkillInstallationRecords() == [zipRecord, record])
        try await reopened.removeSkillInstallationRecord(
            installationDirectory: record.installationDirectory
        )
        try await reopened.removeSkillInstallationRecord(
            installationDirectory: zipRecord.installationDirectory
        )
        #expect(try await reopened.loadSkillInstallationRecords().isEmpty)
    }
}

private actor PrivacyTerminalRuntime: TerminalRuntime {
    func launch(_ request: TerminalLaunch) {}
    func stop(paneID: TerminalPaneID) {}
}
