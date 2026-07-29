import BreathNotes
import BreathPersistence
import Foundation
import Testing

@Suite("Notes performance gates")
struct NotesPerformanceTests {
    @Test("a representative library stays within reviewed interaction budgets")
    func representativeLibraryBudgets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "breath-notes-performance-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        let body = String(repeating: "Breath searchable line.\n", count: 40)
        for index in 0..<500 {
            try Data("# Note \(index)\n\n\(body)".utf8).write(
                to: library.appendingPathComponent("note-\(index).md")
            )
        }
        let repository = try SQLiteWorkbenchRepository(
            databaseURL: root.appendingPathComponent("breath.sqlite")
        )
        let service = NotesService(repository: repository)
        let clock = ContinuousClock()

        let indexStart = clock.now
        _ = try await service.selectLibrary(at: library)
        let indexDuration = indexStart.duration(to: clock.now)
        #expect(indexDuration < .seconds(5))

        let openStart = clock.now
        let document = try await service.openDocument(
            relativePath: "note-250.md"
        )
        let openDuration = openStart.duration(to: clock.now)
        #expect(openDuration < .milliseconds(500))

        _ = try await service.updateDocument(
            document.id,
            content: document.content + "\nEdited.\n"
        )
        let saveStart = clock.now
        _ = try await service.saveDocument(document.id)
        let saveDuration = saveStart.duration(to: clock.now)
        #expect(saveDuration < .seconds(5))

        let searchStart = clock.now
        let results = try await service.searchLibrary(
            for: "searchable line",
            limit: 100
        )
        let searchDuration = searchStart.duration(to: clock.now)
        #expect(results.count == 100)
        #expect(searchDuration < .seconds(1))

        print(
            """
            NOTES_BENCHMARK \
            index=\(indexDuration) \
            open=\(openDuration) \
            save=\(saveDuration) \
            search=\(searchDuration)
            """
        )
    }
}
