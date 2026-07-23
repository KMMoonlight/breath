public struct TerminalColorTheme:
    RawRepresentable,
    CaseIterable,
    Hashable,
    Codable,
    Sendable
{
    private static let ghosttyPrefix = "ghostty:"

    public let rawValue: String

    public init?(rawValue: String) {
        switch rawValue {
        case Self.dark.rawValue, Self.light.rawValue:
            self.rawValue = rawValue
        default:
            guard rawValue.hasPrefix(Self.ghosttyPrefix) else { return nil }
            let name = String(rawValue.dropFirst(Self.ghosttyPrefix.count))
            guard GhosttyThemeCatalog.definition(named: name) != nil else { return nil }
            self.rawValue = rawValue
        }
    }

    private init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }

    public static let dark = TerminalColorTheme(uncheckedRawValue: "dark")
    public static let light = TerminalColorTheme(uncheckedRawValue: "light")

    // Source-compatible names for settings saved before the complete Ghostty
    // catalog was exposed.
    public static let solarizedDark = ghostty(named: "iTerm2 Solarized Dark")
    public static let solarizedLight = ghostty(named: "iTerm2 Solarized Light")
    public static let dracula = ghostty(named: "Dracula")
    public static let nord = ghostty(named: "Nord")
    public static let gruvboxDark = ghostty(named: "Gruvbox Dark")
    public static let gruvboxLight = ghostty(named: "Gruvbox Light")
    public static let catppuccinMocha = ghostty(named: "Catppuccin Mocha")
    public static let catppuccinLatte = ghostty(named: "Catppuccin Latte")
    public static let tokyoNight = ghostty(named: "TokyoNight")
    public static let tokyoNightDay = ghostty(named: "TokyoNight Day")
    public static let atomOneDark = ghostty(named: "Atom One Dark")
    public static let atomOneLight = ghostty(named: "Atom One Light")

    public static let allCases: [TerminalColorTheme] = [
        .dark,
        .light,
    ] + GhosttyThemeCatalog.definitions.map {
        TerminalColorTheme(
            uncheckedRawValue: ghosttyPrefix + $0.name
        )
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
        if let pairedRawValue = Self.appearancePairs[rawValue],
           let paired = TerminalColorTheme(rawValue: pairedRawValue),
           paired.appearance == appearance
        {
            return paired
        }
        return appearance == .light ? .light : .dark
    }

    public var displayName: String {
        switch self {
        case .dark:
            "Breath 深色"
        case .light:
            "Breath 浅色"
        default:
            ghosttyName ?? rawValue
        }
    }

    public var palette: TerminalColorPalette {
        switch self {
        case .dark:
            Self.darkPalette
        case .light:
            Self.lightPalette
        default:
            ghosttyName
                .flatMap(GhosttyThemeCatalog.definition(named:))?
                .palette
                ?? Self.darkPalette
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storedValue = try container.decode(String.self)
        if let migratedValue = Self.legacyRawValues[storedValue] {
            self = migratedValue
        } else {
            self = TerminalColorTheme(rawValue: storedValue) ?? .dark
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private var ghosttyName: String? {
        guard rawValue.hasPrefix(Self.ghosttyPrefix) else { return nil }
        return String(rawValue.dropFirst(Self.ghosttyPrefix.count))
    }

    private var appearance: ResolvedApplicationAppearance {
        let background = palette.background
        let perceivedBrightness =
            Int(background.red) * 299
            + Int(background.green) * 587
            + Int(background.blue) * 114
        return perceivedBrightness >= 150_000 ? .light : .dark
    }

    private static func ghostty(named name: String) -> TerminalColorTheme {
        precondition(
            GhosttyThemeCatalog.definition(named: name) != nil,
            "Unknown bundled Ghostty theme: \(name)"
        )
        return TerminalColorTheme(uncheckedRawValue: ghosttyPrefix + name)
    }

    private static let appearancePairs: [String: String] = [
        solarizedDark.rawValue: solarizedLight.rawValue,
        solarizedLight.rawValue: solarizedDark.rawValue,
        gruvboxDark.rawValue: gruvboxLight.rawValue,
        gruvboxLight.rawValue: gruvboxDark.rawValue,
        catppuccinMocha.rawValue: catppuccinLatte.rawValue,
        catppuccinLatte.rawValue: catppuccinMocha.rawValue,
        tokyoNight.rawValue: tokyoNightDay.rawValue,
        tokyoNightDay.rawValue: tokyoNight.rawValue,
        atomOneDark.rawValue: atomOneLight.rawValue,
        atomOneLight.rawValue: atomOneDark.rawValue,
    ]

    private static let legacyRawValues: [String: TerminalColorTheme] = [
        "solarizedDark": .solarizedDark,
        "solarizedLight": .solarizedLight,
        "dracula": .dracula,
        "nord": .nord,
        "gruvboxDark": .gruvboxDark,
        "gruvboxLight": .gruvboxLight,
        "catppuccinMocha": .catppuccinMocha,
        "catppuccinLatte": .catppuccinLatte,
        "tokyoNight": .tokyoNight,
        "tokyoNightDay": .tokyoNightDay,
        "atomOneDark": .atomOneDark,
        "atomOneLight": .atomOneLight,
    ]

    private static let darkPalette = makePalette(
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

    private static let lightPalette = makePalette(
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
