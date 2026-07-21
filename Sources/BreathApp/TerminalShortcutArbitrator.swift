enum TerminalShortcutArbitrator {
    static func eventToForward<Event>(
        _ event: Event,
        terminalHasInputFocus: Bool,
        matchesBreathShortcut: (Event) -> Bool,
        terminalHandler: (Event) -> Bool
    ) -> Event? {
        guard terminalHasInputFocus, matchesBreathShortcut(event) else {
            return event
        }
        return terminalHandler(event) ? nil : event
    }
}
