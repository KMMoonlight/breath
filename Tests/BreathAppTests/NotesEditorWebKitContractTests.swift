@testable import BreathApp
import Foundation
import Testing
import WebKit

@MainActor
@Suite("Notes editor WebKit contract")
struct NotesEditorWebKitContractTests {
    @Test("mode switching preserves an untouched markdown document exactly")
    func untouchedSourceFidelity() async throws {
        let webView = try await makeEditor()
        let source = """
        ---
        title: "Breath"
        tags: [swift, notes]
        ---

        # Heading

        [TOC]

        A footnote[^1].

        [^1]: Kept exactly.
        """.replacingOccurrences(of: "\n", with: "\r\n")
        try await load(source, into: webView)

        let initial = try #require(
            try await webView.evaluateJavaScript(
                "window.breathNotes.currentMarkdown()"
            ) as? String
        )
        #expect(initial == source)

        _ = try await webView.evaluateJavaScript(
            "window.breathNotes.setMode('source')"
        )
        _ = try await webView.evaluateJavaScript(
            "window.breathNotes.setMode('wysiwyg')"
        )
        let afterSwitch = try #require(
            try await webView.evaluateJavaScript(
                "window.breathNotes.currentMarkdown()"
            ) as? String
        )
        #expect(afterSwitch == source)
    }

    @Test("active HTML is removed and complex renderers stay offline")
    func safeComplexRendering() async throws {
        let webView = try await makeEditor()
        try await load(
            """
            <img src="x" onerror="window.pwned = true">
            <script>window.pwned = true</script>

            Math: $x^2$.

            ```mermaid
            graph TD
              A --> B
            ```

            ```html
            <script>example shown as code</script>
            ```
            """,
            into: webView
        )
        try? await Task.sleep(for: .milliseconds(300))

        let activeHTMLValue = try await webView.evaluateJavaScript(
                """
                Boolean(
                  document.querySelector('#editor script')
                  || document.querySelector('#editor [onerror]')
                  || window.pwned
                )
                """
        )
        guard let activeHTML = activeHTMLValue as? Bool else {
            Issue.record("Editor safety probe did not return a Boolean")
            return
        }
        #expect(!activeHTML)
        let hasMathValue = try await webView.evaluateJavaScript(
            "Boolean(document.querySelector('.math-preview'))"
        )
        guard let hasMath = hasMathValue as? Bool else {
            Issue.record("Math renderer probe did not return a Boolean")
            return
        }
        let hasMermaidValue = try await webView.evaluateJavaScript(
            "Boolean(document.querySelector('.mermaid-preview'))"
        )
        guard let hasMermaid = hasMermaidValue as? Bool else {
            Issue.record("Mermaid renderer probe did not return a Boolean")
            return
        }
        #expect(hasMath)
        #expect(hasMermaid)
        let preservesCode = try #require(
            try await webView.evaluateJavaScript(
                """
                Array.from(document.querySelectorAll('pre code')).some(
                  node => node.textContent.includes(
                    '<script>example shown as code</script>'
                  )
                )
                """
            ) as? Bool
        )
        #expect(preservesCode)
    }

    private func makeEditor() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        let htmlURL = try #require(BreathResources.notesEditorHTMLURL)
        webView.loadFileURL(
            htmlURL,
            allowingReadAccessTo: htmlURL.deletingLastPathComponent()
        )
        for _ in 0..<200 {
            if !webView.isLoading,
               (try? await webView.evaluateJavaScript(
                   "typeof window.breathNotes === 'object'"
               ) as? Bool) == true
            {
                return webView
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Editor did not become ready")
        return webView
    }

    private func load(_ content: String, into webView: WKWebView) async throws {
        let payload: [String: Any] = [
            "documentID": UUID().uuidString,
            "version": 1,
            "content": content,
            "mode": "wysiwyg",
            "theme": "github",
            "appearance": "light",
            "kind": "markdown",
            "relativePath": "contract.md",
            "showsCodeLineNumbers": false,
            "spellCheckEnabled": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = try #require(String(data: data, encoding: .utf8))
        _ = try await webView.evaluateJavaScript(
            "window.breathNotes.load(\(json))"
        )
    }
}
