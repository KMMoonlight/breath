@testable import BreathApp
import BreathNotes
import BreathPersistence
import Foundation
import Testing

@MainActor
@Suite("Notes application model")
struct NotesApplicationModelTests {
    @Test("an immediate save flushes the latest debounced editor change")
    func saveFlushesLatestEditorChange() async throws {
        let fixture = try NotesApplicationFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("latest.md")
        try Data("saved".utf8).write(to: noteURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let model = NotesApplicationModel(
            service: NotesService(repository: repository)
        )

        model.selectLibrary(fixture.libraryURL)
        await waitUntil { model.snapshot.entries.count == 1 }
        let entry = try #require(model.snapshot.entries.first)
        model.open(entry)
        await waitUntil { model.selectedDocument != nil }
        let document = try #require(model.selectedDocument)

        model.updateDocument(document.id, content: "first")
        model.updateDocument(document.id, content: "latest")
        #expect(model.selectedDocument?.content == "latest")
        #expect(model.selectedDocument?.isDirty == true)

        #expect(await model.prepareForTermination(decision: .save))
        #expect(
            String(decoding: try Data(contentsOf: noteURL), as: UTF8.self)
                == "latest"
        )
        #expect(model.selectedDocument?.isDirty == false)
    }

    @Test("new notes and folders request immediate inline rename")
    func creationRequestsInlineRename() async throws {
        let fixture = try NotesApplicationFixture()
        defer { fixture.remove() }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let model = NotesApplicationModel(
            service: NotesService(repository: repository)
        )
        model.selectLibrary(fixture.libraryURL)
        await waitUntil { model.snapshot.library != nil }

        model.createMarkdownDocument()
        await waitUntil { model.inlineRenameRequest != nil }
        #expect(model.inlineRenameRequest == "未命名.md")
        model.consumeInlineRenameRequest()

        model.createFolder()
        await waitUntil { model.inlineRenameRequest != nil }
        #expect(model.inlineRenameRequest == "未命名文件夹")
    }

    @Test("a save snapshot cannot overwrite an edit typed while saving")
    func saveSnapshotOverlaysConcurrentEdit() async throws {
        let fixture = try NotesApplicationFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("race.md")
        try Data("saved".utf8).write(to: noteURL)
        let repository = BlockingNotesIndexRepository()
        let model = NotesApplicationModel(
            service: NotesService(repository: repository)
        )
        model.selectLibrary(fixture.libraryURL)
        await waitUntil { model.snapshot.entries.count == 1 }
        model.open(try #require(model.snapshot.entries.first))
        await waitUntil { model.selectedDocument != nil }
        let id = try #require(model.selectedDocument?.id)
        model.updateDocument(id, content: "first edit")
        try? await Task.sleep(for: .milliseconds(300))
        await repository.blockNextIndexReplacement()

        model.saveSelectedDocument()
        await repository.waitUntilIndexReplacementIsBlocked()
        model.updateDocument(id, content: "latest edit")
        await repository.releaseIndexReplacement()

        await waitUntil {
            model.selectedDocument?.content == "latest edit"
                && model.selectedDocument?.savedContent == "first edit"
        }
        #expect(model.selectedDocument?.isDirty == true)
        #expect(
            String(decoding: try Data(contentsOf: noteURL), as: UTF8.self)
                == "first edit"
        )
    }

