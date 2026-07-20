import AppKit
import BreathCore
import BreathTerminal
import Foundation
import Testing
@testable import BreathApp

@Suite("Terminal keyboard shortcuts")
struct TerminalKeyboardShortcutTests {
    @Test("Command-W requests closing the focused terminal pane")
    func commandWClosesFocusedPane() {
        #expect(
            TerminalKeyboardShortcut.requestsPaneClose(
                modifiers: [.command],
                charactersIgnoringModifiers: "w",
                isRepeat: false
            )
        )
        #expect(
            TerminalKeyboardShortcut.requestsPaneClose(
                modifiers: [.command, .capsLock],
                charactersIgnoringModifiers: "W",
                isRepeat: false
            )
        )
        #expect(
            !TerminalKeyboardShortcut.requestsPaneClose(
                modifiers: [.command, .shift],
                charactersIgnoringModifiers: "w",
                isRepeat: false
            )
        )
        #expect(
            !TerminalKeyboardShortcut.requestsPaneClose(
                modifiers: [.command],
                charactersIgnoringModifiers: "w",
                isRepeat: true
            )
        )
    }

    @MainActor
    @Test("Command-W transfers focus so it can close terminals consecutively")
    func commandWTransfersFocusForConsecutiveCloses() async throws {
        let firstTerminalView = FocusableTerminalTestView()
        let secondTerminalView = FocusableTerminalTestView()
        let thirdTerminalView = FocusableTerminalTestView()
        let firstHost = TerminalHostView()
        let secondHost = TerminalHostView()
        let thirdHost = TerminalHostView()
        firstHost.install(firstTerminalView)
        secondHost.install(secondTerminalView)
        thirdHost.install(thirdTerminalView)

        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 960, height: 180)
        )
        firstHost.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        secondHost.frame = NSRect(x: 320, y: 0, width: 320, height: 180)
        thirdHost.frame = NSRect(x: 640, y: 0, width: 320, height: 180)
        contentView.addSubview(firstHost)
        contentView.addSubview(secondHost)
        contentView.addSubview(thirdHost)
        let window = TerminalFocusTestWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        var closedTerminalCount = 0
        firstHost.onCloseShortcut = { completion in
            closedTerminalCount += 1
            firstHost.removeFromSuperview()
            completion(true)
        }
        secondHost.onCloseShortcut = { completion in
            closedTerminalCount += 1
            secondHost.removeFromSuperview()
            completion(true)
        }
        thirdHost.onCloseShortcut = { completion in
            closedTerminalCount += 1
            thirdHost.removeFromSuperview()
            completion(true)
        }

        #expect(window.makeFirstResponder(firstTerminalView))
        NSApp.sendEvent(try commandWEvent(for: window, eventNumber: 1))
        await Task.yield()

        #expect(closedTerminalCount == 1)
        #expect(window.firstResponder === secondTerminalView)

        NSApp.sendEvent(try commandWEvent(for: window, eventNumber: 2))
        await Task.yield()

        #expect(closedTerminalCount == 2)
        #expect(window.firstResponder === thirdTerminalView)

        NSApp.sendEvent(try commandWEvent(for: window, eventNumber: 3))
        await Task.yield()

        #expect(closedTerminalCount == 2)
        #expect(window.firstResponder === thirdTerminalView)
    }

    @MainActor
    @Test("Command-W cannot queue closing the final terminal while the prior close is pending")
    func commandWDoesNotQueueClosingFinalTerminal() async throws {
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
        var closeRequestCount = 0
        var pendingCompletion: TerminalPaneCloseCompletion?
        firstHost.onCloseShortcut = { completion in
            closeRequestCount += 1
            pendingCompletion = completion
        }
        secondHost.onCloseShortcut = { completion in
            closeRequestCount += 1
            completion(true)
        }

        #expect(window.makeFirstResponder(firstTerminalView))
        NSApp.sendEvent(try commandWEvent(for: window, eventNumber: 1))
        await Task.yield()
        #expect(closeRequestCount == 1)
        #expect(window.firstResponder === secondTerminalView)

        NSApp.sendEvent(try commandWEvent(for: window, eventNumber: 2))
        await Task.yield()

        #expect(closeRequestCount == 1)
        #expect(window.firstResponder === secondTerminalView)

        firstHost.removeFromSuperview()
        pendingCompletion?(true)
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
}

@MainActor
private func commandWEvent(
    for window: NSWindow,
    eventNumber: Int
) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )
    )
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
