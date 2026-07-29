import Foundation

enum BreathResources {
    static let bundle: Bundle = {
        if let resourcesURL = Bundle.main.resourceURL {
            let packagedBundleURL = resourcesURL.appendingPathComponent(
                "Breath_BreathApp.bundle",
                isDirectory: true
            )
            if let packagedBundle = Bundle(url: packagedBundleURL) {
                return packagedBundle
            }
        }
        return .module
    }()

    static var notesEditorHTMLURL: URL? {
        bundle.url(
            forResource: "editor",
            withExtension: "html",
            subdirectory: "NotesEditor"
        ) ?? bundle.url(
            forResource: "editor",
            withExtension: "html"
        )
    }
}
