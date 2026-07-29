import BreathCore
import Foundation

public struct NoteLibraryID:
    RawRepresentable,
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct NoteDocumentID:
    RawRepresentable,
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct NoteLibrary: Equatable, Codable, Sendable, Identifiable {
    public let id: NoteLibraryID
    public let rootPath: String

    public init(id: NoteLibraryID, rootPath: String) {
        self.id = id
        self.rootPath = rootPath
    }

    public var displayName: String {
        URL(fileURLWithPath: rootPath, isDirectory: true).lastPathComponent
    }
}

public enum NoteLibraryAvailability: Equatable, Sendable {
    case available
    case unavailable
}

public enum NoteDocumentKind: String, Equatable, Codable, Sendable {
    case markdown
    case plainText
}

public enum NoteDocumentExternalState: Equatable, Sendable {
    case inSync
    case conflict(diskContent: String)
    case missing
}

public enum NoteExternalConflictResolution: Equatable, Sendable {
    case overwriteDisk
    case reloadDisk
}

public enum NoteCloseDecision: Equatable, Sendable {
    case save
    case discard
    case cancel
}

public enum NoteImportConflictResolution: Equatable, Sendable {
    case keepBoth
    case replace
    case cancel
}

public struct NoteImportResult: Equatable, Sendable {
    public let sourceURL: URL
    public let relativePath: String

    public init(sourceURL: URL, relativePath: String) {
        self.sourceURL = sourceURL
        self.relativePath = relativePath
    }
}

public enum NoteLibraryEntryKind: String, Equatable, Codable, Sendable {
    case folder
    case markdown
    case plainText
    case image
    case pdf
    case attachment
}

public struct NoteLibraryEntry: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let name: String
    public let kind: NoteLibraryEntryKind
    public let children: [NoteLibraryEntry]
    public let creationDate: Date?
    public let modificationDate: Date?

    public init(
        relativePath: String,
        name: String,
        kind: NoteLibraryEntryKind,
        children: [NoteLibraryEntry] = [],
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.relativePath = relativePath
        self.name = name
        self.kind = kind
        self.children = children
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    public var id: String { relativePath }
}

public struct NoteDocument: Equatable, Sendable, Identifiable {
    public let id: NoteDocumentID
    public let relativePath: String
    public let kind: NoteDocumentKind
    public let content: String
    public let savedContent: String
    public let externalState: NoteDocumentExternalState

    public init(
        id: NoteDocumentID,
        relativePath: String,
        kind: NoteDocumentKind,
        content: String,
        savedContent: String,
        externalState: NoteDocumentExternalState = .inSync
    ) {
        self.id = id
        self.relativePath = relativePath
        self.kind = kind
        self.content = content
        self.savedContent = savedContent
        self.externalState = externalState
    }

    public var isDirty: Bool {
        content != savedContent
    }
}

public struct NoteRecoveryDraft: Equatable, Codable, Sendable {
    public let relativePath: String
    public let content: String
    public let savedContent: String
    public let hadUTF8BOM: Bool

    public init(
        relativePath: String,
        content: String,
        savedContent: String,
        hadUTF8BOM: Bool
    ) {
        self.relativePath = relativePath
        self.content = content
        self.savedContent = savedContent
        self.hadUTF8BOM = hadUTF8BOM
    }
}

public struct NotesPersistedState: Equatable, Codable, Sendable {
    public var library: NoteLibrary?
    public var openDocumentPaths: [String]
    public var selectedDocumentPath: String?
    public var recoveryDrafts: [String: NoteRecoveryDraft]
    public var preferences: NotesPreferences
    public var lastSelectedAgent: AgentKind?
    public var noteAgentRecoveryBinding: NoteAgentRecoveryBinding?

    public init(
        library: NoteLibrary? = nil,
        openDocumentPaths: [String] = [],
        selectedDocumentPath: String? = nil,
        recoveryDrafts: [String: NoteRecoveryDraft] = [:],
        preferences: NotesPreferences = .default,
        lastSelectedAgent: AgentKind? = nil,
        noteAgentRecoveryBinding: NoteAgentRecoveryBinding? = nil
    ) {
        self.library = library
        self.openDocumentPaths = openDocumentPaths
        self.selectedDocumentPath = selectedDocumentPath
        self.recoveryDrafts = recoveryDrafts
        self.preferences = preferences
        self.lastSelectedAgent = lastSelectedAgent
        self.noteAgentRecoveryBinding = noteAgentRecoveryBinding
    }

    public static let empty = NotesPersistedState()

    private enum CodingKeys: String, CodingKey {
        case library
        case openDocumentPaths
        case selectedDocumentPath
        case recoveryDrafts
        case preferences
        case lastSelectedAgent
        case noteAgentRecoveryBinding
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            library: try container.decodeIfPresent(
                NoteLibrary.self,
                forKey: .library
            ),
            openDocumentPaths: try container.decodeIfPresent(
                [String].self,
                forKey: .openDocumentPaths
            ) ?? [],
            selectedDocumentPath: try container.decodeIfPresent(
                String.self,
                forKey: .selectedDocumentPath
            ),
            recoveryDrafts: try container.decodeIfPresent(
                [String: NoteRecoveryDraft].self,
                forKey: .recoveryDrafts
            ) ?? [:],
            preferences: try container.decodeIfPresent(
                NotesPreferences.self,
                forKey: .preferences
            ) ?? .default,
            lastSelectedAgent: try container.decodeIfPresent(
                AgentKind.self,
                forKey: .lastSelectedAgent
            ),
            noteAgentRecoveryBinding: try container.decodeIfPresent(
                NoteAgentRecoveryBinding.self,
                forKey: .noteAgentRecoveryBinding
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(library, forKey: .library)
        try container.encode(openDocumentPaths, forKey: .openDocumentPaths)
        try container.encodeIfPresent(
            selectedDocumentPath,
            forKey: .selectedDocumentPath
        )
        try container.encode(recoveryDrafts, forKey: .recoveryDrafts)
        try container.encode(preferences, forKey: .preferences)
        try container.encodeIfPresent(
            lastSelectedAgent,
            forKey: .lastSelectedAgent
        )
        try container.encodeIfPresent(
            noteAgentRecoveryBinding,
            forKey: .noteAgentRecoveryBinding
        )
    }
}

public struct NotesSnapshot: Equatable, Sendable {
    public let library: NoteLibrary?
    public let entries: [NoteLibraryEntry]
    public let documents: [NoteDocument]
    public let selectedDocumentID: NoteDocumentID?
    public let preferences: NotesPreferences
    public let libraryAvailability: NoteLibraryAvailability
    public let lastSelectedAgent: AgentKind?
    public let noteAgentRecoveryBinding: NoteAgentRecoveryBinding?
    public let searchIndexStatus: NoteSearchIndexStatus

