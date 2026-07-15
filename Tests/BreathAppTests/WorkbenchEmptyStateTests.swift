import Foundation
import BreathTestSupport
import Testing

@Suite("Workbench empty states")
struct WorkbenchEmptyStateTests {
    @Test("passive workbench empty states keep the App Shell quiet")
    func passiveEmptyStatesAreQuiet() async throws {
        await NativeUITestGate.shared.acquire()
        defer { NativeUITestGate.shared.release() }
        let packageDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let executable = packageDirectory.appendingPathComponent(".build/debug/Breath")
        let sparkle = packageDirectory.appendingPathComponent(".build/debug/Sparkle.framework")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppShellTestError.missingExecutable(executable.path)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-app-shell-\(UUID().uuidString)", isDirectory: true)
        let app = temporaryDirectory.appendingPathComponent("BreathAppShellVerifier.app", isDirectory: true)
        let macOSDirectory = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resultURL = temporaryDirectory.appendingPathComponent("result.txt")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(
            at: macOSDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: macOSDirectory.appendingPathComponent("Breath"),
            withDestinationURL: executable
        )
        try FileManager.default.createSymbolicLink(
            at: macOSDirectory.appendingPathComponent("Sparkle.framework"),
            withDestinationURL: sparkle
        )
        try makeInfoPlist(
            from: packageDirectory.appendingPathComponent("Resources/Info.plist.in"),
            at: app.appendingPathComponent("Contents/Info.plist")
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-W",
            "-n",
            app.path,
            "--args",
            "--verify-quiet-empty-states",
            "--result-file",
            resultURL.path,
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let processOutput = String(data: data, encoding: .utf8) ?? ""
        let result = (try? String(contentsOf: resultURL, encoding: .utf8)) ?? processOutput

        #expect(
            process.terminationReason == .exit
                && process.terminationStatus == 0
                && result == "ok",
            Comment(rawValue: result.isEmpty ? "isolated App Shell verifier failed" : result)
        )
    }
}

private func makeInfoPlist(from templateURL: URL, at destinationURL: URL) throws {
    let data = try Data(contentsOf: templateURL)
    guard var plist = try PropertyListSerialization.propertyList(
        from: data,
        format: nil
    ) as? [String: Any] else {
        throw AppShellTestError.invalidInfoPlist
    }
    plist["CFBundleIdentifier"] = "app.breath.tests.app-shell.\(UUID().uuidString)"
    plist["CFBundleDisplayName"] = "Breath App Shell Verifier"
    plist["LSUIElement"] = true
    let result = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .xml,
        options: 0
    )
    try result.write(to: destinationURL, options: .atomic)
}

private enum AppShellTestError: Error {
    case invalidInfoPlist
    case missingExecutable(String)
}
