import AppKit
import SwiftUI

/// A native commit-message editor that preserves AppKit's marked-text lifecycle.
///
/// SwiftUI can refresh the surrounding workbench while an input method is still
/// composing text. Applying the model's previous value during that window clears
/// the candidate composition, so model synchronization is deliberately deferred
/// until the input method commits its marked text.
struct GitCommitMessageEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 5, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.applyExternalText(text, to: textView)
        context.coordinator.requestFocusIfNeeded(for: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GitCommitMessageEditor

        init(parent: GitCommitMessageEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            setFocused(true)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            publishFinalText(from: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                publishFinalText(from: textView)
            }
            setFocused(false)
        }

        func publishFinalText(from textView: NSTextView) {
            guard !textView.hasMarkedText() else { return }
            guard parent.text != textView.string else { return }
            parent.text = textView.string
        }

        func applyExternalText(_ text: String, to textView: NSTextView) {
            guard !textView.hasMarkedText() else { return }
            guard textView.string != text else { return }

            let selection = textView.selectedRange()
            textView.string = text
            let textLength = (text as NSString).length
            let location = min(selection.location, textLength)
            let length = min(selection.length, textLength - location)
            textView.setSelectedRange(
                NSRange(location: location, length: length)
            )
        }

        func requestFocusIfNeeded(for textView: NSTextView) {
            guard parent.isFocused else { return }
            guard textView.window?.firstResponder !== textView else { return }

            DispatchQueue.main.async { [weak textView] in
                guard let textView, let window = textView.window else { return }
                guard window.firstResponder !== textView else { return }
                window.makeFirstResponder(textView)
            }
        }

        private func setFocused(_ focused: Bool) {
            guard parent.isFocused != focused else { return }
            parent.isFocused = focused
        }
    }
}
