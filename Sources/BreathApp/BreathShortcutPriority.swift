import AppKit
import BreathCore
import SwiftUI

struct BreathShortcutDefinition {
    let character: Character
    let modifiers: EventModifiers

    init(_ character: Character, modifiers: EventModifiers) {
        self.character = character
        self.modifiers = modifiers
    }

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }

    func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty,
              Self.modifiers(from: event.modifierFlags) == modifiers
        else {
            return false
        }
        return String(character).caseInsensitiveCompare(characters) == .orderedSame
    }

    private static func modifiers(
        from flags: NSEvent.ModifierFlags
    ) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}

enum BreathShortcutCatalog {
    static let openMainWindow = BreathShortcutDefinition("n", modifiers: [.command])
    static let newWorkSession = BreathShortcutDefinition("t", modifiers: [.command])
    static let openSettings = BreathShortcutDefinition(",", modifiers: [.command])
    static let splitHorizontally = BreathShortcutDefinition("d", modifiers: [.command])
    static let splitVertically = BreathShortcutDefinition(
        "d",
        modifiers: [.command, .shift]
    )
    static let closePane = BreathShortcutDefinition("w", modifiers: [.command])

    static func selectPane(_ number: Int) -> BreathShortcutDefinition {
        BreathShortcutDefinition(
            Character(String(number)),
            modifiers: [.command]
        )
    }

    static func matches(_ event: NSEvent) -> Bool {
        let definitions = [
            openMainWindow,
            newWorkSession,
            openSettings,
            splitHorizontally,
            splitVertically,
            closePane,
        ] + (1...9).map(selectPane)
        return definitions.contains { $0.matches(event) }
    }
}

struct BreathShortcutPriority: Equatable {
    private(set) var focusedTerminalPaneID: TerminalPaneID?
    private(set) var lastFocusedTerminalPaneID: TerminalPaneID?

    mutating func updateTerminalFocus(
        paneID: TerminalPaneID,
        isFocused: Bool
    ) {
        if isFocused {
            focusedTerminalPaneID = paneID
            lastFocusedTerminalPaneID = paneID
        } else if focusedTerminalPaneID == paneID {
            focusedTerminalPaneID = nil
        }
    }

    func allowsBreathShortcut(targeting paneID: TerminalPaneID? = nil) -> Bool {
        guard let paneID else { return true }
        return (focusedTerminalPaneID ?? lastFocusedTerminalPaneID) == paneID
    }
}

extension View {
    func breathKeyboardShortcut(
        _ shortcut: BreathShortcutDefinition,
        priority: BreathShortcutPriority,
        targeting paneID: TerminalPaneID? = nil
    ) -> some View {
        keyboardShortcut(
            priority.allowsBreathShortcut(targeting: paneID)
                ? shortcut.keyboardShortcut
                : nil
        )
    }
}
