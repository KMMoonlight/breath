import Testing
@testable import BreathApp

@Suite("Git conflict document")
struct GitConflictDocumentTests {
    @Test("conflict blocks can accept either side, both sides, or neither")
    func resolvesIndividualBlocks() throws {
        let contents = """
        before
        <<<<<<< HEAD
        ours
        =======
        theirs
        >>>>>>> feature
        after
        """
        let document = GitConflictDocument(contents: contents)
        let block = try #require(document.blocks.first)

        #expect(document.resolving(block, with: .ours) == "before\nours\nafter")
        #expect(document.resolving(block, with: .theirs) == "before\ntheirs\nafter")
        #expect(
            document.resolving(block, with: .both)
                == "before\nours\ntheirs\nafter"
        )
        #expect(document.resolving(block, with: .ignore) == "before\nafter")
    }

    @Test("multiple conflict blocks keep stable identities and untouched content")
    func resolvesOneBlockAtATime() throws {
        let contents = """
        <<<<<<< HEAD
        first ours
        =======
        first theirs
        >>>>>>> feature
        middle
        <<<<<<< HEAD
        second ours
        =======
        second theirs
        >>>>>>> feature
        """
        let first = GitConflictDocument(contents: contents)
        let second = GitConflictDocument(contents: contents)

        #expect(first.blocks.map(\.id) == second.blocks.map(\.id))
        let resolved = first.resolving(
            try #require(first.blocks.first),
            with: .ours
        )
        #expect(resolved.contains("first ours"))
        #expect(resolved.contains("<<<<<<< HEAD"))
        #expect(resolved.contains("second theirs"))
    }
}
