import Foundation
import Testing
@testable import BreathCore

@Suite("Breath settings boundaries")
struct SettingsTests {
    @Test("application language offers system, Chinese, and English")
    func applicationLanguageBoundary() {
        #expect(ApplicationLanguage.allCases == [.system, .chinese, .english])
        #expect(ApplicationSettings().language == .system)
    }

    @Test("application font size defaults to 12 within an 11 to 14 range")
    func applicationFontSizeBoundary() {
        #expect(ApplicationSettings.fontSizeRange == 11...14)
        #expect(ApplicationSettings().fontSize == 12)
        #expect(ApplicationSettings(fontSize: 10).fontSize == 11)
        #expect(ApplicationSettings(fontSize: 15).fontSize == 14)
    }

    @Test("legacy application settings default the font size to 12")
    func legacyApplicationFontSizeDefault() throws {
        let payload = Data(
            #"{"appearance":"dark","sidebarDensity":"compact"}"#.utf8
        )

        let settings = try JSONDecoder().decode(ApplicationSettings.self, from: payload)

        #expect(settings.fontSize == 12)
        #expect(settings.language == .system)
    }

    @Test("terminal shortcut ownership defaults to Breath-first")
    func terminalShortcutPolicyDefault() {
        #expect(SettingsSnapshot.default.terminalShortcutPolicy == .breathFirst)
    }

    @Test("legacy settings snapshots default terminal shortcut ownership to Breath-first")
    func legacyTerminalShortcutPolicyDefault() throws {
        let payload = Data(
            """
            {
              "application": {
                "appearance": "system",
                "sidebarDensity": "comfortable",
                "fontSize": 12,
                "language": "system"
              },
              "terminal": {
                "fontFamily": "Menlo",
                "fontSize": 13,
                "colorTheme": "dark",
                "cursorStyle": "block"
              }
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(SettingsSnapshot.self, from: payload)

        #expect(settings.terminalShortcutPolicy == .breathFirst)
    }

    @Test("settings written by the Ghostty catalog remain readable by older builds")
    func ghosttyCatalogThemeCompatibility() throws {
        let payload = Data(
            """
            {
              "application": {
                "appearance": "system",
                "sidebarDensity": "comfortable",
                "fontSize": 12,
                "language": "system"
              },
              "terminal": {
                "fontFamily": "JetBrainsMonoNL Nerd Font Mono",
                "fontSize": 16,
                "colorTheme": "ghostty:Dracula+",
                "cursorStyle": "block"
              },
              "terminalShortcutPolicy": "breath-first"
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(SettingsSnapshot.self, from: payload)

        #expect(settings.terminal.colorTheme == .dracula)
        #expect(settings.terminal.fontFamily == "JetBrainsMonoNL Nerd Font Mono")
        #expect(settings.terminal.fontSize == 16)
    }

    @Test("application and terminal styles are separate value objects")
    func separateStyleDomains() throws {
        var settings = SettingsSnapshot.default
        settings.application.appearance = .dark
        settings.application.sidebarDensity = .compact
        settings.application.fontSize = 14
        settings.application.language = .english
        settings.terminal.fontFamily = "SF Mono"
        settings.terminal.fontSize = 15
        settings.terminal.colorTheme = .solarizedDark
        settings.terminal.cursorStyle = .bar

        #expect(
            settings.application
                == ApplicationSettings(
                    appearance: .dark,
                    sidebarDensity: .compact,
                    fontSize: 14,
                    language: .english
                )
        )
        #expect(
            settings.terminal == TerminalSettings(
                fontFamily: "SF Mono",
                fontSize: 15,
                colorTheme: .solarizedDark,
                cursorStyle: .bar
            )
        )
    }

    @Test("terminal themes expose one shared palette")
    func terminalThemePalettes() {
        #expect(TerminalColorTheme.allCases.count == 14)
        #expect(
            TerminalColorTheme.dark.palette.background
                == TerminalRGBColor(red: 0x10, green: 0x12, blue: 0x18)
        )
        #expect(
            TerminalColorTheme.light.palette.background
                == TerminalRGBColor(red: 0xF7, green: 0xF7, blue: 0xF5)
        )
        #expect(
            TerminalColorTheme.solarizedDark.palette.background
                == TerminalRGBColor(red: 0x00, green: 0x2B, blue: 0x36)
        )
        #expect(TerminalColorTheme.dracula.palette.background == TerminalRGBColor(hex: 0x282A36))
        #expect(TerminalColorTheme.nord.palette.background == TerminalRGBColor(hex: 0x2E3440))
        #expect(TerminalColorTheme.gruvboxDark.palette.background == TerminalRGBColor(hex: 0x282828))
        #expect(
            TerminalColorTheme.catppuccinMocha.palette.background
                == TerminalRGBColor(hex: 0x1E1E2E)
        )
        #expect(TerminalColorTheme.tokyoNight.palette.background == TerminalRGBColor(hex: 0x1A1B26))
        #expect(TerminalColorTheme.atomOneDark.palette.background == TerminalRGBColor(hex: 0x21252B))
        #expect(TerminalColorTheme.gruvboxLight.palette.background == TerminalRGBColor(hex: 0xFBF1C7))
        #expect(
            TerminalColorTheme.catppuccinLatte.palette.background
                == TerminalRGBColor(hex: 0xEFF1F5)
        )
        #expect(TerminalColorTheme.tokyoNightDay.palette.background == TerminalRGBColor(hex: 0xE1E2E7))
        #expect(TerminalColorTheme.atomOneLight.palette.background == TerminalRGBColor(hex: 0xFAFAFA))
        for theme in TerminalColorTheme.allCases {
            #expect(theme.palette.ansiColors.count == 16)
        }
    }

    @Test("terminal themes resolve to the application appearance")
    func terminalThemesFollowApplicationAppearance() {
        #expect(
            TerminalColorTheme.compatible(with: .light)
                == [
                    .light,
                    .solarizedLight,
                    .gruvboxLight,
                    .catppuccinLatte,
                    .tokyoNightDay,
                    .atomOneLight,
                ]
        )
        #expect(!TerminalColorTheme.compatible(with: .dark).contains(.light))
        #expect(!TerminalColorTheme.compatible(with: .dark).contains(.solarizedLight))
        #expect(TerminalColorTheme.dracula.resolved(for: .dark) == .dracula)
        #expect(TerminalColorTheme.dracula.resolved(for: .light) == .light)
        #expect(TerminalColorTheme.solarizedDark.resolved(for: .light) == .solarizedLight)
        #expect(TerminalColorTheme.solarizedLight.resolved(for: .dark) == .solarizedDark)
        #expect(TerminalColorTheme.gruvboxDark.resolved(for: .light) == .gruvboxLight)
        #expect(TerminalColorTheme.catppuccinLatte.resolved(for: .dark) == .catppuccinMocha)
        #expect(TerminalColorTheme.tokyoNight.resolved(for: .light) == .tokyoNightDay)
        #expect(TerminalColorTheme.atomOneLight.resolved(for: .dark) == .atomOneDark)
    }
}
