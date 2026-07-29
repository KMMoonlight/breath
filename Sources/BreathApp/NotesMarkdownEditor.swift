import AppKit
import BreathNotes
import SwiftUI
import WebKit

struct NotesMarkdownEditor: NSViewRepresentable {
    let document: NoteDocument
    let libraryRoot: URL?
    let sourceMode: Bool
    let theme: String
    let appearance: String
    let language: String
    let showsCodeLineNumbers: Bool
    let spellCheckEnabled: Bool
    let findQuery: String?
    let findRevision: Int
    let findBackwards: Bool
    let onChange: (String) -> Void
    let onOpenLink: (String) -> Void
    let onImportAttachment: (Data, String) async -> String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.messageHandlerName
        )
        configuration.setURLSchemeHandler(
            context.coordinator.resourceHandler,
            forURLScheme: NoteEditorResourceSchemeHandler.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onChange = onChange
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onImportAttachment = onImportAttachment

        guard let htmlURL = BreathResources.notesEditorHTMLURL else {
            context.coordinator.presentResourceError(in: webView)
            return webView
        }
        webView.loadFileURL(
            htmlURL,
            allowingReadAccessTo: htmlURL.deletingLastPathComponent()
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onImportAttachment = onImportAttachment
        context.coordinator.pendingDocument = document
        context.coordinator.pendingLibraryRoot = libraryRoot
        context.coordinator.pendingSourceMode = sourceMode
        context.coordinator.pendingTheme = theme
        context.coordinator.pendingAppearance = appearance
        context.coordinator.pendingLanguage = language
        context.coordinator.pendingCodeLineNumbers = showsCodeLineNumbers
        context.coordinator.pendingSpellCheck = spellCheckEnabled
        context.coordinator.pendingFindQuery = findQuery
        context.coordinator.pendingFindRevision = findRevision
        context.coordinator.pendingFindBackwards = findBackwards
        context.coordinator.synchronizeIfReady()
    }

    static func dismantleNSView(
        _ webView: WKWebView,
        coordinator: Coordinator
    ) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator:
        NSObject,
        WKNavigationDelegate,
        WKScriptMessageHandler
    {
        static let messageHandlerName = "breathNotes"

        weak var webView: WKWebView?
        var onChange: ((String) -> Void)?
        var onOpenLink: ((String) -> Void)?
        var onImportAttachment: ((Data, String) async -> String?)?
        let resourceHandler = NoteEditorResourceSchemeHandler()
        var pendingDocument: NoteDocument?
        var pendingLibraryRoot: URL?
        var pendingSourceMode = false
        var pendingTheme = "github"
        var pendingAppearance = "light"
        var pendingLanguage = "zh-Hans"
        var pendingCodeLineNumbers = false
        var pendingSpellCheck = true
        var pendingFindQuery: String?
        var pendingFindRevision = 0
        var pendingFindBackwards = false
        private var isReady = false
        private var loadedDocumentID: NoteDocumentID?
        private var loadedContent: String?
        private var loadedVersion = 0
        private var appliedSourceMode: Bool?
        private var appliedTheme: String?
        private var appliedAppearance: String?
        private var appliedLanguage: String?
        private var appliedCodeLineNumbers: Bool?
        private var appliedSpellCheck: Bool?
        private var appliedFindQuery: String?
        private var appliedFindRevision = -1

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            isReady = true
            synchronizeIfReady()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (
                WKNavigationActionPolicy
            ) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                onOpenLink?(url.absoluteString)
                decisionHandler(.cancel)
                return
            }
            let editorURL = BreathResources.notesEditorHTMLURL?
                .standardizedFileURL
            if url.isFileURL,
               url.standardizedFileURL == editorURL
            {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isReady = false
            loadedDocumentID = nil
            loadedContent = nil
            appliedFindQuery = nil
            appliedFindRevision = -1
            guard let htmlURL = BreathResources.notesEditorHTMLURL else {
                presentResourceError(in: webView)
                return
            }
            webView.loadFileURL(
                htmlURL,
                allowingReadAccessTo: htmlURL.deletingLastPathComponent()
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageHandlerName,
                  let body = message.body as? [String: Any],
                  let name = body["name"] as? String,
                  let documentID = body["documentID"] as? String,
                  documentID == pendingDocument?.id.rawValue.uuidString,
                  let version = body["version"] as? Int,
                  version == loadedVersion
            else {
                return
            }
            switch name {
            case "editorChange":
                if let content = body["content"] as? String {
                    loadedContent = content
                    onChange?(content)
                }
            case "openLink":
                if let href = body["href"] as? String {
                    onOpenLink?(href)
                }
            case "importAttachment":
                guard let encoded = body["base64"] as? String,
                      let data = Data(base64Encoded: encoded),
                      let filename = body["filename"] as? String,
                      let mimeType = body["mimeType"] as? String,
                      let onImportAttachment
                else {
                    return
                }
                Task {
                    guard let path = await onImportAttachment(data, filename),
                          documentID == pendingDocument?.id.rawValue.uuidString,
                          version == loadedVersion
                    else {
                        return
                    }
                    _ = try? await webView?.evaluateJavaScript(
                        """
                        window.breathNotes.insertAttachment(
                          \(Self.jsString(path)),
                          \(Self.jsString(mimeType)),
                          \(Self.jsString(filename))
                        )
                        """
                    )
                }
            default:
                break
            }
        }

        func synchronizeIfReady() {
            guard isReady, let webView, let document = pendingDocument else {
                return
            }
            resourceHandler.update(
                libraryRoot: pendingLibraryRoot,
                documentRelativePath: document.relativePath
            )
            if loadedDocumentID != document.id
                || loadedContent != document.content
            {
                loadedVersion += 1
                let payload = EditorLoadPayload(
                    documentID: document.id.rawValue.uuidString,
                    version: loadedVersion,
                    content: document.content,
                    mode: pendingSourceMode ? "source" : "wysiwyg",
                    theme: pendingTheme,
                    appearance: pendingAppearance,
                    language: pendingLanguage,
                    kind: document.kind.rawValue,
                    relativePath: document.relativePath,
                    showsCodeLineNumbers: pendingCodeLineNumbers,
                    spellCheckEnabled: pendingSpellCheck
                )
                guard let data = try? JSONEncoder().encode(payload),
                      let json = String(data: data, encoding: .utf8)
                else {
                    return
                }
                loadedDocumentID = document.id
                loadedContent = document.content
                appliedSourceMode = pendingSourceMode
                appliedTheme = pendingTheme
                appliedAppearance = pendingAppearance
                appliedLanguage = pendingLanguage
                appliedCodeLineNumbers = pendingCodeLineNumbers
                appliedSpellCheck = pendingSpellCheck
                appliedFindQuery = nil
                appliedFindRevision = -1
                webView.evaluateJavaScript(
                    "window.breathNotes.load(\(json))"
                ) { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        self?.synchronizeIfReady()
                    }
                }
                return
            }
            if appliedSourceMode != pendingSourceMode {
                let mode = pendingSourceMode ? "source" : "wysiwyg"
                webView.evaluateJavaScript(
                    "window.breathNotes.setMode(\(Self.jsString(mode)))"
                )
                appliedSourceMode = pendingSourceMode
            }
            if appliedTheme != pendingTheme
                || appliedAppearance != pendingAppearance
            {
                webView.evaluateJavaScript(
                    """
                    window.breathNotes.setTheme(
                      \(Self.jsString(pendingTheme)),
                      \(Self.jsString(pendingAppearance))
                    )
                    """
                )
                appliedTheme = pendingTheme
                appliedAppearance = pendingAppearance
            }
            if appliedLanguage != pendingLanguage {
                webView.evaluateJavaScript(
                    "window.breathNotes.setLanguage(\(Self.jsString(pendingLanguage)))"
                )
                appliedLanguage = pendingLanguage
            }
            if appliedCodeLineNumbers != pendingCodeLineNumbers
                || appliedSpellCheck != pendingSpellCheck
            {
                webView.evaluateJavaScript(
                    """
                    window.breathNotes.setPreferences(
                      \(pendingCodeLineNumbers),
                      \(pendingSpellCheck)
                    )
                    """
                )
                appliedCodeLineNumbers = pendingCodeLineNumbers
                appliedSpellCheck = pendingSpellCheck
            }
            if let pendingFindQuery,
               !pendingFindQuery.isEmpty,
               appliedFindQuery != pendingFindQuery
                || appliedFindRevision != pendingFindRevision
            {
                webView.evaluateJavaScript(
                    """
                    window.breathNotes.find(
                      \(Self.jsString(pendingFindQuery)),
                      \(pendingFindBackwards)
                    )
                    """
                )
                appliedFindQuery = pendingFindQuery
                appliedFindRevision = pendingFindRevision
            }
        }

        func presentResourceError(in webView: WKWebView) {
            webView.loadHTMLString(
                """
                <html><body style="font-family: -apple-system; padding: 24px">
                Markdown editor resources are unavailable.
                </body></html>
                """,
                baseURL: nil
            )
        }

        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let result = String(data: data, encoding: .utf8)
            else {
                return "\"\""
            }
            return result
        }
    }
}

private struct EditorLoadPayload: Encodable {
    let documentID: String
    let version: Int
    let content: String
    let mode: String
    let theme: String
    let appearance: String
    let language: String
    let kind: String
    let relativePath: String
    let showsCodeLineNumbers: Bool
    let spellCheckEnabled: Bool
}
