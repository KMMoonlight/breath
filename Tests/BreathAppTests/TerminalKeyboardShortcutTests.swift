import AppKit
import BreathCore
import BreathTerminal
import Foundation
import Testing
@testable import BreathApp

@Suite("Terminal keyboard shortcuts")
struct TerminalKeyboardShortcutTests {
    @Test("session tabs and split panes use the requested navigation shortcuts")
    func requestedNavigationShortcuts() throws {
        let nextTab = try commandKeyEvent("n")
        let previousPane = try commandKeyEvent("[")
        let nextPane = try commandKeyEvent("]")
        let formerNumberShortcut = try commandKeyEvent("1")

        #expect(BreathShortcutCatalog.nextWorkSessionTab.matches(nextTab))
        #expect(BreathShortcutCatalog.previousPane.matches(previousPane))
        #expect(BreathShortcutCatalog.nextPane.matches(nextPane))
        #expect(!BreathShortcutCatalog.matches(formerNumberShortcut))
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

    @Test("terminal-consumed shortcut does not reach Breath")
    func terminalConsumedShortcutStopsRouting() {
        let event = "shift-tab"

        let forwarded = TerminalShortcutArbitrator.eventToForward(
            event,
            terminalHasInputFocus: true,
            matchesBreathShortcut: { _ in true },
            terminalHandler: { _ in true }
        )

        #expect(forwarded == nil)
    }

    @Test("unhandled terminal shortcut falls back to Breath")
    func unhandledTerminalShortcutFallsBackToBreath() {
        let event = "command-t"

        let forwarded = TerminalShortcutArbitrator.eventToForward(
            event,
            terminalHasInputFocus: true,
            matchesBreathShortcut: { _ in true },
            terminalHandler: { _ in false }
        )

        #expect(forwarded == event)
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
