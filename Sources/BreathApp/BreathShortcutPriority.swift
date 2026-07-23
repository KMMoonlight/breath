import AppKit
import BreathCore
import SwiftUI

struct BreathShortcutMatch: Equatable {
    let scope: BreathShortcut.Scope
    let allowInTerminal: Bool

    static let application = Self(scope: .application, allowInTerminal: false)
    static let terminal = Self(scope: .terminal, allowInTerminal: false)

    init(_ shortcut: BreathShortcut) {
        scope = shortcut.scope
        allowInTerminal = shortcut.allowInTerminal
    }

    init(scope: BreathShortcut.Scope, allowInTerminal: Bool) {
        self.scope = scope
        self.allowInTerminal = allowInTerminal
    }

    var isAllowedInTerminal: Bool {
        scope == .terminal || allowInTerminal
    }
}

struct BreathShortcutDefinition {
    let character: Character
    let modifiers: EventModifiers
    let match: BreathShortcutMatch

    init(_ shortcut: BreathShortcut) {
        character = shortcut.character
        var eventModifiers: EventModifiers = []
        if shortcut.modifiers.contains(.command) { eventModifiers.insert(.command) }
        if shortcut.modifiers.contains(.option) { eventModifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { eventModifiers.insert(.control) }
        if shortcut.modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        modifiers = eventModifiers
        match = BreathShortcutMatch(shortcut)
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
    private static let registered = BreathShortcut.registeredByBreath.map(
        BreathShortcutDefinition.init
    )

    static func match(for event: NSEvent) -> BreathShortcutMatch? {
        registered.first(where: { $0.matches(event) })?.match
    }
}

enum TerminalCloseShortcutTarget: Equatable {
    case pane(TerminalPaneID)
    case workSession(WorkSessionID)
}

enum TerminalCloseShortcutResolver {
    static func target(
        for session: WorkSession,
        preferredPaneID: TerminalPaneID?
    ) -> TerminalCloseShortcutTarget {
        let paneIDs = session.layout.paneIDs
        guard paneIDs.count > 1 else {
            return .workSession(session.id)
        }
        let paneID = preferredPaneID.flatMap { preferredPaneID in
            paneIDs.contains(preferredPaneID) ? preferredPaneID : nil
        } ?? paneIDs[0]
        return .pane(paneID)
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
