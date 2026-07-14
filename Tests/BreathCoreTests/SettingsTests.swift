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
}
