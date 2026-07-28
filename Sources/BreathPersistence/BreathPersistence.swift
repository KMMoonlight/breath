import BreathAutomation
import BreathCore
import BreathSkills
import Foundation
import GRDB

public final class SQLiteWorkbenchRepository: WorkbenchRepository, SettingsRepository,
    SkillInstallationRecordRepository, AutomationRepository, @unchecked Sendable
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
}
