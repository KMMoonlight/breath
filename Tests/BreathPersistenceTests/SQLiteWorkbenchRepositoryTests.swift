import BreathAgents
import BreathCore
import BreathNotes
import BreathPersistence
import BreathSkills
import Foundation
import GRDB
import Testing

@Suite("SQLite workbench repository")
struct SQLiteWorkbenchRepositoryTests {
    @Test("legacy sessions without worktree metadata remain local sessions")
    func legacySessionDecodingDefaultsToLocalCheckout() throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [
                Workspace(
                    id: workspaceID,
                    path: "/tmp/project",
                    displayName: "project"
                ),
            ],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Legacy",
                    pane: TerminalPane(id: TerminalPaneID(rawValue: UUID()))
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var sessions = try #require(
            object["workSessions"] as? [[String: Any]]
        )
        sessions[0].removeValue(forKey: "managedWorktree")
        object["workSessions"] = sessions
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            WorkbenchSnapshot.self,
            from: legacyPayload
        )

        #expect(decoded.workSessions.first?.managedWorktree == nil)
        #expect(
            decoded.workSessions.first?.workingDirectory(
                workspacePath: "/tmp/project"
            ) == "/tmp/project"
        )
    }

    @Test("managed worktree migrates the created branch coding key")
    func managedWorktreeCreatedBranchCodingKeyMigration() throws {
        let worktree = ManagedWorktree(
            workspaceID: WorkspaceID(rawValue: UUID()),
            workSessionID: WorkSessionID(rawValue: UUID()),
            rootPath: "/tmp/worktrees/workspace/session",
            gitCommonDirectory: "/tmp/project/.git",
            baselineCommit: "0123456789abcdef",
            workspaceRelativePath: "apps/client",
            branchName: "breath/session",
            createdBranch: true
        )

        let encoded = try JSONEncoder().encode(worktree)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["createdBranch"] as? Bool == true)
        #expect(object["createdTaskBranch"] == nil)

        object["createdTaskBranch"] = object.removeValue(
            forKey: "createdBranch"
        )
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            ManagedWorktree.self,
            from: legacyPayload
        )
        #expect(decoded.createdBranch == true)
    }

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
                    pane: TerminalPane(id: paneID),
                    managedWorktree: ManagedWorktree(
                        workspaceID: workspaceID,
                        workSessionID: sessionID,
                        rootPath: "/tmp/worktrees/workspace/session",
                        gitCommonDirectory: "/tmp/project/.git",
                        baselineCommit: "0123456789abcdef",
                        workspaceRelativePath: "",
                        branchName: "task/round-trip"
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )

        try await repository.save(expected)

        let reopened = try SQLiteWorkbenchRepository(databaseURL: databaseURL)
        let actual = try await reopened.load()
        #expect(actual == expected)
    }

    @Test("application, terminal, and proxy settings survive a repository round trip")
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
            ),
            terminalShortcutPolicy: .terminalFirst,
            networkProxy: NetworkProxySettings(
                mode: .manual,
                manualURL: "http://127.0.0.1:7890",
                username: "breath"
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

    @Test("an existing pre-Notes database migrates without touching note files")
    func preNotesDatabaseMigration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-notes-migration-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let databaseURL = root.appendingPathComponent("breath.sqlite")
        let noteURL = root.appendingPathComponent("source.md")
        let noteBytes = Data([0xEF, 0xBB, 0xBF]) + Data("# Source\r\n".utf8)
        try noteBytes.write(to: noteURL)

        let legacyDatabase = try DatabaseQueue(path: databaseURL.path)
        try await legacyDatabase.write { database in
            try database.create(table: "grdb_migrations") { table in
                table.column("identifier", .text).notNull().primaryKey()
            }
            for identifier in [
                "createWorkbenchSnapshot",
                "createSettingsSnapshot",
                "createSkillInstallationRecord",
                "createAutomationSnapshot",
            ] {
                try database.execute(
                    sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                    arguments: [identifier]
                )
            }
            try database.create(table: "workbenchSnapshot") { table in
                table.column("id", .integer).primaryKey()
                table.column("payload", .blob).notNull()
            }
            try database.create(table: "settingsSnapshot") { table in
                table.column("id", .integer).primaryKey()
                table.column("payload", .blob).notNull()
            }
            try database.create(table: "skillInstallationRecord") { table in
                table.column("installationPath", .text).primaryKey()
                table.column("payload", .blob).notNull()
            }
            try database.create(table: "automationSnapshot") { table in
                table.column("id", .integer).primaryKey()
                table.column("payload", .blob).notNull()
            }
        }

        let repository = try SQLiteWorkbenchRepository(
            databaseURL: databaseURL
        )
        #expect(try await repository.loadNotesState() == .empty)
        #expect(try Data(contentsOf: noteURL) == noteBytes)
    }

    @Test("a corrupt Notes state is isolated without blocking a clean restart")
    func corruptNotesStateIsolation() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-corrupt-notes-\(UUID().uuidString).sqlite"
            )
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: databaseURL
        )
        let database = try DatabaseQueue(path: databaseURL.path)
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO notesState (id, payload) VALUES (1, ?)",
                arguments: [Data("not-json".utf8)]
            )
        }

        #expect(try await repository.loadNotesState() == .empty)
        #expect(try await repository.loadNotesState() == .empty)
    }

    @Test("one corrupt recovery draft does not erase healthy Notes state")
    func corruptRecoveryDraftIsolation() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-corrupt-draft-\(UUID().uuidString).sqlite"
            )
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: databaseURL
        )
        let library = NoteLibrary(
            id: NoteLibraryID(rawValue: UUID()),
            rootPath: "/tmp/notes"
        )
        let state = NotesPersistedState(
            library: library,
            openDocumentPaths: ["good.md", "bad.md"],
            recoveryDrafts: [
                "good.md": NoteRecoveryDraft(
                    relativePath: "good.md",
                    content: "healthy edit",
                    savedContent: "saved",
                    hadUTF8BOM: false
                ),
                "bad.md": NoteRecoveryDraft(
                    relativePath: "bad.md",
                    content: "will corrupt",
                    savedContent: "saved",
                    hadUTF8BOM: false
                ),
            ]
        )
        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(state)
            ) as? [String: Any]
        )
        var drafts = try #require(
            object["recoveryDrafts"] as? [String: Any]
        )
        drafts["bad.md"] = ["relativePath": "bad.md", "content": 42]
        object["recoveryDrafts"] = drafts
        let payload = try JSONSerialization.data(withJSONObject: object)
        let database = try DatabaseQueue(path: databaseURL.path)
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO notesState (id, payload) VALUES (1, ?)",
                arguments: [payload]
            )
        }

        let recovered = try await repository.loadNotesState()
        #expect(recovered.library == library)
        #expect(recovered.openDocumentPaths == ["good.md", "bad.md"])
        #expect(recovered.recoveryDrafts["good.md"]?.content == "healthy edit")
        #expect(recovered.recoveryDrafts["bad.md"] == nil)
        #expect(try await repository.loadNotesState() == recovered)
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
