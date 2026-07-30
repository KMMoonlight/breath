import AppKit
import BreathCore
import BreathTestSupport
import BreathTerminal
import Foundation
import Testing
@testable import BreathApp

@Suite("Terminal keyboard shortcuts")
struct TerminalKeyboardShortcutTests {
    @Test("numbered session tabs and split panes use the requested navigation shortcuts")
    func requestedNavigationShortcuts() throws {
        let firstTab = try commandKeyEvent("1")
        let ninthTab = try commandKeyEvent("9")
        let formerNextTab = try commandKeyEvent("n")
        let newSession = try commandKeyEvent("t")
        let previousPane = try commandKeyEvent("[")
        let nextPane = try commandKeyEvent("]")

        #expect(BreathShortcutCatalog.workSessionTabs[0].shortcut.matches(firstTab))
        #expect(BreathShortcutCatalog.workSessionTabs[8].shortcut.matches(ninthTab))
        #expect(
            BreathShortcutCatalog.match(for: formerNextTab) == nil
        )
        #expect(BreathShortcutCatalog.newWorkSession.matches(newSession))
        #expect(BreathShortcutCatalog.previousPane.matches(previousPane))
        #expect(BreathShortcutCatalog.nextPane.matches(nextPane))
    }

    @Test("terminal focus gives terminal shortcuts priority")
    func terminalFocusGivesTerminalPriority() {
        let paneID = TerminalPaneID(rawValue: UUID())
        var priority = BreathShortcutPriority()

        #expect(priority.allowsBreathShortcut())
        #expect(!priority.allowsBreathShortcut(targeting: paneID))

        priority.updateTerminalFocus(paneID: paneID, isFocused: true)

        #expect(priority.allowsBreathShortcut())
        #expect(priority.allowsBreathShortcut(targeting: paneID))

        priority.updateTerminalFocus(paneID: paneID, isFocused: false)

        #expect(priority.allowsBreathShortcut())
        #expect(priority.allowsBreathShortcut(targeting: paneID))
    }

    @Test("stale blur from another terminal does not clear the focused terminal")
    func staleTerminalBlurPreservesCurrentFocus() {
        let firstPaneID = TerminalPaneID(rawValue: UUID())
        let secondPaneID = TerminalPaneID(rawValue: UUID())
        var priority = BreathShortcutPriority()

        priority.updateTerminalFocus(paneID: firstPaneID, isFocused: true)
        priority.updateTerminalFocus(paneID: secondPaneID, isFocused: true)
        priority.updateTerminalFocus(paneID: firstPaneID, isFocused: false)

        #expect(priority.focusedTerminalPaneID == secondPaneID)
        #expect(priority.allowsBreathShortcut(targeting: secondPaneID))
        #expect(!priority.allowsBreathShortcut(targeting: firstPaneID))
    }

    @Test("each work session remembers its last focused pane")
    func workSessionsRememberLastFocusedPane() {
        let firstSessionID = WorkSessionID(rawValue: UUID())
        let secondSessionID = WorkSessionID(rawValue: UUID())
        let firstPaneID = TerminalPaneID(rawValue: UUID())
        let secondPaneID = TerminalPaneID(rawValue: UUID())
        var priority = BreathShortcutPriority()

        priority.updateTerminalFocus(
            paneID: firstPaneID,
            workSessionID: firstSessionID,
            isFocused: true
        )
        priority.updateTerminalFocus(
            paneID: secondPaneID,
            workSessionID: secondSessionID,
            isFocused: true
        )

        #expect(priority.lastFocusedTerminalPaneID(in: firstSessionID) == firstPaneID)
        #expect(priority.lastFocusedTerminalPaneID(in: secondSessionID) == secondPaneID)
    }

    @Test("Breath-first keeps registered application shortcuts in Breath")
    func breathFirstKeepsApplicationShortcuts() {
        let event = "command-t"
        var terminalReceivedEvent = false

        let forwarded = TerminalShortcutArbitrator.eventToForward(
            event,
            policy: .breathFirst,
            terminalHasInputFocus: true,
            shortcutMatch: { _ in .application },
            terminalHandler: { _ in terminalReceivedEvent = true }
        )

        #expect(forwarded == event)
        #expect(!terminalReceivedEvent)
    }

    @Test("terminal-first sends registered application shortcuts only to the terminal")
    func terminalFirstSendsApplicationShortcutsToTerminal() {
        let event = "command-t"
        var terminalReceivedEvent: String?

        let forwarded = TerminalShortcutArbitrator.eventToForward(
            event,
            policy: .terminalFirst,
            terminalHasInputFocus: true,
            shortcutMatch: { _ in .application },
            terminalHandler: { terminalReceivedEvent = $0 }
        )

        #expect(forwarded == nil)
        #expect(terminalReceivedEvent == event)
    }

    @Test("terminal-first keeps terminal-scoped Breath shortcuts in Breath")
    func terminalFirstKeepsTerminalScopedShortcuts() {
        let event = "command-d"
        var terminalReceivedEvent = false

        let forwarded = TerminalShortcutArbitrator.eventToForward(
            event,
            policy: .terminalFirst,
            terminalHasInputFocus: true,
            shortcutMatch: { _ in .terminal },
            terminalHandler: { _ in terminalReceivedEvent = true }
        )

        #expect(forwarded == event)
        #expect(!terminalReceivedEvent)
    }

    @Test("terminal-first keeps explicitly allowed application shortcuts in Breath")
    func terminalFirstKeepsAllowedApplicationShortcuts() {
        let event = "allowed-application-shortcut"
        var terminalReceivedEvent = false

        let forwarded = TerminalShortcutArbitrator.eventToForward(
            event,
            policy: .terminalFirst,
            terminalHasInputFocus: true,
            shortcutMatch: { _ in
                BreathShortcutMatch(
                    scope: .application,
                    allowInTerminal: true
                )
            },
            terminalHandler: { _ in terminalReceivedEvent = true }
        )

        #expect(forwarded == event)
        #expect(!terminalReceivedEvent)
    }

    @Test("unregistered shortcuts continue through the terminal input path")
    func unregisteredShortcutsContinueNormally() {
        let event = "shift-tab"
        var terminalReceivedEvent = false

        let forwarded = TerminalShortcutArbitrator.eventToForward(
            event,
            policy: .breathFirst,
            terminalHasInputFocus: true,
            shortcutMatch: { _ in nil },
            terminalHandler: { _ in terminalReceivedEvent = true }
        )

        #expect(forwarded == event)
        #expect(!terminalReceivedEvent)
    }

    @Test("shortcut catalog separates application and terminal ownership")
    func shortcutCatalogSeparatesOwnership() throws {
        #expect(
            BreathShortcutCatalog.match(for: try commandKeyEvent("t"))
                == .application
        )
        #expect(
            BreathShortcutCatalog.match(for: try commandKeyEvent("d"))
                == .terminal
        )
    }

    @Test("close shortcut closes the work-session tab when no split exists")
    func closeShortcutTargetsSinglePaneSession() {
        let sessionID = WorkSessionID(rawValue: UUID())
        let paneID = TerminalPaneID(rawValue: UUID())
        let session = WorkSession(
            id: sessionID,
            workspaceID: WorkspaceID(rawValue: UUID()),
            title: "Single pane",
            pane: TerminalPane(id: paneID)
        )

        #expect(
            TerminalCloseShortcutResolver.target(
                for: session,
                preferredPaneID: paneID
            ) == .workSession(sessionID)
        )
    }

    @Test("close shortcut closes the focused pane when the session is split")
    func closeShortcutTargetsFocusedSplitPane() {
        let sessionID = WorkSessionID(rawValue: UUID())
        let firstPaneID = TerminalPaneID(rawValue: UUID())
        let secondPaneID = TerminalPaneID(rawValue: UUID())
        let session = WorkSession(
            id: sessionID,
            workspaceID: WorkspaceID(rawValue: UUID()),
            title: "Split",
            layout: .split(
                orientation: .horizontal,
                fraction: 0.5,
                first: .pane(TerminalPane(id: firstPaneID)),
                second: .pane(TerminalPane(id: secondPaneID))
            )
        )

        #expect(
            TerminalCloseShortcutResolver.target(
                for: session,
                preferredPaneID: secondPaneID
            ) == .pane(secondPaneID)
        )
    }

    @MainActor
    @Test("terminal focus moves input to the requested pane")
    func terminalFocusMovesInputToRequestedPane() {
        let paneID = TerminalPaneID(rawValue: UUID())
        let terminalView = FocusableTerminalTestView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180)
        )
        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180)
        )
        contentView.addSubview(terminalView)
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        let provider = TerminalFocusTestProvider(
            paneID: paneID,
            terminalView: terminalView
        )

        #expect(TerminalInputFocus.move(to: paneID, using: provider))
        #expect(window.firstResponder === terminalView)
    }

    @MainActor
    @Test("moving terminal focus clears the previous pane state")
    func movingTerminalFocusClearsPreviousPaneState() async {
        let secondPaneID = TerminalPaneID(rawValue: UUID())
        let firstTerminalView = FocusableTerminalTestView()
        let secondTerminalView = FocusableTerminalTestView()
        let firstHost = TerminalHostView()
        let secondHost = TerminalHostView()
        firstHost.install(firstTerminalView)
        secondHost.install(secondTerminalView)

        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 180)
        )
        firstHost.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        secondHost.frame = NSRect(x: 320, y: 0, width: 320, height: 180)
        contentView.addSubview(firstHost)
        contentView.addSubview(secondHost)
        let window = TerminalFocusTestWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        let provider = TerminalFocusTestProvider(
            paneID: secondPaneID,
            terminalView: secondTerminalView
        )
        var firstHasInputFocus = false
        var secondHasInputFocus = false
        firstHost.onFocusChange = { firstHasInputFocus = $0 }
        secondHost.onFocusChange = { secondHasInputFocus = $0 }

        #expect(window.makeFirstResponder(firstTerminalView))
        firstHost.synchronizeFocusState()
        #expect(firstHasInputFocus)

        #expect(TerminalInputFocus.move(to: secondPaneID, using: provider))
        await Task.yield()
        #expect(window.firstResponder === secondTerminalView)
        #expect(!firstHasInputFocus)
        #expect(secondHasInputFocus)
    }

    @MainActor
    @Test("clicking an application panel preserves visible terminal focus")
    func clickingApplicationPanelPreservesVisibleTerminalFocus() async throws {
        let terminalView = FocusableTerminalTestView()
        let terminalHost = TerminalHostView()
        terminalHost.install(terminalView)
        let applicationPanel = FocusStealingApplicationPanelTestView()
        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 180)
        )
        terminalHost.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        applicationPanel.frame = NSRect(x: 320, y: 0, width: 320, height: 180)
        contentView.addSubview(terminalHost)
        contentView.addSubview(applicationPanel)
        let window = TerminalFocusTestWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        var terminalHasInputFocus = false
        terminalHost.onFocusChange = { terminalHasInputFocus = $0 }

        #expect(window.makeFirstResponder(terminalView))
        terminalHost.synchronizeFocusState()
        #expect(terminalHasInputFocus)

        let click = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 480, y: 90),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        NSApp.sendEvent(click)
        applicationPanel.mouseDown(with: click)
        await Task.yield()

        #expect(window.firstResponder === terminalView)
        #expect(terminalHasInputFocus)
    }

    @MainActor
    @Test("a terminal leaving the visible window clears its focus state")
    func hiddenTerminalClearsFocusState() {
        let terminalView = FocusableTerminalTestView()
        let terminalHost = TerminalHostView()
        terminalHost.install(terminalView)
        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180)
        )
        terminalHost.frame = contentView.bounds
        contentView.addSubview(terminalHost)
        let window = TerminalFocusTestWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        var terminalHasInputFocus = false
        terminalHost.onFocusChange = { terminalHasInputFocus = $0 }

        #expect(window.makeFirstResponder(terminalView))
        terminalHost.synchronizeFocusState()
        #expect(terminalHasInputFocus)

        terminalHost.isHidden = true

        #expect(window.firstResponder !== terminalView)
        #expect(!terminalHasInputFocus)
    }

    @MainActor
    @Test("a hidden retained terminal stops monitoring keyboard events")
    func hiddenRetainedTerminalStopsMonitoringKeyboardEvents() async throws {
        await NativeUITestGate.shared.acquire()
        defer { NativeUITestGate.shared.release() }
        _ = NSApplication.shared
        let terminalView = FocusableTerminalTestView()
        let terminalHost = TerminalHostView()
        terminalHost.install(terminalView)
        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180)
        )
        terminalHost.frame = contentView.bounds
        contentView.addSubview(terminalHost)
        let window = TerminalFocusTestWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        #expect(terminalHost.isMonitoringFocusEvents)

        terminalHost.isHidden = true
        #expect(!terminalHost.isMonitoringFocusEvents)

        terminalHost.isHidden = false
        #expect(terminalHost.isMonitoringFocusEvents)
    }

    private func commandKeyEvent(_ characters: String) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 0
            )
        )
    }
}

@MainActor
private final class TerminalFocusTestProvider: TerminalViewProviding {
    let paneID: TerminalPaneID
    let terminalView: NSView

    init(paneID: TerminalPaneID, terminalView: NSView) {
        self.paneID = paneID
        self.terminalView = terminalView
    }

    func view(for paneID: TerminalPaneID) -> NSView? {
        paneID == self.paneID ? terminalView : nil
    }
}

private final class FocusableTerminalTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private final class FocusStealingApplicationPanelTestView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
}

@MainActor
private final class TerminalFocusTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
