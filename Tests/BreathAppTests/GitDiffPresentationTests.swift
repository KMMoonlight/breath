import Testing
@testable import BreathApp

@Suite("Git diff presentation")
struct GitDiffPresentationTests {
    @Test("changed files form a GitHub-style directory tree")
    func changedFileTree() throws {
        let files = [
            GitChangedFile(path: ".github/workflows/pr_lint.yml", kind: .modified),
            GitChangedFile(path: "README.md", kind: .modified),
            GitChangedFile(path: "test/check.py", kind: .deleted),
            GitChangedFile(path: "test/new.py", kind: .added),
            GitChangedFile(path: "ubuntu_2204/configv2/nginx.conf", kind: .modified),
            GitChangedFile(path: "ubuntu_2204/migrate.py", kind: .untracked),
        ]

        let roots = GitChangedFileTreeBuilder().build(files)

        #expect(roots.map(\.name) == [
            ".github/workflows",
            "test",
            "ubuntu_2204",
            "README.md",
        ])
        #expect(roots[0].children.map(\.name) == ["pr_lint.yml"])
        #expect(roots[1].children.map(\.name) == ["check.py", "new.py"])
        #expect(roots[1].children[0].file?.kind == .deleted)
        #expect(roots[2].children.map(\.name) == ["configv2", "migrate.py"])
        #expect(roots[2].children[0].children.map(\.name) == ["nginx.conf"])
        #expect(roots[2].children[1].file?.kind == .untracked)
    }

    @Test("unified diff lines carry semantic highlighting and line numbers")
    func unifiedDiffLines() {
        let diff = [
            "diff --git a/example.py b/example.py",
            "index 1111111..2222222 100644",
            "--- a/example.py",
            "+++ b/example.py",
            "@@ -10,2 +10,3 @@ def run():",
            " same()",
            "-old_value = 1",
            "+new_value = 2",
            "+return new_value",
            "\\ No newline at end of file",
        ].joined(separator: "\n")

        let lines = GitUnifiedDiffParser().parse(diff)

        #expect(lines.map(\.kind) == [
            .metadata, .metadata, .metadata, .metadata, .hunk,
            .context, .deletion, .addition, .addition, .marker,
        ])
        #expect(lines[5].content == "same()")
        #expect(lines[5].oldLineNumber == 10)
        #expect(lines[5].newLineNumber == 10)
        #expect(lines[6].oldLineNumber == 11)
        #expect(lines[6].newLineNumber == nil)
        #expect(lines[7].oldLineNumber == nil)
        #expect(lines[7].newLineNumber == 11)
        #expect(lines[8].newLineNumber == 12)
    }

    @Test("code tokens are highlighted for the selected file language")
    func codeSyntaxTokens() {
        let code = #"let title: String = "Diff"; let count = 42 // changed"#

        let tokens = GitCodeSyntaxHighlighter().tokens(
            in: code,
            filePath: "Sources/Example.swift"
        )

        #expect(tokens.contains(GitCodeToken(text: "let", kind: .keyword)))
        #expect(tokens.contains(GitCodeToken(text: "String", kind: .type)))
        #expect(tokens.contains(GitCodeToken(text: "\"Diff\"", kind: .string)))
        #expect(tokens.contains(GitCodeToken(text: "42", kind: .number)))
        #expect(tokens.contains(GitCodeToken(text: "// changed", kind: .comment)))
    }

    @Test("deleted code resembling a file header remains a deletion")
    func deletedCodeResemblingFileHeader() {
        let diff = [
            "--- a/query.sql",
            "+++ b/query.sql",
            "@@ -1 +1 @@",
            "--- removed SQL comment",
        ].joined(separator: "\n")

        let lines = GitUnifiedDiffParser().parse(diff)

        #expect(lines.last?.kind == .deletion)
        #expect(lines.last?.content == "-- removed SQL comment")
    }
}
