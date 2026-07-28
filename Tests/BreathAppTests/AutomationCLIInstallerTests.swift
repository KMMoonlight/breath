import Foundation
import Testing
@testable import BreathApp

@Suite("Automation CLI installer")
struct AutomationCLIInstallerTests {
    @Test("installs a Breath-owned symlink without changing PATH")
    func installsSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let executable = root.appendingPathComponent("Breath")
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = AutomationCLIInstaller(
            homeDirectory: home,
            applicationExecutableURL: executable
        )

        #expect(installer.status() == .notInstalled)
        try installer.install()
        #expect(installer.status() == .installed)
        let destination = home.appendingPathComponent(".local/bin/breath")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: destination.path
            ) == executable.path
        )
    }

    @Test("does not overwrite an existing command")
    func preservesExistingCommand() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        let executable = root.appendingPathComponent("Breath")
        try FileManager.default.createDirectory(
            at: bin,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("breath").path,
            contents: Data("user command".utf8)
        )
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = AutomationCLIInstaller(
            homeDirectory: home,
            applicationExecutableURL: executable
        )

        #expect(installer.status() == .conflict)
        #expect(throws: AutomationCLIInstallerError.destinationOccupied) {
            try installer.install()
        }
        #expect(
            try String(
                contentsOf: bin.appendingPathComponent("breath"),
                encoding: .utf8
            ) == "user command"
        )
    }

    @Test("trigger command never launches Breath when its socket is absent")
    func triggerDoesNotLaunchApplication() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: home) }
        var output: [String] = []
        var errors: [String] = []

        let exitCode = AutomationTriggerCommand().run(
            arguments: ["trigger", "K7mQ2xR8v4Np"],
            homeDirectory: home,
            standardOutput: { output.append($0) },
            standardError: { errors.append($0) }
        )

        #expect(exitCode != 0)
        #expect(output.isEmpty)
        #expect(errors == ["Breath is not running"])
    }
}
