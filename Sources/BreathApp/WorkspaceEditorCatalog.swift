import Foundation

struct InstalledWorkspaceEditor: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let applicationURL: URL
}

struct WorkspaceEditorCatalog: Sendable {
    struct Definition: Sendable {
        let id: String
        let displayName: String
        let bundleIdentifiers: [String]
    }

    static let common = WorkspaceEditorCatalog(definitions: [
        Definition(
            id: "visual-studio-code",
            displayName: "Visual Studio Code",
            bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        ),
        Definition(id: "cursor", displayName: "Cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]),
        Definition(id: "zed", displayName: "Zed", bundleIdentifiers: ["dev.zed.Zed"]),
        Definition(id: "xcode", displayName: "Xcode", bundleIdentifiers: ["com.apple.dt.Xcode"]),
        Definition(
            id: "sublime-text",
            displayName: "Sublime Text",
            bundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"]
        ),
        Definition(id: "nova", displayName: "Nova", bundleIdentifiers: ["com.panic.Nova"]),
        Definition(id: "bbedit", displayName: "BBEdit", bundleIdentifiers: ["com.barebones.bbedit"]),
        Definition(id: "vscodium", displayName: "VSCodium", bundleIdentifiers: ["com.vscodium"]),
        Definition(
            id: "intellij-idea",
            displayName: "IntelliJ IDEA",
            bundleIdentifiers: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
        ),
        Definition(id: "webstorm", displayName: "WebStorm", bundleIdentifiers: ["com.jetbrains.WebStorm"]),
        Definition(
            id: "pycharm",
            displayName: "PyCharm",
            bundleIdentifiers: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]
        ),
        Definition(id: "android-studio", displayName: "Android Studio", bundleIdentifiers: ["com.google.android.studio"]),
        Definition(id: "coteditor", displayName: "CotEditor", bundleIdentifiers: ["com.coteditor.CotEditor"]),
        Definition(id: "textmate", displayName: "TextMate", bundleIdentifiers: ["com.macromates.TextMate"]),
        Definition(id: "macvim", displayName: "MacVim", bundleIdentifiers: ["org.vim.MacVim"]),
    ])

    private let definitions: [Definition]

    init(definitions: [Definition]) {
        self.definitions = definitions
    }

    func installedEditors(
        resolvingApplicationURL: (String) -> URL?
    ) -> [InstalledWorkspaceEditor] {
        definitions.compactMap { definition in
            for bundleIdentifier in definition.bundleIdentifiers {
                if let applicationURL = resolvingApplicationURL(bundleIdentifier) {
                    return InstalledWorkspaceEditor(
                        id: definition.id,
                        displayName: definition.displayName,
                        bundleIdentifier: bundleIdentifier,
                        applicationURL: applicationURL
                    )
                }
            }
            return nil
        }
    }
}

struct WorkspaceEditorSelection: Sendable {
    func selectedEditor(
        preferredID: String,
        from editors: [InstalledWorkspaceEditor]
    ) -> InstalledWorkspaceEditor? {
        editors.first { $0.id == preferredID } ?? editors.first
    }
}
