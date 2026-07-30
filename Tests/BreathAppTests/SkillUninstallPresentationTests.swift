import BreathCore
import BreathSkills
import Foundation
import Testing
@testable import BreathApp

@Suite("Skill uninstall presentation")
struct SkillUninstallPresentationTests {
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
            isSymbolicLink: true
        )
        let skill = GlobalSkill(
            name: "review",
            description: "Review before shipping.",
            manifest: "---",
            contentDigest: "digest",
            files: [],
            copies: [codexSharedCopy, kimiSharedCopy, claudeCopy]
        )

        let presentation = SkillUninstallSelectionPresentation(skill: skill)

        #expect(presentation.selectableCopies.map(\.agent) == [.claudeCode])
        let sharedCopy = try #require(presentation.sharedCopies.first)
        #expect(presentation.sharedCopies.count == 1)
        #expect(sharedCopy.directory == sharedLink)
        #expect(sharedCopy.resolvedDirectory == externalDirectory)
        #expect(sharedCopy.action == .removeSymbolicLink)
        #expect(sharedCopy.affectedAgentDisplayNames == ["Codex", "Kimi Code"])
    }

    private func installedCopy(
        agent: AgentKind,
        displayName: String,
        directory: URL,
        resolvedDirectory: URL? = nil,
        isSymbolicLink: Bool = false
    ) -> InstalledSkillCopy {
        InstalledSkillCopy(
            agent: agent,
            agentDisplayName: displayName,
            directory: directory,
            resolvedDirectory: resolvedDirectory ?? directory,
            isSymbolicLink: isSymbolicLink
        )
    }
}