    public init(
        library: NoteLibrary?,
        entries: [NoteLibraryEntry],
        documents: [NoteDocument],
        selectedDocumentID: NoteDocumentID?,
        preferences: NotesPreferences = .default,
        libraryAvailability: NoteLibraryAvailability = .available,
        lastSelectedAgent: AgentKind? = nil,
        noteAgentRecoveryBinding: NoteAgentRecoveryBinding? = nil,
        searchIndexStatus: NoteSearchIndexStatus = .ready
    ) {
        self.library = library
        self.entries = entries
        self.documents = documents
        self.selectedDocumentID = selectedDocumentID
        self.preferences = preferences
        self.libraryAvailability = libraryAvailability
        self.lastSelectedAgent = lastSelectedAgent
        self.noteAgentRecoveryBinding = noteAgentRecoveryBinding
        self.searchIndexStatus = searchIndexStatus
    }

    public static let empty = NotesSnapshot(
        library: nil,
        entries: [],
        documents: [],
        selectedDocumentID: nil,
        preferences: .default,
        libraryAvailability: .unavailable,
        lastSelectedAgent: nil,
        noteAgentRecoveryBinding: nil,
        searchIndexStatus: .ready
    )
}

public enum NoteSearchIndexStatus: Equatable, Sendable {
    case ready
    case rebuilding
    case degraded(String)
}

public struct NoteSearchDocument: Equatable, Sendable {
    public let relativePath: String
    public let content: String

    public init(relativePath: String, content: String) {
        self.relativePath = relativePath
        self.content = content
    }
}

public struct NoteSearchResult: Equatable, Sendable, Identifiable {
    public let relativePath: String
    public let snippet: String
    public let line: Int

    public init(relativePath: String, snippet: String, line: Int) {
        self.relativePath = relativePath
        self.snippet = snippet
        self.line = line
    }

    public var id: String {
        "\(relativePath):\(line):\(snippet)"
    }
}

public protocol NotesRepository: Sendable {
    func loadNotesState() async throws -> NotesPersistedState
    func saveNotesState(_ state: NotesPersistedState) async throws
    func replaceNoteSearchIndex(
        libraryID: NoteLibraryID,
        documents: [NoteSearchDocument]
    ) async throws
    func searchNotes(
        libraryID: NoteLibraryID,
        query: String,
        limit: Int
    ) async throws -> [NoteSearchResult]
}

public protocol NoteFileTrashing: Sendable {
    func trashItem(at url: URL) async throws -> URL?
}

public struct MacOSNoteTrash: NoteFileTrashing, Sendable {
    public init() {}

    public func trashItem(at url: URL) async throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(
            at: url,
            resultingItemURL: &resultingURL
        )
        return resultingURL as URL?
    }
}

public enum NotesError: Error, Equatable, Sendable {
    case libraryUnavailable(String)
    case pathOutsideLibrary(String)
    case symbolicLinkNotAllowed(String)
    case unsupportedDocumentType(String)
    case documentNotOpen(NoteDocumentID)
    case invalidTextEncoding(String)
    case trashDidNotReturnLocation(String)
    case noFileOperationToUndo
    case unresolvedExternalConflict(String)
    case externallyMissing(String)
    case destinationAlreadyExists(String)
    case dirtyDocumentsBlockFileOperation([String])
    case dirtyDocumentsBlockLibraryChange([String])
    case destinationInsideSource(String)
    case fileChangedDuringMove(String)
    case moveRollbackFailed(String)
    case librarySwitchRollbackFailed(String)
}

extension NotesError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .libraryUnavailable(path):
            "笔记库不可访问：\(path)"
        case let .pathOutsideLibrary(path):
            "路径不在笔记库中：\(path)"
        case let .symbolicLinkNotAllowed(path):
            "笔记库不允许使用符号链接：\(path)"
        case let .unsupportedDocumentType(fileExtension):
            "不支持编辑 .\(fileExtension) 文件"
        case .documentNotOpen:
            "笔记标签已关闭"
        case let .invalidTextEncoding(path):
            "无法以 UTF-8 读取：\(path)"
        case let .trashDidNotReturnLocation(path):
            "无法确认文件已移入废纸篓：\(path)"
        case .noFileOperationToUndo:
            "没有可撤销的文件操作"
        case let .unresolvedExternalConflict(path):
            "请先处理外部修改冲突：\(path)"
        case let .externallyMissing(path):
            "文件已不存在，请使用“另存为”：\(path)"
        case let .destinationAlreadyExists(path):
            "目标已存在：\(path)"
        case let .dirtyDocumentsBlockFileOperation(paths):
            "请先保存或丢弃这些笔记的修改：\(paths.joined(separator: "、"))"
        case let .dirtyDocumentsBlockLibraryChange(paths):
            "更换笔记库前请处理未保存笔记：\(paths.joined(separator: "、"))"
        case let .destinationInsideSource(path):
            "不能把文件夹移动到自身内部：\(path)"
        case let .fileChangedDuringMove(path):
            "文件在移动过程中被外部修改：\(path)"
        case let .moveRollbackFailed(details):
            "移动失败且未能完整回滚：\(details)"
        case let .librarySwitchRollbackFailed(details):
            "笔记库切换失败且索引未能恢复：\(details)"
        }
    }
}

