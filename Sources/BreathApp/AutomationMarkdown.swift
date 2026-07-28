import Markdown

struct AutomationMarkdownDocument: Equatable, Sendable {
    let blocks: [AutomationMarkdownBlock]

    init(parsing source: String) {
        let document = Document(parsing: source)
        blocks = document.children.compactMap(
            AutomationMarkdownParser.block
        )
    }
}

indirect enum AutomationMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, content: AutomationMarkdownText)
    case paragraph(AutomationMarkdownText)
    case blockQuote([AutomationMarkdownBlock])
    case unorderedList([AutomationMarkdownListItem])
    case orderedList(start: Int, items: [AutomationMarkdownListItem])
    case codeBlock(language: String?, code: String)
    case thematicBreak
    case table(AutomationMarkdownTable)
    case htmlBlock(String)
}

struct AutomationMarkdownListItem: Equatable, Sendable {
    let checkbox: Bool?
    let blocks: [AutomationMarkdownBlock]
}

struct AutomationMarkdownText: Equatable, Sendable {
    let spans: [AutomationMarkdownSpan]
}

struct AutomationMarkdownTable: Equatable, Sendable {
    let alignments: [AutomationMarkdownTableAlignment?]
    let header: [AutomationMarkdownText]
    let rows: [[AutomationMarkdownText]]
}

enum AutomationMarkdownTableAlignment: Equatable, Sendable {
    case left
    case center
    case right
}

indirect enum AutomationMarkdownSpan: Equatable, Sendable {
    case text(String)
    case emphasis([AutomationMarkdownSpan])
    case strong([AutomationMarkdownSpan])
    case strikethrough([AutomationMarkdownSpan])
    case inlineCode(String)
    case link(
        destination: String?,
        title: String?,
        children: [AutomationMarkdownSpan]
    )
    case image(
        source: String?,
        title: String?,
        children: [AutomationMarkdownSpan]
    )
    case softBreak
    case lineBreak
    case inlineHTML(String)
}

private enum AutomationMarkdownParser {
    static func block(_ markup: Markup) -> AutomationMarkdownBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(
                level: heading.level,
                content: inlineText(heading)
            )
        case let paragraph as Paragraph:
            return .paragraph(inlineText(paragraph))
        case let quote as BlockQuote:
            return .blockQuote(quote.children.compactMap(block))
        case let list as UnorderedList:
            return .unorderedList(list.listItems.map(listItem))
        case let list as OrderedList:
            return .orderedList(
                start: Int(list.startIndex),
                items: list.listItems.map(listItem)
            )
        case let code as CodeBlock:
            return .codeBlock(
                language: code.language,
                code: code.code
            )
        case is ThematicBreak:
            return .thematicBreak
        case let table as Table:
            return .table(
                AutomationMarkdownTable(
                    alignments: table.columnAlignments.map(tableAlignment),
                    header: table.head.cells.map(inlineText),
                    rows: table.body.rows.map { row in
                        row.cells.map(inlineText)
                    }
                )
            )
        case let html as HTMLBlock:
            return .htmlBlock(html.rawHTML)
        default:
            return nil
        }
    }

    static func listItem(_ item: ListItem) -> AutomationMarkdownListItem {
        AutomationMarkdownListItem(
            checkbox: item.checkbox.map { checkbox in
                switch checkbox {
                case .checked: true
                case .unchecked: false
                }
            },
            blocks: item.children.compactMap(block)
        )
    }

    static func inlineText(_ markup: Markup) -> AutomationMarkdownText {
        AutomationMarkdownText(
            spans: markup.children.compactMap(span)
        )
    }

    static func tableAlignment(
        _ alignment: Table.ColumnAlignment?
    ) -> AutomationMarkdownTableAlignment? {
        switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case nil: nil
        }
    }

    static func span(_ markup: Markup) -> AutomationMarkdownSpan? {
        switch markup {
        case let text as Markdown.Text:
            return .text(text.string)
        case let emphasis as Emphasis:
            return .emphasis(emphasis.children.compactMap(span))
        case let strong as Strong:
            return .strong(strong.children.compactMap(span))
        case let strikethrough as Strikethrough:
            return .strikethrough(
                strikethrough.children.compactMap(span)
            )
        case let code as InlineCode:
            return .inlineCode(code.code)
        case let link as Link:
            return .link(
                destination: link.destination,
                title: link.title,
                children: link.children.compactMap(span)
            )
        case let image as Image:
            return .image(
                source: image.source,
                title: image.title,
                children: image.children.compactMap(span)
            )
        case is SoftBreak:
            return .softBreak
        case is LineBreak:
            return .lineBreak
        case let html as InlineHTML:
            return .inlineHTML(html.rawHTML)
        default:
            return nil
        }
    }
}
