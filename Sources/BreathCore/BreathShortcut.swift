public struct BreathShortcut: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        case application
        case terminal
    }

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
    public let scope: Scope
    public let allowInTerminal: Bool

    public init(
        _ character: Character,
        modifiers: Modifiers,
        scope: Scope = .application,
        allowInTerminal: Bool = false
    ) {
        self.character = character
        self.modifiers = modifiers
        self.scope = scope
        self.allowInTerminal = allowInTerminal
    }
}

public extension BreathShortcut {
    static let newWorkSession = Self("t", modifiers: [.command])
    static let workSessionTabs = (1...9).map { number in
        Self(Character(String(number)), modifiers: [.command])
    }
    static let previousPane = Self(
        "[",
        modifiers: [.command],
        scope: .terminal
    )
    static let nextPane = Self(
        "]",
        modifiers: [.command],
        scope: .terminal
    )
    static let openSettings = Self(",", modifiers: [.command])
    static let splitHorizontally = Self(
        "d",
        modifiers: [.command],
        scope: .terminal
    )
    static let splitVertically = Self(
        "d",
        modifiers: [.command, .shift],
        scope: .terminal
    )
    static let closePane = Self(
        "w",
        modifiers: [.command],
        scope: .terminal
    )

    static let registeredByBreath = [
        newWorkSession,
        previousPane,
        nextPane,
        openSettings,
        splitHorizontally,
        splitVertically,
        closePane,
    ] + workSessionTabs
}
