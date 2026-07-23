import Testing
@testable import BreathCore

@Suite("Application shortcuts")
struct BreathShortcutTests {
    @Test("one inventory owns terminal routing and Ghostty host unbinding")
    func sharedInventory() {
        #expect(
            BreathShortcut.workSessionTabs.map(\.character)
                == Array("123456789")
        )
        #expect(BreathShortcut.registeredByBreath.contains(.newWorkSession))
        #expect(BreathShortcut.registeredByBreath.contains(.previousPane))
        #expect(BreathShortcut.registeredByBreath.contains(.nextPane))
        #expect(BreathShortcut.registeredByBreath.contains(.openSettings))
        #expect(BreathShortcut.registeredByBreath.contains(.splitHorizontally))
        #expect(BreathShortcut.registeredByBreath.contains(.splitVertically))
        #expect(BreathShortcut.registeredByBreath.contains(.closePane))
        #expect(BreathShortcut.newWorkSession.scope == .application)
        #expect(BreathShortcut.previousPane.scope == .terminal)
        #expect(BreathShortcut.splitHorizontally.scope == .terminal)
    }
}
