import BreathCore
import CoreGraphics
import Foundation
import BreathTestSupport
import Testing
@testable import BreathApp

@Suite("Workbench empty states")
struct WorkbenchEmptyStateTests {
    @Test("blank canvas rejects icon-only placeholder pixels")
    func canvasTopologyRejectsIconOnlyContent() throws {
        let background = TerminalRGBColor(red: 0x10, green: 0x12, blue: 0x18)
        let solid = try SolidCanvasInspection(
            image: makeCanvas(background: background, fixture: .solid),
            background: background
        )
        let icon = try SolidCanvasInspection(
            image: makeCanvas(background: background, fixture: .centeredIcon),
            background: background
        )
        let edgeDecoration = try SolidCanvasInspection(
            image: makeCanvas(background: background, fixture: .edgeDecoration),
            background: background
        )
        let smallRegion = try SolidCanvasInspection(
            image: makeCanvas(background: background, fixture: .smallBackgroundRegion),
            background: background
        )

        #expect(solid.isSolid)
        #expect(!icon.isSolid)
        #expect(edgeDecoration.isSolid)
        #expect(!smallRegion.isSolid)
    }

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

private func makeCanvas(
    background: TerminalRGBColor,
    fixture: CanvasFixture
) throws -> CGImage {
    let width = 100
    let height = 80
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    let backgroundColor = CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat(background.red) / 255,
            CGFloat(background.green) / 255,
            CGFloat(background.blue) / 255,
            1,
        ]
    )!
    let decorationColor = CGColor(
        colorSpace: colorSpace,
        components: [0.8, 0.8, 0.8, 1]
    )!
    context.setFillColor(backgroundColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    switch fixture {
    case .solid:
        break
    case .centeredIcon:
        context.setFillColor(decorationColor)
        context.fill(CGRect(x: 45, y: 30, width: 10, height: 20))
    case .edgeDecoration:
        context.setFillColor(decorationColor)
        context.fill(CGRect(x: 0, y: 38, width: 30, height: 4))
    case .smallBackgroundRegion:
        context.setFillColor(decorationColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 40, y: 30, width: 20, height: 20))
    }
    return try #require(context.makeImage())
}

private enum CanvasFixture {
    case solid
    case centeredIcon
    case edgeDecoration
    case smallBackgroundRegion
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
