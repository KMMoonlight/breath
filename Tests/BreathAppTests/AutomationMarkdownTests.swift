import Testing
@testable import BreathApp

@Suite("Automation Markdown")
struct AutomationMarkdownTests {
    @Test("parses block hierarchy and inline emphasis")
    func parsesBlockHierarchy() {
        let document = AutomationMarkdownDocument(
            parsing: """
            # Summary

            Paragraph with **bold**.

            - First
              - Nested
            """
        )

        #expect(
            document.blocks == [
                .heading(
                    level: 1,
                    content: AutomationMarkdownText(spans: [
                        .text("Summary"),
                    ])
                ),
                .paragraph(
                    AutomationMarkdownText(spans: [
                        .text("Paragraph with "),
                        .strong([.text("bold")]),
                        .text("."),
                    ])
                ),
                .unorderedList([
                    AutomationMarkdownListItem(
                        taskMarker: nil,
                        blocks: [
                            .paragraph(
                                AutomationMarkdownText(spans: [
                                    .text("First"),
                                ])
                            ),
                            .unorderedList([
                                AutomationMarkdownListItem(
                                    taskMarker: nil,
                                    blocks: [
                                        .paragraph(
                                            AutomationMarkdownText(spans: [
                                                .text("Nested"),
                                            ])
                                        ),
                                    ]
                                ),
                            ]),
                        ]
                    ),
                ]),
            ]
        )
    }

    @Test("parses the complete safe GFM block and inline set")
    func parsesCompleteGFMSet() {
        let document = AutomationMarkdownDocument(
            parsing: """
            > See *note* and [docs](https://example.com).

            3. [x] Done with ~~legacy~~ and `code`
            4. ![diagram](https://example.com/diagram.png)

            ---

            ```swift
            let value = 1
            ```

            | Name | State |
            | :--- | ----: |
            | Agent | Ready |

            <div>safe</div>
            """
        )

        #expect(
            document.blocks == [
                .blockQuote([
                    .paragraph(
                        AutomationMarkdownText(spans: [
                            .text("See "),
                            .emphasis([.text("note")]),
                            .text(" and "),
                            .link(
                                destination: "https://example.com",
                                children: [.text("docs")]
                            ),
                            .text("."),
                        ])
                    ),
                ]),
                .orderedList(
                    start: 3,
                    items: [
                        AutomationMarkdownListItem(
                            taskMarker: .checked,
                            blocks: [
                                .paragraph(
                                    AutomationMarkdownText(spans: [
                                        .text("Done with "),
                                        .strikethrough([.text("legacy")]),
                                        .text(" and "),
                                        .inlineCode("code"),
                                    ])
                                ),
                            ]
                        ),
                        AutomationMarkdownListItem(
                            taskMarker: nil,
                            blocks: [
                                .paragraph(
                                    AutomationMarkdownText(spans: [
                                        .image(
                                            children: [.text("diagram")]
                                        ),
                                    ])
                                ),
                            ]
                        ),
                    ]
                ),
                .thematicBreak,
                .codeBlock(language: "swift", code: "let value = 1\n"),
                .table(
                    AutomationMarkdownTable(
                        alignments: [.left, .right],
                        header: [
                            AutomationMarkdownText(spans: [.text("Name")]),
                            AutomationMarkdownText(spans: [.text("State")]),
                        ],
                        rows: [[
                            AutomationMarkdownText(spans: [.text("Agent")]),
                            AutomationMarkdownText(spans: [.text("Ready")]),
                        ]]
                    )
                ),
                .htmlBlock("<div>safe</div>\n"),
            ]
        )
    }

    @Test("preserves soft breaks, hard breaks, and safe inline HTML")
    func preservesInlineBreaksAndHTML() {
        let hardBreakLine = "second" + String(repeating: " ", count: 2)
        let document = AutomationMarkdownDocument(
            parsing: [
                "first",
                hardBreakLine,
                "third <kbd>Enter</kbd>",
            ].joined(separator: "\n")
        )

        #expect(
            document.blocks == [
                .paragraph(
                    AutomationMarkdownText(spans: [
                        .text("first"),
                        .softBreak,
                        .text("second"),
                        .lineBreak,
                        .text("third "),
                        .inlineHTML("<kbd>"),
                        .text("Enter"),
                        .inlineHTML("</kbd>"),
                    ])
                ),
            ]
        )
    }
}
