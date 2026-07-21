import BreathAgents
import BreathCore
import BreathSkills
import Foundation
import Testing

@Suite("Global Skills use cases")
struct GlobalSkillsServiceTests {
    @Test("Codex Skill files become one browsable global Skill")
    func scansCodexSkill() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(
            agent: .codex,
            directoryName: "review",
            manifest: """
                ---
                name: review # YAML comments are not part of the value
                description: Review a change before it ships.
                metadata:
                  author: example-org
                ---
                # Review
                """,
            files: ["references/checklist.md": "Check behavior and tests."]
        )
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            agentAdapters: AgentAdapterRegistry.builtIn.adapters,
            environment: [:]
        )

        let snapshot = await service.scan()

        let skill = try #require(snapshot.skills.first)
        #expect(snapshot.skills.count == 1)
        #expect(skill.name == "review")
        #expect(skill.author == "example-org")
        #expect(skill.description == "Review a change before it ships.")
        #expect(skill.copies.map(\.agent) == [.codex])
        #expect(skill.files.map(\.relativePath) == ["SKILL.md", "references/checklist.md"])
        #expect(snapshot.unrecognizedItems.isEmpty)
    }

    @Test("an invalid custom configuration root is disabled without guessing or losing provenance")
    func rejectsUnreliableCustomRoot() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(
            agent: .codex,
            directoryName: "review",
            manifest: """
                ---
                name: review
                description: Review from the default root.
                ---
                """
        )
        let initial = await GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:]
        ).scan()
        let skill = try #require(initial.skills.first)
        let copy = try #require(skill.copies.first)
        let records = MemorySkillRecordRepository(records: [
            SkillInstallationRecord(
                agent: .codex,
                installationDirectory: copy.directory,
                skillName: skill.name,
                origin: .remote(SkillRemoteProvenance(
                    source: .github,
                    repository: "example/skills",
                    sourceRelativePath: "review",
                    reference: SkillSourceReference(kind: .branch, value: "main"),
                    resolvedCommit: "commit-1"
                )),
                installedContentDigest: skill.contentDigest,
                installedAt: .distantPast,
                updatedAt: .distantPast
            ),
        ])
        let codex = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == .codex }
        )
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            agentAdapters: [codex],
            environment: ["CODEX_HOME": "relative/config"],
            recordRepository: records
        )

        let snapshot = await service.scan()

        #expect(snapshot.skills.isEmpty)
        #expect(snapshot.targets.first?.directory == nil)
        #expect(snapshot.targets.first?.availability.isSelectable == false)
        #expect(try await records.loadSkillInstallationRecords().count == 1)
        #expect(FileManager.default.fileExists(atPath: copy.directory.path))
    }

    @Test("identical copies aggregate while same-name variants and invalid items stay distinct")
    func aggregatesAcrossAgents() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let sharedManifest = """
            ---
            name: review
            description: Review before shipping.
            ---
            """
        try fixture.writeSkill(agent: .codex, directoryName: "review", manifest: sharedManifest)
        try fixture.writeSkill(agent: .claudeCode, directoryName: "review", manifest: sharedManifest)
        try fixture.writeSkill(
            agent: .geminiCLI,
            directoryName: "review",
            manifest: """
                ---
                name: review
                description: Review only documentation.
                ---
                """
        )
        try fixture.writeInvalidItem(agent: .pi, directoryName: "broken")
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:]
        )

        let snapshot = await service.scan()

        #expect(snapshot.skills.count == 2)
        let shared = try #require(snapshot.skills.first {
            $0.description == "Review before shipping."
        })
        #expect(Set(shared.copies.map(\.agent)) == Set([.codex, .claudeCode]))
        #expect(snapshot.skills.allSatisfy { $0.name == "review" })
        #expect(snapshot.targets.count == AgentAdapterRegistry.builtIn.adapters.count)
        #expect(snapshot.unrecognizedItems.count == 1)
        #expect(snapshot.unrecognizedItems.first?.agent == .pi)
        #expect(snapshot.unrecognizedItems.first?.reason.contains("SKILL.md") == true)
    }

    @Test("external symbolic links are browsable without changing their shared target")
    func scansExternalSymbolicLink() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let external = fixture.home.deletingLastPathComponent()
            .appendingPathComponent("external-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data(
            """
            ---
            name: external-review
            description: Shared by another installer.
            ---
            """.utf8
        ).write(to: external.appendingPathComponent("SKILL.md"))
        let link = try fixture.skillRoot(for: .codex)
            .appendingPathComponent("external-review", isDirectory: true)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)

        let snapshot = await GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:]
        ).scan()

        let copy = try #require(snapshot.skills.first?.copies.first)
        #expect(copy.isSymbolicLink)
        #expect(copy.directory == link)
        #expect(copy.resolvedDirectory == external.resolvingSymlinksInPath())
        #expect(FileManager.default.fileExists(atPath: external.path))
    }

    @Test("Codex discovers skills CLI shared roots and copies them locally for another Agent")
    func recognizesCodexSharedSkillsCLIInstall() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let sharedContainer = fixture.home.appendingPathComponent(".agents", isDirectory: true)
        let sharedSkill = sharedContainer
            .appendingPathComponent("skills/agent-browser", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sharedSkill,
            withIntermediateDirectories: true
        )
        try Data(
            """
            ---
            name: agent-browser
            description: Automates browser interactions.
            ---
            local shared content
            """.utf8
        ).write(to: sharedSkill.appendingPathComponent("SKILL.md"))
        try Data(
            """
            {
              "version": 3,
              "skills": {
                "Agent Browser": {
                  "source": "Vercel-Labs/Agent-Browser",
                  "sourceType": "github",
                  "sourceUrl": "https://github.com/vercel-labs/agent-browser.git",
                  "skillPath": "skills/agent-browser/SKILL.md",
                  "skillFolderHash": "shared-folder-hash"
                }
              }
            }
            """.utf8
        ).write(to: sharedContainer.appendingPathComponent(".skill-lock.json"))
        let claudeLink = try fixture.skillRoot(for: .claudeCode)
            .appendingPathComponent("agent-browser", isDirectory: true)
        try FileManager.default.createDirectory(
            at: claudeLink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: claudeLink,
            withDestinationURL: sharedSkill
        )
        let records = MemorySkillRecordRepository()
        let github = StubGitHubProvider(archiveData: Data())
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records,
            githubProvider: github
        )

        let snapshot = await service.scan()
        let skill = try #require(snapshot.skills.first)
        let codexSharedCopy = try #require(skill.copies.first { $0.agent == .codex })
        let claudeCopy = try #require(skill.copies.first { $0.agent == .claudeCode })

        #expect(!codexSharedCopy.isSymbolicLink)
        #expect(codexSharedCopy.isSharedAgentDiscoveryCopy)
        #expect(codexSharedCopy.directory == sharedSkill.standardizedFileURL)
        #expect(codexSharedCopy.resolvedDirectory == sharedSkill.resolvingSymlinksInPath())
        #expect(claudeCopy.isSymbolicLink)
        #expect(claudeCopy.resolvedDirectory == sharedSkill.resolvingSymlinksInPath())
        #expect(codexSharedCopy.source == .github)
        #expect(codexSharedCopy.repository == "vercel-labs/agent-browser")
        #expect(codexSharedCopy.sourceRelativePath == "skills/agent-browser")
        #expect(codexSharedCopy.catalogSkillID == nil)
        #expect(codexSharedCopy.sourceIdentity == nil)
        #expect(codexSharedCopy.installationOrigin?.sharedProvenance?.skillIdentifier
            == "Agent Browser")
        #expect(codexSharedCopy.installationOrigin?.sharedProvenance?.contentHash
            == "shared-folder-hash")
        #expect(codexSharedCopy.installationOrigin?.sharedProvenance?.sourceURL
            == "https://github.com/vercel-labs/agent-browser.git")
        let catalogEntry = SkillsShSearchResult(
            id: "vercel-labs/agent-browser/agent-browser",
            slug: "agent-browser",
            name: "agent-browser",
            description: "Automates browser interactions.",
            source: "vercel-labs/agent-browser",
            installs: 1,
            sourceType: "github",
            installURL: URL(string: "https://github.com/vercel-labs/agent-browser"),
            pageURL: try #require(URL(
                string: "https://skills.sh/vercel-labs/agent-browser/agent-browser"
            ))
        )
        #expect(codexSharedCopy.matchesSkillsShCatalogEntry(catalogEntry))
        let inconsistentCatalogEntry = SkillsShSearchResult(
            id: "another-owner/agent-browser/agent-browser",
            slug: catalogEntry.slug,
            name: catalogEntry.name,
            description: catalogEntry.description,
            source: catalogEntry.source,
            installs: catalogEntry.installs,
            sourceType: catalogEntry.sourceType,
            installURL: catalogEntry.installURL,
            pageURL: catalogEntry.pageURL
        )
        #expect(!codexSharedCopy.matchesSkillsShCatalogEntry(inconsistentCatalogEntry))

        let batch = try await service.discoverSkill(
            fromInstalledCopy: codexSharedCopy,
            sourceLabel: "Local Copy · Codex"
        )
        let candidate = try #require(batch.candidates.first)
        let codexPreview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )
        #expect(codexPreview.items.first?.action == .alreadyInstalled)
        #expect(codexPreview.items.first?.targetDirectory == sharedSkill.standardizedFileURL)
        #expect((await service.previewUninstall(
            skillID: skill.id,
            targetAgents: [.codex]
        )).items.isEmpty)

        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.geminiCLI]
        )
        let result = await service.install(preview)

        #expect(await github.requestedLocators().isEmpty)
        #expect(result.items.first?.status == .succeeded)
        #expect(Set(result.snapshot.skills.first?.copies.map(\.agent) ?? [])
            == Set([.codex, .claudeCode, .geminiCLI]))
        let geminiDirectory = try fixture.skillRoot(for: .geminiCLI)
            .appendingPathComponent("agent-browser", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: geminiDirectory.path))
        #expect(FileManager.default.fileExists(atPath: sharedSkill.path))
        let geminiRecord = try #require(
            try await records.loadSkillInstallationRecords().first {
                $0.agent == .geminiCLI
            }
        )
        #expect(geminiRecord.origin.sharedProvenance?.skillIdentifier == "Agent Browser")
        #expect(result.snapshot.skills.first?.copies.allSatisfy {
            $0.matchesSkillsShCatalogEntry(catalogEntry)
        } == true)
    }

    @Test("local Agent installation rejects nested symbolic links")
    func rejectsNestedLinkWhenCopyingInstalledSkill() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let sharedContainer = fixture.home.appendingPathComponent(".agents", isDirectory: true)
        let sharedSkill = sharedContainer.appendingPathComponent(
            "skills/review",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sharedSkill,
            withIntermediateDirectories: true
        )
        try Data(
            """
            ---
            name: review
            description: Review changes.
            ---
            """.utf8
        ).write(to: sharedSkill.appendingPathComponent("SKILL.md"))
        let outsideFile = fixture.home.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: sharedSkill.appendingPathComponent("outside.md"),
            withDestinationURL: outsideFile
        )
        try Data(
            """
            {
              "version": 3,
              "skills": {
                "review": {
                  "source": "example/skills",
                  "sourceType": "github",
                  "sourceUrl": "https://github.com/example/skills.git",
                  "skillPath": "skills/review/SKILL.md",
                  "skillFolderHash": "shared-folder-hash"
                }
              }
            }
            """.utf8
        ).write(to: sharedContainer.appendingPathComponent(".skill-lock.json"))
        let claudeLink = try fixture.skillRoot(for: .claudeCode)
            .appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(
            at: claudeLink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: claudeLink,
            withDestinationURL: sharedSkill
        )
        let github = StubGitHubProvider(archiveData: Data())
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            githubProvider: github
        )
        let copy = try #require((await service.scan()).skills.first?.copies.first)

        await #expect(throws: SkillSourceError.invalidSkill(
            "The installed Skill contains a symbolic link and cannot be copied as an independent Agent installation."
        )) {
            try await service.discoverSkill(
                fromInstalledCopy: copy,
                sourceLabel: "Local Copy · Claude Code"
            )
        }
        #expect(await github.requestedLocators().isEmpty)
    }

    @Test("snapshot stream notices a Skill installed outside Breath")
    func observesExternalInstall() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:]
        )
        var updates = service.snapshots(debouncedBy: .milliseconds(20)).makeAsyncIterator()
        let initial = await updates.next()
        #expect(initial?.skills.isEmpty == true)

        try fixture.writeSkill(
            agent: .codex,
            directoryName: "added-elsewhere",
            manifest: """
                ---
                name: added-elsewhere
                description: Installed by another tool.
                ---
                """
        )

        let changed = await updates.next()
        #expect(changed?.skills.map(\.name) == ["added-elsewhere"])
    }

    @Test("provenance follows the real directory and preserves a verified local modification")
    func reconcilesRemoteProvenance() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(
            agent: .codex,
            directoryName: "review",
            manifest: """
                ---
                name: review
                description: Review before shipping.
                ---
                """
        )
        let initial = await GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:]
        ).scan()
        let copy = try #require(initial.skills.first?.copies.first)
        let digest = try #require(initial.skills.first?.contentDigest)
        let records = MemorySkillRecordRepository(records: [
            SkillInstallationRecord(
                agent: .codex,
                installationDirectory: copy.directory,
                skillName: "review",
                origin: .remote(SkillRemoteProvenance(
                    source: .github,
                    repository: "example/skills",
                    sourceRelativePath: "review",
                    reference: SkillSourceReference(kind: .branch, value: "main"),
                    resolvedCommit: "commit-1"
                )),
                installedContentDigest: digest,
                installedAt: .distantPast,
                updatedAt: .distantPast
            ),
        ])
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records
        )

        let recorded = await service.scan()
        #expect(recorded.skills.first?.copies.first?.source == .github)
        #expect(recorded.skills.first?.copies.first?.updateState == .current)

        try Data("local note".utf8).write(
            to: copy.directory.appendingPathComponent("notes.md")
        )
        let modified = await service.scan()
        #expect(modified.skills.first?.copies.first?.source == .github)
        #expect(modified.skills.first?.copies.first?.updateState == .locallyModified)
    }

    @Test("one reviewed ZIP Skill installs as a physical Agent-owned directory")
    func installsOneZipSkill() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let zipURL = fixture.home.appendingPathComponent("review.zip")
        try StoredZIP.make([
            "review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review a change before it ships.
                ---
                """.utf8
            ),
            "review/references/checklist.md": Data("Check behavior and tests.".utf8),
        ]).write(to: zipURL)
        let records = MemorySkillRecordRepository()
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records
        )

        let batch = try await service.discoverSkills(inZip: zipURL)
        let candidate = try #require(batch.candidates.first)
        #expect(batch.candidates.count == 1)
        #expect(candidate.name == "review")
        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )
        #expect(preview.items.map(\.action) == [.install])

        let result = await service.install(preview)

        #expect(result.items.map(\.status) == [.succeeded])
        let installed = try fixture.skillRoot(for: .codex)
            .appendingPathComponent("review", isDirectory: true)
        let values = try installed.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        #expect(values.isDirectory == true)
        #expect(values.isSymbolicLink != true)
        #expect(try String(contentsOf: installed.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("Review a change"))
        let installedNames = try FileManager.default.contentsOfDirectory(atPath: installed.path)
        #expect(!installedNames.contains { $0.hasPrefix(".breath") })
        let snapshot = await service.scan()
        #expect(snapshot.skills.first?.copies.first?.source == .zip)
        #expect(snapshot.skills.first?.copies.first?.updateState == .unavailable)
        #expect(try await records.loadSkillInstallationRecords().first?.source == .zip)
        try Data("local ZIP edit".utf8).write(
            to: installed.appendingPathComponent("local.md")
        )
        let editedZIP = await service.scan()
        #expect(editedZIP.skills.first?.copies.first?.source == .zip)
        #expect(editedZIP.skills.first?.copies.first?.isLocallyModified == false)
        #expect(editedZIP.skills.first?.copies.first?.updateState == .unavailable)
    }

    @Test("unsafe ZIP paths are rejected before anything reaches an Agent directory")
    func rejectsUnsafeZipPath() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let zipURL = fixture.home.appendingPathComponent("unsafe.zip")
        try StoredZIP.make([
            "../escape/SKILL.md": Data(
                """
                ---
                name: escape
                description: Must not escape.
                ---
                """.utf8
            ),
        ]).write(to: zipURL)
        let service = GlobalSkillsService(homeDirectory: fixture.home, environment: [:])

        do {
            _ = try await service.discoverSkills(inZip: zipURL)
            Issue.record("unsafe ZIP unexpectedly produced candidates")
        } catch let error as SkillSourceError {
            guard case .unsafeArchivePath = error else {
                Issue.record("unexpected ZIP error: \(error)")
                return
            }
        }

        #expect(!FileManager.default.fileExists(
            atPath: fixture.home.appendingPathComponent("escape").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: try fixture.skillRoot(for: .codex).path
        ))
    }

    @Test("a real deflated ZIP preserves resources without executing bundled scripts")
    func importsRealDeflatedZipWithoutExecutingScripts() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let sourceRoot = fixture.home.appendingPathComponent("zip-source", isDirectory: true)
        let skillRoot = sourceRoot.appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(
            at: skillRoot.appendingPathComponent("references", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(
            """
            ---
            name: review
            description: Review a real compressed archive.
            ---
            """.utf8
        ).write(to: skillRoot.appendingPathComponent("SKILL.md"))
        try Data(String(repeating: "check behavior and tests\n", count: 1_000).utf8).write(
            to: skillRoot.appendingPathComponent("references/checklist.md")
        )
        let sentinel = fixture.home.appendingPathComponent("script-ran")
        try Data("#!/bin/sh\ntouch \"(sentinel.path)\"\n".utf8).write(
            to: skillRoot.appendingPathComponent("install.sh")
        )
        let archiveURL = fixture.home.appendingPathComponent("review-deflated.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = sourceRoot
        zip.arguments = ["-q", "-Z", "deflate", "-r", archiveURL.path, "review"]
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)

        let service = GlobalSkillsService(homeDirectory: fixture.home, environment: [:])
        let batch = try await service.discoverSkills(inZip: archiveURL)
        let candidate = try #require(batch.candidates.first)
        #expect(candidate.files.contains { $0.relativePath == "install.sh" })
        #expect(candidate.files.contains { $0.relativePath == "references/checklist.md" })
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))

        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )
        let result = await service.install(preview)
        #expect(result.items.first?.status == .succeeded)
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test("multi-Skill installation skips same-name content by default and can replace it explicitly")
    func batchInstallAndReplacement() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(
            agent: .codex,
            directoryName: "review",
            manifest: """
                ---
                name: review
                description: Existing review behavior.
                ---
                old
                """
        )
        let zipURL = fixture.home.appendingPathComponent("collection.zip")
        try StoredZIP.make([
            "review/SKILL.md": Data(
                """
                ---
                name: review
                description: Replacement review behavior.
                ---
                new
                """.utf8
            ),
            "summarize/SKILL.md": Data(
                """
                ---
                name: summarize
                description: Summarize a discussion.
                ---
                """.utf8
            ),
        ]).write(to: zipURL)
        let service = GlobalSkillsService(homeDirectory: fixture.home, environment: [:])
        let batch = try await service.discoverSkills(inZip: zipURL)
        #expect(Set(batch.candidates.map(\.name)) == Set(["review", "summarize"]))

        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: Set(batch.candidates.map(\.id)),
            targetAgents: [.codex, .claudeCode]
        )
        let codexReview = try #require(preview.items.first {
            $0.targetID.agent == .codex && $0.candidate.name == "review"
        })
        #expect(codexReview.action == .skip)
        #expect(codexReview.existingMatch == .sameName)
        #expect(codexReview.existingDescription == "Existing review behavior.")
        #expect(preview.items.filter { $0.action == .install }.count == 3)

        let result = await service.install(preview)
        #expect(result.items.filter { $0.status == .succeeded }.count == 3)
        #expect(result.items.filter { $0.status == .skipped }.count == 1)
        let codexManifest = try String(
            contentsOf: codexReview.targetDirectory.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
        #expect(codexManifest.contains("Existing review behavior"))

        let replacementBatch = try await service.discoverSkills(inZip: zipURL)
        let replacementCandidate = try #require(
            replacementBatch.candidates.first { $0.name == "review" }
        )
        let replacementID = SkillInstallationTargetID(
            candidateID: replacementCandidate.id,
            agent: .codex
        )
        let replacementPreview = await service.previewInstallation(
            batch: replacementBatch,
            candidateIDs: [replacementCandidate.id],
            targetAgents: [.codex],
            replacementChoices: [replacementID: .replace]
        )
        #expect(replacementPreview.items.first?.action == .replace)

        let replacement = await service.install(replacementPreview)
        #expect(replacement.items.first?.status == .succeeded)
        let replacedManifest = try String(
            contentsOf: codexReview.targetDirectory.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
        #expect(replacedManifest.contains("Replacement review behavior"))
    }

    @Test("installation rechecks Agent availability and same-name aliases after preview")
    func rechecksInstallationTargetBeforeCommit() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let zipURL = fixture.home.appendingPathComponent("review.zip")
        try StoredZIP.make([
            "review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review before shipping.
                ---
                """.utf8
            ),
        ]).write(to: zipURL)
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            targetAvailability: [.codex: .available]
        )
        let batch = try await service.discoverSkills(inZip: zipURL)
        let candidate = try #require(batch.candidates.first)
        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )

        await service.updateTargetAvailability([
            .codex: .unavailable(reason: "Codex is no longer available."),
        ])
        let unavailable = await service.install(preview)
        #expect(unavailable.items.first?.status == .failed)
        #expect(!FileManager.default.fileExists(
            atPath: try fixture.skillRoot(for: .codex).appendingPathComponent("review").path
        ))

        let secondBatch = try await service.discoverSkills(inZip: zipURL)
        let secondCandidate = try #require(secondBatch.candidates.first)
        await service.updateTargetAvailability([.codex: .available])
        let secondPreview = await service.previewInstallation(
            batch: secondBatch,
            candidateIDs: [secondCandidate.id],
            targetAgents: [.codex]
        )
        try fixture.writeSkill(
            agent: .codex,
            directoryName: "alias-directory",
            manifest: """
                ---
                name: review
                description: Installed elsewhere after preview.
                ---
                """
        )

        let stale = await service.install(secondPreview)
        #expect(stale.items.first?.status == .failed)
        #expect(stale.items.first?.message.contains("changed after preview") == true)
        #expect(!FileManager.default.fileExists(
            atPath: try fixture.skillRoot(for: .codex).appendingPathComponent("review").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: try fixture.skillRoot(for: .codex)
                .appendingPathComponent("alias-directory/SKILL.md").path
        ))
    }

    @Test("valid candidates remain installable when another candidate is invalid")
    func installsValidCandidatesBesideRejectedCandidates() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let zipURL = fixture.home.appendingPathComponent("partially-valid.zip")
        try StoredZIP.make([
            "review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review valid changes.
                ---
                """.utf8
            ),
            "broken/SKILL.md": Data(
                """
                ---
                name: broken
                ---
                """.utf8
            ),
            "missing-manifest/README.md": Data("Not a Skill manifest.".utf8),
            "malformed/SKILL.md": Data(
                """
                ---
                name: malformed
                description: [unterminated
                ---
                """.utf8
            ),
        ]).write(to: zipURL)
        let service = GlobalSkillsService(homeDirectory: fixture.home, environment: [:])

        let batch = try await service.discoverSkills(inZip: zipURL)

        let candidate = try #require(batch.candidates.first)
        #expect(batch.candidates.map(\.name) == ["review"])
        #expect(batch.rejectedCandidates.count == 3)
        let rejections = Dictionary(uniqueKeysWithValues: batch.rejectedCandidates.map {
            ($0.sourceRelativePath, $0.message)
        })
        #expect(rejections["broken"]?.contains("description") == true)
        #expect(rejections["missing-manifest"]?.contains("SKILL.md") == true)
        #expect(rejections["malformed"]?.contains("frontmatter") == true)
        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )
        let result = await service.install(preview)
        #expect(result.items.first?.status == .succeeded)
        #expect(result.snapshot.skills.map(\.name) == ["review"])
    }

    @Test("public GitHub installation records the resolved upstream without touching Skill files")
    func installsFromGitHubWithProvenance() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let archive = StoredZIP.make([
            "example-skills-commit/skills/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review from GitHub.
                ---
                """.utf8
            ),
            "example-skills-commit/skills/review/references/checklist.md": Data("Check it.".utf8),
        ])
        let github = StubGitHubProvider(archiveData: archive)
        let records = MemorySkillRecordRepository()
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records,
            githubProvider: github
        )

        let batch = try await service.discoverSkills(
            fromGitHub: "example/skills:skills/review"
        )
        let candidate = try #require(batch.candidates.first)
        #expect(candidate.remoteProvenance?.repository == "example/skills")
        #expect(candidate.remoteProvenance?.sourceRelativePath == "skills/review")
        #expect(candidate.remoteProvenance?.resolvedCommit == "commit-2")
        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )

        let result = await service.install(preview)

        #expect(result.items.first?.status == .succeeded)
        let record = try #require(try await records.loadSkillInstallationRecords().first)
        #expect(record.source == .github)
        #expect(record.repository == "example/skills")
        #expect(record.sourceRelativePath == "skills/review")
        #expect(record.reference == SkillSourceReference(kind: .branch, value: "main"))
        #expect(record.resolvedCommit == "commit-2")
        let installedFiles = try FileManager.default.contentsOfDirectory(
            atPath: record.installationDirectory.path
        )
        #expect(!installedFiles.contains { $0.hasPrefix(".breath") })
        let snapshot = await service.scan()
        #expect(snapshot.skills.first?.copies.first?.source == .github)
        #expect(snapshot.skills.first?.copies.first?.updateState == .current)
        #expect(await github.requestedLocators() == [
            GitHubSkillLocator(
                repository: "example/skills",
                subdirectory: "skills/review"
            ),
        ])
    }

    @Test("a failed target rolls back independently while other Agent installs succeed")
    func keepsBatchSuccessWhenOneRecordCommitFails() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let archive = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review with independent target commits.
                ---
                """.utf8
            ),
        ])
        let records = SelectivelyFailingSkillRecordRepository(failingAgents: [.claudeCode])
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records,
            githubProvider: StubGitHubProvider(archiveData: archive)
        )
        let batch = try await service.discoverSkills(fromGitHub: "example/skills")
        let candidate = try #require(batch.candidates.first)
        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex, .claudeCode]
        )

        let result = await service.install(preview)

        #expect(result.items.first { $0.targetID.agent == .codex }?.status == .succeeded)
        #expect(result.items.first { $0.targetID.agent == .claudeCode }?.status == .failed)
        #expect(FileManager.default.fileExists(
            atPath: try fixture.skillRoot(for: .codex).appendingPathComponent("review").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: try fixture.skillRoot(for: .claudeCode).appendingPathComponent("review").path
        ))
        #expect(result.snapshot.skills.count == 1)
        #expect(result.snapshot.skills.first?.copies.map(\.agent) == [.codex])
    }

    @Test("replacing a remote Skill from ZIP clears its obsolete update provenance")
    func zipReplacementClearsRemoteProvenance() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let remoteArchive = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review from GitHub.
                ---
                """.utf8
            ),
        ])
        let records = MemorySkillRecordRepository()
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records,
            githubProvider: StubGitHubProvider(archiveData: remoteArchive)
        )
        let remoteBatch = try await service.discoverSkills(fromGitHub: "example/skills")
        let remoteCandidate = try #require(remoteBatch.candidates.first)
        let remotePreview = await service.previewInstallation(
            batch: remoteBatch,
            candidateIDs: [remoteCandidate.id],
            targetAgents: [.codex]
        )
        #expect((await service.install(remotePreview)).items.first?.status == .succeeded)
        #expect(try await records.loadSkillInstallationRecords().count == 1)

        let zipURL = fixture.home.appendingPathComponent("local-review.zip")
        try StoredZIP.make([
            "review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review from a local ZIP.
                ---
                """.utf8
            ),
        ]).write(to: zipURL)
        let zipBatch = try await service.discoverSkills(inZip: zipURL)
        let zipCandidate = try #require(zipBatch.candidates.first)
        let targetID = SkillInstallationTargetID(
            candidateID: zipCandidate.id,
            agent: .codex
        )
        let zipPreview = await service.previewInstallation(
            batch: zipBatch,
            candidateIDs: [zipCandidate.id],
            targetAgents: [.codex],
            replacementChoices: [targetID: .replace]
        )

        let replacement = await service.install(zipPreview)

        #expect(replacement.items.first?.status == .succeeded)
        #expect(try await records.loadSkillInstallationRecords().count == 1)
        #expect(try await records.loadSkillInstallationRecords().first?.source == .zip)
        #expect(replacement.snapshot.skills.first?.copies.first?.source == .zip)
        #expect(replacement.snapshot.skills.first?.copies.first?.updateState == .unavailable)
    }

    @Test("writes are serialized per Agent while independent Agent directories run concurrently")
    func coordinatesConcurrentAgentWrites() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let archive = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review changes.
                ---
                """.utf8
            ),
            "example-skills-commit/summarize/SKILL.md": Data(
                """
                ---
                name: summarize
                description: Summarize changes.
                ---
                """.utf8
            ),
        ])
        let records = MeasuringSkillRecordRepository()
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records,
            githubProvider: StubGitHubProvider(archiveData: archive)
        )
        let batch = try await service.discoverSkills(fromGitHub: "example/skills")
        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: Set(batch.candidates.map(\.id)),
            targetAgents: [.codex, .claudeCode]
        )

        let result = await service.install(preview)
        let measurements = await records.measurements()

        #expect(result.items.count == 4)
        #expect(result.items.allSatisfy { $0.status == .succeeded })
        #expect(measurements.maximumByAgent[.codex] == 1)
        #expect(measurements.maximumByAgent[.claudeCode] == 1)
        #expect(measurements.maximumGlobal >= 2)
    }

    @Test("skills.sh search keeps unknown audits honest and requires high-risk confirmation")
    func searchesAndInstallsFromSkillsSh() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let pageURL = try #require(URL(string: "https://skills.sh/example/skills/review"))
        let installURL = try #require(URL(string: "https://github.com/example/skills"))
        let searchResult = SkillsShSearchResult(
            id: "example/skills/review",
            slug: "review",
            name: "Review",
            description: "Review a change.",
            source: "example/skills",
            installs: 42,
            sourceType: "github",
            installURL: installURL,
            pageURL: pageURL
        )
        let catalog = StubSkillsShProvider(
            results: [searchResult],
            audit: SkillSecurityAudit(
                riskLevel: .high,
                summary: "Review shell access before installing.",
                checkedAt: Date(timeIntervalSince1970: 500)
            )
        )
        let archive = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review from the catalog.
                ---
                """.utf8
            ),
        ])
        let github = StubGitHubProvider(archiveData: archive)
        let records = MemorySkillRecordRepository()
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records,
            githubProvider: github,
            skillsShProvider: catalog
        )

        let results = try await service.searchSkillsSh(query: "review")
        let auditedResult = try #require(results.first)
        #expect(auditedResult.securityAudit.riskLevel == .high)
        #expect(auditedResult.securityAudit.checkedAt == Date(timeIntervalSince1970: 500))
        let batch = try await service.discoverSkill(fromSkillsSh: auditedResult)
        let candidate = try #require(batch.candidates.first)
        #expect(candidate.source == .skillsSh)
        #expect(candidate.securityAudit.riskLevel == .high)
        #expect(candidate.securityAudit.checkedAt == Date(timeIntervalSince1970: 500))
        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )

        let unconfirmed = await service.install(preview)
        #expect(unconfirmed.items.first?.status == .failed)
        #expect(unconfirmed.items.first?.message.contains("high-risk") == true)

        let confirmedBatch = try await service.discoverSkill(fromSkillsSh: auditedResult)
        let confirmedCandidate = try #require(confirmedBatch.candidates.first)
        let confirmedPreview = await service.previewInstallation(
            batch: confirmedBatch,
            candidateIDs: [confirmedCandidate.id],
            targetAgents: [.codex]
        )
        let confirmed = await service.install(
            confirmedPreview,
            confirmedRiskCandidateIDs: [confirmedCandidate.id]
        )
        #expect(confirmed.items.first?.status == .succeeded)
        #expect(
            confirmed.snapshot.skills.first?.copies.first?.catalogSkillID
                == "example/skills/review"
        )
        #expect(try await records.loadSkillInstallationRecords().first?.source == .skillsSh)
        #expect(await catalog.queries() == ["review"])
        #expect(await catalog.auditedIDs() == ["example/skills/review"])
    }

    @Test("skills.sh identity recognizes an installed Skill after its manifest name changes")
    func matchesInstalledSkillsShIdentity() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(
            agent: .codex,
            directoryName: "old-review",
            manifest: """
                ---
                name: old-review
                description: Previously installed review behavior.
                ---
                old
                """
        )
        let initial = await GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:]
        ).scan()
        let installed = try #require(initial.skills.first)
        let installedCopy = try #require(installed.copies.first)
        let records = MemorySkillRecordRepository(records: [
            SkillInstallationRecord(
                agent: .codex,
                installationDirectory: installedCopy.directory,
                skillName: installed.name,
                origin: .remote(SkillRemoteProvenance(
                    source: .skillsSh,
                    repository: "example/skills",
                    sourceRelativePath: "review",
                    reference: SkillSourceReference(kind: .branch, value: "main"),
                    resolvedCommit: "old-commit",
                    catalogSkillID: "example/skills/review"
                )),
                installedContentDigest: installed.contentDigest,
                installedAt: .distantPast,
                updatedAt: .distantPast
            ),
        ])
        let searchResult = SkillsShSearchResult(
            id: "example/skills/review",
            slug: "review",
            name: "Renamed Review",
            description: nil,
            source: "example/skills",
            installs: 42,
            sourceType: "github",
            installURL: try #require(URL(string: "https://github.com/example/skills")),
            pageURL: try #require(URL(string: "https://skills.sh/example/skills/review"))
        )
        let archive = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: renamed-review
                description: Renamed review behavior.
                ---
                new
                """.utf8
            ),
        ])
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records,
            githubProvider: StubGitHubProvider(archiveData: archive),
            skillsShProvider: StubSkillsShProvider(results: [searchResult], audit: .unknown)
        )
        let batch = try await service.discoverSkill(fromSkillsSh: searchResult)
        let candidate = try #require(batch.candidates.first)
        let preview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )
        let item = try #require(preview.items.first)

        #expect(item.action == .skip)
        #expect(item.existingMatch == .sameSourceIdentity)
        #expect(candidate.remoteProvenance?.sourceIdentity == .skillsSh(
            catalogSkillID: "example/skills/review"
        ))
        #expect(item.existingDirectory == installedCopy.directory)
        #expect(item.expectedSameNamePaths.isEmpty)

        let replacement = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex],
            replacementChoices: [item.targetID: .replace]
        )
        let result = await service.install(replacement)

        #expect(result.items.first?.status == .succeeded)
        #expect(result.snapshot.skills.first?.name == "renamed-review")
        #expect(result.snapshot.skills.first?.copies.first?.catalogSkillID == searchResult.id)
        #expect(result.snapshot.skills.first?.copies.first?.directory == installedCopy.directory)
    }

    @Test("GitHub source identity normalizes repository case and path separators")
    func normalizesGitHubSourceIdentity() {
        #expect(
            SkillSourceIdentity(
                source: .github,
                repository: "/Example/Skills/",
                sourceRelativePath: "/skills/review/",
                catalogSkillID: nil
            ) == .github(
                repository: "example/skills",
                sourceRelativePath: "skills/review"
            )
        )
        #expect(
            SkillSourceIdentity(
                source: .skillsSh,
                repository: "Example/Skills",
                sourceRelativePath: "Review",
                catalogSkillID: " Example/Skills/Review "
            ) == .skillsSh(catalogSkillID: "Example/Skills/Review")
        )
    }

    @Test("skills.sh selects the slug-matched nested Skill over a repository manifest")
    func selectsNestedSkillsShCandidate() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let pageURL = try #require(URL(string: "https://skills.sh/example/kami/kami"))
        let searchResult = SkillsShSearchResult(
            id: "example/kami/kami",
            slug: "kami",
            name: "kami",
            description: "Typeset documents.",
            source: "example/kami",
            installs: 42,
            sourceType: "github",
            installURL: try #require(URL(string: "https://github.com/example/kami")),
            pageURL: pageURL
        )
        let archive = StoredZIP.make([
            "example-kami-commit/SKILL.md": Data(
                """
                ---
                name: kami
                description: Repository-wide instructions.
                ---
                """.utf8
            ),
            "example-kami-commit/site/index.html": Data("website".utf8),
            "example-kami-commit/plugins/kami/skills/kami/SKILL.md": Data(
                """
                ---
                name: kami
                description: Typeset documents.
                ---
                """.utf8
            ),
            "example-kami-commit/plugins/kami/skills/kami/references/guide.md": Data(
                "Guide".utf8
            ),
        ])
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            githubProvider: StubGitHubProvider(archiveData: archive),
            skillsShProvider: StubSkillsShProvider(results: [searchResult], audit: .unknown)
        )

        let batch = try await service.discoverSkill(fromSkillsSh: searchResult)
        let candidate = try #require(batch.candidates.first)

        #expect(batch.candidates.count == 1)
        #expect(candidate.sourceRelativePath == "plugins/kami/skills/kami")
        #expect(candidate.description == "Typeset documents.")
        #expect(candidate.files.map(\.relativePath) == ["SKILL.md", "references/guide.md"])
        #expect(!candidate.warnings.contains { $0.kind == .directoryNameMismatch })
    }

    @Test("skills.sh does not fall back to a repository manifest when its slug path is invalid")
    func rejectsInvalidNestedSkillsShCandidate() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let searchResult = SkillsShSearchResult(
            id: "example/kami/kami",
            slug: "kami",
            name: "kami",
            description: nil,
            source: "example/kami",
            installs: 42,
            sourceType: "github",
            installURL: try #require(URL(string: "https://github.com/example/kami")),
            pageURL: try #require(URL(string: "https://skills.sh/example/kami/kami"))
        )
        let archive = StoredZIP.make([
            "example-kami-commit/SKILL.md": Data(
                """
                ---
                name: kami
                description: Repository-wide instructions.
                ---
                """.utf8
            ),
            "example-kami-commit/plugins/kami/skills/kami/SKILL.md": Data(
                """
                ---
                name: kami
                ---
                """.utf8
            ),
        ])
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            githubProvider: StubGitHubProvider(archiveData: archive),
            skillsShProvider: StubSkillsShProvider(results: [searchResult], audit: .unknown)
        )

        let batch = try await service.discoverSkill(fromSkillsSh: searchResult)

        #expect(batch.candidates.isEmpty)
        #expect(batch.rejectedCandidates.map(\.sourceRelativePath) == [
            "plugins/kami/skills/kami",
        ])
    }

    @Test("update checks are explicit, ignore unrelated commits, and protect locally modified targets")
    func checksAndInstallsOneUpdate() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let versionOne = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review version one.
                ---
                v1
                """.utf8
            ),
        ])
        let versionTwo = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review version two.
                ---
                v2
                """.utf8
            ),
        ])
        let github = MutableGitHubProvider(
            archiveData: versionOne,
            commit: "commit-1"
        )
        let records = MemorySkillRecordRepository()
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: records,
            githubProvider: github
        )
        let initialBatch = try await service.discoverSkills(
            fromGitHub: "example/skills:review"
        )
        let initialCandidate = try #require(initialBatch.candidates.first)
        let initialPreview = await service.previewInstallation(
            batch: initialBatch,
            candidateIDs: [initialCandidate.id],
            targetAgents: [.codex, .claudeCode]
        )
        #expect((await service.install(initialPreview)).items.allSatisfy {
            $0.status == .succeeded
        })
        let initialRecords = try await records.loadSkillInstallationRecords()
        let installedAtByPath = Dictionary(uniqueKeysWithValues: initialRecords.map {
            ($0.installationDirectory.standardizedFileURL.path, $0.installedAt)
        })
        try await Task.sleep(for: .milliseconds(10))
        #expect(await github.requestCount() == 1)

        let claudeDirectory = try fixture.skillRoot(for: .claudeCode)
            .appendingPathComponent("review", isDirectory: true)
        try Data("keep this local note".utf8).write(
            to: claudeDirectory.appendingPathComponent("local.md")
        )
        _ = await service.scan()
        #expect(await github.requestCount() == 1)
        await github.set(archiveData: versionTwo, commit: "commit-2")

        let checked = await service.checkForUpdates()

        let update = try #require(checked.updates.first)
        #expect(!checked.usedSessionCache)
        #expect(update.oldCommits == ["commit-1"])
        #expect(update.newCommit == "commit-2")
        #expect(update.targets.count == 2)
        #expect(update.targets.first { $0.agent == .codex }?.isSelectedByDefault == true)
        #expect(update.targets.first { $0.agent == .claudeCode }?.isLocallyModified == true)
        #expect(update.targets.first { $0.agent == .claudeCode }?.isSelectedByDefault == false)
        #expect((await service.checkForUpdates()).usedSessionCache)
        #expect(await github.requestCount() == 2)

        let updatePreview = await service.previewUpdate(
            update,
            targetAgents: [.codex, .claudeCode]
        )
        #expect(updatePreview.items.allSatisfy { $0.action == .replace })
        let installed = await service.install(updatePreview)
        #expect(installed.items.allSatisfy { $0.status == .succeeded })
        let updatedRecords = try await records.loadSkillInstallationRecords()
        #expect(Set(updatedRecords.compactMap(\.resolvedCommit)) == ["commit-2"])
        #expect(updatedRecords.allSatisfy {
            $0.installedAt == installedAtByPath[$0.installationDirectory.standardizedFileURL.path]
                && $0.updatedAt > $0.installedAt
        })
        #expect(try String(
            contentsOf: claudeDirectory.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        ).contains("version two"))
        #expect(!FileManager.default.fileExists(
            atPath: claudeDirectory.appendingPathComponent("local.md").path
        ))

        await service.beginUpdateCheckSession()
        let nextPageSession = await service.checkForUpdates()
        #expect(!nextPageSession.usedSessionCache)
        #expect(await github.requestCount() == 3)

        await github.set(archiveData: versionTwo, commit: "commit-3")
        let unrelatedCommit = await service.checkForUpdates(force: true)
        #expect(unrelatedCommit.updates.isEmpty)
        #expect(unrelatedCommit.failures.isEmpty)
    }

    @Test("skills.sh updates preserve audits and require high-risk confirmation")
    func skillsShUpdatesRequireConfirmation() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let versionOne = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review version one.
                ---
                v1
                """.utf8
            ),
        ])
        let versionTwo = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review version two.
                ---
                v2
                """.utf8
            ),
        ])
        let github = MutableGitHubProvider(archiveData: versionOne, commit: "commit-1")
        let catalogResult = SkillsShSearchResult(
            id: "example/skills/review",
            slug: "review",
            name: "Review",
            description: "Review a change.",
            source: "example/skills",
            installs: 42,
            sourceType: "github",
            installURL: URL(string: "https://github.com/example/skills"),
            pageURL: try #require(URL(string: "https://skills.sh/example/skills/review"))
        )
        let catalog = StubSkillsShProvider(
            results: [catalogResult],
            audit: SkillSecurityAudit(
                riskLevel: .critical,
                summary: "Critical audit finding.",
                checkedAt: Date(timeIntervalSince1970: 900)
            )
        )
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: MemorySkillRecordRepository(),
            githubProvider: github,
            skillsShProvider: catalog
        )
        let auditedResult = try #require(
            try await service.searchSkillsSh(query: "review").first
        )
        let batch = try await service.discoverSkill(fromSkillsSh: auditedResult)
        let candidate = try #require(batch.candidates.first)
        let initialPreview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: [.codex]
        )
        #expect((await service.install(
            initialPreview,
            confirmedRiskCandidateIDs: [candidate.id]
        )).items.first?.status == .succeeded)

        await github.set(archiveData: versionTwo, commit: "commit-2")
        let update = try #require((await service.checkForUpdates()).updates.first)
        #expect(update.candidate.securityAudit.riskLevel == .critical)
        #expect(update.candidate.securityAudit.checkedAt == Date(timeIntervalSince1970: 900))
        let preview = await service.previewUpdate(update, targetAgents: [.codex])

        let result = await service.install(preview)

        #expect(result.items.first?.status == .failed)
        #expect(result.items.first?.message.contains("high-risk") == true)
        #expect(await catalog.auditedIDs() == [
            "example/skills/review",
            "example/skills/review",
        ])
    }

    @Test("all supported Agents scan, install, update, and uninstall Skills")
    func everyAgentSupportsTheFullSkillLifecycle() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let agents = Set(AgentKind.allCases)
        let versionOne = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review version one.
                ---
                """.utf8
            ),
        ])
        let versionTwo = StoredZIP.make([
            "example-skills-commit/review/SKILL.md": Data(
                """
                ---
                name: review
                description: Review version two.
                ---
                """.utf8
            ),
        ])
        let github = MutableGitHubProvider(archiveData: versionOne, commit: "commit-1")
        let trash = RecordingSkillTrash(
            recoveryDirectory: fixture.home.appendingPathComponent("Trash", isDirectory: true)
        )
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: MemorySkillRecordRepository(),
            githubProvider: github,
            trash: trash
        )
        let batch = try await service.discoverSkills(fromGitHub: "example/skills")
        let candidate = try #require(batch.candidates.first)
        let installPreview = await service.previewInstallation(
            batch: batch,
            candidateIDs: [candidate.id],
            targetAgents: agents
        )

        let installed = await service.install(installPreview)

        #expect(installed.items.count == agents.count)
        #expect(installed.items.allSatisfy { $0.status == .succeeded })
        let installedSkill = try #require(installed.snapshot.skills.first)
        #expect(Set(installedSkill.copies.map(\.agent)) == agents)

        await github.set(archiveData: versionTwo, commit: "commit-2")
        let update = try #require((await service.checkForUpdates()).updates.first)
        #expect(Set(update.targets.map(\.agent)) == agents)
        let updatePreview = await service.previewUpdate(update, targetAgents: agents)
        let updated = await service.install(updatePreview)
        #expect(updated.items.allSatisfy { $0.status == .succeeded })
        #expect(updated.snapshot.skills.first?.description == "Review version two.")

        let skill = try #require(updated.snapshot.skills.first)
        let uninstallPreview = await service.previewUninstall(
            skillID: skill.id,
            targetAgents: agents
        )
        let uninstalled = await service.uninstall(uninstallPreview)
        #expect(uninstalled.items.count == agents.count)
        #expect(uninstalled.items.allSatisfy { $0.status == .succeeded })
        #expect(uninstalled.snapshot.skills.isEmpty)
    }

    @Test("optional Skill manifest declarations are retained for installation review")
    func parsesOptionalManifestDeclarations() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let zipURL = fixture.home.appendingPathComponent("declared.zip")
        try StoredZIP.make([
            "review/SKILL.md": Data(
                """
                ---
                name: review
                description: >-
                  Review a

                  change.
                license: Apache-2.0
                compatibility: Requires git 2.40 or newer.
                metadata:
                  author: example-org
                  owner: platform
                  category: engineering
                allowed-tools:
                  - Read
                  - Grep
                  - Glob
                ---
                """.utf8
            ),
        ]).write(to: zipURL)
        let service = GlobalSkillsService(homeDirectory: fixture.home, environment: [:])

        let candidate = try #require(
            try await service.discoverSkills(inZip: zipURL).candidates.first
        )

        #expect(candidate.declarations.license == "Apache-2.0")
        #expect(candidate.declarations.author == "example-org")
        #expect(candidate.description == "Review a\nchange.")
        #expect(candidate.declarations.compatibility == "Requires git 2.40 or newer.")
        #expect(candidate.declarations.metadata?.contains("owner: platform") == true)
        #expect(candidate.declarations.metadata?.contains("category: engineering") == true)
        #expect(candidate.declarations.allowedTools == "- Read\n- Grep\n- Glob")
    }

    @Test("uninstall trashes physical copies but removes only an external link")
    func uninstallsSelectedCopiesSafely() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        let manifest = """
            ---
            name: review
            description: Review before shipping.
            ---
            """
        try fixture.writeSkill(
            agent: .codex,
            directoryName: "review",
            manifest: manifest
        )
        let external = fixture.home.deletingLastPathComponent()
            .appendingPathComponent("shared-review-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: external.appendingPathComponent("SKILL.md"))
        let claudeLink = try fixture.skillRoot(for: .claudeCode)
            .appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(
            at: claudeLink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: claudeLink, withDestinationURL: external)
        let trash = RecordingSkillTrash(
            recoveryDirectory: fixture.home.appendingPathComponent("Trash", isDirectory: true)
        )
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            trash: trash
        )
        let snapshot = await service.scan()
        let skill = try #require(snapshot.skills.first)
        #expect(skill.copies.count == 2)
        let preview = await service.previewUninstall(
            skillID: skill.id,
            targetAgents: [.codex, .claudeCode]
        )
        #expect(preview.items.first { $0.agent == .codex }?.action == .moveToTrash)
        #expect(preview.items.first { $0.agent == .claudeCode }?.action == .removeSymbolicLink)

        let result = await service.uninstall(preview)

        #expect(result.items.allSatisfy { $0.status == .succeeded })
        #expect(result.snapshot.skills.isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: try fixture.skillRoot(for: .codex).appendingPathComponent("review").path
        ))
        #expect(!FileManager.default.fileExists(atPath: claudeLink.path))
        #expect(FileManager.default.fileExists(atPath: external.path))
        #expect(await trash.trashedItems().map(\.lastPathComponent) == ["review"])
    }

    @Test("uninstall reports source-record cleanup failures after preserving disk truth")
    func reportsUninstallRecordCleanupFailure() async throws {
        let fixture = try SkillsFixture()
        defer { fixture.remove() }
        try fixture.writeSkill(
            agent: .codex,
            directoryName: "review",
            manifest: """
                ---
                name: review
                description: Review before shipping.
                ---
                """
        )
        let trash = RecordingSkillTrash(
            recoveryDirectory: fixture.home.appendingPathComponent("Trash", isDirectory: true)
        )
        let service = GlobalSkillsService(
            homeDirectory: fixture.home,
            environment: [:],
            recordRepository: FailingRemovalSkillRecordRepository(),
            trash: trash
        )
        let skill = try #require((await service.scan()).skills.first)
        let preview = await service.previewUninstall(
            skillID: skill.id,
            targetAgents: [.codex]
        )

        let result = await service.uninstall(preview)

        #expect(result.items.first?.status == .failed)
        #expect(result.items.first?.message.contains("source record") == true)
        #expect(result.items.first?.diagnostic?.contains("SkillInstallationError") == true)
        #expect(result.snapshot.skills.isEmpty)
        #expect(await trash.trashedItems().map(\.lastPathComponent) == ["review"])
    }
}

private struct SkillsFixture {
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-skills-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true
        )
    }

    func writeSkill(
        agent: AgentKind,
        directoryName: String,
        manifest: String,
        files: [String: String] = [:]
    ) throws {
        let skillURL = try skillRoot(for: agent)
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: skillURL,
            withIntermediateDirectories: true
        )
        try Data(manifest.utf8).write(to: skillURL.appendingPathComponent("SKILL.md"))
        for (relativePath, contents) in files {
            let fileURL = skillURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: fileURL)
        }
    }

    func writeInvalidItem(agent: AgentKind, directoryName: String) throws {
        try FileManager.default.createDirectory(
            at: try skillRoot(for: agent).appendingPathComponent(directoryName),
            withIntermediateDirectories: true
        )
    }

    func skillRoot(for agent: AgentKind) throws -> URL {
        let adapter = try #require(
            AgentAdapterRegistry.builtIn.adapters.first { $0.kind == agent }
        )
        return try #require(adapter.globalSkills).resolveDirectory(
            homeDirectory: home,
            environment: [:]
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: home)
    }
}

private actor MemorySkillRecordRepository: SkillInstallationRecordRepository {
    private var records: [SkillInstallationRecord]

    init(records: [SkillInstallationRecord] = []) {
        self.records = records
    }

    func loadSkillInstallationRecords() async throws -> [SkillInstallationRecord] {
        records
    }

    func saveSkillInstallationRecord(_ record: SkillInstallationRecord) async throws {
        records.removeAll { $0.installationDirectory == record.installationDirectory }
        records.append(record)
    }

    func removeSkillInstallationRecord(installationDirectory: URL) async throws {
        records.removeAll { $0.installationDirectory == installationDirectory }
    }
}

private actor SelectivelyFailingSkillRecordRepository: SkillInstallationRecordRepository {
    private let failingAgents: Set<AgentKind>
    private var records: [SkillInstallationRecord] = []

    init(failingAgents: Set<AgentKind>) {
        self.failingAgents = failingAgents
    }

    func loadSkillInstallationRecords() async throws -> [SkillInstallationRecord] {
        records
    }

    func saveSkillInstallationRecord(_ record: SkillInstallationRecord) async throws {
        guard !failingAgents.contains(record.agent) else {
            throw TestRecordError.saveFailed
        }
        records.removeAll { $0.installationDirectory == record.installationDirectory }
        records.append(record)
    }

    func removeSkillInstallationRecord(installationDirectory: URL) async throws {
        records.removeAll { $0.installationDirectory == installationDirectory }
    }
}

private actor FailingRemovalSkillRecordRepository: SkillInstallationRecordRepository {
    func loadSkillInstallationRecords() async throws -> [SkillInstallationRecord] { [] }

    func saveSkillInstallationRecord(_ record: SkillInstallationRecord) async throws {}

    func removeSkillInstallationRecord(installationDirectory: URL) async throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private actor MeasuringSkillRecordRepository: SkillInstallationRecordRepository {
    struct Measurements: Sendable {
        let maximumGlobal: Int
        let maximumByAgent: [AgentKind: Int]
    }

    private var records: [SkillInstallationRecord] = []
    private var activeGlobal = 0
    private var activeByAgent: [AgentKind: Int] = [:]
    private var maximumGlobal = 0
    private var maximumByAgent: [AgentKind: Int] = [:]

    func loadSkillInstallationRecords() async throws -> [SkillInstallationRecord] {
        records
    }

    func saveSkillInstallationRecord(_ record: SkillInstallationRecord) async throws {
        activeGlobal += 1
        activeByAgent[record.agent, default: 0] += 1
        maximumGlobal = max(maximumGlobal, activeGlobal)
        maximumByAgent[record.agent] = max(
            maximumByAgent[record.agent, default: 0],
            activeByAgent[record.agent, default: 0]
        )
        do {
            try await Task.sleep(for: .milliseconds(40))
        } catch {
            finish(record.agent)
            throw error
        }
        records.removeAll { $0.installationDirectory == record.installationDirectory }
        records.append(record)
        finish(record.agent)
    }

    func removeSkillInstallationRecord(installationDirectory: URL) async throws {
        records.removeAll { $0.installationDirectory == installationDirectory }
    }

    func measurements() -> Measurements {
        Measurements(
            maximumGlobal: maximumGlobal,
            maximumByAgent: maximumByAgent
        )
    }

    private func finish(_ agent: AgentKind) {
        activeGlobal -= 1
        activeByAgent[agent, default: 1] -= 1
    }
}

private enum TestRecordError: Error {
    case saveFailed
}

private actor StubGitHubProvider: GitHubSkillProviding {
    private let archiveData: Data
    private var locators: [GitHubSkillLocator] = []
    private var commitIndex = 1

    init(archiveData: Data) {
        self.archiveData = archiveData
    }

    func resolve(_ locator: GitHubSkillLocator) async throws -> GitHubResolvedSkillArchive {
        locators.append(locator)
        commitIndex += 1
        return GitHubResolvedSkillArchive(
            repository: locator.repository,
            subdirectory: locator.subdirectory,
            reference: locator.reference ?? SkillSourceReference(kind: .branch, value: "main"),
            resolvedCommit: "commit-\(commitIndex)",
            archiveData: archiveData
        )
    }

    func requestedLocators() -> [GitHubSkillLocator] {
        locators
    }
}

private actor StubSkillsShProvider: SkillsShProviding {
    private let results: [SkillsShSearchResult]
    private let auditResult: SkillSecurityAudit
    private var searchQueries: [String] = []
    private var auditIDs: [String] = []

    init(results: [SkillsShSearchResult], audit: SkillSecurityAudit) {
        self.results = results
        auditResult = audit
    }

    func search(query: String, limit: Int) async throws -> [SkillsShSearchResult] {
        searchQueries.append(query)
        return Array(results.prefix(limit))
    }

    func audit(skillID: String) async throws -> SkillSecurityAudit {
        auditIDs.append(skillID)
        return auditResult
    }

    func queries() -> [String] {
        searchQueries
    }

    func auditedIDs() -> [String] {
        auditIDs
    }
}

private actor MutableGitHubProvider: GitHubSkillProviding {
    private var archiveData: Data
    private var commit: String
    private var requests = 0

    init(archiveData: Data, commit: String) {
        self.archiveData = archiveData
        self.commit = commit
    }

    func resolve(_ locator: GitHubSkillLocator) async throws -> GitHubResolvedSkillArchive {
        requests += 1
        return GitHubResolvedSkillArchive(
            repository: locator.repository,
            subdirectory: locator.subdirectory,
            reference: locator.reference ?? SkillSourceReference(kind: .branch, value: "main"),
            resolvedCommit: commit,
            archiveData: archiveData
        )
    }

    func set(archiveData: Data, commit: String) {
        self.archiveData = archiveData
        self.commit = commit
    }

    func requestCount() -> Int {
        requests
    }
}

private actor RecordingSkillTrash: SkillTrashing {
    private let recoveryDirectory: URL
    private var items: [URL] = []

    init(recoveryDirectory: URL) {
        self.recoveryDirectory = recoveryDirectory
    }

    func moveToTrash(_ url: URL) async throws {
        try FileManager.default.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )
        var destination = recoveryDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = recoveryDirectory.appendingPathComponent(
                "\(UUID().uuidString)-\(url.lastPathComponent)"
            )
        }
        try FileManager.default.moveItem(at: url, to: destination)
        items.append(destination)
    }

    func trashedItems() -> [URL] {
        items
    }
}

private enum StoredZIP {
    static func make(_ files: [String: Data]) -> Data {
        var archive = Data()
        var central = Data()
        var entryCount: UInt16 = 0
        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
            let name = Data(path.utf8)
            let checksum = crc32(contents)
            let localOffset = UInt32(archive.count)
            archive.appendLittleEndian(UInt32(0x04034B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(checksum)
            archive.appendLittleEndian(UInt32(contents.count))
            archive.appendLittleEndian(UInt32(contents.count))
            archive.appendLittleEndian(UInt16(name.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(name)
            archive.append(contents)

            central.appendLittleEndian(UInt32(0x02014B50))
            central.appendLittleEndian(UInt16(0x031E))
            central.appendLittleEndian(UInt16(20))
            central.appendLittleEndian(UInt16(0x0800))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(checksum)
            central.appendLittleEndian(UInt32(contents.count))
            central.appendLittleEndian(UInt32(contents.count))
            central.appendLittleEndian(UInt16(name.count))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt32(0o100644 << 16))
            central.appendLittleEndian(localOffset)
            central.append(name)
            entryCount += 1
        }
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.appendLittleEndian(UInt32(0x06054B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(entryCount)
        archive.appendLittleEndian(entryCount)
        archive.appendLittleEndian(UInt32(central.count))
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB88320 & (0 &- (crc & 1)))
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var encoded = value.littleEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }
}
