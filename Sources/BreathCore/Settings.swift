public enum ApplicationAppearance: String, Equatable, Codable, Sendable {
    case system
    case light
    case dark
}

public enum SidebarDensity: String, Equatable, Codable, Sendable {
    case comfortable
    case compact
}

public struct ApplicationSettings: Equatable, Codable, Sendable {
    public var appearance: ApplicationAppearance
    public var sidebarDensity: SidebarDensity

    public init(
        appearance: ApplicationAppearance = .system,
        sidebarDensity: SidebarDensity = .comfortable
    ) {
        self.appearance = appearance
        self.sidebarDensity = sidebarDensity
    }
}

public enum TerminalColorTheme: String, Equatable, Codable, Sendable {
    case dark
    case light
    case solarizedDark

    public var palette: TerminalColorPalette {
        switch self {
        case .dark:
            TerminalColorPalette(
                background: TerminalRGBColor(red: 0x10, green: 0x12, blue: 0x18),
                foreground: TerminalRGBColor(red: 0xE7, green: 0xEA, blue: 0xF0),
                cursor: TerminalRGBColor(red: 0xA8, green: 0xB2, blue: 0xD1)
            )
        case .light:
            TerminalColorPalette(
                background: TerminalRGBColor(red: 0xF7, green: 0xF7, blue: 0xF5),
                foreground: TerminalRGBColor(red: 0x20, green: 0x21, blue: 0x24),
                cursor: TerminalRGBColor(red: 0x32, green: 0x5C, blue: 0xC0)
            )
        case .solarizedDark:
            TerminalColorPalette(
                background: TerminalRGBColor(red: 0x00, green: 0x2B, blue: 0x36),
                foreground: TerminalRGBColor(red: 0x83, green: 0x94, blue: 0x96),
                cursor: TerminalRGBColor(red: 0x93, green: 0xA1, blue: 0xA1)
            )
        }
    }
}

public struct TerminalColorPalette: Equatable, Sendable {
    public let background: TerminalRGBColor
    public let foreground: TerminalRGBColor
    public let cursor: TerminalRGBColor

    public init(
        background: TerminalRGBColor,
        foreground: TerminalRGBColor,
        cursor: TerminalRGBColor
    ) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
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

public struct SettingsSnapshot: Equatable, Codable, Sendable {
    public var application: ApplicationSettings
    public var terminal: TerminalSettings

    public init(
        application: ApplicationSettings = ApplicationSettings(),
        terminal: TerminalSettings = TerminalSettings()
    ) {
        self.application = application
        self.terminal = terminal
    }

    public static let `default` = SettingsSnapshot()
}

public protocol SettingsRepository: Sendable {
    func loadSettings() async throws -> SettingsSnapshot
    func saveSettings(_ settings: SettingsSnapshot) async throws
}
