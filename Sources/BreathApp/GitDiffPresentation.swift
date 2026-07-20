import Foundation

struct GitChangedFileTreeNode: Identifiable, Equatable, Sendable {
    let name: String
    let path: String
    let file: GitChangedFile?
    let children: [GitChangedFileTreeNode]

    var id: String {
        file == nil ? "directory:\(path)" : "file:\(path)"
    }

    var isDirectory: Bool { file == nil }
}

struct GitChangedFileTreeBuilder: Sendable {
    func build(_ files: [GitChangedFile]) -> [GitChangedFileTreeNode] {
        let root = GitChangedFileTreeDirectory(name: "", path: "")
        for file in files {
            insert(file, into: root)
        }
        return children(of: root)
    }

    private func insert(
        _ file: GitChangedFile,
        into root: GitChangedFileTreeDirectory
    ) {
        let components = file.path.split(separator: "/").map(String.init)
        guard let fileName = components.last else { return }

        var directory = root
        for component in components.dropLast() {
            if let existing = directory.directories[component] {
                directory = existing
            } else {
                let path = directory.path.isEmpty
                    ? component
                    : "\(directory.path)/\(component)"
                let next = GitChangedFileTreeDirectory(
                    name: component,
                    path: path
                )
                directory.directories[component] = next
                directory = next
            }
        }
        directory.files[fileName] = file
    }

    private func children(
        of directory: GitChangedFileTreeDirectory
    ) -> [GitChangedFileTreeNode] {
        let directories = directory.directories.values
            .sorted { orderedBefore($0.name, $1.name) }
            .map(makeDirectoryNode)
        let files = directory.files
            .sorted { orderedBefore($0.key, $1.key) }
            .map { name, file in
                GitChangedFileTreeNode(
                    name: name,
                    path: file.path,
                    file: file,
                    children: []
                )
            }
        return directories + files
    }

    private func makeDirectoryNode(
        _ directory: GitChangedFileTreeDirectory
    ) -> GitChangedFileTreeNode {
        var current = directory
        var name = directory.name
        while current.files.isEmpty,
              current.directories.count == 1,
              let next = current.directories.values.first
        {
            current = next
            name += "/\(next.name)"
        }
        return GitChangedFileTreeNode(
            name: name,
            path: current.path,
            file: nil,
            children: children(of: current)
        )
    }

    private func orderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}

private final class GitChangedFileTreeDirectory {
    let name: String
    let path: String
    var directories: [String: GitChangedFileTreeDirectory] = [:]
    var files: [String: GitChangedFile] = [:]

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

enum GitDiffLineKind: Equatable, Sendable {
    case metadata
    case hunk
    case context
    case addition
    case deletion
    case marker
}

struct GitDiffLine: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: GitDiffLineKind
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

struct GitUnifiedDiffParser: Sendable {
    func parse(_ diff: String) -> [GitDiffLine] {
        var rawLines = diff
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if diff.hasSuffix("\n"), rawLines.last == "" {
            rawLines.removeLast()
        }

        var oldLineNumber: Int?
        var newLineNumber: Int?
        var isInsideHunk = false
        return rawLines.enumerated().map { index, rawLine in
            if let starts = hunkStarts(in: rawLine) {
                oldLineNumber = starts.old
                newLineNumber = starts.new
                isInsideHunk = true
                return line(index, .hunk, rawLine)
            }
            if rawLine.hasPrefix("diff --git ") {
                isInsideHunk = false
                oldLineNumber = nil
                newLineNumber = nil
                return line(index, .metadata, rawLine)
            }
            if !isInsideHunk {
                return line(index, .metadata, rawLine)
            }
            if rawLine.hasPrefix("\\") {
                return line(index, .marker, rawLine)
            }
            if rawLine.hasPrefix("+") {
                let currentNewLineNumber = newLineNumber
                newLineNumber = newLineNumber.map { $0 + 1 }
                return line(
                    index,
                    .addition,
                    String(rawLine.dropFirst()),
                    new: currentNewLineNumber
                )
            }
            if rawLine.hasPrefix("-") {
                let currentOldLineNumber = oldLineNumber
                oldLineNumber = oldLineNumber.map { $0 + 1 }
                return line(
                    index,
                    .deletion,
                    String(rawLine.dropFirst()),
                    old: currentOldLineNumber
                )
            }

            let currentOldLineNumber = oldLineNumber
            let currentNewLineNumber = newLineNumber
            oldLineNumber = oldLineNumber.map { $0 + 1 }
            newLineNumber = newLineNumber.map { $0 + 1 }
            let content = rawLine.hasPrefix(" ")
                ? String(rawLine.dropFirst())
                : rawLine
            return line(
                index,
                .context,
                content,
                old: currentOldLineNumber,
                new: currentNewLineNumber
            )
        }
    }

