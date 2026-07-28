#if DEBUG
import AppKit
import BreathAutomation
import BreathCore
import BreathTerminal
import Foundation

@MainActor
struct AppShellTestingHarness {
    let model: BreathApplicationModel
    let terminalEngine: AppShellTestingTerminalEngine

    init(
        snapshot: WorkbenchSnapshot,
        automationSnapshot: AutomationSnapshot = .empty,
        supportDirectory: URL
    ) throws {
        let terminalEngine = AppShellTestingTerminalEngine()
        self.terminalEngine = terminalEngine
        model = try BreathApplicationModel(
            homeDirectory: supportDirectory,
            supportDirectory: supportDirectory,
            terminalEngineOverride: terminalEngine
        )
        model.prepareForAppShellTesting(
            snapshot: snapshot,
            automationSnapshot: automationSnapshot
        )
    }
}

@MainActor
final class AppShellTestingTerminalEngine: TerminalEngine, TerminalViewProviding, @unchecked Sendable {
    private(set) var openedLaunches: [TerminalLaunch] = []

    func open(_ launch: TerminalLaunch) async throws {
        openedLaunches.append(launch)
    }

    func close(_ paneID: TerminalPaneID) async {}

    func apply(settings: TerminalSettings) async {}

    func view(for paneID: TerminalPaneID) -> NSView? {
        nil
    }
}
#endif
