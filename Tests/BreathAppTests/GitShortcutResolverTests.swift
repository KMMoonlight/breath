import SwiftUI
import Testing
@testable import BreathApp

@Suite("Git shortcut routing")
struct GitShortcutResolverTests {
    @Test("page shortcut events resolve without creating menu commands")
    @MainActor
    func resolvesPageShortcutEvent() throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "r",
                charactersIgnoringModifiers: "r",
                isARepeat: false,
                keyCode: 15
            )
        )

        #expect(
            GitShortcutResolver.commandID(
                matching: event,
                preferences: GitGlobalPreferences(),
                requiredScope: .gitWorkbench
            ) == "git.refresh"
        )
    }

    @Test("default Git shortcuts resolve in their declared scope")
    func resolvesDefaults() {
        let preferences = GitGlobalPreferences()

        #expect(
            GitShortcutResolver.resolve(
                commandID: "git.open",
                preferences: preferences,
                requiredScope: .global
            )?.modifiers == .command
        )
        #expect(
            GitShortcutResolver.resolve(
                commandID: "git.commit",
                preferences: preferences,
                requiredScope: .global
            ) == nil
        )
        #expect(
            GitShortcutResolver.resolve(
                commandID: "git.nextDifference",
                preferences: preferences
            ) != nil
        )
    }

    @Test("conflicting shortcuts are visible in settings but not activated")
    func rejectsConflicts() {
        var preferences = GitGlobalPreferences()
        preferences.shortcuts = [
            GitShortcutBinding(
                commandID: "git.open",
                keys: "⌘9",
                scope: .global
            ),
            GitShortcutBinding(
                commandID: "git.push",
                keys: "⌘9",
                scope: .global
            ),
        ]

        #expect(
            GitShortcutResolver.resolve(
                commandID: "git.open",
                preferences: preferences
            ) == nil
        )
        #expect(
            GitShortcutResolver.resolve(
                commandID: "git.push",
                preferences: preferences
            ) == nil
        )
    }
}
