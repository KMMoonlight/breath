import BreathCore
import AppKit

public protocol TerminalEngine: Sendable {
    func open(_ launch: TerminalLaunch) async throws
    func close(_ paneID: TerminalPaneID) async
    func apply(settings: TerminalSettings) async
    func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async
}

public extension TerminalEngine {
    func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async {}
}

public enum TerminalPasteSafety {
    public static func requiresConfirmation(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar == "\n" || scalar == "\r" || (scalar.value < 0x20 && scalar != "\t")
        }
    }
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

    public func setProcessExitHandler(
        _ handler: @escaping @Sendable (TerminalPaneID) -> Void
    ) async {
        await engine.setProcessExitHandler(handler)
    }
}
