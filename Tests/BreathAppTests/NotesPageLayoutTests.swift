import Foundation
import Testing

@Suite("Notes page layout")
struct NotesPageLayoutTests {
    @Test("the Notes toolbar stays clear of the macOS window controls")
    func toolbarReservesWindowControlSpace() throws {
        let notesSource = try compactSource("NotesView.swift")
        let usesWindowAwareLeadingPadding = notesSource.contains(
            ".pageToolbarLeadingPadding()"
        )

        #expect(usesWindowAwareLeadingPadding)
    }

    @Test("an unconfigured Note Library leaves the content canvas blank")
    func unconfiguredLibraryDoesNotShowAnEmptyStateMessage() throws {
        let notesSource = try compactSource("NotesView.swift")
        let rendersBlankCanvas = notesSource.contains(
            "ifmodel.snapshot.library==nil{Color.clear}"
        )
        let declaresLargeEmptyState = notesSource.contains(
            "privatevarlibraryEmptyState"
        )
        let showsLibraryExplanation = notesSource.contains(
            "选择或创建一个本地目录"
        )

        #expect(rendersBlankCanvas)
        #expect(!declaresLargeEmptyState)
        #expect(!showsLibraryExplanation)
    }

    private func compactSource(_ name: String) throws -> String {
        try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/BreathApp")
                .appendingPathComponent(name),
            encoding: .utf8
        )
        .filter { !$0.isWhitespace }
    }

    private var packageRoot: URL {
        URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    }
}
