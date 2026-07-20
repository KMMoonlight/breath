import AppKit
import SwiftUI
import Testing
@testable import BreathApp

@Suite("Git commit message editor")
@MainActor
struct GitCommitMessageEditorTests {
    @Test("marked text is neither persisted nor overwritten")
    func protectsInputMethodComposition() {
        var persistedText = ""
        var writeCount = 0
        var isFocused = false
        let editor = GitCommitMessageEditor(
            text: Binding(
                get: { persistedText },
                set: {
                    persistedText = $0
                    writeCount += 1
                }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            )
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(frame: .zero)

        textView.setMarkedText(
            "pin",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(textView.hasMarkedText())

        coordinator.publishFinalText(from: textView)
        coordinator.applyExternalText("external refresh", to: textView)

        #expect(persistedText.isEmpty)
        #expect(writeCount == 0)
        #expect(textView.string == "pin")

        textView.unmarkText()
        textView.string = "拼"
        coordinator.publishFinalText(from: textView)

        #expect(persistedText == "拼")
        #expect(writeCount == 1)
    }

    @Test("finalized text accepts later model updates without moving selection out of bounds")
    func appliesExternalTextAfterComposition() {
        var persistedText = "initial"
        var isFocused = false
        let editor = GitCommitMessageEditor(
            text: Binding(
                get: { persistedText },
                set: { persistedText = $0 }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            )
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(frame: .zero)
        textView.string = "a much longer old value"
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        coordinator.applyExternalText("短", to: textView)

        #expect(textView.string == "短")
        #expect(textView.selectedRange().location == 1)
    }
}
