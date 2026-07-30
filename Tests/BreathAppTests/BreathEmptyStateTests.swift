import Foundation
import Testing

@Suite("Breath empty state")
struct BreathEmptyStateTests {
    @Test("the shared empty state stays visually compact")
    func sharedEmptyStateStaysCompact() throws {
        let source = try appSource("BreathEmptyState.swift")
        let compact = source.filter { !$0.isWhitespace }

        #expect(compact.contains("structBreathEmptyState<Actions:View>:View"))
        #expect(compact.contains("staticleticonSize:CGFloat=20"))
        #expect(compact.contains(".font(.callout.weight(.medium))"))
        #expect(compact.contains(".font(.caption)"))
        #expect(!compact.contains(".font(.title"))
        #expect(!compact.contains(".font(.largeTitle"))
    }

    @Test("app empty states use the shared component instead of large system placeholders")
    func appEmptyStatesUseSharedComponent() throws {
        let sourceNames = [
            "AgentQuotaView.swift",
            "AutomationView.swift",
            "BreathSettingsView.swift",
            "GitDiffView.swift",
            "GitWorkbenchView.swift",
            "NotesView.swift",
            "SkillManagementSheets.swift",
            "SkillsView.swift",
            "WorkbenchView.swift",
        ]
        let sources = try sourceNames.map(appSource)

        #expect(sources.allSatisfy { !$0.contains("ContentUnavailableView") })
        #expect(sources.allSatisfy { $0.contains("BreathEmptyState") })
    }

    @Test("formerly blank surfaces use the shared component")
    func formerlyBlankSurfacesUseSharedComponent() throws {
        let expectations = [
            (
                "AutomationView.swift",
                "title:localizer.string(\"尚未创建自动化\")"
            ),
            (
                "WorkbenchView.swift",
                "title:localizer.string(WorkbenchAccessibility.noSelectedWorkSession)"
            ),
            (
                "AgentQuotaView.swift",
                "elseifmodel.cards.isEmpty{BreathEmptyState("
            ),
            (
                "AgentQuotaView.swift",
                "case.notLoggedIn:BreathEmptyState("
            ),
        ]

        for (sourceName, expectedFragment) in expectations {
            let compact = try appSource(sourceName).filter { !$0.isWhitespace }
            #expect(compact.contains(expectedFragment))
        }
    }

    @Test("remaining empty branches use the shared component")
    func remainingEmptyBranchesUseSharedComponent() throws {
        let expectations = [
            (
                "WorkbenchView.swift",
                "ifmodel.snapshot.workspaces.isEmpty{BreathEmptyState("
            ),
            (
                "WorkbenchView.swift",
                "iffilteredStartBranches.isEmpty{BreathEmptyState("
            ),
            (
                "AutomationView.swift",
                "ifruns.isEmpty{BreathEmptyState("
            ),
            (
                "BreathSettingsView.swift",
                "title:localizer.string(\"没有Worktree分支或目录\")"
            ),
            (
                "SkillManagementSheets.swift",
                "ifitem.changes.isEmpty{BreathEmptyState("
            ),
            (
                "GitWorkbenchView.swift",
                "iflocalBranches.isEmpty,remoteBranches.isEmpty{BreathEmptyState("
            ),
            (
                "GitWorkbenchView.swift",
                "ifrequest.choices.isEmpty{BreathEmptyState("
            ),
        ]

        for (sourceName, expectedFragment) in expectations {
            let compact = try appSource(sourceName).filter { !$0.isWhitespace }
            #expect(compact.contains(expectedFragment))
        }
    }

    @Test("an unavailable Git diff uses the compact shared presentation")
    func unavailableGitDiffUsesCompactSharedPresentation() throws {
        let source = try appSource("GitWorkbenchView.swift")
        let unavailableStart = try #require(
            source.range(of: "if diff.isBinary || diff.isTooLarge")
        )
        let loadingStart = try #require(
            source.range(
                of: "} else if documentStore.isLoading",
                range: unavailableStart.upperBound..<source.endIndex
            )
        )
        let unavailableState = source[
            unavailableStart.lowerBound..<loadingStart.lowerBound
        ]

        #expect(unavailableState.contains("BreathEmptyState("))
        #expect(!unavailableState.contains(".font(.title"))
        #expect(!unavailableState.contains(".font(.system(size: 36))"))
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