    @Test("conflict reload cancels queued recovery instead of reviving it")
    func conflictReloadCancelsQueuedEdit() async throws {
        let fixture = try NotesApplicationFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("conflict.md")
        try Data("saved".utf8).write(to: noteURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let model = NotesApplicationModel(
            service: NotesService(repository: repository)
        )
        model.selectLibrary(fixture.libraryURL)
        await waitUntil { model.snapshot.entries.count == 1 }
        model.open(try #require(model.snapshot.entries.first))
        await waitUntil { model.selectedDocument != nil }
        let id = try #require(model.selectedDocument?.id)
        model.updateDocument(id, content: "first edit")
        try? await Task.sleep(for: .milliseconds(300))
        try Data("disk edit".utf8).write(to: noteURL)
        model.refresh()
        await waitUntil {
            if case .conflict = model.selectedDocument?.externalState {
                return true
            }
            return false
        }

        model.updateDocument(id, content: "queued edit")
        model.resolveConflict(id, resolution: .reloadDisk)
        await waitUntil { model.selectedDocument?.content == "disk edit" }
        try? await Task.sleep(for: .milliseconds(350))

        #expect(model.selectedDocument?.content == "disk edit")
        #expect(model.selectedDocument?.isDirty == false)
    }

    @Test("conflict overwrite flushes the latest queued edit")
    func conflictOverwriteFlushesQueuedEdit() async throws {
        let fixture = try NotesApplicationFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("conflict.md")
        try Data("saved".utf8).write(to: noteURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let model = NotesApplicationModel(
            service: NotesService(repository: repository)
        )
        model.selectLibrary(fixture.libraryURL)
        await waitUntil { model.snapshot.entries.count == 1 }
        model.open(try #require(model.snapshot.entries.first))
        await waitUntil { model.selectedDocument != nil }
        let id = try #require(model.selectedDocument?.id)
        model.updateDocument(id, content: "first edit")
        try? await Task.sleep(for: .milliseconds(300))
        try Data("disk edit".utf8).write(to: noteURL)
        model.refresh()
        await waitUntil {
            if case .conflict = model.selectedDocument?.externalState {
                return true
            }
            return false
        }

        model.updateDocument(id, content: "latest queued edit")
        model.resolveConflict(id, resolution: .overwriteDisk)
        await waitUntil { model.selectedDocument?.isDirty == false }

        #expect(
            String(decoding: try Data(contentsOf: noteURL), as: UTF8.self)
                == "latest queued edit"
        )
    }

    @Test("discard termination validation is non-destructive until commit")
    func discardTerminationUsesTwoPhases() async throws {
        let fixture = try NotesApplicationFixture()
        defer { fixture.remove() }
        let noteURL = fixture.libraryURL.appendingPathComponent("quit.md")
        try Data("saved".utf8).write(to: noteURL)
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: fixture.databaseURL
        )
        let model = NotesApplicationModel(
            service: NotesService(repository: repository)
        )
        model.selectLibrary(fixture.libraryURL)
        await waitUntil { model.snapshot.entries.count == 1 }
        model.open(try #require(model.snapshot.entries.first))
        await waitUntil { model.selectedDocument != nil }
        let id = try #require(model.selectedDocument?.id)
        model.updateDocument(id, content: "latest unsaved edit")

        #expect(await model.validateTermination(decision: .discard))
        #expect(model.selectedDocument?.content == "latest unsaved edit")
        #expect(model.selectedDocument?.isDirty == true)
        #expect(!(await model.prepareForTermination(decision: .cancel)))
        #expect(model.selectedDocument?.content == "latest unsaved edit")

        #expect(await model.prepareForTermination(decision: .discard))
        #expect(model.selectedDocument?.content == "saved")
        #expect(model.selectedDocument?.isDirty == false)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor BlockingNotesIndexRepository: NotesRepository {
    private var state = NotesPersistedState.empty
    private var shouldBlockNextIndex = false
    private var isIndexBlocked = false
    private var indexContinuation: CheckedContinuation<Void, Never>?

    func blockNextIndexReplacement() {
        shouldBlockNextIndex = true
    }

    func waitUntilIndexReplacementIsBlocked() async {
        while !isIndexBlocked {
            await Task.yield()
        }
    }

    func releaseIndexReplacement() {
        indexContinuation?.resume()
        indexContinuation = nil
        isIndexBlocked = false
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
        guard shouldBlockNextIndex else { return }
        shouldBlockNextIndex = false
        isIndexBlocked = true
        await withCheckedContinuation { continuation in
            indexContinuation = continuation
        }
    }

    func searchNotes(
        libraryID: NoteLibraryID,
        query: String,
        limit: Int
    ) async throws -> [NoteSearchResult] {
        []
    }
}

private struct NotesApplicationFixture {
    let rootURL: URL
    let libraryURL: URL
    let databaseURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-notes-application-\(UUID().uuidString)",
            isDirectory: true
        )
        libraryURL = rootURL.appendingPathComponent(
            "library",
            isDirectory: true
        )
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
