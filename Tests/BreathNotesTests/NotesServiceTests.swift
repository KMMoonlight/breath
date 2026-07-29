import BreathNotes
import BreathPersistence
import Foundation
import Testing

@Suite("Notes service")
struct NotesServiceTests {
    @Test("user opens, edits, and explicitly saves the first note")
    func openEditAndSaveFirstNote() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("hello.md")
        try Data("# Hello\n\nOriginal.\n".utf8).write(to: noteURL)

        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)

        let selected = try await service.selectLibrary(at: fixture.libraryURL)
        #expect(selected.library?.rootPath == fixture.libraryURL.path)

        let opened = try await service.openDocument(relativePath: "hello.md")
        #expect(opened.content == "# Hello\n\nOriginal.\n")
        #expect(!opened.isDirty)

        let edited = try await service.updateDocument(
            opened.id,
            content: "# Hello\n\nEdited.\n"
        )
        #expect(edited.isDirty)
        #expect(String(decoding: try Data(contentsOf: noteURL), as: UTF8.self)
            == "# Hello\n\nOriginal.\n")

        let saved = try await service.saveDocument(opened.id)
        #expect(!saved.isDirty)
        #expect(String(decoding: try Data(contentsOf: noteURL), as: UTF8.self)
            == "# Hello\n\nEdited.\n")

        let restoredService = NotesService(repository: repository)
        let restored = try await restoredService.restore()
        #expect(restored.library?.rootPath == fixture.libraryURL.path)
    }

    @Test("explicit save preserves UTF-8 BOM and original CRLF bytes")
    func savePreservesEncodingDetails() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("windows.md")
        let original = Data([0xEF, 0xBB, 0xBF])
            + Data("# Heading\r\n\r\nOriginal.\r\n".utf8)
        try original.write(to: noteURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        let opened = try await service.openDocument(
            relativePath: "windows.md"
        )

        _ = try await service.updateDocument(
            opened.id,
            content: "# Heading\r\n\r\nEdited.\r\n"
        )
        _ = try await service.saveDocument(opened.id)

        let expected = Data([0xEF, 0xBB, 0xBF])
            + Data("# Heading\r\n\r\nEdited.\r\n".utf8)
        #expect(try Data(contentsOf: noteURL) == expected)
    }

    @Test("library tree ignores hidden items and symlinks and restores clean tabs")
    func browseAndRestoreLibrary() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let folderURL = fixture.libraryURL.appendingPathComponent(
            "Guides",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        try Data("# Two".utf8).write(
            to: fixture.libraryURL.appendingPathComponent("note2.md")
        )
        try Data("# Ten".utf8).write(
            to: fixture.libraryURL.appendingPathComponent("note10.md")
        )
        try Data("secret".utf8).write(
            to: fixture.libraryURL.appendingPathComponent(".hidden.md")
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.libraryURL.appendingPathComponent("linked.md"),
            withDestinationURL: fixture.libraryURL.appendingPathComponent("note2.md")
        )

        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        let selected = try await service.selectLibrary(at: fixture.libraryURL)

        #expect(selected.entries.map(\.name) == ["Guides", "note2.md", "note10.md"])
        #expect(!selected.entries.contains { $0.name == ".hidden.md" })
        #expect(!selected.entries.contains { $0.name == "linked.md" })

        _ = try await service.openDocument(relativePath: "note2.md")
        _ = try await service.openDocument(relativePath: "note10.md")

        let restoredService = NotesService(repository: repository)
        let restored = try await restoredService.restore()
        #expect(restored.documents.map(\.relativePath) == ["note2.md", "note10.md"])
        #expect(
            restored.documents.first(where: { $0.id == restored.selectedDocumentID })?
                .relativePath == "note10.md"
        )
    }

    @Test("deleting a dirty note discards memory and undo restores the disk version")
    func deleteDirtyNoteAndUndo() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("draft.md")
        try Data("saved".utf8).write(to: noteURL)
        let trash = TestNoteTrash(rootURL: fixture.rootURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository, trash: trash)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        let opened = try await service.openDocument(relativePath: "draft.md")
        _ = try await service.updateDocument(opened.id, content: "unsaved")

        let deleted = try await service.deleteItems(relativePaths: ["draft.md"])
        #expect(deleted.documents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        #expect(try await trash.lastTrashedContents() == "saved")

        let restored = try await service.undoLastFileOperation()
        #expect(FileManager.default.fileExists(atPath: noteURL.path))
        #expect(String(decoding: try Data(contentsOf: noteURL), as: UTF8.self) == "saved")
        #expect(restored.documents.isEmpty)
    }

    @Test("dirty note recovers after a crash without overwriting its source")
    func recoverDirtyNoteAfterCrash() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("recovery.md")
        try Data("disk version".utf8).write(to: noteURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        let opened = try await service.openDocument(relativePath: "recovery.md")
        _ = try await service.updateDocument(
            opened.id,
            content: "recovered draft"
        )

        #expect(String(decoding: try Data(contentsOf: noteURL), as: UTF8.self)
            == "disk version")

        let relaunched = NotesService(repository: repository)
        let recovered = try await relaunched.restore()
        let recoveredDocument = try #require(recovered.documents.first)
        #expect(recoveredDocument.content == "recovered draft")
        #expect(recoveredDocument.isDirty)

        _ = try await relaunched.saveDocument(recoveredDocument.id)
        let afterSave = try await NotesService(repository: repository).restore()
        #expect(afterSave.documents.first?.content == "recovered draft")
        #expect(afterSave.documents.first?.isDirty == false)
    }

    @Test("external changes reload clean notes and conflict with dirty notes")
    func reconcileExternalChanges() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("shared.md")
        try Data("one".utf8).write(to: noteURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        let opened = try await service.openDocument(relativePath: "shared.md")

        try Data("two".utf8).write(to: noteURL, options: .atomic)
        let cleanReload = try await service.refreshLibrary()
        #expect(cleanReload.documents.first?.content == "two")
        #expect(cleanReload.documents.first?.externalState == .inSync)

        _ = try await service.updateDocument(opened.id, content: "mine")
        try Data("theirs".utf8).write(to: noteURL, options: .atomic)
        let conflicted = try await service.refreshLibrary()
        #expect(conflicted.documents.first?.content == "mine")
        #expect(
            conflicted.documents.first?.externalState
                == .conflict(diskContent: "theirs")
        )

        let reloaded = try await service.resolveExternalConflict(
            opened.id,
            resolution: .reloadDisk
        )
        #expect(reloaded.content == "theirs")
        #expect(!reloaded.isDirty)
        #expect(reloaded.externalState == .inSync)
    }

    @Test("renaming a note atomically rewrites relative links with a minimal diff")
    func renameNoteAndRewriteLinks() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let targetURL = fixture.libraryURL.appendingPathComponent("target.md")
        let referenceURL = fixture.libraryURL.appendingPathComponent("reference.md")
        try Data("# Target\r\n".utf8).write(to: targetURL)
        let originalReference =
            "# Reference\r\n\r\nSee [Target](target.md).\r\n\r\nUntouched  \r\n"
        try Data(originalReference.utf8).write(to: referenceURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        _ = try await service.openDocument(relativePath: "target.md")
        _ = try await service.openDocument(relativePath: "reference.md")

        let preview = try await service.previewMove(
            relativePath: "target.md",
            destinationRelativePath: "renamed.md"
        )
        #expect(preview.affectedDocumentCount == 1)
        #expect(preview.affectedLinkCount == 1)

        let moved = try await service.moveItem(
            relativePath: "target.md",
            destinationRelativePath: "renamed.md"
        )
        #expect(!FileManager.default.fileExists(atPath: targetURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.libraryURL
                    .appendingPathComponent("renamed.md").path
            )
        )
        #expect(
            String(decoding: try Data(contentsOf: referenceURL), as: UTF8.self)
                == originalReference.replacingOccurrences(
                    of: "(target.md)",
                    with: "(renamed.md)"
                )
        )
        #expect(
            moved.documents.first(where: {
                $0.relativePath == "reference.md"
            })?.isDirty == false
        )
        #expect(
            moved.documents.contains(where: {
                $0.relativePath == "renamed.md"
            })
        )
    }

    @Test("move rewrites titled and angle-wrapped CommonMark links")
    func moveRewritesCommonMarkLinkForms() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        try Data("# Target\n".utf8).write(
            to: fixture.libraryURL.appendingPathComponent(
                "target with space.md"
            )
        )
        let referenceURL = fixture.libraryURL.appendingPathComponent(
            "reference.md"
        )
        let original = """
        [Titled](<target with space.md> "A title")
        [Reference]: <target with space.md>
        """
        try Data(original.utf8).write(to: referenceURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)

        let preview = try await service.previewMove(
            relativePath: "target with space.md",
            destinationRelativePath: "renamed note.md"
        )
        #expect(preview.affectedLinkCount == 2)
        _ = try await service.moveItem(
            relativePath: "target with space.md",
            destinationRelativePath: "renamed note.md"
        )

        let updated = String(
            decoding: try Data(contentsOf: referenceURL),
            as: UTF8.self
        )
        #expect(
            updated == original.replacingOccurrences(
                of: "<target with space.md>",
                with: "<renamed%20note.md>"
            )
        )
    }

    @Test("a folder cannot be moved into its own descendant")
    func rejectsMoveIntoDescendantWithoutSideEffects() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let folder = fixture.libraryURL.appendingPathComponent(
            "folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        try Data("# Note".utf8).write(
            to: folder.appendingPathComponent("note.md")
        )
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)

        await #expect(
            throws: NotesError.destinationInsideSource(
                "folder/subfolder/folder"
            )
        ) {
            try await service.moveItem(
                relativePath: "folder",
                destinationRelativePath: "folder/subfolder/folder"
            )
        }
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("subfolder").path
            )
        )
    }

    @Test("a failed library index leaves the current library untouched")
    func failedLibrarySelectionIsAtomic() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let otherLibrary = fixture.rootURL.appendingPathComponent(
            "other",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: otherLibrary,
            withIntermediateDirectories: true
        )
        try Data("# Old".utf8).write(
            to: fixture.libraryURL.appendingPathComponent("old.md")
        )
        try Data("# New".utf8).write(
            to: otherLibrary.appendingPathComponent("new.md")
        )
        let repository = ControllableNotesRepository()
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        let opened = try await service.openDocument(relativePath: "old.md")
        await repository.failNextIndexReplacement()

        await #expect(throws: TestNotesRepositoryError.self) {
            try await service.selectLibrary(
                at: otherLibrary,
                discardUnsavedChanges: true
            )
        }
        let snapshot = await service.snapshot()
        #expect(snapshot.library?.rootPath == fixture.libraryURL.path)
        #expect(snapshot.documents.map(\.id) == [opened.id])
        #expect(snapshot.entries.contains { $0.relativePath == "old.md" })
    }

    @Test("an index failure does not turn a committed save into failure")
    func indexFailureDoesNotFailSave() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("note.md")
        try Data("old".utf8).write(to: noteURL)
        let repository = ControllableNotesRepository()
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        let opened = try await service.openDocument(relativePath: "note.md")
        _ = try await service.updateDocument(opened.id, content: "new")
        await repository.failNextIndexReplacement()

        let saved = try await service.saveDocument(opened.id)
        #expect(!saved.isDirty)
        #expect(
            String(decoding: try Data(contentsOf: noteURL), as: UTF8.self)
                == "new"
        )
        #expect(!(await service.snapshot().documents[0].isDirty))
    }

    @Test("new notes use collision-safe names and become selected tabs")
    func createCollisionSafeNotes() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)

        let first = try await service.createMarkdownDocument()
        let second = try await service.createMarkdownDocument()

        #expect(first.relativePath == "未命名.md")
        #expect(second.relativePath == "未命名 2.md")
        #expect(
            await service.snapshot().documents.map(\.relativePath)
                == ["未命名.md", "未命名 2.md"]
        )
        #expect(
            await service.snapshot().selectedDocumentID == second.id
        )
    }

    @Test("library search returns paths snippets and line numbers from rebuildable index")
    func searchLibrary() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        try Data(
            """
            ---
            tags: [swift, macos]
            ---

            First line.
            Searchable phrase lives here.
            """.utf8
        ).write(
            to: fixture.libraryURL.appendingPathComponent("indexed.md")
        )
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)

        let results = try await service.searchLibrary(for: "Searchable phrase")
        let result = try #require(results.first)
        #expect(result.relativePath == "indexed.md")
        #expect(result.line == 6)
        #expect(result.snippet.contains("Searchable phrase"))

        let frontMatterResults = try await service.searchLibrary(for: "swift")
        #expect(frontMatterResults.map(\.relativePath) == ["indexed.md"])
    }

    @Test("notes preferences survive restart and keep light and dark themes separate")
    func persistNotesPreferences() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)

        let preferences = NotesPreferences(
            sidebarWidth: 312,
            lightTheme: .newsprint,
            darkTheme: .night,
            showsCodeLineNumbers: true,
            spellCheckEnabled: false,
            agentDrawerWidth: 560
        )
        let updated = try await service.updatePreferences(preferences)
        #expect(updated.preferences == preferences)

        let restored = try await NotesService(repository: repository).restore()
        #expect(restored.preferences == preferences)
        #expect(NoteMarkdownTheme.lightThemes.contains(.newsprint))
        #expect(NoteMarkdownTheme.darkThemes == [.night])
    }

    @Test("undo reverses newly created notes and folders")
    func undoCreation() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(
            repository: repository,
            trash: TestNoteTrash(rootURL: fixture.rootURL)
        )
        _ = try await service.selectLibrary(at: fixture.libraryURL)

        let note = try await service.createMarkdownDocument()
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.libraryURL
                    .appendingPathComponent(note.relativePath).path
            )
        )
        _ = try await service.undoLastFileOperation()
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.libraryURL
                    .appendingPathComponent(note.relativePath).path
            )
        )
        #expect(await service.snapshot().documents.isEmpty)

        _ = try await service.createFolder()
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.libraryURL
                    .appendingPathComponent("未命名文件夹").path
            )
        )
        _ = try await service.undoLastFileOperation()
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.libraryURL
                    .appendingPathComponent("未命名文件夹").path
            )
        )
    }

    @Test("missing tabs restore as unavailable and keep recovery content")
    func restoreMissingTab() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("missing.md")
        try Data("saved".utf8).write(to: noteURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        let opened = try await service.openDocument(relativePath: "missing.md")
        _ = try await service.updateDocument(opened.id, content: "recovered")
        try FileManager.default.removeItem(at: noteURL)

        let restored = try await NotesService(repository: repository).restore()
        let document = try #require(restored.documents.first)
        #expect(document.relativePath == "missing.md")
        #expect(document.content == "recovered")
        #expect(document.externalState == .missing)
        #expect(document.isDirty)
    }

    @Test("attachments are copied into the library with collision-safe names")
    func importAttachment() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)

        let first = try await service.importAttachment(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            suggestedFilename: "diagram.png"
        )
        let second = try await service.importAttachment(
            data: Data([0x01]),
            suggestedFilename: "diagram.png"
        )

        #expect(first == "_attachments/diagram.png")
        #expect(second == "_attachments/diagram 2.png")
        #expect(
            try Data(contentsOf: fixture.libraryURL.appendingPathComponent(first))
                == Data([0x89, 0x50, 0x4E, 0x47])
        )
    }

    @Test("large document policy accounts for structure as well as byte size")
    func largeDocumentPolicy() {
        let ordinary = NoteDocumentComplexity.analyze(
            "# Title\n\nA small document.\n"
        )
        #expect(ordinary.recommendedMode == .wysiwyg)

        let tableHeavy = NoteDocumentComplexity.analyze(
            Array(repeating: "| a | b | c |\n", count: 4_100).joined()
        )
        #expect(tableHeavy.tableRowCount == 4_100)
        #expect(tableHeavy.recommendedMode == .source)

        let diagramHeavy = NoteDocumentComplexity.analyze(
            Array(
                repeating: "```mermaid\ngraph TD\nA-->B\n```\n",
                count: 260
            ).joined()
        )
        #expect(diagramHeavy.mermaidBlockCount == 260)
        #expect(diagramHeavy.recommendedMode == .source)
    }

    @Test("Finder imports copy files and folders without moving their sources")
    func importFinderItems() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let sourceDirectory = fixture.rootURL.appendingPathComponent(
            "source",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let source = sourceDirectory.appendingPathComponent("guide.md")
        try Data("# Imported".utf8).write(to: source)
        try Data("# Existing".utf8).write(
            to: fixture.libraryURL.appendingPathComponent("guide.md")
        )
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(
            repository: repository,
            trash: TestNoteTrash(rootURL: fixture.rootURL)
        )
        _ = try await service.selectLibrary(at: fixture.libraryURL)

        let imported = try await service.importItems(
            [source],
            conflictResolution: .keepBoth
        )
        #expect(imported.map(\.relativePath) == ["guide 2.md"])
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(
            String(
                decoding: try Data(
                    contentsOf: fixture.libraryURL
                        .appendingPathComponent("guide 2.md")
                ),
                as: UTF8.self
            ) == "# Imported"
        )

        _ = try await service.undoLastFileOperation()
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.libraryURL
                    .appendingPathComponent("guide 2.md").path
            )
        )
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("note agent persistence stores only agent identity and official session id")
    func persistNoteAgentBinding() async throws {
        let fixture = try NotesFixture()
        defer { fixture.remove() }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let service = NotesService(repository: repository)
        _ = try await service.selectLibrary(at: fixture.libraryURL)
        let binding = NoteAgentRecoveryBinding(
            agent: .codex,
            sessionID: "official-session-123"
        )

        _ = try await service.updateNoteAgentPersistence(
            lastSelectedAgent: .codex,
            recoveryBinding: binding
        )

        let restored = try await NotesService(repository: repository).restore()
        #expect(restored.lastSelectedAgent == .codex)
        #expect(restored.noteAgentRecoveryBinding == binding)
        let rawDatabase = String(
            decoding: try Data(contentsOf: fixture.databaseURL),
            as: UTF8.self
        )
        #expect(!rawDatabase.contains("prompt"))
        #expect(!rawDatabase.contains("terminal scrollback"))
    }
}

