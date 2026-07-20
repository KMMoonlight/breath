import AppKit
import BreathCore
import BreathPersistence
import BreathTerminal
import Foundation
import Testing
@testable import BreathApp

@Suite("Startup restoration")
struct StartupRestorationTests {
    @MainActor
    @Test("saved layout becomes visible before a slow Agent resume finishes")
    func savedLayoutPrecedesAgentResume() async throws {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-startup-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let storedSnapshot = WorkbenchSnapshot(
            workspaces: [
                Workspace(
                    id: workspaceID,
                    path: supportDirectory.path,
                    displayName: "Startup test"
                ),
            ],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Restored Agent",
                    pane: TerminalPane(
                        id: paneID,
                        state: .running,
                        agentBinding: AgentBinding(
                            agent: .codex,
                            sessionID: "thread-123",
                            isActive: true
                        )
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: supportDirectory.appendingPathComponent("breath.sqlite")
        )
        try await repository.save(storedSnapshot)
        let terminalEngine = SuspendedStartupTerminalEngine()
        let model = try BreathApplicationModel(
            homeDirectory: supportDirectory,
            supportDirectory: supportDirectory,
            terminalEngineOverride: terminalEngine
        )

        model.start()
        for _ in 0..<1_000 {
            if model.isReady && terminalEngine.openCallCount == 1 { break }
            await Task.yield()
        }

        #expect(model.isReady)
        #expect(model.isRestoringSelectedSession)
        #expect(model.snapshot == storedSnapshot)
        #expect(!model.canPerformCommands)

        terminalEngine.allowOpen()
        for _ in 0..<1_000 {
            if model.canPerformCommands { break }
            await Task.yield()
        }

        #expect(model.canPerformCommands)
        #expect(!model.isRestoringSelectedSession)
    }

    @MainActor
    @Test("closing a split updates the app snapshot before terminal teardown finishes")
    func closeSplitPublishesBeforeTeardown() async throws {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-close-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let firstPaneID = TerminalPaneID(rawValue: UUID())
        let secondPaneID = TerminalPaneID(rawValue: UUID())
        let storedSnapshot = WorkbenchSnapshot(
            workspaces: [
                Workspace(
                    id: workspaceID,
                    path: supportDirectory.path,
                    displayName: "Close test"
                ),
            ],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Split session",
                    layout: .split(
                        orientation: .horizontal,
                        fraction: 0.5,
                        first: .pane(TerminalPane(id: firstPaneID)),
                        second: .pane(TerminalPane(id: secondPaneID))
                    )
                ),
            ],
            selectedWorkSessionID: sessionID
        )
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: supportDirectory.appendingPathComponent("breath.sqlite")
        )
        try await repository.save(storedSnapshot)
        let terminalEngine = SuspendedCloseTerminalEngine()
        let model = try BreathApplicationModel(
            homeDirectory: supportDirectory,
            supportDirectory: supportDirectory,
            terminalEngineOverride: terminalEngine
        )
        model.start()
        for _ in 0..<1_000 {
            if model.canPerformCommands { break }
            await Task.yield()
        }

        var closeCompleted = false
        model.closePane(secondPaneID) { didClose in
            closeCompleted = didClose
        }
        for _ in 0..<1_000 {
            if terminalEngine.closeCallCount == 1 { break }
            await Task.yield()
        }

        #expect(terminalEngine.closeCallCount == 1)
        #expect(model.snapshot.workSessions.first?.layout.paneIDs == [firstPaneID])
        #expect(!closeCompleted)

        terminalEngine.allowCloses()
        for _ in 0..<1_000 {
            if closeCompleted { break }
            await Task.yield()
        }
        #expect(closeCompleted)
    }
}

@MainActor
private final class SuspendedStartupTerminalEngine:
    TerminalEngine,
    TerminalViewProviding,
    @unchecked Sendable
{
    private(set) var openCallCount = 0
    private var opensAllowed = false

    func open(_ launch: TerminalLaunch) async throws {
        openCallCount += 1
        while !opensAllowed { await Task.yield() }
    }

    func close(_ paneID: TerminalPaneID) async {}

    func apply(settings: TerminalSettings) async {}

    func view(for paneID: TerminalPaneID) -> NSView? {
        nil
    }

    func allowOpen() {
        opensAllowed = true
    }
}

@MainActor
private final class SuspendedCloseTerminalEngine:
    TerminalEngine,
    TerminalViewProviding,
    @unchecked Sendable
{
    private(set) var closeCallCount = 0
    private var closesAllowed = false

    func open(_ launch: TerminalLaunch) async throws {}

    func close(_ paneID: TerminalPaneID) async {
        closeCallCount += 1
        while !closesAllowed { await Task.yield() }
    }

    func apply(settings: TerminalSettings) async {}

    func view(for paneID: TerminalPaneID) -> NSView? {
        nil
    }

    func allowCloses() {
        closesAllowed = true
    }
}
