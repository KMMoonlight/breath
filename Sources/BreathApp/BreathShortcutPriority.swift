import AppKit
import BreathCore
import SwiftUI

struct BreathShortcutDefinition {
    let character: Character
    let modifiers: EventModifiers

    init(_ shortcut: BreathShortcut) {
        character = shortcut.character
        var eventModifiers: EventModifiers = []
        if shortcut.modifiers.contains(.command) { eventModifiers.insert(.command) }
        if shortcut.modifiers.contains(.option) { eventModifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { eventModifiers.insert(.control) }
        if shortcut.modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        modifiers = eventModifiers
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

struct WorkSessionTabShortcut: Identifiable {
    let selectionIndex: Int
    let displayNumber: Int
    let shortcut: BreathShortcutDefinition

    var id: Int { selectionIndex }
}

enum BreathShortcutCatalog {
    static let newWorkSession = BreathShortcutDefinition(.newWorkSession)
    static let workSessionTabs = BreathShortcut.workSessionTabs
        .enumerated()
        .map { offset, shortcut in
            WorkSessionTabShortcut(
                selectionIndex: offset,
                displayNumber: offset + 1,
                shortcut: BreathShortcutDefinition(shortcut)
            )
        }
    static let previousPane = BreathShortcutDefinition(.previousPane)
    static let nextPane = BreathShortcutDefinition(.nextPane)
    static let openSettings = BreathShortcutDefinition(.openSettings)
    static let splitHorizontally = BreathShortcutDefinition(.splitHorizontally)
    static let splitVertically = BreathShortcutDefinition(.splitVertically)
    static let closePane = BreathShortcutDefinition(.closePane)
    private static let terminalFirst = BreathShortcut.terminalFirst.map(
        BreathShortcutDefinition.init
    )

    static func matchesTerminalFirstShortcut(_ event: NSEvent) -> Bool {
        terminalFirst.contains { $0.matches(event) }
    }
}

struct BreathShortcutPriority: Equatable {
    private(set) var focusedTerminalPaneID: TerminalPaneID?
    private(set) var lastFocusedTerminalPaneID: TerminalPaneID?
    private var lastFocusedPaneIDsByWorkSession: [WorkSessionID: TerminalPaneID] = [:]

    mutating func updateTerminalFocus(
        paneID: TerminalPaneID,
        workSessionID: WorkSessionID? = nil,
        isFocused: Bool
    ) {
        if isFocused {
            focusedTerminalPaneID = paneID
            lastFocusedTerminalPaneID = paneID
            if let workSessionID {
                lastFocusedPaneIDsByWorkSession[workSessionID] = paneID
            }
        } else if focusedTerminalPaneID == paneID {
            focusedTerminalPaneID = nil
        }
    }

    func lastFocusedTerminalPaneID(
        in workSessionID: WorkSessionID
    ) -> TerminalPaneID? {
        lastFocusedPaneIDsByWorkSession[workSessionID]
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
