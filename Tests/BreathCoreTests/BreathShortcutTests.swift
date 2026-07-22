import Testing
@testable import BreathCore

@Suite("Application shortcuts")
struct BreathShortcutTests {
    @Test("one inventory owns numbered tabs and terminal arbitration")
    func sharedInventory() {
        #expect(
            BreathShortcut.workSessionTabs.map(\.character)
                == Array("123456789")
        )
        #expect(BreathShortcut.terminalFirst.contains(.newWorkSession))
        #expect(BreathShortcut.terminalFirst.contains(.previousPane))
        #expect(BreathShortcut.terminalFirst.contains(.nextPane))
        #expect(BreathShortcut.terminalFirst.contains(.openSettings))
        #expect(BreathShortcut.terminalFirst.contains(.splitHorizontally))
        #expect(BreathShortcut.terminalFirst.contains(.splitVertically))
        #expect(BreathShortcut.terminalFirst.contains(.closePane))
    }
}