    private func hunkStarts(in line: String) -> (old: Int, new: Int)? {
        let fields = line.split(separator: " ")
        guard fields.count >= 3,
              fields[0] == "@@",
              let old = lineNumber(in: fields[1], prefix: "-"),
              let new = lineNumber(in: fields[2], prefix: "+")
        else {
            return nil
        }
        return (old, new)
    }

    private func lineNumber(
        in field: Substring,
        prefix: Character
    ) -> Int? {
        guard field.first == prefix else { return nil }
        return Int(field.dropFirst().split(separator: ",").first ?? "")
    }

    private func line(
        _ id: Int,
        _ kind: GitDiffLineKind,
        _ content: String,
        old: Int? = nil,
        new: Int? = nil
    ) -> GitDiffLine {
        GitDiffLine(
            id: id,
            kind: kind,
            content: content,
            oldLineNumber: old,
            newLineNumber: new
        )
    }
}

enum GitCodeTokenKind: Equatable, Sendable {
    case plain
    case keyword
    case type
    case string
    case number
    case comment
}

struct GitCodeToken: Equatable, Sendable {
    let text: String
    let kind: GitCodeTokenKind
}

struct GitCodeSyntaxHighlighter: Sendable {
    func tokens(in code: String, filePath: String) -> [GitCodeToken] {
        let rules = GitCodeLanguageRules(filePath: filePath)
        let characters = Array(code)
        var tokens: [GitCodeToken] = []
        var index = 0

        while index < characters.count {
            if let commentPrefix = rules.commentPrefixes.first(where: {
                matches($0, in: characters, at: index)
            }) {
                let comment = String(characters[index...])
                append(comment, kind: .comment, to: &tokens)
                index += max(commentPrefix.count, comment.count)
                continue
            }

            let character = characters[index]
            if rules.stringDelimiters.contains(character) {
                let endIndex = stringEnd(
                    in: characters,
                    from: index,
                    delimiter: character
                )
                append(
                    String(characters[index..<endIndex]),
                    kind: .string,
                    to: &tokens
                )
                index = endIndex
                continue
            }

            if character.isNumber {
                let endIndex = numberEnd(in: characters, from: index)
                append(
                    String(characters[index..<endIndex]),
                    kind: .number,
                    to: &tokens
                )
                index = endIndex
                continue
            }

            if isIdentifierStart(character) {
                let endIndex = identifierEnd(in: characters, from: index)
                let identifier = String(characters[index..<endIndex])
                let kind: GitCodeTokenKind
                if rules.keywords.contains(identifier) {
                    kind = .keyword
                } else if rules.types.contains(identifier)
                            || identifier.first?.isUppercase == true
                {
                    kind = .type
                } else {
                    kind = .plain
                }
                append(identifier, kind: kind, to: &tokens)
                index = endIndex
                continue
            }

            append(String(character), kind: .plain, to: &tokens)
            index += 1
        }
        return tokens
    }

    private func matches(
        _ value: String,
        in characters: [Character],
        at index: Int
    ) -> Bool {
        let candidate = Array(value)
        guard index + candidate.count <= characters.count else { return false }
        return Array(characters[index..<(index + candidate.count)]) == candidate
    }

    private func stringEnd(
        in characters: [Character],
        from startIndex: Int,
        delimiter: Character
    ) -> Int {
        var index = startIndex + 1
        while index < characters.count {
            if characters[index] == "\\" {
                index = min(index + 2, characters.count)
            } else if characters[index] == delimiter {
                return index + 1
            } else {
                index += 1
            }
        }
        return characters.count
    }

    private func numberEnd(
        in characters: [Character],
        from startIndex: Int
    ) -> Int {
        var index = startIndex + 1
        while index < characters.count {
            let character = characters[index]
            guard character.isNumber
                    || character.isLetter
                    || character == "."
                    || character == "_"
            else {
                break
            }
            index += 1
        }
        return index
    }

    private func identifierEnd(
        in characters: [Character],
        from startIndex: Int
    ) -> Int {
        var index = startIndex + 1
        while index < characters.count,
              isIdentifierContinuation(characters[index])
        {
            index += 1
        }
        return index
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$"
    }

