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
