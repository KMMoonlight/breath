import BreathCore

enum TerminalShortcutArbitrator {
    static func eventToForward<Event>(
        _ event: Event,
        policy: TerminalShortcutPolicy,
        terminalHasInputFocus: Bool,
        shortcutMatch: (Event) -> BreathShortcutMatch?,
        terminalHandler: (Event) -> Void
    ) -> Event? {
        guard terminalHasInputFocus,
              let match = shortcutMatch(event)
        else {
            return event
        }
        guard policy == .terminalFirst, !match.isAllowedInTerminal else {
            return event
        }
        terminalHandler(event)
        return nil
    }
}
