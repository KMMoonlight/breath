import Foundation

enum AutomationCLIInstallationStatus: Equatable {
    case notInstalled
    case installed
    case conflict
}

enum AutomationCLIInstallerError: LocalizedError, Equatable {
    case destinationOccupied

    var errorDescription: String? {
        switch self {
        case .destinationOccupied:
            "“~/.local/bin/breath” 已存在，并且不属于 Breath。"
        }
    }
}

struct AutomationCLIInstaller {
    let homeDirectory: URL
    let applicationExecutableURL: URL

    private var binDirectory: URL {
        homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
    }

    var destinationURL: URL {
        binDirectory.appendingPathComponent("breath")
    }

    func status() -> AutomationCLIInstallationStatus {
        guard FileManager.default.fileExists(
            atPath: destinationURL.path
        ) || (try? destinationURL.resourceValues(
            forKeys: [.isSymbolicLinkKey]
        ).isSymbolicLink) == true
        else {
            return .notInstalled
        }
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(
            atPath: destinationURL.path
        ) else {
            return .conflict
        }
        let resolvedDestination: URL
        if destination.hasPrefix("/") {
            resolvedDestination = URL(fileURLWithPath: destination)
        } else {
            resolvedDestination = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(destination)
        }
        return resolvedDestination.standardizedFileURL
            == applicationExecutableURL.standardizedFileURL
            ? .installed
            : .conflict
    }

    func install() throws {
        switch status() {
        case .installed:
            return
        case .conflict:
            throw AutomationCLIInstallerError.destinationOccupied
        case .notInstalled:
            break
        }
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.createSymbolicLink(
            at: destinationURL,
            withDestinationURL: applicationExecutableURL
        )
    }
}
