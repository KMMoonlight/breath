import BreathNotes
import Foundation
import Testing

@Suite("Note resource resolver")
struct NoteResourceResolverTests {
    @Test("relative resources stay inside the note library")
    func resolvesRelativeResource() throws {
        let root = URL(fileURLWithPath: "/tmp/library", isDirectory: true)
        let resolved = try NoteResourceResolver.resolveLocalResource(
            "../images/diagram.png",
            relativeTo: "guides/setup.md",
            libraryRoot: root
        )
        #expect(resolved.path == "/tmp/library/images/diagram.png")
    }

    @Test("absolute and escaping resources are rejected")
    func rejectsEscapingResource() {
        let root = URL(fileURLWithPath: "/tmp/library", isDirectory: true)
        #expect(throws: NotesError.pathOutsideLibrary("/etc/passwd")) {
            try NoteResourceResolver.resolveLocalResource(
                "/etc/passwd",
                relativeTo: "guide.md",
                libraryRoot: root
            )
        }
        #expect(throws: NotesError.pathOutsideLibrary("../../secret.png")) {
            try NoteResourceResolver.resolveLocalResource(
                "../../secret.png",
                relativeTo: "guide.md",
                libraryRoot: root
            )
        }
    }

    @Test("a library symlink cannot expose an outside resource")
    func rejectsSymlinkEscape() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-note-resource-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = temporary.appendingPathComponent(
            "library",
            isDirectory: true
        )
        let outside = temporary.appendingPathComponent(
            "outside",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        try Data("outside".utf8).write(
            to: outside.appendingPathComponent("image.png")
        )
        try FileManager.default.createSymbolicLink(
            at: library.appendingPathComponent("linked"),
            withDestinationURL: outside
        )

        #expect(throws: NotesError.self) {
            try NoteResourceResolver.resolveExistingLocalResource(
                "linked/image.png",
                relativeTo: "note.md",
                libraryRoot: library
            )
        }
    }
}
