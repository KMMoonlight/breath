@testable import BreathApp
import Foundation
import Testing

@Suite("Notes release readiness")
struct NotesReleaseReadinessTests {
    @Test("the editor ships six offline themes behind a restrictive CSP")
    func offlineThemesAndCSP() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let resources = root.appendingPathComponent(
            "Sources/BreathApp/Resources/NotesEditor",
            isDirectory: true
        )
        let html = try String(
            contentsOf: resources.appendingPathComponent("editor.html"),
            encoding: .utf8
        )
        let css = try String(
            contentsOf: resources.appendingPathComponent("editor.css"),
            encoding: .utf8
        )
        let package = try String(
            contentsOf: root.appendingPathComponent(
                "Web/NotesEditor/package.json"
            ),
            encoding: .utf8
        )

        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("script-src 'self'"))
        #expect(html.contains("connect-src 'none'"))
        #expect(!html.contains("https://"))
        #expect(!html.contains("http://"))
        for theme in ["gothic", "newsprint", "night", "pixyll", "whitey"] {
            #expect(css.contains("data-theme=\"\(theme)\""))
        }
        for dependency in [
            "\"@tiptap/core\": \"3.29.2\"",
            "\"dompurify\": \"3.4.12\"",
            "\"highlight.js\": \"11.11.1\"",
            "\"katex\": \"0.18.1\"",
            "\"mermaid\": \"11.16.0\"",
        ] {
            #expect(package.contains(dependency))
        }
        #expect(!package.contains("^"))
        #expect(!package.contains("~"))
    }

    @Test("release evidence and dependency audit stay checked in")
    func releaseEvidenceExists() {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        for path in [
            "docs/notes-dependency-audit.md",
            "docs/notes-release-readiness.md",
            "docs/adr/0044-use-webkit-for-notes-markdown-canvas.md",
            "docs/adr/0045-scope-note-agent-conversations-to-note-library.md",
        ] {
            #expect(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                )
            )
        }
    }

    @Test("the packaged notices cover every locked editor dependency")
    func noticesCoverLockfile() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let lockData = try Data(
            contentsOf: root.appendingPathComponent(
                "Web/NotesEditor/package-lock.json"
            )
        )
        let lock = try #require(
            JSONSerialization.jsonObject(with: lockData) as? [String: Any]
        )
        let packages = try #require(
            lock["packages"] as? [String: [String: Any]]
        )
        let notices = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/Resources/NotesEditor/THIRD_PARTY_NOTICES.txt"
            ),
            encoding: .utf8
        )
        for (packagePath, metadata) in packages
            where packagePath.hasPrefix("node_modules/")
        {
            let name = (metadata["name"] as? String)
                ?? packagePath.components(
                    separatedBy: "/node_modules/"
                ).last?
                .replacingOccurrences(of: "node_modules/", with: "")
                ?? packagePath
            let version = try #require(metadata["version"] as? String)
            #expect(notices.contains("## \(name)@\(version)\n"))
        }
        #expect(
            notices.contains(
                "Generated from Web/NotesEditor/package-lock.json."
            )
        )
    }
}
