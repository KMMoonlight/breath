public struct BreathShortcut: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let command = Self(rawValue: 1 << 0)
        public static let shift = Self(rawValue: 1 << 1)
        public static let option = Self(rawValue: 1 << 2)
        public static let control = Self(rawValue: 1 << 3)
    }

    public let character: Character
    public let modifiers: Modifiers

    public init(_ character: Character, modifiers: Modifiers) {
        self.character = character
        self.modifiers = modifiers
    }
}

public extension BreathShortcut {
    static let newWorkSession = Self("t", modifiers: [.command])
    static let workSessionTabs = (1...9).map { number in
        Self(Character(String(number)), modifiers: [.command])
    }
    static let previousPane = Self("[", modifiers: [.command])
    static let nextPane = Self("]", modifiers: [.command])
    static let openSettings = Self(",", modifiers: [.command])
    static let splitHorizontally = Self("d", modifiers: [.command])
    static let splitVertically = Self("d", modifiers: [.command, .shift])
    static let closePane = Self("w", modifiers: [.command])

    static let terminalFirst = [
        newWorkSession,
        previousPane,
        nextPane,
        openSettings,
        splitHorizontally,
        splitVertically,
        closePane,
    ] + workSessionTabs
}