private struct NotesFixture {
    let rootURL: URL
    let libraryURL: URL
    let databaseURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-notes-\(UUID().uuidString)",
            isDirectory: true
        )
        libraryURL = rootURL.appendingPathComponent("library", isDirectory: true)
        databaseURL = rootURL.appendingPathComponent("breath.sqlite")
        try FileManager.default.createDirectory(
            at: libraryURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor TestNoteTrash: NoteFileTrashing {
    private let rootURL: URL
    private var lastURL: URL?

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func trashItem(at url: URL) async throws -> URL? {
        let trashDirectory = rootURL.appendingPathComponent(
            "trash",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: trashDirectory,
            withIntermediateDirectories: true
        )
        let destination = trashDirectory.appendingPathComponent(
            "\(UUID().uuidString)-\(url.lastPathComponent)"
        )
        try FileManager.default.moveItem(at: url, to: destination)
        lastURL = destination
        return destination
    }

    func lastTrashedContents() throws -> String? {
        guard let lastURL else { return nil }
        return String(
            decoding: try Data(contentsOf: lastURL),
            as: UTF8.self
        )
    }
}

private struct TestNotesRepositoryError: Error {}

private actor ControllableNotesRepository: NotesRepository {
    private var state = NotesPersistedState.empty
    private var shouldFailNextIndexReplacement = false
    private var indexedDocuments: [NoteSearchDocument] = []

    func failNextIndexReplacement() {
        shouldFailNextIndexReplacement = true
    }

    func loadNotesState() async throws -> NotesPersistedState {
        state
    }

    func saveNotesState(_ state: NotesPersistedState) async throws {
        self.state = state
    }

    func replaceNoteSearchIndex(
        libraryID: NoteLibraryID,
        documents: [NoteSearchDocument]
    ) async throws {
        if shouldFailNextIndexReplacement {
            shouldFailNextIndexReplacement = false
            throw TestNotesRepositoryError()
        }
        indexedDocuments = documents
    }

    func searchNotes(
        libraryID: NoteLibraryID,
        query: String,
        limit: Int
    ) async throws -> [NoteSearchResult] {
        indexedDocuments.compactMap { document in
            guard document.content.localizedCaseInsensitiveContains(query)
            else {
                return nil
            }
            return NoteSearchResult(
                relativePath: document.relativePath,
                snippet: document.content,
                line: 1
            )
        }
    }
}
