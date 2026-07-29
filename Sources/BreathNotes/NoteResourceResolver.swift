import Foundation

public enum NoteResourceResolver {
    public static func resolveLocalResource(
        _ resourcePath: String,
        relativeTo documentRelativePath: String,
        libraryRoot: URL
    ) throws -> URL {
        let decoded = resourcePath.removingPercentEncoding ?? resourcePath
        guard !decoded.isEmpty,
              !NSString(string: decoded).isAbsolutePath,
              URL(string: decoded)?.scheme == nil
        else {
            throw NotesError.pathOutsideLibrary(resourcePath)
        }

        let root = libraryRoot.standardizedFileURL
        let documentDirectory = root
            .appendingPathComponent(documentRelativePath)
            .deletingLastPathComponent()
        let candidate = documentDirectory
            .appendingPathComponent(decoded)
            .standardizedFileURL
        let boundary = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(boundary) else {
            throw NotesError.pathOutsideLibrary(resourcePath)
        }
        return candidate
    }

    public static func resolveExistingLocalResource(
        _ resourcePath: String,
        relativeTo documentRelativePath: String,
        libraryRoot: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = libraryRoot.standardizedFileURL
        let candidate = try resolveLocalResource(
            resourcePath,
            relativeTo: documentRelativePath,
            libraryRoot: root
        )
        let relative = String(candidate.path.dropFirst(root.path.count))
        var cursor = root
        for component in relative.split(separator: "/") {
            cursor.appendPathComponent(String(component))
            guard fileManager.fileExists(atPath: cursor.path) else {
                throw NotesError.libraryUnavailable(candidate.path)
            }
            if try cursor.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink == true {
                throw NotesError.symbolicLinkNotAllowed(cursor.path)
            }
        }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let canonicalCandidate = candidate.resolvingSymlinksInPath()
            .standardizedFileURL
        let boundary = canonicalRoot.path.hasSuffix("/")
            ? canonicalRoot.path
            : canonicalRoot.path + "/"
        guard canonicalCandidate.path.hasPrefix(boundary) else {
            throw NotesError.pathOutsideLibrary(resourcePath)
        }
        return candidate
    }
}
