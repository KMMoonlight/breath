import BreathCore
import Foundation
import GRDB

public final class SQLiteWorkbenchRepository: WorkbenchRepository, SettingsRepository, @unchecked Sendable {
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
}
