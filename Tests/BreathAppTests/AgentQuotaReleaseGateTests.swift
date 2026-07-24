import Foundation
import Testing

@Suite("Agent quota release gate")
struct AgentQuotaReleaseGateTests {
    @Test("quota cards are responsive and preserve official value semantics")
    func responsiveValuePresentation() throws {
        let source = try appSource("AgentQuotaView.swift")
        let percentage = try #require(
            source.range(of: "case .percentage(let value, let direction):")
        )
        let amount = try #require(
            source.range(of: "case .amount(let value, let unit):")
        )
        let percentageBlock = source[percentage.lowerBound..<amount.lowerBound]
        let amountEnd = try #require(
            source.range(
                of: "if let resetsAt = window.resetsAt",
                range: amount.upperBound..<source.endIndex
            )
        )
        let amountBlock = source[amount.lowerBound..<amountEnd.lowerBound]

        #expect(source.contains("static let cardWidth: CGFloat = 360"))
        #expect(source.contains(
            ".adaptive(\n                                        minimum: AgentQuotaLayout.cardWidth,\n                                        maximum: AgentQuotaLayout.cardWidth"
        ))
        #expect(source.contains("width: AgentQuotaLayout.cardWidth"))
        #expect(source.contains("GridItem(.adaptive(minimum: 145)"))
        #expect(percentageBlock.contains("ProgressView("))
        #expect(!amountBlock.contains("ProgressView("))
        #expect(source.contains("direction == .used"))
        #expect(source.contains("window.warning ? .orange : .accentColor"))
        #expect(!source.contains("%.0f%%"))
    }

    @Test("reset details use the adjacent info icon and local timezone")
    func resetTooltip() throws {
        let source = try appSource("AgentQuotaView.swift")

        #expect(source.contains("ExplanationLabel(exactResetTime(resetsAt))"))
        #expect(source.contains("Text(localizer.string(window.name))"))
        #expect(source.contains("formatter.timeZone = .current"))
        #expect(source.contains("RelativeDateTimeFormatter()"))
    }

    @Test("quota page stays quiet, read-only, accessible, and free of internal metadata")
    func quietReadOnlyPage() throws {
        let source = try appSource("AgentQuotaView.swift")

        #expect(source.contains("if model.cards.isEmpty"))
        #expect(source.contains("Color(nsColor: .windowBackgroundColor)"))
        #expect(source.contains(".accessibilityLabel(localizer.string(\"全部刷新\"))"))
        #expect(source.contains("localizer.format(\"刷新 %@ 额度\", card.displayName)"))
        #expect(source.range(
            of: #"Label\(\s*localizer\.string\("全部刷新"\)"#,
            options: .regularExpression
        ) != nil)
        #expect(source.range(
            of: #"Label\(\s*localizer\.string\("刷新"\)"#,
            options: .regularExpression
        ) != nil)
        #expect(!source.contains("查询来源"))
        #expect(!source.contains("完成时间"))
        #expect(!source.contains("fallback"))
        #expect(!source.contains("登录按钮"))
        #expect(!source.contains("安装按钮"))
        #expect(!source.contains("凭据配置"))
    }

    @Test("quota implementation never persists or logs credentials and raw CLI output")
    func credentialBoundary() throws {
        let adapter = try appSource("AgentQuotaAdapters.swift")
        let commands = try appSource("AgentQuotaCommands.swift")
        let domain = try appSource("AgentQuotaDomain.swift")
        let combined = adapter + commands + domain

        #expect(!combined.contains("UserDefaults"))
        #expect(!combined.contains("SQLite"))
        #expect(!combined.contains("print("))
        #expect(!combined.contains("Logger"))
        #expect(!combined.contains(".write(to:"))
        #expect(commands.contains("AgentQuotaCommandOutput(data: <redacted>"))
        #expect(commands.contains("guard captured.count <= 1024 * 1024"))
        #expect(commands.contains("processEnvironment(baseEnvironment)"))
        #expect(adapter.contains("AgentQuotaRedirectDelegate"))
        #expect(adapter.contains("request.url?.scheme?.lowercased() == \"https\""))
        #expect(adapter.contains("caseInsensitiveCompare(allowedHost)"))
    }

    private func appSource(_ name: String) throws -> String {
        try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/BreathApp")
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }

    private var packageRoot: URL {
        URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    }
}
