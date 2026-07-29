import Foundation

public enum NoteThemeAppearance: String, Codable, Sendable {
    case light
    case dark
}

public enum NoteMarkdownTheme: String, CaseIterable, Codable, Sendable {
    case github
    case gothic
    case newsprint
    case night
    case pixyll
    case whitey

    public var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gothic: "Gothic"
        case .newsprint: "Newsprint"
        case .night: "Night"
        case .pixyll: "Pixyll"
        case .whitey: "Whitey"
        }
    }

    /// Classification follows the appearance of Typora's bundled themes.
    public var appearance: NoteThemeAppearance {
        self == .night ? .dark : .light
    }

    public static let lightThemes = allCases.filter { $0.appearance == .light }
    public static let darkThemes = allCases.filter { $0.appearance == .dark }
}

public struct NotesPreferences: Equatable, Codable, Sendable {
    public var sidebarWidth: Double
    public var lightTheme: NoteMarkdownTheme
    public var darkTheme: NoteMarkdownTheme
    public var showsCodeLineNumbers: Bool
    public var spellCheckEnabled: Bool
    public var agentDrawerWidth: Double

    public init(
        sidebarWidth: Double = 250,
        lightTheme: NoteMarkdownTheme = .github,
        darkTheme: NoteMarkdownTheme = .night,
        showsCodeLineNumbers: Bool = false,
        spellCheckEnabled: Bool = true,
        agentDrawerWidth: Double = 420
    ) {
        self.sidebarWidth = Self.clampSidebarWidth(sidebarWidth)
        self.lightTheme = lightTheme.appearance == .light ? lightTheme : .github
        self.darkTheme = darkTheme.appearance == .dark ? darkTheme : .night
        self.showsCodeLineNumbers = showsCodeLineNumbers
        self.spellCheckEnabled = spellCheckEnabled
        self.agentDrawerWidth = Self.clampAgentDrawerWidth(agentDrawerWidth)
    }

    public static let `default` = NotesPreferences()

    public static func clampSidebarWidth(_ width: Double) -> Double {
        min(max(width, 180), 420)
    }

    public static func clampAgentDrawerWidth(
        _ width: Double,
        availableWidth: Double = .greatestFiniteMagnitude
    ) -> Double {
        let maximum = min(720, availableWidth * 0.45)
        return min(max(width, 340), max(340, maximum))
    }

    private enum CodingKeys: String, CodingKey {
        case sidebarWidth
        case lightTheme
        case darkTheme
        case showsCodeLineNumbers
        case spellCheckEnabled
        case agentDrawerWidth
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sidebarWidth: try container.decodeIfPresent(
                Double.self,
                forKey: .sidebarWidth
            ) ?? 250,
            lightTheme: try container.decodeIfPresent(
                NoteMarkdownTheme.self,
                forKey: .lightTheme
            ) ?? .github,
            darkTheme: try container.decodeIfPresent(
                NoteMarkdownTheme.self,
                forKey: .darkTheme
            ) ?? .night,
            showsCodeLineNumbers: try container.decodeIfPresent(
                Bool.self,
                forKey: .showsCodeLineNumbers
            ) ?? false,
            spellCheckEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .spellCheckEnabled
            ) ?? true,
            agentDrawerWidth: try container.decodeIfPresent(
                Double.self,
                forKey: .agentDrawerWidth
            ) ?? 420
        )
    }
}

public enum NoteEditorMode: String, Equatable, Sendable {
    case wysiwyg
    case source
}

public struct NoteDocumentComplexity: Equatable, Sendable {
    public let byteCount: Int
    public let lineCount: Int
    public let tableRowCount: Int
    public let mathExpressionCount: Int
    public let mermaidBlockCount: Int
    public let htmlElementCount: Int

    public init(
        byteCount: Int,
        lineCount: Int,
        tableRowCount: Int,
        mathExpressionCount: Int,
        mermaidBlockCount: Int,
        htmlElementCount: Int
    ) {
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.tableRowCount = tableRowCount
        self.mathExpressionCount = mathExpressionCount
        self.mermaidBlockCount = mermaidBlockCount
        self.htmlElementCount = htmlElementCount
    }

    public var recommendedMode: NoteEditorMode {
        if byteCount > 2_000_000
            || lineCount > 50_000
            || tableRowCount > 4_000
            || mathExpressionCount > 2_000
            || mermaidBlockCount > 250
            || htmlElementCount > 2_000
        {
            return .source
        }
        return .wysiwyg
    }

    public static func analyze(_ content: String) -> NoteDocumentComplexity {
        let lines = content.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        var tableRows = 0
        var mermaidBlocks = 0
        var mathExpressions = 0
        var htmlElements = 0
        var inMermaid = false

        for lineSlice in lines {
            let line = String(lineSlice)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```mermaid") {
                mermaidBlocks += 1
                inMermaid = true
            } else if inMermaid, trimmed.hasPrefix("```") {
                inMermaid = false
            }
            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|") {
                tableRows += 1
            }
            mathExpressions += line.components(separatedBy: "$").count / 2
            htmlElements += line.reduce(into: 0) { count, character in
                if character == "<" { count += 1 }
            }
        }

        return NoteDocumentComplexity(
            byteCount: content.lengthOfBytes(using: .utf8),
            lineCount: lines.count,
            tableRowCount: tableRows,
            mathExpressionCount: mathExpressions,
            mermaidBlockCount: mermaidBlocks,
            htmlElementCount: htmlElements
        )
    }
}
