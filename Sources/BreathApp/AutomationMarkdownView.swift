import Foundation
import SwiftUI

struct MarkdownAutomationOutput: View {
    private let document: AutomationMarkdownDocument

    init(output: String) {
        document = AutomationMarkdownDocument(parsing: output)
    }

    var body: some View {
        AutomationMarkdownBlocksView(blocks: document.blocks)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AutomationMarkdownBlocksView: View {
    let blocks: [AutomationMarkdownBlock]
    var spacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                AutomationMarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AutomationMarkdownBlockView: View {
    let block: AutomationMarkdownBlock

    @ViewBuilder
    var body: some View {
        switch block {
        case .heading(let level, let content):
            Text(content.attributedString)
                .font(headingFont(level))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let content):
            Text(content.attributedString)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .blockQuote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)
                AutomationMarkdownBlocksView(blocks: blocks, spacing: 8)
                    .foregroundStyle(.secondary)
            }
        case .unorderedList(let items):
            AutomationMarkdownListView(
                style: .unordered,
                items: items
            )
        case .orderedList(let start, let items):
            AutomationMarkdownListView(
                style: .ordered(start: start),
                items: items
            )
        case .codeBlock(let language, let code):
            AutomationMarkdownCodeBlock(
                language: language,
                code: code
            )
        case .thematicBreak:
            Divider()
        case .table(let table):
            AutomationMarkdownTableView(table: table)
        case .htmlBlock(let html):
            AutomationMarkdownCodeBlock(
                language: "HTML",
                code: html
            )
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.bold)
        case 2: .title3.weight(.bold)
        case 3: .headline
        case 4: .subheadline.weight(.semibold)
        case 5: .body.weight(.semibold)
        default: .caption.weight(.semibold)
        }
    }
}

private struct AutomationMarkdownListView: View {
    enum Style {
        case unordered
        case ordered(start: Int)
    }

    let style: Style
    let items: [AutomationMarkdownListItem]
    @Environment(\.applicationLanguage) private var applicationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(marker(for: index))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    if let taskMarker = item.taskMarker {
                        Image(
                            systemName: taskMarker == .checked
                                ? "checkmark.square.fill"
                                : "square"
                        )
                        .foregroundStyle(
                            taskMarker == .checked
                                ? Color.accentColor
                                : Color.secondary
                        )
                        .accessibilityLabel(
                            localizer.string(
                                taskMarker == .checked
                                    ? "已完成"
                                    : "未完成"
                            )
                        )
                    }
                    AutomationMarkdownBlocksView(
                        blocks: item.blocks,
                        spacing: 7
                    )
                }
            }
        }
    }

    private func marker(for index: Int) -> String {
        switch style {
        case .unordered:
            "•"
        case .ordered(let start):
            "\(start + index)."
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private struct AutomationMarkdownCodeBlock: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

private struct AutomationMarkdownTableView: View {
    let table: AutomationMarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                if !table.header.isEmpty {
                    GridRow {
                        ForEach(table.header.indices, id: \.self) { column in
                            cell(
                                table.header[column],
                                column: column,
                                isHeader: true
                            )
                        }
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.rows[row].indices, id: \.self) { column in
                            cell(
                                table.rows[row][column],
                                column: column,
                                isHeader: false
                            )
                        }
                    }
                }
            }
        }
    }

    private func cell(
        _ content: AutomationMarkdownText,
        column: Int,
        isHeader: Bool
    ) -> some View {
        Text(content.attributedString)
            .font(isHeader ? .body.weight(.semibold) : .body)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(
                minWidth: 110,
                maxWidth: 280,
                alignment: alignment(for: column)
            )
            .background(
                isHeader
                    ? Color.primary.opacity(0.055)
                    : Color.clear
            )
            .overlay {
                Rectangle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }

    private func alignment(for column: Int) -> Alignment {
        guard table.alignments.indices.contains(column) else {
            return .leading
        }
        switch table.alignments[column] {
        case .center: return .center
        case .right: return .trailing
        case .left, nil: return .leading
        }
    }
}

private extension AutomationMarkdownText {
    var attributedString: AttributedString {
        AutomationMarkdownAttributedStringBuilder.build(spans)
    }
}

private enum AutomationMarkdownAttributedStringBuilder {
    static func build(
        _ spans: [AutomationMarkdownSpan],
        intent: InlinePresentationIntent = []
    ) -> AttributedString {
        spans.reduce(into: AttributedString()) { result, span in
            result.append(build(span, intent: intent))
        }
    }

    private static func build(
        _ span: AutomationMarkdownSpan,
        intent: InlinePresentationIntent
    ) -> AttributedString {
        switch span {
        case .text(let value):
            return styled(value, intent: intent)
        case .emphasis(let children):
            return build(
                children,
                intent: intent.union(.emphasized)
            )
        case .strong(let children):
            return build(
                children,
                intent: intent.union(.stronglyEmphasized)
            )
        case .strikethrough(let children):
            return build(
                children,
                intent: intent.union(.strikethrough)
            )
        case .inlineCode(let code):
            return styled(
                code,
                intent: intent.union(.code)
            )
        case .link(let destination, let children):
            var value = build(children, intent: intent)
            if let destination,
               let url = URL(string: destination)
            {
                value.link = url
            }
            return value
        case .image(let children):
            var value = styled("▧ ", intent: intent)
            value.append(build(children, intent: intent))
            return value
        case .softBreak:
            return styled(" ", intent: intent)
        case .lineBreak:
            return styled("\n", intent: intent)
        case .inlineHTML(let html):
            return styled(
                html,
                intent: intent.union(.code)
            )
        }
    }

    private static func styled(
        _ value: String,
        intent: InlinePresentationIntent
    ) -> AttributedString {
        var result = AttributedString(value)
        if !intent.isEmpty {
            result.inlinePresentationIntent = intent
        }
        return result
    }
}
