public enum ApplicationAppearance: String, Equatable, Codable, Sendable {
    case system
    case light
    case dark
}

public enum ApplicationLanguage: String, CaseIterable, Equatable, Codable, Sendable {
    case system
    case chinese
    case english
}

public enum ResolvedApplicationAppearance: Equatable, Sendable {
    case light
    case dark
}

public enum SidebarDensity: String, Equatable, Codable, Sendable {
    case comfortable
    case compact
}

public struct ApplicationSettings: Equatable, Codable, Sendable {
    public static let fontSizeRange: ClosedRange<Double> = 11...14

    public var appearance: ApplicationAppearance
    public var sidebarDensity: SidebarDensity
    public var fontSize: Double
    public var language: ApplicationLanguage

    public init(
        appearance: ApplicationAppearance = .system,
        sidebarDensity: SidebarDensity = .comfortable,
        fontSize: Double = 12,
        language: ApplicationLanguage = .system
    ) {
        self.appearance = appearance
        self.sidebarDensity = sidebarDensity
        self.fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        self.language = language
    }

    private enum CodingKeys: String, CodingKey {
        case appearance
        case sidebarDensity
        case fontSize
        case language
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appearance: try container.decode(ApplicationAppearance.self, forKey: .appearance),
            sidebarDensity: try container.decode(SidebarDensity.self, forKey: .sidebarDensity),
            fontSize: try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 12,
            language: try container.decodeIfPresent(ApplicationLanguage.self, forKey: .language)
                ?? .system
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(sidebarDensity, forKey: .sidebarDensity)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(language, forKey: .language)
    }
}

public struct TerminalColorPalette: Equatable, Sendable {
    public let background: TerminalRGBColor
    public let foreground: TerminalRGBColor
    public let cursor: TerminalRGBColor
    public let cursorText: TerminalRGBColor
    public let selectionBackground: TerminalRGBColor
    public let selectionForeground: TerminalRGBColor
    public let ansiColors: [TerminalRGBColor]

    public init(
        background: TerminalRGBColor,
        foreground: TerminalRGBColor,
        cursor: TerminalRGBColor,
        cursorText: TerminalRGBColor,
        selectionBackground: TerminalRGBColor,
        selectionForeground: TerminalRGBColor,
        ansiColors: [TerminalRGBColor]
    ) {
        precondition(ansiColors.count == 16)
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.ansiColors = ansiColors
    }
}

public struct TerminalRGBColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        precondition(hex <= 0xFFFFFF)
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }
}

public enum TerminalCursorStyle: String, Equatable, Codable, Sendable {
    case block
    case bar
    case underline
}

public struct TerminalSettings: Equatable, Codable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var colorTheme: TerminalColorTheme
    public var cursorStyle: TerminalCursorStyle

    public init(
        fontFamily: String = "Menlo",
        fontSize: Double = 13,
        colorTheme: TerminalColorTheme = .dark,
        cursorStyle: TerminalCursorStyle = .block
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.colorTheme = colorTheme
        self.cursorStyle = cursorStyle
    }
}

public enum TerminalShortcutPolicy: String, CaseIterable, Equatable, Codable, Sendable {
    case breathFirst = "breath-first"
    case terminalFirst = "terminal-first"
}

public struct SettingsSnapshot: Equatable, Codable, Sendable {
    public var application: ApplicationSettings
    public var terminal: TerminalSettings
    public var terminalShortcutPolicy: TerminalShortcutPolicy

    public init(
        application: ApplicationSettings = ApplicationSettings(),
        terminal: TerminalSettings = TerminalSettings(),
        terminalShortcutPolicy: TerminalShortcutPolicy = .breathFirst
    ) {
        self.application = application
        self.terminal = terminal
        self.terminalShortcutPolicy = terminalShortcutPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case application
        case terminal
        case terminalShortcutPolicy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            application: try container.decode(ApplicationSettings.self, forKey: .application),
            terminal: try container.decode(TerminalSettings.self, forKey: .terminal),
            terminalShortcutPolicy: try container.decodeIfPresent(
                TerminalShortcutPolicy.self,
                forKey: .terminalShortcutPolicy
            ) ?? .breathFirst
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(application, forKey: .application)
        try container.encode(terminal, forKey: .terminal)
        try container.encode(terminalShortcutPolicy, forKey: .terminalShortcutPolicy)
    }

    public static let `default` = SettingsSnapshot()
}

public protocol SettingsRepository: Sendable {
    func loadSettings() async throws -> SettingsSnapshot
    func saveSettings(_ settings: SettingsSnapshot) async throws
}