    private func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    private func append(
        _ text: String,
        kind: GitCodeTokenKind,
        to tokens: inout [GitCodeToken]
    ) {
        guard !text.isEmpty else { return }
        if let last = tokens.last, last.kind == kind {
            tokens[tokens.count - 1] = GitCodeToken(
                text: last.text + text,
                kind: kind
            )
        } else {
            tokens.append(GitCodeToken(text: text, kind: kind))
        }
    }
}

private struct GitCodeLanguageRules {
    let keywords: Set<String>
    let types: Set<String>
    let commentPrefixes: [String]
    let stringDelimiters: Set<Character>

    init(filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        let fileName = url.lastPathComponent.lowercased()
        let extensionName = url.pathExtension.lowercased()
        stringDelimiters = ["\"", "'"]

        switch extensionName {
        case "swift":
            keywords = [
                "actor", "any", "as", "async", "await", "case", "catch",
                "class", "continue", "default", "defer", "do", "else",
                "enum", "extension", "false", "fileprivate", "for", "func",
                "guard", "if", "import", "in", "init", "internal", "is",
                "let", "nil", "open", "private", "protocol", "public",
                "repeat", "return", "self", "some", "static", "struct",
                "subscript", "switch", "throw", "throws", "true", "try",
                "typealias", "var", "where", "while",
            ]
            types = [
                "Array", "Bool", "Character", "Data", "Date", "Dictionary",
                "Double", "Error", "Float", "Int", "Optional", "Result",
                "Set", "String", "URL", "UUID", "Void",
            ]
            commentPrefixes = ["//"]
        case "py":
            keywords = [
                "and", "as", "assert", "async", "await", "break", "case",
                "class", "continue", "def", "del", "elif", "else", "except",
                "False", "finally", "for", "from", "global", "if", "import",
                "in", "is", "lambda", "match", "None", "nonlocal", "not",
                "or", "pass", "raise", "return", "True", "try", "while",
                "with", "yield",
            ]
            types = ["bool", "bytes", "dict", "float", "int", "list", "set", "str", "tuple"]
            commentPrefixes = ["#"]
        case "js", "jsx", "mjs", "cjs", "ts", "tsx":
            keywords = [
                "async", "await", "break", "case", "catch", "class", "const",
                "continue", "debugger", "default", "delete", "do", "else",
                "export", "extends", "false", "finally", "for", "from",
                "function", "if", "import", "in", "instanceof", "interface",
                "let", "new", "null", "of", "return", "static", "super",
                "switch", "throw", "true", "try", "type", "typeof", "undefined",
                "var", "void", "while", "with", "yield",
            ]
            types = ["any", "boolean", "never", "number", "object", "string", "unknown"]
            commentPrefixes = ["//"]
        case "c", "cc", "cpp", "cxx", "h", "hpp", "go", "java", "kt", "kts", "rs":
            keywords = [
                "break", "case", "class", "const", "continue", "default",
                "else", "enum", "false", "for", "func", "if", "import",
                "interface", "let", "new", "nil", "null", "package", "private",
                "protected", "public", "return", "static", "struct", "switch",
                "throw", "true", "try", "var", "while",
            ]
            types = ["bool", "byte", "char", "double", "float", "int", "long", "short", "string", "void"]
            commentPrefixes = ["//"]
        case "rb", "sh", "bash", "zsh", "fish", "yml", "yaml", "toml":
            keywords = [
                "case", "do", "done", "elif", "else", "end", "esac", "false",
                "fi", "for", "function", "if", "in", "nil", "null", "then",
                "true", "unless", "until", "when", "while",
            ]
            types = []
            commentPrefixes = ["#"]
        case "sql":
            keywords = [
                "ALTER", "AND", "AS", "ASC", "BY", "CREATE", "DELETE", "DESC",
                "DISTINCT", "DROP", "FROM", "GROUP", "HAVING", "INSERT", "INTO",
                "JOIN", "LIMIT", "NOT", "NULL", "ON", "OR", "ORDER", "SELECT",
                "SET", "TABLE", "UPDATE", "VALUES", "WHERE",
            ]
            types = ["BIGINT", "BOOLEAN", "DATE", "INTEGER", "JSON", "TEXT", "TIMESTAMP", "VARCHAR"]
            commentPrefixes = ["--"]
        case "json":
            keywords = ["false", "null", "true"]
            types = []
            commentPrefixes = []
        default:
            keywords = []
            types = []
            commentPrefixes = fileName == "makefile" ? ["#"] : []
        }
    }
}
