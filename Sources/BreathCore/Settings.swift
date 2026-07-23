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

public enum TerminalColorTheme: String, CaseIterable, Equatable, Codable, Sendable {
    case dark
    case light
    case solarizedDark
    case solarizedLight
    case dracula
    case nord
    case gruvboxDark
    case gruvboxLight
    case catppuccinMocha
    case catppuccinLatte
    case tokyoNight
    case tokyoNightDay
    case atomOneDark
    case atomOneLight

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storedValue = try container.decode(String.self)
        if let theme = Self(rawValue: storedValue) {
            self = theme
            return
        }

        // Newer Breath builds persist the complete Ghostty catalog as
        // "ghostty:<theme name>". Older builds must still be able to open the
        // shared settings database after a worktree build has written one of
        // those values.
        let normalizedName = storedValue
            .replacingOccurrences(of: "ghostty:", with: "")
            .lowercased()
        switch normalizedName {
        case let name where name.contains("solarized") && name.contains("light"):
            self = .solarizedLight
        case let name where name.contains("solarized"):
            self = .solarizedDark
        case let name where name.contains("dracula"):
            self = .dracula
        case let name where name.contains("nord"):
            self = .nord
        case let name where name.contains("gruvbox") && name.contains("light"):
            self = .gruvboxLight
        case let name where name.contains("gruvbox"):
            self = .gruvboxDark
        case let name where name.contains("catppuccin") && name.contains("latte"):
            self = .catppuccinLatte
        case let name where name.contains("catppuccin"):
            self = .catppuccinMocha
        case let name where name.contains("tokyonight") && name.contains("day"):
            self = .tokyoNightDay
        case let name where name.contains("tokyonight"):
            self = .tokyoNight
        case let name where name.contains("atom one") && name.contains("light"):
            self = .atomOneLight
        case let name where name.contains("atom one"):
            self = .atomOneDark
        case let name
            where name.contains("light")
                || name.contains("day")
                || name.contains("latte"):
            self = .light
        default:
            self = .dark
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func compatible(
        with appearance: ResolvedApplicationAppearance
    ) -> [TerminalColorTheme] {
        allCases.filter { $0.appearance == appearance }
    }

    public func resolved(
        for appearance: ResolvedApplicationAppearance
    ) -> TerminalColorTheme {
        guard self.appearance != appearance else { return self }
        switch (self, appearance) {
        case (.solarizedDark, .light): return .solarizedLight
        case (.solarizedLight, .dark): return .solarizedDark
        case (.gruvboxDark, .light): return .gruvboxLight
        case (.gruvboxLight, .dark): return .gruvboxDark
        case (.catppuccinMocha, .light): return .catppuccinLatte
        case (.catppuccinLatte, .dark): return .catppuccinMocha
        case (.tokyoNight, .light): return .tokyoNightDay
        case (.tokyoNightDay, .dark): return .tokyoNight
        case (.atomOneDark, .light): return .atomOneLight
        case (.atomOneLight, .dark): return .atomOneDark
        case (_, .light): return .light
        case (_, .dark): return .dark
        }
    }

    private var appearance: ResolvedApplicationAppearance {
        switch self {
        case .light, .solarizedLight, .gruvboxLight, .catppuccinLatte,
             .tokyoNightDay, .atomOneLight: .light
        case .dark, .solarizedDark, .dracula, .nord, .gruvboxDark,
             .catppuccinMocha, .tokyoNight, .atomOneDark: .dark
        }
    }

    public var palette: TerminalColorPalette {
        switch self {
        case .dark:
            Self.makePalette(
                background: 0x101218,
                foreground: 0xE7EAF0,
                cursor: 0xA8B2D1,
                cursorText: 0x101218,
                selectionBackground: 0x2C3650,
                selectionForeground: 0xE7EAF0,
                ansi: [
                    0x1D1F21, 0xCC6566, 0xB6BD68, 0xF0C674,
                    0x82A2BE, 0xB294BB, 0x8ABEB7, 0xC4C8C6,
                    0x666666, 0xD54E53, 0xB9CA4B, 0xE7C547,
                    0x7AA6DA, 0xC397D8, 0x70C0B1, 0xEAEAEA,
                ]
            )
        case .light:
            Self.makePalette(
                background: 0xF7F7F5,
                foreground: 0x202124,
                cursor: 0x325CC0,
                cursorText: 0xF7F7F5,
                selectionBackground: 0xC9D8FF,
                selectionForeground: 0x202124,
                ansi: [
                    0x000000, 0xC91B00, 0x00C200, 0xC7C400,
                    0x0225C7, 0xCA30C7, 0x00C5C7, 0xBABABA,
                    0x686868, 0xFF6E67, 0x39D442, 0xCCC934,
                    0x6871FF, 0xFF77FF, 0x3AD7D9, 0xFFFFFF,
                ]
            )
        case .solarizedDark:
            Self.makePalette(
                background: 0x002B36,
                foreground: 0x839496,
                cursor: 0x93A1A1,
                cursorText: 0x002B36,
                selectionBackground: 0x073642,
                selectionForeground: 0x93A1A1,
                ansi: Self.solarizedANSI
            )
        case .solarizedLight:
            Self.makePalette(
                background: 0xFDF6E3,
                foreground: 0x657B83,
                cursor: 0x657B83,
                cursorText: 0xEEE8D5,
                selectionBackground: 0xEEE8D5,
                selectionForeground: 0x586E75,
                ansi: [
                    0x073642, 0xDC322F, 0x859900, 0xB58900,
                    0x268BD2, 0xD33682, 0x2AA198, 0xBBB5A2,
                    0x002B36, 0xCB4B16, 0x586E75, 0x657B83,
                    0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
                ]
            )
        case .dracula:
            Self.makePalette(
                background: 0x282A36,
                foreground: 0xF8F8F2,
                cursor: 0xF8F8F2,
                cursorText: 0x282A36,
                selectionBackground: 0x44475A,
                selectionForeground: 0xFFFFFF,
                ansi: [
                    0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C,
                    0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
                    0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5,
                    0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF,
                ]
            )
        case .nord:
            Self.makePalette(
                background: 0x2E3440,
                foreground: 0xD8DEE9,
                cursor: 0xECEFF4,
                cursorText: 0x282828,
                selectionBackground: 0xECEFF4,
                selectionForeground: 0x4C566A,
                ansi: [
                    0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B,
                    0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
                    0x596377, 0xBF616A, 0xA3BE8C, 0xEBCB8B,
                    0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4,
                ]
            )
        case .gruvboxDark:
            Self.makePalette(
                background: 0x282828,
                foreground: 0xEBDBB2,
                cursor: 0xEBDBB2,
                cursorText: 0x282828,
                selectionBackground: 0x665C54,
                selectionForeground: 0xEBDBB2,
                ansi: [
                    0x282828, 0xCC241D, 0x98971A, 0xD79921,
                    0x458588, 0xB16286, 0x689D6A, 0xA89984,
                    0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F,
                    0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2,
                ]
            )
        case .gruvboxLight:
            Self.makePalette(
                background: 0xFBF1C7,
                foreground: 0x3C3836,
                cursor: 0x3C3836,
                cursorText: 0xFBF1C7,
                selectionBackground: 0xD5C4A1,
                selectionForeground: 0x3C3836,
                ansi: [
                    0x3C3836, 0xCC241D, 0x98971A, 0xD79921,
                    0x458588, 0xB16286, 0x689D6A, 0xA89984,
                    0x928374, 0x9D0006, 0x79740E, 0xB57614,
                    0x076678, 0x8F3F71, 0x427B58, 0x7C6F64,
                ]
            )
        case .catppuccinMocha:
            Self.makePalette(
                background: 0x1E1E2E,
                foreground: 0xCDD6F4,
                cursor: 0xF5E0DC,
                cursorText: 0x1E1E2E,
                selectionBackground: 0xF5E0DC,
                selectionForeground: 0x1E1E2E,
                ansi: [
                    0x45475A, 0xF38BA8, 0xA6E3A1, 0xF9E2AF,
                    0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xBAC2DE,
                    0x585B70, 0xF7AEC2, 0xC2ECBF, 0xFCD682,
                    0xAECCFC, 0xF398DA, 0xB1EAE1, 0xA6ADC8,
                ]
            )
        case .catppuccinLatte:
            Self.makePalette(
                background: 0xEFF1F5,
                foreground: 0x4C4F69,
                cursor: 0xDC8A78,
                cursorText: 0xEFF1F5,
                selectionBackground: 0xCCD0DA,
                selectionForeground: 0x4C4F69,
                ansi: [
                    0x5C5F77, 0xD20F39, 0x40A02B, 0xDF8E1D,
                    0x1E66F5, 0xEA76CB, 0x179299, 0xACB0BE,
                    0x6C6F85, 0xE64553, 0x40A02B, 0xDF8E1D,
                    0x1E66F5, 0x8839EF, 0x179299, 0xBCC0CC,
                ]
            )
        case .tokyoNight:
            Self.makePalette(
                background: 0x1A1B26,
                foreground: 0xC0CAF5,
                cursor: 0xC0CAF5,
                cursorText: 0x15161E,
                selectionBackground: 0x33467C,
                selectionForeground: 0xC0CAF5,
                ansi: [
                    0x15161E, 0xF7768E, 0x9ECE6A, 0xE0AF68,
                    0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xA9B1D6,
                    0x414868, 0xF7768E, 0x9ECE6A, 0xE0AF68,
                    0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xC0CAF5,
                ]
            )
        case .tokyoNightDay:
            Self.makePalette(
                background: 0xE1E2E7,
                foreground: 0x3760BF,
                cursor: 0x3760BF,
                cursorText: 0xE1E2E7,
                selectionBackground: 0x99A7DF,
                selectionForeground: 0x3760BF,
                ansi: [
                    0xE9E9ED, 0xF52A65, 0x587539, 0x8C6C3E,
                    0x2E7DE9, 0x9854F1, 0x007197, 0x6172B0,
                    0xA1A6C5, 0xF52A65, 0x587539, 0x8C6C3E,
                    0x2E7DE9, 0x9854F1, 0x007197, 0x3760BF,
                ]
            )
        case .atomOneDark:
            Self.makePalette(
                background: 0x21252B,
                foreground: 0xABB2BF,
                cursor: 0xABB2BF,
                cursorText: 0x21252B,
                selectionBackground: 0x323844,
                selectionForeground: 0xABB2BF,
                ansi: [
                    0x21252B, 0xE06C75, 0x98C379, 0xE5C07B,
                    0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
                    0x767676, 0xE06C75, 0x98C379, 0xE5C07B,
                    0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
                ]
            )
        case .atomOneLight:
            Self.makePalette(
                background: 0xFAFAFA,
                foreground: 0x383A42,
                cursor: 0x526FFF,
                cursorText: 0xFAFAFA,
                selectionBackground: 0xE5E5E6,
                selectionForeground: 0x383A42,
                ansi: [
                    0x000000, 0xE45649, 0x50A14F, 0xC18401,
                    0x4078F2, 0xA626A4, 0x0184BC, 0xA0A1A7,
                    0x696C77, 0xE45649, 0x50A14F, 0xC18401,
                    0x4078F2, 0xA626A4, 0x0184BC, 0xFFFFFF,
                ]
            )
        }
    }

    private static let solarizedANSI: [UInt32] = [
        0x073642, 0xDC322F, 0x859900, 0xB58900,
        0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
        0x002B36, 0xCB4B16, 0x586E75, 0x657B83,
        0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
    ]

    private static func makePalette(
        background: UInt32,
        foreground: UInt32,
        cursor: UInt32,
        cursorText: UInt32,
        selectionBackground: UInt32,
        selectionForeground: UInt32,
        ansi: [UInt32]
    ) -> TerminalColorPalette {
        TerminalColorPalette(
            background: TerminalRGBColor(hex: background),
            foreground: TerminalRGBColor(hex: foreground),
            cursor: TerminalRGBColor(hex: cursor),
            cursorText: TerminalRGBColor(hex: cursorText),
            selectionBackground: TerminalRGBColor(hex: selectionBackground),
            selectionForeground: TerminalRGBColor(hex: selectionForeground),
            ansiColors: ansi.map(TerminalRGBColor.init(hex:))
        )
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
