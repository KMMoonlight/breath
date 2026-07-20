import AppKit
import BreathCore
@testable import BreathTerminal
import BreathTestSupport
import Foundation
import ObjectiveC.runtime
import Testing

@Suite("Terminal engine boundary")
struct TerminalEngineRuntimeTests {
    @Test("multiline and control-character pastes require explicit confirmation")
    func pasteSafety() {
        #expect(!TerminalPasteSafety.requiresConfirmation("git status"))
        #expect(TerminalPasteSafety.requiresConfirmation("git status\ngit push"))
        #expect(TerminalPasteSafety.requiresConfirmation("echo ok\u{001B}"))
    }

    @Test("runtime forwards shell lifecycle and live terminal-only styling")
    func lifecycleAndStyle() async throws {
        let engine = RecordingTerminalEngine()
        let runtime = TerminalEngineRuntime(engine: engine)
        let paneID = TerminalPaneID(rawValue: UUID())
        let launch = TerminalLaunch(
            paneID: paneID,
            workingDirectory: "/tmp/project",
            executable: "/bin/zsh",
            arguments: ["-l"],
            environment: ["BREATH_TERMINAL_PANE_ID": paneID.rawValue.uuidString]
        )
        let style = TerminalSettings(
            fontFamily: "SF Mono",
            fontSize: 15,
            colorTheme: .solarizedDark,
            cursorStyle: .bar
        )

        try await runtime.launch(launch)
        await runtime.apply(settings: style)
        await runtime.stop(paneID: paneID)

        #expect(await engine.opened == [launch])
        #expect(await engine.appliedSettings == [style])
        #expect(await engine.closed == [paneID])
    }

    @Test("libghostty creates a native surface, accepts composed text, resizes, and reloads style")
    @MainActor
    func libghosttySurfaceSmoke() async throws {
        await NativeUITestGate.shared.acquire()
        defer { NativeUITestGate.shared.release() }
        try await verifyLibghosttySurface()
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test("writing Ghostty configuration does not instantiate AppKit's shared font manager")
    @MainActor
    func configurationDoesNotAccessSharedFontManager() async throws {
        await NativeUITestGate.shared.acquire()
        defer { NativeUITestGate.shared.release() }

        let sharedSelector = NSSelectorFromString("sharedFontManager")
        let probeSelector = #selector(NSFontManager.breath_test_sharedFontManager)
        let sharedMethod = try #require(class_getClassMethod(NSFontManager.self, sharedSelector))
        let probeMethod = try #require(class_getClassMethod(NSFontManager.self, probeSelector))
        FontManagerSharedAccessProbe.accessCount = 0
        method_exchangeImplementations(sharedMethod, probeMethod)
        defer { method_exchangeImplementations(sharedMethod, probeMethod) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-font-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configurationURL = directory.appendingPathComponent("terminal.ghostty")
        try GhosttyTerminalEngine.writeConfiguration(
            TerminalSettings(fontFamily: "Menlo", colorTheme: .dracula),
            synchronizeRendering: false,
            to: configurationURL
        )

        #expect(FontManagerSharedAccessProbe.accessCount == 0)
        let contents = try String(contentsOf: configurationURL, encoding: .utf8)
        #expect(contents.contains("palette = 0=#21222C"))
        #expect(contents.contains("palette = 15=#FFFFFF"))
        #expect(contents.contains("background = #282A36"))
        #expect(contents.contains("selection-background = #44475A"))
    }
}

private enum FontManagerSharedAccessProbe {
    nonisolated(unsafe) static var accessCount = 0
}

private extension NSFontManager {
    @objc class func breath_test_sharedFontManager() -> NSFontManager {
        FontManagerSharedAccessProbe.accessCount += 1
        return breath_test_sharedFontManager()
    }
}

@MainActor
private func verifyLibghosttySurface() async throws {
    _ = NSApplication.shared
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("breath-ghostty-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let engine = try GhosttyTerminalEngine(
        configurationDirectory: directory,
        agentSocketURL: directory.appendingPathComponent("events.sock"),
        synchronizeRendering: false
    )
    guard engine.usesLibghostty else { return }

    let paneID = TerminalPaneID(rawValue: UUID())
    try await engine.open(
        TerminalLaunch(
            paneID: paneID,
            workingDirectory: "/tmp",
            executable: "/bin/zsh",
            arguments: ["-l"],
            environment: [:]
        )
    )
    let view = try #require(engine.view(for: paneID))
    view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
    view.layoutSubtreeIfNeeded()
    let textInput = try #require(view as? any NSTextInputClient)
    textInput.setMarkedText(
        "拼音",
        selectedRange: NSRange(location: 2, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    textInput.insertText(
        "中文",
        replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    await engine.apply(
        settings: TerminalSettings(
            fontFamily: "SF Mono",
            fontSize: 15,
            colorTheme: .solarizedDark,
            cursorStyle: .bar
        )
    )
    await engine.close(paneID)
    #expect(engine.view(for: paneID) == nil)
}

private actor RecordingTerminalEngine: TerminalEngine {
    private(set) var opened: [TerminalLaunch] = []
    private(set) var appliedSettings: [TerminalSettings] = []
    private(set) var closed: [TerminalPaneID] = []

    func open(_ launch: TerminalLaunch) throws {
        opened.append(launch)
    }

    func close(_ paneID: TerminalPaneID) {
        closed.append(paneID)
    }

    func apply(settings: TerminalSettings) {
        appliedSettings.append(settings)
    }
}
