import Foundation
import Testing
@testable import BreathApp

@Suite("Workspace editor catalog")
struct WorkspaceEditorCatalogTests {
    @Test("only installed common editors are listed in catalog order")
    func installedEditors() {
        let installedApplications = [
            "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            "com.microsoft.VSCodeInsiders": URL(fileURLWithPath: "/Applications/Visual Studio Code Insiders.app"),
            "dev.zed.Zed": URL(fileURLWithPath: "/Applications/Zed.app"),
            "com.jetbrains.WebStorm": URL(fileURLWithPath: "/Applications/WebStorm.app"),
        ]

        let editors = WorkspaceEditorCatalog.common.installedEditors {
            installedApplications[$0]
        }

        #expect(editors.map(\.id) == [
            "visual-studio-code",
            "zed",
            "webstorm",
        ])
        #expect(editors[0].bundleIdentifier == "com.microsoft.VSCode")
        #expect(editors[0].displayName == "Visual Studio Code")
        #expect(editors[1].applicationURL.lastPathComponent == "Zed.app")
    }

    @Test("saved editor is selected and an unavailable preference falls back")
    func editorSelection() {
        let editors = [
            InstalledWorkspaceEditor(
                id: "visual-studio-code",
                displayName: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode",
                applicationURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
            ),
            InstalledWorkspaceEditor(
                id: "zed",
                displayName: "Zed",
                bundleIdentifier: "dev.zed.Zed",
                applicationURL: URL(fileURLWithPath: "/Applications/Zed.app")
            ),
        ]
        let selection = WorkspaceEditorSelection()

        #expect(selection.selectedEditor(preferredID: "zed", from: editors)?.id == "zed")
        #expect(selection.selectedEditor(preferredID: "missing", from: editors)?.id == "visual-studio-code")
        #expect(selection.selectedEditor(preferredID: "", from: []) == nil)
    }

    @Test("Markdown writing apps are not offered as code editors")
    func excludesMarkdownWritingApps() {
        let editors = WorkspaceEditorCatalog.common.installedEditors { bundleIdentifier in
            guard bundleIdentifier == "abnerworks.Typora" else { return nil }
            return URL(fileURLWithPath: "/Applications/Typora.app")
        }

        #expect(editors.isEmpty)
    }
}
