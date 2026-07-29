import Foundation

public struct NoteMovePreview: Equatable, Sendable {
    public let affectedDocumentCount: Int
    public let affectedLinkCount: Int

    public init(affectedDocumentCount: Int, affectedLinkCount: Int) {
        self.affectedDocumentCount = affectedDocumentCount
        self.affectedLinkCount = affectedLinkCount
    }
}

struct NoteMovePlan {
    let sourceRelativePath: String
    let destinationRelativePath: String
    let rewrites: [NoteLinkRewrite]
    let preview: NoteMovePreview
}

struct NoteLinkRewrite {
    let originalRelativePath: String
    let futureRelativePath: String
    let originalContent: String
    let updatedContent: String
    let linkCount: Int
    let hadUTF8BOM: Bool
}

enum MarkdownLinkRewriter {
    private static let patterns = [
        try! NSRegularExpression(
            pattern: #"(!?\[[^\]\n]*\]\(\s*)(<[^>\n]+>|(?:\\.|[^\s()\\]|\([^()\n]*\))+)(?=(?:\s+(?:"[^"\n]*"|'[^'\n]*'|\([^)\n]*\)))?\s*\))"#
        ),
        try! NSRegularExpression(
            pattern: #"(?m)^(\s*\[[^\]]+\]:\s*)(<[^>\n]+>|\S+)"#
        ),
    ]

    static func planMove(
        rootURL: URL,
        sourceRelativePath: String,
        destinationRelativePath: String,
        fileManager: FileManager
    ) throws -> NoteMovePlan {
        let sourceURL = rootURL.appendingPathComponent(
            sourceRelativePath
        ).standardizedFileURL
        let destinationURL = rootURL.appendingPathComponent(
            destinationRelativePath
        ).standardizedFileURL
        var rewrites: [NoteLinkRewrite] = []

        let markdownURLs = try markdownFiles(
            in: rootURL,
            fileManager: fileManager
        )
        for documentURL in markdownURLs {
            let data = try Data(contentsOf: documentURL)
            let bom = Data([0xEF, 0xBB, 0xBF])
            let hadUTF8BOM = data.starts(with: bom)
            let body = hadUTF8BOM ? data.dropFirst(3) : data[...]
            guard let content = String(data: body, encoding: .utf8) else {
                continue
            }
            let originalRelativePath = relativePath(
                from: rootURL,
                to: documentURL
            )
            let futureDocumentURL = replacingMovedPrefix(
                documentURL,
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
            var replacements: [(range: NSRange, value: String)] = []
            let fullRange = NSRange(
                content.startIndex..<content.endIndex,
                in: content
            )
            for pattern in patterns {
                for match in pattern.matches(
                    in: content,
                    range: fullRange
                ) {
                    guard match.numberOfRanges > 2,
                          let destinationRange = Range(
                              match.range(at: 2),
                              in: content
                          )
                    else {
                        continue
                    }
                    let rawDestination = String(content[destinationRange])
                    guard let replacement = rewrittenDestination(
                        rawDestination,
                        sourceDocumentURL: documentURL,
                        futureDocumentURL: futureDocumentURL,
                        movedSourceURL: sourceURL,
                        movedDestinationURL: destinationURL
                    ), replacement != rawDestination
                    else {
                        continue
                    }
                    replacements.append((
                        range: match.range(at: 2),
                        value: replacement
                    ))
                }
            }
            guard !replacements.isEmpty else { continue }
            let updated = applying(replacements, to: content)
            rewrites.append(NoteLinkRewrite(
                originalRelativePath: originalRelativePath,
                futureRelativePath: relativePath(
                    from: rootURL,
                    to: futureDocumentURL
                ),
                originalContent: content,
                updatedContent: updated,
                linkCount: replacements.count,
                hadUTF8BOM: hadUTF8BOM
            ))
        }

        return NoteMovePlan(
            sourceRelativePath: sourceRelativePath,
            destinationRelativePath: destinationRelativePath,
            rewrites: rewrites,
            preview: NoteMovePreview(
                affectedDocumentCount: rewrites.count,
                affectedLinkCount: rewrites.reduce(0) { $0 + $1.linkCount }
            )
        )
    }

    private static func markdownFiles(
        in rootURL: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true,
                  ["md", "markdown"].contains(url.pathExtension.lowercased())
            else {
                continue
            }
            result.append(url.standardizedFileURL)
        }
        return result.sorted { $0.path < $1.path }
    }

    private static func rewrittenDestination(
        _ rawDestination: String,
        sourceDocumentURL: URL,
        futureDocumentURL: URL,
        movedSourceURL: URL,
        movedDestinationURL: URL
    ) -> String? {
        let wrapped = rawDestination.hasPrefix("<")
            && rawDestination.hasSuffix(">")
        let unwrapped = wrapped
            ? String(rawDestination.dropFirst().dropLast())
            : rawDestination
        let pieces = unwrapped.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let pathPart = String(pieces[0])
        let suffix = pieces.count == 2 ? "#\(pieces[1])" : ""
        guard !pathPart.isEmpty,
              !pathPart.hasPrefix("/"),
              URL(string: pathPart)?.scheme == nil
        else {
            return nil
        }
        let decodedPath = pathPart.removingPercentEncoding ?? pathPart
        let originalTarget = sourceDocumentURL
            .deletingLastPathComponent()
            .appendingPathComponent(decodedPath)
            .standardizedFileURL
        let futureTarget = replacingMovedPrefix(
            originalTarget,
            sourceURL: movedSourceURL,
            destinationURL: movedDestinationURL
        )
        guard originalTarget != futureTarget
            || sourceDocumentURL != futureDocumentURL
        else {
            return nil
        }
        let relative = relativePath(
            from: futureDocumentURL.deletingLastPathComponent(),
            to: futureTarget
        ).replacingOccurrences(of: " ", with: "%20")
        let result = relative + suffix
        return wrapped ? "<\(result)>" : result
    }

    private static func replacingMovedPrefix(
        _ url: URL,
        sourceURL: URL,
        destinationURL: URL
    ) -> URL {
        let path = url.standardizedFileURL.path
        let sourcePath = sourceURL.standardizedFileURL.path
        guard path == sourcePath || path.hasPrefix(sourcePath + "/") else {
            return url.standardizedFileURL
        }
        let suffix = String(path.dropFirst(sourcePath.count))
        return URL(
            fileURLWithPath: destinationURL.path + suffix,
            isDirectory: false
        ).standardizedFileURL
    }

    private static func relativePath(from baseURL: URL, to targetURL: URL) -> String {
        let baseComponents = baseURL.standardizedFileURL.pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents
        var common = 0
        while common < baseComponents.count,
              common < targetComponents.count,
              baseComponents[common] == targetComponents[common]
        {
            common += 1
        }
        let parents = Array(
            repeating: "..",
            count: baseComponents.count - common
        )
        let descendants = Array(targetComponents.dropFirst(common))
        let components = parents + descendants
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    private static func applying(
        _ replacements: [(range: NSRange, value: String)],
        to content: String
    ) -> String {
        let mutable = NSMutableString(string: content)
        for replacement in replacements.sorted(by: {
            $0.range.location > $1.range.location
        }) {
            mutable.replaceCharacters(
                in: replacement.range,
                with: replacement.value
            )
        }
        return mutable as String
    }
}
