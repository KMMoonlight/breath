import BreathCore
import BreathSkills
import Foundation
import Testing
@testable import BreathApp

@Suite("Skill uninstall presentation")
struct SkillUninstallPresentationTests {
    @Test("shared warnings and selectable Agents use one top-aligned list")
    func selectionRowsShareOneList() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/SkillManagementSheets.swift"
            ),
            encoding: .utf8
        )
        let viewStart = try #require(source.range(of: "struct SkillUninstallView: View"))
        let riskBadgeStart = try #require(
            source.range(
                of: "private struct RiskBadge: View",
                range: viewStart.upperBound..<source.endIndex
            )
        )
        let viewSource = source[
            viewStart.lowerBound..<riskBadgeStart.lowerBound
        ].filter { !$0.isWhitespace }

        #expect(
            viewSource.contains(
                "}else{List{ForEach(selectionPresentation.selectableCopies)"
            )
        )
        #expect(
            viewSource.contains(
                ".toggleStyle(.checkbox)}ForEach(selectionPresentation.sharedCopies)"
            )
        )
        #expect(!viewSource.contains("List(selectionPresentation.selectableCopies)"))
    }

    @Test("shared copies are one consequence instead of Agent checkboxes")
    func sharedCopiesAreGroupedOutsideSelectableAgents() throws {
        let sharedDirectory = URL(
            fileURLWithPath: "/Users/example/.agents/skills/review",
            isDirectory: true
        )
        let codexSharedCopy = installedCopy(
            agent: .codex,
            displayName: "Codex",
            directory: sharedDirectory
        )
        let kimiSharedCopy = installedCopy(
            agent: .kimiCode,
            displayName: "Kimi Code",
            directory: sharedDirectory
        )
        let claudeCopy = installedCopy(
            agent: .claudeCode,
            displayName: "Claude Code",
            directory: URL(
                fileURLWithPath: "/Users/example/.claude/skills/review",
                isDirectory: true
            ),
            resolvedDirectory: sharedDirectory,
            isSymbolicLink: true
        )
        let antigravityCopy = installedCopy(
            agent: .antigravityCLI,
            displayName: "Antigravity",
            directory: URL(
                fileURLWithPath: "/Users/example/.gemini/antigravity/skills/review",
                isDirectory: true
            )
        )
        let skill = GlobalSkill(
            name: "review",
            description: "Review before shipping.",
            manifest: "---",
            contentDigest: "digest",
            files: [],
            copies: [codexSharedCopy, kimiSharedCopy, claudeCopy, antigravityCopy]
        )

        let presentation = SkillUninstallSelectionPresentation(skill: skill)

        #expect(presentation.selectableCopies.map(\.agent) == [.antigravityCLI])
        let sharedCopy = try #require(presentation.sharedCopies.first)
        #expect(presentation.sharedCopies.count == 1)
        #expect(sharedCopy.directory == sharedDirectory)
        #expect(sharedCopy.affectedAgentDisplayNames == ["Claude Code", "Codex", "Kimi Code"])
    }

    @Test("a shared discovery link affects only Agents that use that same link")
    func sharedDiscoveryLinkIsGroupedByItsPresentedPath() throws {
        let sharedLink = URL(
            fileURLWithPath: "/Users/example/.agents/skills/review",
            isDirectory: true
        )
        let externalDirectory = URL(
            fileURLWithPath: "/Volumes/skills/review",
            isDirectory: true
        )
        let codexSharedCopy = installedCopy(
            agent: .codex,
            displayName: "Codex",
            directory: sharedLink,
            resolvedDirectory: externalDirectory,
            isSymbolicLink: true
        )
        let kimiSharedCopy = installedCopy(
            agent: .kimiCode,
            displayName: "Kimi Code",
            directory: sharedLink,
            resolvedDirectory: externalDirectory,
            isSymbolicLink: true
        )
        let claudeCopy = installedCopy(
            agent: .claudeCode,
            displayName: "Claude Code",
            directory: URL(
                fileURLWithPath: "/Users/example/.claude/skills/review",
                isDirectory: true
            ),
            resolvedDirectory: externalDirectory,
            isSymbolicLink: true,
            symbolicLinkDestination: sharedLink
        )
        let antigravityCopy = installedCopy(
            agent: .antigravityCLI,
            displayName: "Antigravity",
            directory: URL(
                fileURLWithPath: "/Users/example/.gemini/antigravity/skills/review",
                isDirectory: true
            ),
            resolvedDirectory: externalDirectory,
            isSymbolicLink: true,
            symbolicLinkDestination: externalDirectory
        )
        let skill = GlobalSkill(
            name: "review",
            description: "Review before shipping.",
            manifest: "---",
            contentDigest: "digest",
            files: [],
            copies: [codexSharedCopy, kimiSharedCopy, claudeCopy, antigravityCopy]
        )

        let presentation = SkillUninstallSelectionPresentation(skill: skill)

        #expect(presentation.selectableCopies.map(\.agent) == [.antigravityCLI])
        let sharedCopy = try #require(presentation.sharedCopies.first)
        #expect(presentation.sharedCopies.count == 1)
        #expect(sharedCopy.directory == sharedLink)
        #expect(sharedCopy.resolvedDirectory == externalDirectory)
        #expect(sharedCopy.action == .removeSymbolicLink)
        #expect(sharedCopy.affectedAgentDisplayNames == ["Claude Code", "Codex", "Kimi Code"])
    }

    @Test("shared discovery links to one target keep distinct presentation identities")
    func sharedDiscoveryLinkIdentitiesUsePresentedPaths() {
        let externalDirectory = URL(
            fileURLWithPath: "/Volumes/skills/review",
            isDirectory: true
        )
        let firstLink = URL(
            fileURLWithPath: "/Users/example/.agents/skills/review",
            isDirectory: true
        )
        let secondLink = URL(
            fileURLWithPath: "/Users/example/.agents/skills/review-alias",
            isDirectory: true
        )
        let skill = GlobalSkill(
            name: "review",
            description: "Review before shipping.",
            manifest: "---",
            contentDigest: "digest",
            files: [],
            copies: [
                installedCopy(
                    agent: .codex,
                    displayName: "Codex",
                    directory: firstLink,
                    resolvedDirectory: externalDirectory,
                    isSymbolicLink: true,
                    symbolicLinkDestination: externalDirectory
                ),
                installedCopy(
                    agent: .kimiCode,
                    displayName: "Kimi Code",
                    directory: firstLink,
                    resolvedDirectory: externalDirectory,
                    isSymbolicLink: true,
                    symbolicLinkDestination: externalDirectory
                ),
                installedCopy(
                    agent: .codex,
                    displayName: "Codex",
                    directory: secondLink,
                    resolvedDirectory: externalDirectory,
                    isSymbolicLink: true,
                    symbolicLinkDestination: externalDirectory
                ),
                installedCopy(
                    agent: .kimiCode,
                    displayName: "Kimi Code",
                    directory: secondLink,
                    resolvedDirectory: externalDirectory,
                    isSymbolicLink: true,
                    symbolicLinkDestination: externalDirectory
                ),
            ]
        )

        let presentation = SkillUninstallSelectionPresentation(skill: skill)

        #expect(presentation.sharedCopies.count == 2)
        #expect(Set(presentation.sharedCopies.map(\.id)).count == 2)
    }

    private func installedCopy(
        agent: AgentKind,
        displayName: String,
        directory: URL,
        resolvedDirectory: URL? = nil,
        isSymbolicLink: Bool = false,
        symbolicLinkDestination: URL? = nil
    ) -> InstalledSkillCopy {
        InstalledSkillCopy(
            agent: agent,
            agentDisplayName: displayName,
            directory: directory,
            resolvedDirectory: resolvedDirectory ?? directory,
            isSymbolicLink: isSymbolicLink,
            symbolicLinkDestination: symbolicLinkDestination
        )
    }
}