public actor NotesService {
    private let repository: any NotesRepository
    private let fileManager: FileManager
    private let trash: any NoteFileTrashing
    private var state = NotesPersistedState.empty
    private var entries: [NoteLibraryEntry] = []
    private var documents: [NoteDocument] = []
    private var selectedDocumentID: NoteDocumentID?
    private var libraryAvailability: NoteLibraryAvailability = .unavailable
    private var documentHadUTF8BOM: [NoteDocumentID: Bool] = [:]
    private var fileOperationHistory: [FileOperation] = []
    private var searchIndexNeedsRebuild = false
    private var searchIndexStatus: NoteSearchIndexStatus = .ready
    private var searchIndexFingerprint: [String: String] = [:]

    public init(
        repository: any NotesRepository,
        fileManager: FileManager = .default,
        trash: any NoteFileTrashing = MacOSNoteTrash()
    ) {
        self.repository = repository
        self.fileManager = fileManager
        self.trash = trash
    }

    @discardableResult
    public func restore() async throws -> NotesSnapshot {
        state = try await repository.loadNotesState()
        documents = []
        selectedDocumentID = nil
        documentHadUTF8BOM = [:]
        if let library = state.library {
            let rootURL = URL(
                fileURLWithPath: library.rootPath,
                isDirectory: true
            ).standardizedFileURL
            do {
                try validateLibraryRoot(rootURL)
            } catch {
                libraryAvailability = .unavailable
                entries = []
                restoreUnavailableDocuments()
                return snapshot()
            }
            libraryAvailability = .available
            entries = try scanDirectory(rootURL, rootURL: rootURL)
            let paths = state.openDocumentPaths
            for path in paths {
                let draft = state.recoveryDrafts[path]
                var document: NoteDocument
                if let loaded = try? loadDocument(relativePath: path) {
                    document = loaded
                } else if let kind = documentKind(forRelativePath: path) {
                    document = NoteDocument(
                        id: NoteDocumentID(rawValue: UUID()),
                        relativePath: normalizedRelativePath(path),
                        kind: kind,
                        content: draft?.content ?? "",
                        savedContent: draft?.savedContent ?? "",
                        externalState: .missing
                    )
                } else {
                    continue
                }
                if let draft {
                    let externalState: NoteDocumentExternalState =
                        document.externalState == .missing
                        ? .missing
                        : document.content == draft.savedContent
                            ? .inSync
                            : .conflict(diskContent: document.content)
                    document = NoteDocument(
                        id: document.id,
                        relativePath: document.relativePath,
                        kind: document.kind,
                        content: draft.content,
                        savedContent: draft.savedContent,
                        externalState: externalState
                    )
                    documentHadUTF8BOM[document.id] = draft.hadUTF8BOM
                }
                documents.append(document)
            }
            if let selectedPath = state.selectedDocumentPath {
                selectedDocumentID = documents.first(where: {
                    $0.relativePath == selectedPath
                })?.id
            }
            selectedDocumentID = selectedDocumentID ?? documents.last?.id
            try await rebuildSearchIndex()
        } else {
            entries = []
            libraryAvailability = .unavailable
        }
        return snapshot()
    }

    @discardableResult
    public func deleteItems(
        relativePaths: [String]
    ) async throws -> NotesSnapshot {
        let normalizedPaths = topLevelPaths(relativePaths)
        var trashedItems: [TrashedItem] = []
        do {
            for relativePath in normalizedPaths {
                let originalURL = try validatedItemURL(
                    relativePath: relativePath
                )
                guard let trashedURL = try await trash.trashItem(
                    at: originalURL
                ) else {
                    throw NotesError.trashDidNotReturnLocation(relativePath)
                }
                trashedItems.append(TrashedItem(
                    relativePath: relativePath,
                    originalURL: originalURL,
                    trashedURL: trashedURL
                ))
            }
        } catch {
            for item in trashedItems.reversed()
                where fileManager.fileExists(atPath: item.trashedURL.path)
                    && !fileManager.fileExists(atPath: item.originalURL.path)
            {
                try? fileManager.moveItem(
                    at: item.trashedURL,
                    to: item.originalURL
                )
            }
            throw error
        }

        let deletedPaths = Set(trashedItems.map(\.relativePath))
        let deletedIDs = documents.compactMap { document in
            deletedPaths.contains(where: {
                document.relativePath == $0
                    || document.relativePath.hasPrefix($0 + "/")
            }) ? document.id : nil
        }
        documents.removeAll { deletedIDs.contains($0.id) }
        for deletedPath in deletedPaths {
            state.recoveryDrafts = state.recoveryDrafts.filter { path, _ in
                path != deletedPath && !path.hasPrefix(deletedPath + "/")
            }
        }
        for id in deletedIDs {
            documentHadUTF8BOM.removeValue(forKey: id)
        }
        if let selectedDocumentID,
           deletedIDs.contains(selectedDocumentID)
        {
            self.selectedDocumentID = documents.last?.id
        }
        fileOperationHistory.append(.trashed(trashedItems))
        try await persistTabMetadata()
        _ = try await refreshLibrary()
        return snapshot()
    }

    @discardableResult
    public func undoLastFileOperation() async throws -> NotesSnapshot {
        guard let operation = fileOperationHistory.popLast() else {
            throw NotesError.noFileOperationToUndo
        }
        switch operation {
        case let .trashed(items):
            var restored: [TrashedItem] = []
            do {
                for item in items.reversed() {
                    try fileManager.createDirectory(
                        at: item.originalURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(
                        at: item.trashedURL,
                        to: item.originalURL
                    )
                    restored.append(item)
                }
            } catch {
                for item in restored.reversed()
                    where fileManager.fileExists(atPath: item.originalURL.path)
                        && !fileManager.fileExists(atPath: item.trashedURL.path)
                {
                    try? fileManager.moveItem(
                        at: item.originalURL,
                        to: item.trashedURL
                    )
                }
                fileOperationHistory.append(operation)
                throw error
            }
        case let .created(urls):
            do {
                for url in urls.reversed()
                    where fileManager.fileExists(atPath: url.path)
                {
                    let path = relativePath(for: url)
                    documents.removeAll {
                        $0.relativePath == path
                            || $0.relativePath.hasPrefix(path + "/")
                    }
                    guard try await trash.trashItem(at: url) != nil else {
                        throw NotesError.trashDidNotReturnLocation(path)
                    }
                }
            } catch {
                fileOperationHistory.append(operation)
                throw error
            }
        case let .moved(sourcePath, destinationPath):
            do {
                _ = try await moveItem(
                    relativePath: destinationPath,
                    destinationRelativePath: sourcePath
                )
                _ = fileOperationHistory.popLast()
            } catch {
                fileOperationHistory.append(operation)
                throw error
            }
        case let .imported(records):
            do {
                for record in records.reversed() {
                    if fileManager.fileExists(atPath: record.destinationURL.path) {
                        guard try await trash.trashItem(
                            at: record.destinationURL
                        ) != nil else {
                            throw NotesError.trashDidNotReturnLocation(
                                record.destinationURL.path
                            )
                        }
                    }
                    if let backupURL = record.backupURL {
                        try fileManager.moveItem(
                            at: backupURL,
                            to: record.destinationURL
                        )
                    }
                }
            } catch {
                fileOperationHistory.append(operation)
                throw error
            }
        }
        if let selectedDocumentID,
           !documents.contains(where: { $0.id == selectedDocumentID })
        {
            self.selectedDocumentID = documents.last?.id
        }
        try await persistTabMetadata()
        _ = try await refreshLibrary()
        return snapshot()
    }

    public func previewMove(
        relativePath: String,
        destinationRelativePath: String
    ) throws -> NoteMovePreview {
        guard let library = state.library else {
            throw NotesError.libraryUnavailable("")
        }
        let rootURL = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        ).standardizedFileURL
        _ = try validatedItemURL(relativePath: relativePath)
        _ = try validatedDestinationURL(
            relativePath: destinationRelativePath
        )
        return try MarkdownLinkRewriter.planMove(
            rootURL: rootURL,
            sourceRelativePath: normalizedRelativePath(relativePath),
            destinationRelativePath: normalizedRelativePath(
                destinationRelativePath
            ),
            fileManager: fileManager
        ).preview
    }

    @discardableResult
    public func createMarkdownDocument(
        in relativeDirectoryPath: String = ""
    ) async throws -> NoteDocument {
        let directoryURL = try validatedDirectoryURL(
            relativePath: relativeDirectoryPath
        )
        var candidateName = "未命名.md"
        var index = 2
        while fileManager.fileExists(
            atPath: directoryURL.appendingPathComponent(candidateName).path
        ) {
            candidateName = "未命名 \(index).md"
            index += 1
        }
        let url = directoryURL.appendingPathComponent(candidateName)
        try Data().write(to: url, options: .atomic)
        fileOperationHistory.append(.created([url]))
        let rootPath = state.library?.rootPath ?? directoryURL.path
        let relativePath = String(
            url.path.dropFirst(rootPath.count + 1)
        )
        let document = try await openDocument(relativePath: relativePath)
        _ = try await refreshLibrary()
        return document
    }

    @discardableResult
    public func createFolder(
        in relativeDirectoryPath: String = ""
    ) async throws -> NotesSnapshot {
        let directoryURL = try validatedDirectoryURL(
            relativePath: relativeDirectoryPath
        )
        var candidateName = "未命名文件夹"
        var index = 2
        while fileManager.fileExists(
            atPath: directoryURL.appendingPathComponent(candidateName).path
        ) {
            candidateName = "未命名文件夹 \(index)"
            index += 1
        }
        let createdURL = directoryURL.appendingPathComponent(candidateName)
        try fileManager.createDirectory(
            at: createdURL,
            withIntermediateDirectories: false
        )
        fileOperationHistory.append(.created([createdURL]))
        return try await refreshLibrary()
    }

    @discardableResult
    public func closeDocument(
        _ id: NoteDocumentID,
        decision: NoteCloseDecision
    ) async throws -> NotesSnapshot {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            throw NotesError.documentNotOpen(id)
        }
        let document = documents[index]
        if document.isDirty {
            switch decision {
            case .save:
                _ = try await saveDocument(id)
            case .discard:
                state.recoveryDrafts.removeValue(
                    forKey: document.relativePath
                )
            case .cancel:
                return snapshot()
            }
        }
        documents.removeAll { $0.id == id }
        documentHadUTF8BOM.removeValue(forKey: id)
        if selectedDocumentID == id {
            let nextIndex = min(index, documents.count - 1)
            selectedDocumentID = nextIndex >= 0
                ? documents[nextIndex].id
                : nil
        }
        try await persistTabMetadata()
        return snapshot()
    }

    @discardableResult
    public func moveDocumentTab(
        _ id: NoteDocumentID,
        to index: Int
    ) async throws -> NotesSnapshot {
        guard let sourceIndex = documents.firstIndex(where: { $0.id == id })
        else {
            throw NotesError.documentNotOpen(id)
        }
        let document = documents.remove(at: sourceIndex)
        let destination = max(0, min(index, documents.count))
        documents.insert(document, at: destination)
        try await persistTabMetadata()
        return snapshot()
    }

    @discardableResult
    public func moveItem(
        relativePath: String,
        destinationRelativePath: String
    ) async throws -> NotesSnapshot {
        guard let library = state.library else {
            throw NotesError.libraryUnavailable("")
        }
        let sourcePath = normalizedRelativePath(relativePath)
        let destinationPath = normalizedRelativePath(
            destinationRelativePath
        )
        guard !destinationPath.hasPrefix(sourcePath + "/") else {
            throw NotesError.destinationInsideSource(destinationPath)
        }
        let rootURL = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        ).standardizedFileURL
        let sourceURL = try validatedItemURL(relativePath: sourcePath)
        let destinationURL = try validatedDestinationURL(
            relativePath: destinationPath
        )
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw NotesError.destinationAlreadyExists(destinationPath)
        }
        let plan = try MarkdownLinkRewriter.planMove(
            rootURL: rootURL,
            sourceRelativePath: sourcePath,
            destinationRelativePath: destinationPath,
            fileManager: fileManager
        )
        let touchedPaths = Set(
            plan.rewrites.map(\.originalRelativePath)
                + documents.filter {
                    $0.relativePath == sourcePath
                        || $0.relativePath.hasPrefix(sourcePath + "/")
                }.map(\.relativePath)
        )
        let dirtyPaths = documents.filter {
            $0.isDirty && touchedPaths.contains($0.relativePath)
        }.map(\.relativePath)
        guard dirtyPaths.isEmpty else {
            throw NotesError.dirtyDocumentsBlockFileOperation(dirtyPaths)
        }

        let stagingURL = rootURL.appendingPathComponent(
            ".breath-notes-transaction-\(UUID().uuidString)",
            isDirectory: true
        )
        let destinationParent = destinationURL.deletingLastPathComponent()
        let destinationParentExisted = fileManager.fileExists(
            atPath: destinationParent.path
        )
        var committedRewrites: [(target: URL, backup: URL)] = []
        do {
            try fileManager.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: false
            )
            for (index, rewrite) in plan.rewrites.enumerated() {
                let originalURL = rootURL.appendingPathComponent(
                    rewrite.originalRelativePath
                )
                let originalData = encodedUTF8(
                    rewrite.originalContent,
                    withBOM: rewrite.hadUTF8BOM
                )
                guard try Data(contentsOf: originalURL) == originalData else {
                    throw NotesError.fileChangedDuringMove(
                        rewrite.originalRelativePath
                    )
                }
                try encodedUTF8(
                    rewrite.updatedContent,
                    withBOM: rewrite.hadUTF8BOM
                ).write(
                    to: stagingURL.appendingPathComponent(
                        "updated-\(index)"
                    ),
                    options: .atomic
                )
            }
            try fileManager.createDirectory(
                at: destinationParent,
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            for (index, rewrite) in plan.rewrites.enumerated() {
                let targetURL = rootURL.appendingPathComponent(
                    rewrite.futureRelativePath
                )
                let expectedData = encodedUTF8(
                    rewrite.originalContent,
                    withBOM: rewrite.hadUTF8BOM
                )
                guard try Data(contentsOf: targetURL) == expectedData else {
                    throw NotesError.fileChangedDuringMove(
                        rewrite.futureRelativePath
                    )
                }
                let backupURL = stagingURL.appendingPathComponent(
                    "backup-\(index)"
                )
                try fileManager.moveItem(at: targetURL, to: backupURL)
                do {
                    try fileManager.moveItem(
                        at: stagingURL.appendingPathComponent(
                            "updated-\(index)"
                        ),
                        to: targetURL
                    )
                    committedRewrites.append((
                        target: targetURL,
                        backup: backupURL
                    ))
                } catch {
                    try fileManager.moveItem(
                        at: backupURL,
                        to: targetURL
                    )
                    throw error
                }
            }
            try fileManager.removeItem(at: stagingURL)
        } catch {
            var rollbackErrors: [String] = []
            for committed in committedRewrites.reversed() {
                do {
                    if fileManager.fileExists(atPath: committed.target.path) {
                        try fileManager.moveItem(
                            at: committed.target,
                            to: stagingURL.appendingPathComponent(
                                "rolled-back-\(UUID().uuidString)"
                            )
                        )
                    }
                    try fileManager.moveItem(
                        at: committed.backup,
                        to: committed.target
                    )
                } catch {
                    rollbackErrors.append(error.localizedDescription)
                }
            }
            if fileManager.fileExists(atPath: destinationURL.path),
               !fileManager.fileExists(atPath: sourceURL.path)
            {
                do {
                    try fileManager.moveItem(
                        at: destinationURL,
                        to: sourceURL
                    )
                } catch {
                    rollbackErrors.append(error.localizedDescription)
                }
            }
            if rollbackErrors.isEmpty {
                try? fileManager.removeItem(at: stagingURL)
                if !destinationParentExisted {
                    try? fileManager.removeItem(at: destinationParent)
                }
                throw error
            }
            throw NotesError.moveRollbackFailed(
                rollbackErrors.joined(separator: "；")
            )
        }

        for index in documents.indices {
            let current = documents[index]
            var newPath = current.relativePath
            if current.relativePath == sourcePath
                || current.relativePath.hasPrefix(sourcePath + "/")
            {
                newPath = destinationPath
                    + current.relativePath.dropFirst(sourcePath.count)
            }
            let rewrite = plan.rewrites.first(where: {
                $0.originalRelativePath == current.relativePath
            })
            let newContent = rewrite?.updatedContent ?? current.content
            documents[index] = NoteDocument(
                id: current.id,
                relativePath: newPath,
                kind: current.kind,
                content: newContent,
                savedContent: newContent
            )
        }
        fileOperationHistory.append(.moved(
            sourcePath: sourcePath,
            destinationPath: destinationPath
        ))
        try await persistTabMetadata()
        _ = try await refreshLibrary()
        return snapshot()
    }

    @discardableResult
    public func selectLibrary(
        at url: URL,
        discardUnsavedChanges: Bool = false
    ) async throws -> NotesSnapshot {
        let dirtyPaths = documents.filter(\.isDirty).map(\.relativePath)
        if !dirtyPaths.isEmpty, !discardUnsavedChanges {
            throw NotesError.dirtyDocumentsBlockLibraryChange(dirtyPaths)
        }
        let rootURL = url.standardizedFileURL
        try validateLibraryRoot(rootURL)
        if state.library?.rootPath == rootURL.path {
            return snapshot()
        }
        let existingID = state.library.flatMap {
            $0.rootPath == rootURL.path ? $0.id : nil
        }
        let nextLibrary = NoteLibrary(
            id: existingID ?? NoteLibraryID(rawValue: UUID()),
            rootPath: rootURL.path
        )
        let nextEntries = try scanDirectory(rootURL, rootURL: rootURL)
        let nextIndexedDocuments = try searchDocuments(
            entries: nextEntries,
            rootURL: rootURL
        )
        let nextState = NotesPersistedState(
            library: NoteLibrary(
                id: nextLibrary.id,
                rootPath: rootURL.path
            ),
            preferences: state.preferences,
            lastSelectedAgent: state.lastSelectedAgent,
            noteAgentRecoveryBinding: nil
        )
        let previousIndex: (
            libraryID: NoteLibraryID,
            documents: [NoteSearchDocument]
        )? = try state.library.map { previousLibrary in
            let previousRoot = URL(
                fileURLWithPath: previousLibrary.rootPath,
                isDirectory: true
            )
            return (
                previousLibrary.id,
                try searchDocuments(
                    entries: entries,
                    rootURL: previousRoot
                )
            )
        }
        do {
            try await repository.replaceNoteSearchIndex(
                libraryID: nextLibrary.id,
                documents: nextIndexedDocuments
            )
            try await repository.saveNotesState(nextState)
        } catch {
            if let previousIndex {
                do {
                    try await repository.replaceNoteSearchIndex(
                        libraryID: previousIndex.libraryID,
                        documents: previousIndex.documents
                    )
                } catch {
                    throw NotesError.librarySwitchRollbackFailed(
                        error.localizedDescription
                    )
                }
            }
            throw error
        }

        state = nextState
        documents = []
        selectedDocumentID = nil
        documentHadUTF8BOM = [:]
        entries = nextEntries
        libraryAvailability = .available
        searchIndexNeedsRebuild = false
        searchIndexStatus = .ready
        searchIndexFingerprint = try indexFingerprint(
            entries: nextEntries,
            rootURL: rootURL
        )
        return snapshot()
    }

    @discardableResult
    public func openDocument(relativePath: String) async throws -> NoteDocument {
        if let existing = documents.first(where: {
            $0.relativePath == normalizedRelativePath(relativePath)
        }) {
            selectedDocumentID = existing.id
            try await persistTabMetadata()
            return existing
        }

        let document = try loadDocument(relativePath: relativePath)
        documents.append(document)
        selectedDocumentID = document.id
        try await persistTabMetadata()
        return document
    }

    @discardableResult
    public func selectDocument(
        _ id: NoteDocumentID
    ) async throws -> NotesSnapshot {
        guard documents.contains(where: { $0.id == id }) else {
            throw NotesError.documentNotOpen(id)
        }
        selectedDocumentID = id
        try await persistTabMetadata()
        return snapshot()
    }

    @discardableResult
    public func refreshLibrary() async throws -> NotesSnapshot {
        guard let library = state.library else {
            return snapshot()
        }
        let rootURL = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        ).standardizedFileURL
        do {
            try validateLibraryRoot(rootURL)
        } catch {
            libraryAvailability = .unavailable
            throw error
        }
        libraryAvailability = .available
        let previousEntries = entries
        entries = try scanDirectory(rootURL, rootURL: rootURL)
        try reconcileOpenDocuments()
        let nextFingerprint = try indexFingerprint(
            entries: entries,
            rootURL: rootURL
        )
        if entries != previousEntries
            || searchIndexNeedsRebuild
            || nextFingerprint != searchIndexFingerprint
        {
            try await rebuildSearchIndex()
        }
        return snapshot()
    }

    @discardableResult
    public func updateDocument(
        _ id: NoteDocumentID,
        content: String
    ) async throws -> NoteDocument {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            throw NotesError.documentNotOpen(id)
        }
        let current = documents[index]
        let updated = NoteDocument(
            id: current.id,
            relativePath: current.relativePath,
            kind: current.kind,
            content: content,
            savedContent: current.savedContent,
            externalState: current.externalState
        )
        documents[index] = updated
        selectedDocumentID = id
        state.recoveryDrafts[current.relativePath] = NoteRecoveryDraft(
            relativePath: current.relativePath,
            content: content,
            savedContent: current.savedContent,
            hadUTF8BOM: documentHadUTF8BOM[id] == true
        )
        try await repository.saveNotesState(state)
        return updated
    }

    @discardableResult
    public func saveDocument(_ id: NoteDocumentID) async throws -> NoteDocument {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            throw NotesError.documentNotOpen(id)
        }
        let current = documents[index]
        switch current.externalState {
        case .inSync:
            break
        case .conflict:
            throw NotesError.unresolvedExternalConflict(current.relativePath)
        case .missing:
            throw NotesError.externallyMissing(current.relativePath)
        }
        return try await writeDocument(at: index)
    }

    @discardableResult
    public func saveDocument(
        _ id: NoteDocumentID,
        as relativePath: String
    ) async throws -> NoteDocument {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            throw NotesError.documentNotOpen(id)
        }
        let normalized = normalizedRelativePath(relativePath)
        guard documentKind(forRelativePath: normalized) != nil else {
            throw NotesError.unsupportedDocumentType(
                URL(fileURLWithPath: normalized).pathExtension
            )
        }
        let destination = try validatedDestinationURL(
            relativePath: normalized
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw NotesError.destinationAlreadyExists(normalized)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let current = documents[index]
        var data = Data()
        if documentHadUTF8BOM[current.id] == true {
            data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        }
        data.append(Data(current.content.utf8))
        try data.write(to: destination, options: .atomic)
        let saved = NoteDocument(
            id: current.id,
            relativePath: normalized,
            kind: current.kind,
            content: current.content,
            savedContent: current.content
        )
        documents[index] = saved
        state.recoveryDrafts.removeValue(forKey: current.relativePath)
        fileOperationHistory.append(.created([destination]))
        try await persistTabMetadata()
        _ = try await refreshLibrary()
        return saved
    }

    public func searchLibrary(
        for query: String,
        limit: Int = 100
    ) async throws -> [NoteSearchResult] {
        guard let library = state.library else {
            throw NotesError.libraryUnavailable("")
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await repository.searchNotes(
            libraryID: library.id,
            query: trimmed,
            limit: max(1, min(limit, 500))
        )
    }

    public func rebuildSearchIndex() async throws {
        guard let library = state.library else { return }
        searchIndexStatus = .rebuilding
        let rootURL = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        )
        do {
            let indexedDocuments = try searchDocuments(
                entries: entries,
                rootURL: rootURL
            )
            try await repository.replaceNoteSearchIndex(
                libraryID: library.id,
                documents: indexedDocuments
            )
            searchIndexFingerprint = try indexFingerprint(
                entries: entries,
                rootURL: rootURL
            )
            searchIndexNeedsRebuild = false
            searchIndexStatus = .ready
        } catch {
            searchIndexNeedsRebuild = true
            searchIndexStatus = .degraded(error.localizedDescription)
            throw error
        }
    }

    @discardableResult
    public func updatePreferences(
        _ preferences: NotesPreferences
    ) async throws -> NotesSnapshot {
        state.preferences = preferences
        try await repository.saveNotesState(state)
        return snapshot()
    }

    @discardableResult
    public func updateNoteAgentPersistence(
        lastSelectedAgent: AgentKind?,
        recoveryBinding: NoteAgentRecoveryBinding?
    ) async throws -> NotesSnapshot {
        state.lastSelectedAgent = lastSelectedAgent
        state.noteAgentRecoveryBinding = recoveryBinding
        try await repository.saveNotesState(state)
        return snapshot()
    }

    public func prepareForTermination(
        decision: NoteCloseDecision
    ) async throws -> Bool {
        let dirtyIDs = documents.filter(\.isDirty).map(\.id)
        guard !dirtyIDs.isEmpty else { return true }
        switch decision {
        case .cancel:
            return false
        case .save:
            for id in dirtyIDs {
                _ = try await saveDocument(id)
            }
        case .discard:
            for document in documents where document.isDirty {
                state.recoveryDrafts.removeValue(
                    forKey: document.relativePath
                )
            }
            try await repository.saveNotesState(state)
        }
        return true
    }

    @discardableResult
    public func importAttachment(
        data: Data,
        suggestedFilename: String
    ) async throws -> String {
        let attachmentsURL = try attachmentsDirectoryURL()
        let rawName = URL(
            fileURLWithPath: suggestedFilename
        ).lastPathComponent
        let safeName = rawName.isEmpty || rawName == "." || rawName == ".."
            ? "附件"
            : rawName
        let destination = collisionSafeURL(
            named: safeName,
            in: attachmentsURL
        )
        try data.write(to: destination, options: .atomic)
        fileOperationHistory.append(.created([destination]))
        _ = try await refreshLibrary()
        return relativePath(for: destination)
    }

    @discardableResult
    public func importItems(
        _ sourceURLs: [URL],
        into relativeDirectoryPath: String = "",
        conflictResolution: NoteImportConflictResolution
    ) async throws -> [NoteImportResult] {
        let directory = try validatedDirectoryURL(
            relativePath: relativeDirectoryPath
        )
        var records: [ImportedItem] = []
        var results: [NoteImportResult] = []
        do {
            for sourceURL in sourceURLs {
                let source = sourceURL.standardizedFileURL
                try validateImportSource(source)
                let initialDestination = directory.appendingPathComponent(
                    source.lastPathComponent
                )
                let destination: URL
                var backupURL: URL?
                if fileManager.fileExists(atPath: initialDestination.path) {
                    switch conflictResolution {
                    case .keepBoth:
                        destination = collisionSafeURL(
                            named: source.lastPathComponent,
                            in: directory
                        )
                    case .cancel:
                        throw NotesError.destinationAlreadyExists(
                            relativePath(for: initialDestination)
                        )
                    case .replace:
                        destination = initialDestination
                        let backupDirectory = fileManager.temporaryDirectory
                            .appendingPathComponent(
                                "breath-note-import-\(UUID().uuidString)",
                                isDirectory: true
                            )
                        try fileManager.createDirectory(
                            at: backupDirectory,
                            withIntermediateDirectories: false
                        )
                        let backup = backupDirectory.appendingPathComponent(
                            source.lastPathComponent
                        )
                        try fileManager.moveItem(
                            at: initialDestination,
                            to: backup
                        )
                        backupURL = backup
                    }
                } else {
                    destination = initialDestination
                }
                do {
                    try fileManager.copyItem(at: source, to: destination)
                } catch {
                    if let backupURL {
                        try? fileManager.moveItem(
                            at: backupURL,
                            to: destination
                        )
                    }
                    throw error
                }
                records.append(ImportedItem(
                    destinationURL: destination,
                    backupURL: backupURL
                ))
                results.append(NoteImportResult(
                    sourceURL: source,
                    relativePath: relativePath(for: destination)
                ))
            }
        } catch {
            for record in records.reversed() {
                try? fileManager.removeItem(at: record.destinationURL)
                if let backupURL = record.backupURL {
                    try? fileManager.moveItem(
                        at: backupURL,
                        to: record.destinationURL
                    )
                }
            }
            throw error
        }
        fileOperationHistory.append(.imported(records))
        _ = try await refreshLibrary()
        return results
    }

    @discardableResult
    public func resolveExternalConflict(
        _ id: NoteDocumentID,
        resolution: NoteExternalConflictResolution
    ) async throws -> NoteDocument {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            throw NotesError.documentNotOpen(id)
        }
        switch resolution {
        case .overwriteDisk:
            let current = documents[index]
            guard case .conflict = current.externalState else {
                return current
            }
            documents[index] = NoteDocument(
                id: current.id,
                relativePath: current.relativePath,
                kind: current.kind,
                content: current.content,
                savedContent: current.savedContent
            )
            return try await writeDocument(at: index)
        case .reloadDisk:
            let current = documents[index]
            let url = try validatedDocumentURL(
                relativePath: current.relativePath
            )
            let decoded = try decodeText(
                Data(contentsOf: url),
                path: current.relativePath
            )
            let reloaded = NoteDocument(
                id: current.id,
                relativePath: current.relativePath,
                kind: current.kind,
                content: decoded.content,
                savedContent: decoded.content
            )
            documents[index] = reloaded
            documentHadUTF8BOM[id] = decoded.hadUTF8BOM
            state.recoveryDrafts.removeValue(forKey: current.relativePath)
            try await repository.saveNotesState(state)
            return reloaded
        }
    }

    private func writeDocument(at index: Int) async throws -> NoteDocument {
        let current = documents[index]
        let documentURL = try validatedDocumentURL(
            relativePath: current.relativePath
        )
        var data = Data()
        if documentHadUTF8BOM[current.id] == true {
            data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        }
        data.append(Data(current.content.utf8))
        try data.write(to: documentURL, options: .atomic)

        let saved = NoteDocument(
            id: current.id,
            relativePath: current.relativePath,
            kind: current.kind,
            content: current.content,
            savedContent: current.content
        )
        documents[index] = saved
        state.recoveryDrafts.removeValue(forKey: current.relativePath)
        try await repository.saveNotesState(state)
        if let library = state.library {
            let rootURL = URL(
                fileURLWithPath: library.rootPath,
                isDirectory: true
            ).standardizedFileURL
            entries = try scanDirectory(rootURL, rootURL: rootURL)
            do {
                try await rebuildSearchIndex()
            } catch {
                searchIndexNeedsRebuild = true
            }
        }
        return saved
    }

    public func snapshot() -> NotesSnapshot {
        NotesSnapshot(
            library: state.library,
            entries: entries,
            documents: documents,
            selectedDocumentID: selectedDocumentID,
            preferences: state.preferences,
            libraryAvailability: libraryAvailability,
            lastSelectedAgent: state.lastSelectedAgent,
            noteAgentRecoveryBinding: state.noteAgentRecoveryBinding,
            searchIndexStatus: searchIndexStatus
        )
    }

    private func persistTabMetadata() async throws {
        state.openDocumentPaths = documents.map(\.relativePath)
        state.selectedDocumentPath = documents.first(where: {
            $0.id == selectedDocumentID
        })?.relativePath
        try await repository.saveNotesState(state)
    }

    private func restoreUnavailableDocuments() {
        documents = state.openDocumentPaths.compactMap { path in
            guard let kind = documentKind(forRelativePath: path) else {
                return nil
            }
            let draft = state.recoveryDrafts[path]
            let document = NoteDocument(
                id: NoteDocumentID(rawValue: UUID()),
                relativePath: normalizedRelativePath(path),
                kind: kind,
                content: draft?.content ?? "",
                savedContent: draft?.savedContent ?? "",
                externalState: .missing
            )
            if let draft {
                documentHadUTF8BOM[document.id] = draft.hadUTF8BOM
            }
            return document
        }
        if let selectedPath = state.selectedDocumentPath {
            selectedDocumentID = documents.first(where: {
                $0.relativePath == selectedPath
            })?.id
        }
        selectedDocumentID = selectedDocumentID ?? documents.last?.id
    }

    private func loadDocument(relativePath: String) throws -> NoteDocument {
        let documentURL = try validatedDocumentURL(relativePath: relativePath)
        let kind = try documentKind(for: documentURL)
        let data = try Data(contentsOf: documentURL)
        let decoded = try decodeText(data, path: relativePath)
        let document = NoteDocument(
            id: NoteDocumentID(rawValue: UUID()),
            relativePath: normalizedRelativePath(relativePath),
            kind: kind,
            content: decoded.content,
            savedContent: decoded.content
        )
        documentHadUTF8BOM[document.id] = decoded.hadUTF8BOM
        return document
    }

    private func reconcileOpenDocuments() throws {
        for index in documents.indices {
            let current = documents[index]
            let url = try validatedItemURL(
                relativePath: current.relativePath
            )
            guard fileManager.fileExists(atPath: url.path) else {
                documents[index] = NoteDocument(
                    id: current.id,
                    relativePath: current.relativePath,
                    kind: current.kind,
                    content: current.content,
                    savedContent: current.savedContent,
                    externalState: .missing
                )
                continue
            }
            let decoded = try decodeText(
                Data(contentsOf: url),
                path: current.relativePath
            )
            if decoded.content == current.savedContent {
                if current.externalState != .inSync {
                    documents[index] = NoteDocument(
                        id: current.id,
                        relativePath: current.relativePath,
                        kind: current.kind,
                        content: current.content,
                        savedContent: current.savedContent
                    )
                }
                continue
            }
            if current.isDirty {
                documents[index] = NoteDocument(
                    id: current.id,
                    relativePath: current.relativePath,
                    kind: current.kind,
                    content: current.content,
                    savedContent: current.savedContent,
                    externalState: .conflict(
                        diskContent: decoded.content
                    )
                )
            } else {
                documents[index] = NoteDocument(
                    id: current.id,
                    relativePath: current.relativePath,
                    kind: current.kind,
                    content: decoded.content,
                    savedContent: decoded.content
                )
                documentHadUTF8BOM[current.id] = decoded.hadUTF8BOM
            }
        }
    }

    private func validateLibraryRoot(_ rootURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: rootURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw NotesError.libraryUnavailable(rootURL.path)
        }
        let values = try rootURL.resourceValues(forKeys: [
            .isSymbolicLinkKey,
            .isReadableKey,
        ])
        guard values.isSymbolicLink != true else {
            throw NotesError.symbolicLinkNotAllowed(rootURL.path)
        }
        guard values.isReadable != false else {
            throw NotesError.libraryUnavailable(rootURL.path)
        }
    }

    private func validatedDocumentURL(relativePath: String) throws -> URL {
        try validatedItemURL(relativePath: relativePath)
    }

    private func validatedItemURL(relativePath: String) throws -> URL {
        guard let library = state.library else {
            throw NotesError.libraryUnavailable("")
        }
        let rootURL = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        ).standardizedFileURL
        try validateLibraryRoot(rootURL)
        let normalized = normalizedRelativePath(relativePath)
        guard !normalized.isEmpty, !NSString(string: normalized).isAbsolutePath else {
            throw NotesError.pathOutsideLibrary(relativePath)
        }
        let candidate = rootURL
            .appendingPathComponent(normalized)
            .standardizedFileURL
        let boundary = rootURL.path.hasSuffix("/")
            ? rootURL.path
            : rootURL.path + "/"
        guard candidate.path.hasPrefix(boundary) else {
            throw NotesError.pathOutsideLibrary(relativePath)
        }

        var cursor = rootURL
        for component in normalized.split(separator: "/") {
            cursor.appendPathComponent(String(component))
            if fileManager.fileExists(atPath: cursor.path) {
                let values = try cursor.resourceValues(forKeys: [
                    .isSymbolicLinkKey,
                ])
                if values.isSymbolicLink == true {
                    throw NotesError.symbolicLinkNotAllowed(relativePath)
                }
            }
        }
        return candidate
    }

    private func validatedDestinationURL(
        relativePath: String
    ) throws -> URL {
        guard let library = state.library else {
            throw NotesError.libraryUnavailable("")
        }
        let rootURL = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        ).standardizedFileURL
        let normalized = normalizedRelativePath(relativePath)
        guard !normalized.isEmpty,
              !NSString(string: normalized).isAbsolutePath
        else {
            throw NotesError.pathOutsideLibrary(relativePath)
        }
        let candidate = rootURL
            .appendingPathComponent(normalized)
            .standardizedFileURL
        let boundary = rootURL.path.hasSuffix("/")
            ? rootURL.path
            : rootURL.path + "/"
        guard candidate.path.hasPrefix(boundary) else {
            throw NotesError.pathOutsideLibrary(relativePath)
        }
        var cursor = rootURL
        for component in normalized.split(separator: "/").dropLast() {
            cursor.appendPathComponent(String(component))
            if fileManager.fileExists(atPath: cursor.path) {
                let values = try cursor.resourceValues(forKeys: [
                    .isSymbolicLinkKey,
                ])
                if values.isSymbolicLink == true {
                    throw NotesError.symbolicLinkNotAllowed(relativePath)
                }
            }
        }
        return candidate
    }

    private func validatedDirectoryURL(
        relativePath: String
    ) throws -> URL {
        guard let library = state.library else {
            throw NotesError.libraryUnavailable("")
        }
        if relativePath.isEmpty {
            let root = URL(
                fileURLWithPath: library.rootPath,
                isDirectory: true
            ).standardizedFileURL
            try validateLibraryRoot(root)
            return root
        }
        let url = try validatedItemURL(relativePath: relativePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw NotesError.libraryUnavailable(url.path)
        }
        return url
    }

    private func attachmentsDirectoryURL() throws -> URL {
        guard let library = state.library else {
            throw NotesError.libraryUnavailable("")
        }
        let rootURL = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        ).standardizedFileURL
        try validateLibraryRoot(rootURL)
        let attachmentsURL = rootURL.appendingPathComponent(
            "_attachments",
            isDirectory: true
        )
        if !fileManager.fileExists(atPath: attachmentsURL.path) {
            try fileManager.createDirectory(
                at: attachmentsURL,
                withIntermediateDirectories: false
            )
        }
        return try validatedDirectoryURL(relativePath: "_attachments")
    }

    private func topLevelPaths(_ paths: [String]) -> [String] {
        let normalized = Array(Set(paths.map(normalizedRelativePath))).sorted()
        return normalized.filter { path in
            !normalized.contains(where: {
                $0 != path && path.hasPrefix($0 + "/")
            })
        }
    }

    private func scanDirectory(
        _ directoryURL: URL,
        rootURL: URL
    ) throws -> [NoteLibraryEntry] {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .creationDateKey,
            .contentModificationDateKey,
        ]
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )
        var scanned: [NoteLibraryEntry] = []
        for childURL in childURLs where !childURL.lastPathComponent.hasPrefix(".") {
            let values = try childURL.resourceValues(forKeys: resourceKeys)
            guard values.isSymbolicLink != true else { continue }
            let relativePath = String(
                childURL.standardizedFileURL.path
                    .dropFirst(rootURL.path.count + 1)
            )
            if values.isDirectory == true {
                scanned.append(NoteLibraryEntry(
                    relativePath: relativePath,
                    name: childURL.lastPathComponent,
                    kind: .folder,
                    children: try scanDirectory(childURL, rootURL: rootURL),
                    creationDate: values.creationDate,
                    modificationDate: values.contentModificationDate
                ))
            } else {
                scanned.append(NoteLibraryEntry(
                    relativePath: relativePath,
                    name: childURL.lastPathComponent,
                    kind: libraryEntryKind(for: childURL),
                    creationDate: values.creationDate,
                    modificationDate: values.contentModificationDate
                ))
            }
        }
        return scanned.sorted { lhs, rhs in
            if (lhs.kind == .folder) != (rhs.kind == .folder) {
                return lhs.kind == .folder
            }
            return lhs.name.localizedStandardCompare(rhs.name)
                == .orderedAscending
        }
    }

    private func flattened(
        _ entries: [NoteLibraryEntry]
    ) -> [NoteLibraryEntry] {
        entries.flatMap { [$0] + flattened($0.children) }
    }

    private func searchDocuments(
        entries: [NoteLibraryEntry],
        rootURL: URL
    ) throws -> [NoteSearchDocument] {
        try flattened(entries).compactMap { entry in
            guard entry.kind == .markdown || entry.kind == .plainText else {
                return nil
            }
            let url = rootURL.appendingPathComponent(entry.relativePath)
            let data = try Data(contentsOf: url)
            let bom = Data([0xEF, 0xBB, 0xBF])
            let body = data.starts(with: bom) ? data.dropFirst(3) : data[...]
            guard let content = String(data: body, encoding: .utf8) else {
                return nil
            }
            return NoteSearchDocument(
                relativePath: entry.relativePath,
                content: content
            )
        }
    }

    private func indexFingerprint(
        entries: [NoteLibraryEntry],
        rootURL: URL
    ) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: flattened(entries).compactMap {
            entry in
            guard entry.kind == .markdown || entry.kind == .plainText else {
                return nil
            }
            let values = try rootURL.appendingPathComponent(
                entry.relativePath
            ).resourceValues(forKeys: [
                .fileResourceIdentifierKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ])
            let identifier = values.fileResourceIdentifier
                .map { String(describing: $0) } ?? ""
            let size = values.fileSize.map(String.init) ?? ""
            let modification = values.contentModificationDate
                .map { String($0.timeIntervalSinceReferenceDate) } ?? ""
            return (
                entry.relativePath,
                "\(identifier)|\(size)|\(modification)"
            )
        })
    }

    private func libraryEntryKind(for url: URL) -> NoteLibraryEntryKind {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "txt":
            return .plainText
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg":
            return .image
        case "pdf":
            return .pdf
        default:
            return .attachment
        }
    }

    private func normalizedRelativePath(_ path: String) -> String {
        let standardized = NSString(string: path).standardizingPath
        if standardized == "." {
            return ""
        }
        return standardized.hasPrefix("./")
            ? String(standardized.dropFirst(2))
            : standardized
    }

    private func documentKind(for url: URL) throws -> NoteDocumentKind {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "txt":
            return .plainText
        default:
            throw NotesError.unsupportedDocumentType(url.pathExtension)
        }
    }

    private func documentKind(
        forRelativePath path: String
    ) -> NoteDocumentKind? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "txt":
            return .plainText
        default:
            return nil
        }
    }

    private func collisionSafeURL(named name: String, in directory: URL) -> URL {
        let sourceURL = URL(fileURLWithPath: name)
        let fileExtension = sourceURL.pathExtension
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let numberedName = fileExtension.isEmpty
                ? "\(stem) \(index)"
                : "\(stem) \(index).\(fileExtension)"
            candidate = directory.appendingPathComponent(numberedName)
            index += 1
        }
        return candidate
    }

    private func relativePath(for url: URL) -> String {
        guard let rootPath = state.library?.rootPath else {
            return url.lastPathComponent
        }
        let boundary = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(boundary)
            ? String(path.dropFirst(boundary.count))
            : url.lastPathComponent
    }

    private func validateImportSource(_ sourceURL: URL) throws {
        let values = try sourceURL.resourceValues(forKeys: [
            .isSymbolicLinkKey,
            .isDirectoryKey,
        ])
        guard values.isSymbolicLink != true else {
            throw NotesError.symbolicLinkNotAllowed(sourceURL.path)
        }
        guard values.isDirectory == true else { return }
        guard let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for case let url as URL in enumerator {
            if try url.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink == true {
                throw NotesError.symbolicLinkNotAllowed(url.path)
            }
        }
    }

    private func decodeText(
        _ data: Data,
        path: String
    ) throws -> (content: String, hadUTF8BOM: Bool) {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let hadUTF8BOM = data.starts(with: bom)
        let body = hadUTF8BOM ? data.dropFirst(3) : data[...]
        guard let content = String(data: body, encoding: .utf8) else {
            throw NotesError.invalidTextEncoding(path)
        }
        return (content, hadUTF8BOM)
    }

    private func encodedUTF8(_ content: String, withBOM: Bool) -> Data {
        var data = Data()
        if withBOM {
            data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        }
        data.append(Data(content.utf8))
        return data
    }
}

private struct TrashedItem: Sendable {
    let relativePath: String
    let originalURL: URL
    let trashedURL: URL
}

private enum FileOperation: Sendable {
    case trashed([TrashedItem])
    case created([URL])
    case moved(sourcePath: String, destinationPath: String)
    case imported([ImportedItem])
}

private struct ImportedItem: Sendable {
    let destinationURL: URL
    let backupURL: URL?
}
