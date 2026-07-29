import Foundation

public enum NoteTabTitle {
    public static func disambiguated(
        relativePath: String,
        among relativePaths: [String]
    ) -> String {
        let name = (relativePath as NSString).lastPathComponent
        let duplicates = relativePaths.filter {
            ($0 as NSString).lastPathComponent == name
        }
        guard duplicates.count > 1 else {
            return name
        }

        let components = relativePath.split(separator: "/").map(String.init)
        let parentComponents = Array(components.dropLast())
        guard !parentComponents.isEmpty else {
            return "\(name) — /"
        }
        for depth in 1...parentComponents.count {
            let candidate = suffixTitle(
                for: relativePath,
                parentDepth: depth
            )
            let matches = duplicates.filter {
                suffixTitle(for: $0, parentDepth: depth) == candidate
            }
            if matches.count == 1 {
                return candidate
            }
        }
        return relativePath
    }

    private static func suffixTitle(
        for relativePath: String,
        parentDepth: Int
    ) -> String {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let name = components.last else {
            return relativePath
        }
        let parents = components.dropLast()
        let selectedParents = parents.suffix(parentDepth)
        return (selectedParents + [name]).joined(separator: "/")
    }
}
