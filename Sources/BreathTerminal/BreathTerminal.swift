import BreathCore
import AppKit

public protocol TerminalEngine: Sendable {
    func open(_ launch: TerminalLaunch) async throws
    func close(_ paneID: TerminalPaneID) async
    func apply(settings: TerminalSettings) async
}

@MainActor
public protocol TerminalViewProviding: AnyObject {
    func view(for paneID: TerminalPaneID) -> NSView?
}

public final class TerminalEngineRuntime: TerminalRuntime, @unchecked Sendable {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    public func launch(_ request: TerminalLaunch) async throws {
        try await engine.open(request)
    }

    public func stop(paneID: TerminalPaneID) async {
        await engine.close(paneID)
    }

    public func apply(settings: TerminalSettings) async {
        await engine.apply(settings: settings)
    }
}
