import Testing
@testable import BreathCore

@Suite("Breath settings boundaries")
struct SettingsTests {
    @Test("application and terminal styles are separate value objects")
    func separateStyleDomains() throws {
        var settings = SettingsSnapshot.default
        settings.application.appearance = .dark
        settings.application.sidebarDensity = .compact
        settings.terminal.fontFamily = "SF Mono"
        settings.terminal.fontSize = 15
        settings.terminal.colorTheme = .solarizedDark
        settings.terminal.cursorStyle = .bar

        #expect(settings.application == ApplicationSettings(appearance: .dark, sidebarDensity: .compact))
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
    }
}
