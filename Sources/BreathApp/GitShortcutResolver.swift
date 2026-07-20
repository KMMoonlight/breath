import AppKit
import SwiftUI

struct GitResolvedShortcut: Equatable {
    let key: KeyEquivalent
    let character: Character
    let modifiers: EventModifiers
}

enum GitShortcutResolver {
    static func resolve(
        commandID: String,
        preferences: GitGlobalPreferences,
        requiredScope: GitShortcutScope? = nil
    ) -> GitResolvedShortcut? {
        guard let binding = preferences.shortcuts.first(where: {
            $0.commandID == commandID
        }), !binding.keys.isEmpty,
              requiredScope == nil || binding.scope == requiredScope
        else {
            return nil
        }
        let conflicts = preferences.shortcuts.contains {
            $0.commandID != binding.commandID
                && !$0.keys.isEmpty
                && $0.keys == binding.keys
                && (
                    $0.scope == binding.scope
                        || $0.scope == .global
                        || binding.scope == .global
                )
        }
        guard !conflicts else { return nil }
        return parse(binding.keys)
    }

    private static func parse(_ text: String) -> GitResolvedShortcut? {
        var remaining = text
        var modifiers: EventModifiers = []
        for (symbol, modifier) in [
            ("⌘", EventModifiers.command),
            ("⌥", EventModifiers.option),
            ("⌃", EventModifiers.control),
            ("⇧", EventModifiers.shift),
        ] where remaining.contains(symbol) {
            remaining = remaining.replacingOccurrences(of: symbol, with: "")
            modifiers.insert(modifier)
        }
        let normalized = remaining.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else { return nil }
        let keyCharacter: Character
        if normalized.hasPrefix("F"),
           let functionNumber = Int(normalized.dropFirst()),
           (1...20).contains(functionNumber),
           let scalar = UnicodeScalar(0xF703 + functionNumber)
        {
            keyCharacter = Character(scalar)
        } else if normalized.count == 1, let character = normalized.first {
            keyCharacter = Character(character.lowercased())
        } else {
            return nil
        }
        return GitResolvedShortcut(
            key: KeyEquivalent(keyCharacter),
            character: keyCharacter,
            modifiers: modifiers
        )
    }

    static func commandID(
        matching event: NSEvent,
        preferences: GitGlobalPreferences,
        requiredScope: GitShortcutScope
    ) -> String? {
        guard event.type == .keyDown,
              let eventCharacters = event.charactersIgnoringModifiers,
              !eventCharacters.isEmpty
        else {
            return nil
        }
        let eventModifiers = modifiers(from: event.modifierFlags)
        return preferences.shortcuts.lazy.compactMap { binding in
            guard binding.scope == requiredScope,
                  let shortcut = resolve(
                      commandID: binding.commandID,
                      preferences: preferences,
                      requiredScope: requiredScope
                  ),
                  shortcut.modifiers == eventModifiers,
                  String(shortcut.character).caseInsensitiveCompare(
                      eventCharacters
                  ) == .orderedSame
            else {
                return nil
            }
            return binding.commandID
        }.first
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

private struct GitKeyboardShortcutModifier: ViewModifier {
    let commandID: String
    let preferences: GitGlobalPreferences
    let requiredScope: GitShortcutScope?

    @ViewBuilder
    func body(content: Content) -> some View {
        if requiredScope == .global,
           let shortcut = GitShortcutResolver.resolve(
            commandID: commandID,
            preferences: preferences,
            requiredScope: requiredScope
        ) {
            content.keyboardShortcut(
                shortcut.key,
                modifiers: shortcut.modifiers
            )
        } else {
            content
        }
    }
}

struct GitShortcutEventHost: NSViewRepresentable {
    let preferences: GitGlobalPreferences
    let onCommand: (String) -> Void

    func makeNSView(context: Context) -> GitShortcutEventNSView {
        let view = GitShortcutEventNSView()
        view.configure(preferences: preferences, onCommand: onCommand)
        return view
    }

    func updateNSView(_ nsView: GitShortcutEventNSView, context: Context) {
        nsView.configure(preferences: preferences, onCommand: onCommand)
    }
}

@MainActor
final class GitShortcutEventNSView: NSView {
    private var eventMonitor: Any?
    private var preferences = GitGlobalPreferences()
    private var onCommand: ((String) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEventMonitor()
    }

    func configure(
        preferences: GitGlobalPreferences,
        onCommand: @escaping (String) -> Void
    ) {
        self.preferences = preferences
        self.onCommand = onCommand
    }

    private func updateEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  let commandID = GitShortcutResolver.commandID(
                      matching: event,
                      preferences: self.preferences,
                      requiredScope: .gitWorkbench
                  )
            else {
                return event
            }
            self.onCommand?(commandID)
            return nil
        }
    }
}

extension View {
    func gitKeyboardShortcut(
        _ commandID: String,
        preferences: GitGlobalPreferences,
        requiredScope: GitShortcutScope? = nil
    ) -> some View {
        modifier(
            GitKeyboardShortcutModifier(
                commandID: commandID,
                preferences: preferences,
                requiredScope: requiredScope
            )
        )
    }
}
