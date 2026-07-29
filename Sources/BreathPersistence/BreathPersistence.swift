import BreathAutomation
import BreathCore
import BreathNotes
import BreathSkills
import Foundation
import GRDB

public final class SQLiteWorkbenchRepository: WorkbenchRepository, SettingsRepository,
    SkillInstallationRecordRepository, AutomationRepository, NotesRepository,
    @unchecked Sendable
{
    private let databaseQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        databaseQueue = try DatabaseQueue(path: databaseURL.path)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("createWorkbenchSnapshot") { database in
            try database.create(table: "workbenchSnapshot") { table in
                table.column("id", .integer).primaryKey()
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("createSettingsSnapshot") { database in
            try database.create(table: "settingsSnapshot") { table in
                table.column("id", .integer).primaryKey()
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("createSkillInstallationRecord") { database in
            try database.create(table: "skillInstallationRecord") { table in
                table.column("installationPath", .text).primaryKey()
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("createAutomationSnapshot") { database in
            try database.create(table: "automationSnapshot") { table in
                table.column("id", .integer).primaryKey()
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("createNotesState") { database in
            try database.create(table: "notesState") { table in
                table.column("id", .integer).primaryKey()
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("createNotesSearchIndex") { database in
            try database.execute(
                sql: """
                    CREATE VIRTUAL TABLE notesSearch USING fts5(
                        libraryID UNINDEXED,
                        relativePath UNINDEXED,
                        content,
                        tokenize = 'unicode61'
                    )
                    """
            )
        }
        try migrator.migrate(databaseQueue)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: databaseURL.path
        )
    }

    public func load() async throws -> WorkbenchSnapshot {
        try await databaseQueue.read { database in
            guard let payload = try Data.fetchOne(
                database,
                sql: "SELECT payload FROM workbenchSnapshot WHERE id = 1"
            ) else {
                return .empty
            }
            return try JSONDecoder().decode(WorkbenchSnapshot.self, from: payload)
        }
    }

    public func save(_ snapshot: WorkbenchSnapshot) async throws {
        let payload = try JSONEncoder().encode(snapshot)
        try await databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO workbenchSnapshot (id, payload)
                    VALUES (1, ?)
                    ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                    """,
                arguments: [payload]
            )
        }
    }

    public func loadSettings() async throws -> SettingsSnapshot {
        try await databaseQueue.read { database in
            guard let payload = try Data.fetchOne(
                database,
                sql: "SELECT payload FROM settingsSnapshot WHERE id = 1"
            ) else {
                return .default
            }
            return try JSONDecoder().decode(SettingsSnapshot.self, from: payload)
        }
    }

    public func saveSettings(_ settings: SettingsSnapshot) async throws {
        let payload = try JSONEncoder().encode(settings)
        try await databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO settingsSnapshot (id, payload)
                    VALUES (1, ?)
                    ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                    """,
                arguments: [payload]
            )
        }
    }

    public func loadSkillInstallationRecords() async throws -> [SkillInstallationRecord] {
        try await databaseQueue.read { database in
            let payloads = try Data.fetchAll(
                database,
                sql: "SELECT payload FROM skillInstallationRecord ORDER BY installationPath"
            )
            return try payloads.map {
                try JSONDecoder().decode(SkillInstallationRecord.self, from: $0)
            }
        }
    }

    public func saveSkillInstallationRecord(_ record: SkillInstallationRecord) async throws {
        let payload = try JSONEncoder().encode(record)
        try await databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO skillInstallationRecord (installationPath, payload)
                    VALUES (?, ?)
                    ON CONFLICT(installationPath) DO UPDATE SET payload = excluded.payload
                    """,
                arguments: [record.installationDirectory.path, payload]
            )
        }
    }

    public func removeSkillInstallationRecord(installationDirectory: URL) async throws {
        try await databaseQueue.write { database in
            try database.execute(
                sql: "DELETE FROM skillInstallationRecord WHERE installationPath = ?",
                arguments: [installationDirectory.path]
            )
        }
    }

    public func loadAutomationSnapshot() async throws -> AutomationSnapshot {
        try await databaseQueue.read { database in
            guard let payload = try Data.fetchOne(
                database,
                sql: "SELECT payload FROM automationSnapshot WHERE id = 1"
            ) else {
                return .empty
            }
            return try JSONDecoder().decode(AutomationSnapshot.self, from: payload)
        }
    }

    public func saveAutomationSnapshot(_ snapshot: AutomationSnapshot) async throws {
        let payload = try JSONEncoder().encode(snapshot)
        try await databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO automationSnapshot (id, payload)
                    VALUES (1, ?)
                    ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                    """,
                arguments: [payload]
            )
        }
    }

    public func loadNotesState() async throws -> NotesPersistedState {
        let payload = try await databaseQueue.read { database in
            try Data.fetchOne(
                database,
                sql: "SELECT payload FROM notesState WHERE id = 1"
            )
        }
        guard let payload else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(
                NotesPersistedState.self,
                from: payload
            )
        } catch is DecodingError {
            if let recovered = Self.salvageNotesState(from: payload) {
                try await saveNotesState(recovered)
                return recovered
            }
            try await databaseQueue.write { database in
                try database.execute(
                    sql: "DELETE FROM notesState WHERE id = 1"
                )
            }
            return .empty
        }
    }

    private static func salvageNotesState(
        from payload: Data
    ) -> NotesPersistedState? {
        guard var object = try? JSONSerialization.jsonObject(
            with: payload
        ) as? [String: Any],
        let drafts = object["recoveryDrafts"] as? [String: Any]
        else {
            return nil
        }
        let decoder = JSONDecoder()
        let validDrafts = drafts.filter { _, value in
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value)
            else {
                return false
            }
            return (try? decoder.decode(
                NoteRecoveryDraft.self,
                from: data
            )) != nil
        }
        guard validDrafts.count < drafts.count else {
            return nil
        }
        object["recoveryDrafts"] = validDrafts
        guard JSONSerialization.isValidJSONObject(object),
              let repairedPayload = try? JSONSerialization.data(
                withJSONObject: object
              )
        else {
            return nil
        }
        return try? decoder.decode(
            NotesPersistedState.self,
            from: repairedPayload
        )
    }

    public func saveNotesState(_ state: NotesPersistedState) async throws {
        let payload = try JSONEncoder().encode(state)
        try await databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO notesState (id, payload)
                    VALUES (1, ?)
                    ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                    """,
                arguments: [payload]
            )
        }
    }

    public func replaceNoteSearchIndex(
        libraryID: NoteLibraryID,
        documents: [NoteSearchDocument]
    ) async throws {
        try await databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM notesSearch")
            for document in documents {
                try database.execute(
                    sql: """
                        INSERT INTO notesSearch (
                            libraryID,
                            relativePath,
                            content
                        ) VALUES (?, ?, ?)
                        """,
                    arguments: [
                        libraryID.rawValue.uuidString,
                        document.relativePath,
                        document.content,
                    ]
                )
            }
        }
    }

    public func searchNotes(
        libraryID: NoteLibraryID,
        query: String,
        limit: Int
    ) async throws -> [NoteSearchResult] {
        try await databaseQueue.read { database in
            let sanitizedQuery = query.replacingOccurrences(
                of: "\"",
                with: "\"\""
            )
            let escapedQuery = "\"\(sanitizedQuery)\""
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT relativePath, content
                    FROM notesSearch
                    WHERE notesSearch MATCH ? AND libraryID = ?
                    ORDER BY rank
                    LIMIT ?
                    """,
                arguments: [
                    escapedQuery,
                    libraryID.rawValue.uuidString,
                    limit,
                ]
            )
            return rows.compactMap { row in
                let relativePath: String = row["relativePath"]
                let content: String = row["content"]
                guard let match = content.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) else {
                    return nil
                }
                let line = content[..<match.lowerBound].reduce(1) {
                    $1 == "\n" ? $0 + 1 : $0
                }
                let lines = content.split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                )
                let snippet = line <= lines.count
                    ? String(lines[line - 1]).trimmingCharacters(
                        in: .whitespaces
                    )
                    : query
                return NoteSearchResult(
                    relativePath: relativePath,
                    snippet: snippet,
                    line: line
                )
            }
        }
    }
}
