import AppKit
import BreathCore
import BreathNotes
import Foundation

@MainActor
final class NotesApplicationModel: ObservableObject {
    @Published private(set) var snapshot: NotesSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var sourceModeDocumentIDs: Set<NoteDocumentID> = []
    @Published private(set) var searchResults: [NoteSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var inlineRenameRequest: String?
    @Published var searchQuery = ""
    @Published private(set) var previewedImageURL: URL?
    @Published var lastError: String?

    private let service: NotesService
    private var searchTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var pendingEdits: [NoteDocumentID: String] = [:]
    private var recoveryTasks: [NoteDocumentID: Task<Void, Never>] = [:]

    init(service: NotesService) {
        self.service = service
    }

    var selectedDocument: NoteDocument? {
        snapshot.documents.first(where: {
            $0.id == snapshot.selectedDocumentID
        })
    }

    var isLibraryAvailable: Bool {
        snapshot.library != nil
            && snapshot.libraryAvailability == .available
    }

    var hasDirtyDocuments: Bool {
        snapshot.documents.contains(where: \.isDirty)
    }

    func restore() async {
        await perform {
            self.applyServiceSnapshot(try await self.service.restore())
        }
        startMonitoring()
    }

    func selectLibrary(
        _ url: URL,
        discardUnsavedChanges: Bool = false
    ) {
        Task {
            await perform {
                if !discardUnsavedChanges {
                    try await self.flushPendingEdits()
                }
                let previousDocumentIDs = self.snapshot.documents.map(\.id)
                let selected = try await self.service.selectLibrary(
                    at: url,
                    discardUnsavedChanges: discardUnsavedChanges
                )
                self.cancelPendingEdits(ids: previousDocumentIDs)
                self.applyServiceSnapshot(selected)
            }
        }
    }

    func open(_ entry: NoteLibraryEntry) {
        switch entry.kind {
        case .markdown, .plainText:
            previewedImageURL = nil
            Task {
                await perform {
                    _ = try await self.service.openDocument(
                        relativePath: entry.relativePath
                    )
                    self.applyServiceSnapshot(await self.service.snapshot())
                    if let document = self.selectedDocument,
                       document.kind == .plainText
                        || NoteDocumentComplexity.analyze(document.content)
                            .recommendedMode == .source
                    {
                        self.sourceModeDocumentIDs.insert(document.id)
                    }
                }
            }
        case .image:
            guard let url = libraryURL?.appendingPathComponent(
                entry.relativePath
            ) else { return }
            previewedImageURL = url
        case .pdf, .attachment:
            guard let url = libraryURL?.appendingPathComponent(
                entry.relativePath
            ) else { return }
            NSWorkspace.shared.open(url)
        case .folder:
            break
        }
    }

    func selectDocument(_ id: NoteDocumentID) {
        Task {
            await perform {
                self.applyServiceSnapshot(
                    try await self.service.selectDocument(id)
                )
            }
        }
    }

    func updateDocument(_ id: NoteDocumentID, content: String) {
        guard let current = snapshot.documents.first(where: { $0.id == id })
        else { return }
        replaceDocument(
            NoteDocument(
                id: current.id,
                relativePath: current.relativePath,
                kind: current.kind,
                content: content,
                savedContent: current.savedContent,
                externalState: current.externalState
            )
        )
        pendingEdits[id] = content
        recoveryTasks[id]?.cancel()
        recoveryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.flushPendingEdits(ids: [id])
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    func saveSelectedDocument() {
        guard let id = snapshot.selectedDocumentID else { return }
        Task {
            await perform {
                try await self.flushPendingEdits(ids: [id])
                _ = try await self.service.saveDocument(id)
                self.applyServiceSnapshot(await self.service.snapshot())
            }
        }
    }

    func saveDocument(_ id: NoteDocumentID) {
        Task {
            await perform {
                try await self.flushPendingEdits(ids: [id])
                _ = try await self.service.saveDocument(id)
                self.applyServiceSnapshot(await self.service.snapshot())
            }
        }
    }

    func saveDocument(
        _ id: NoteDocumentID,
        as relativePath: String
    ) async throws -> NoteDocument {
        try await flushPendingEdits(ids: [id])
        let document = try await service.saveDocument(id, as: relativePath)
        applyServiceSnapshot(await service.snapshot())
        lastError = nil
        return document
    }

    func closeDocument(
        _ id: NoteDocumentID,
        decision: NoteCloseDecision
    ) {
        Task {
            await perform {
                if decision == .save {
                    try await self.flushPendingEdits(ids: [id])
                } else if decision == .discard {
                    self.cancelPendingEdits(ids: [id])
                }
                self.applyServiceSnapshot(
                    try await self.service.closeDocument(
                        id,
                        decision: decision
                    )
                )
                self.sourceModeDocumentIDs.remove(id)
            }
        }
    }

    func closeDocuments(
        _ ids: [NoteDocumentID],
        decision: NoteCloseDecision
    ) {
        Task {
            await perform {
                if decision == .save {
                    try await self.flushPendingEdits(ids: ids)
                } else if decision == .discard {
                    self.cancelPendingEdits(ids: ids)
                }
                for id in ids {
                    self.applyServiceSnapshot(
                        try await self.service.closeDocument(
                            id,
                            decision: decision
                        )
                    )
                    self.sourceModeDocumentIDs.remove(id)
                }
            }
        }
    }

    func moveDocumentTab(_ id: NoteDocumentID, to index: Int) {
        Task {
            await perform {
                self.applyServiceSnapshot(
                    try await self.service.moveDocumentTab(
                        id,
                        to: index
                    )
                )
            }
        }
    }

    func createMarkdownDocument(in directory: String = "") {
        Task {
            await perform {
                let document = try await self.service.createMarkdownDocument(
                    in: directory
                )
                self.applyServiceSnapshot(await self.service.snapshot())
                self.inlineRenameRequest = document.relativePath
            }
        }
    }

    func createFolder(in directory: String = "") {
        Task {
            await perform {
                let existingPaths = Set(
                    self.flattenedEntries(self.snapshot.entries)
                        .map(\.relativePath)
                )
                self.applyServiceSnapshot(
                    try await self.service.createFolder(
                        in: directory
                    )
                )
                self.inlineRenameRequest = self.flattenedEntries(
                    self.snapshot.entries
                ).first {
                    $0.kind == .folder
                        && !existingPaths.contains($0.relativePath)
                }?.relativePath
            }
        }
    }

    func consumeInlineRenameRequest() {
        inlineRenameRequest = nil
    }

    func deleteItems(_ paths: [String]) {
        Task {
            await perform {
                let ids = self.snapshot.documents.filter { document in
                    paths.contains {
                        document.relativePath == $0
                            || document.relativePath.hasPrefix($0 + "/")
                    }
                }.map(\.id)
                self.cancelPendingEdits(ids: ids)
                self.applyServiceSnapshot(
                    try await self.service.deleteItems(
                        relativePaths: paths
                    )
                )
            }
        }
    }

    func undoLastFileOperation() {
        Task {
            await perform {
                self.applyServiceSnapshot(
                    try await self.service.undoLastFileOperation()
                )
            }
        }
    }

    func moveItem(from source: String, to destination: String) {
        Task {
            await perform {
                try await self.flushPendingEdits()
                self.applyServiceSnapshot(
                    try await self.service.moveItem(
                        relativePath: source,
                        destinationRelativePath: destination
                    )
                )
            }
        }
    }

    func previewMove(
        from source: String,
        to destination: String
    ) async throws -> NoteMovePreview {
        try await flushPendingEdits()
        return try await service.previewMove(
            relativePath: source,
            destinationRelativePath: destination
        )
    }

    func resolveConflict(
        _ id: NoteDocumentID,
        resolution: NoteExternalConflictResolution
    ) {
        Task {
            await perform {
                if resolution == .overwriteDisk {
                    try await self.flushPendingEdits(ids: [id])
                } else {
                    self.cancelPendingEdits(ids: [id])
                }
                _ = try await self.service.resolveExternalConflict(
                    id,
                    resolution: resolution
                )
                self.applyServiceSnapshot(await self.service.snapshot())
            }
        }
    }

    func updatePreferences(_ transform: (inout NotesPreferences) -> Void) {
        var preferences = snapshot.preferences
        transform(&preferences)
        Task {
            await perform {
                self.applyServiceSnapshot(
                    try await self.service.updatePreferences(
                        preferences
                    )
                )
            }
        }
    }

    func searchLibrary(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            do {
                let results = try await service.searchLibrary(for: query)
                guard !Task.isCancelled, searchQuery == query else { return }
                searchResults = results
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                isSearching = false
                lastError = error.localizedDescription
            }
        }
    }

    func rebuildSearchIndex() {
        Task {
            await perform {
                do {
                    try await self.service.rebuildSearchIndex()
                } catch {
                    self.applyServiceSnapshot(await self.service.snapshot())
                    throw error
                }
                self.applyServiceSnapshot(await self.service.snapshot())
            }
        }
    }

    func importAttachment(
        data: Data,
        filename: String
    ) async -> String? {
        do {
            let path = try await service.importAttachment(
                data: data,
                suggestedFilename: filename
            )
            applyServiceSnapshot(await service.snapshot())
            lastError = nil
            return path
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func importItems(
        _ urls: [URL],
        into directory: String = "",
        conflictResolution: NoteImportConflictResolution = .keepBoth
    ) {
        Task {
            await perform {
                _ = try await self.service.importItems(
                    urls,
                    into: directory,
                    conflictResolution: conflictResolution
                )
                self.applyServiceSnapshot(await self.service.snapshot())
            }
        }
    }

    func updateNoteAgentPersistence(
        lastSelectedAgent: AgentKind?,
        recoveryBinding: NoteAgentRecoveryBinding?
    ) async throws {
        applyServiceSnapshot(
            try await service.updateNoteAgentPersistence(
                lastSelectedAgent: lastSelectedAgent,
                recoveryBinding: recoveryBinding
            )
        )
    }

    func prepareForTermination(
        decision: NoteCloseDecision
    ) async -> Bool {
        if decision == .cancel {
            return !hasDirtyDocuments && pendingEdits.isEmpty
        }
        do {
            if decision == .save {
                try await flushPendingEdits()
            }
            let result = try await service.prepareForTermination(
                decision: decision
            )
            if result, decision == .discard {
                cancelPendingEdits()
            }
            applyServiceSnapshot(await service.snapshot())
            return result
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func validateTermination(
        decision: NoteCloseDecision
    ) async -> Bool {
        if decision == .cancel {
            return !hasDirtyDocuments && pendingEdits.isEmpty
        }
        if decision == .save {
            do {
                try await flushPendingEdits()
                applyServiceSnapshot(await service.snapshot())
            } catch {
                lastError = error.localizedDescription
                return false
            }
        }
        return true
    }

    func toggleSourceMode() {
        guard let document = selectedDocument,
              document.kind != .plainText
        else { return }
        let id = document.id
        if sourceModeDocumentIDs.contains(id) {
            sourceModeDocumentIDs.remove(id)
        } else {
            sourceModeDocumentIDs.insert(id)
        }
    }

    func isSourceMode(_ id: NoteDocumentID) -> Bool {
        sourceModeDocumentIDs.contains(id)
    }

    func refresh() {
        Task {
            await perform {
                try await self.flushPendingEdits()
                self.applyServiceSnapshot(
                    try await self.service.refreshLibrary()
                )
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled,
                      self.snapshot.library != nil
                else {
                    continue
                }
                do {
                    try await self.flushPendingEdits()
                    self.applyServiceSnapshot(
                        try await self.service.refreshLibrary()
                    )
                } catch {
                    if self.isLibraryAvailable {
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    private var libraryURL: URL? {
        snapshot.library.map {
            URL(fileURLWithPath: $0.rootPath, isDirectory: true)
        }
    }

    private func flattenedEntries(
        _ entries: [NoteLibraryEntry]
    ) -> [NoteLibraryEntry] {
        entries.flatMap { [$0] + flattenedEntries($0.children) }
    }

    private func replaceDocument(_ replacement: NoteDocument) {
        snapshot = NotesSnapshot(
            library: snapshot.library,
            entries: snapshot.entries,
            documents: snapshot.documents.map {
                $0.id == replacement.id ? replacement : $0
            },
            selectedDocumentID: snapshot.selectedDocumentID,
            preferences: snapshot.preferences,
            libraryAvailability: snapshot.libraryAvailability,
            lastSelectedAgent: snapshot.lastSelectedAgent,
            noteAgentRecoveryBinding: snapshot.noteAgentRecoveryBinding,
            searchIndexStatus: snapshot.searchIndexStatus
        )
    }

    private func applyServiceSnapshot(_ incoming: NotesSnapshot) {
        let overlaidDocuments = incoming.documents.map { document in
            guard let pendingContent = pendingEdits[document.id] else {
                return document
            }
            return NoteDocument(
                id: document.id,
                relativePath: document.relativePath,
                kind: document.kind,
                content: pendingContent,
                savedContent: document.savedContent,
                externalState: document.externalState
            )
        }
        snapshot = NotesSnapshot(
            library: incoming.library,
            entries: incoming.entries,
            documents: overlaidDocuments,
            selectedDocumentID: incoming.selectedDocumentID,
            preferences: incoming.preferences,
            libraryAvailability: incoming.libraryAvailability,
            lastSelectedAgent: incoming.lastSelectedAgent,
            noteAgentRecoveryBinding: incoming.noteAgentRecoveryBinding,
            searchIndexStatus: incoming.searchIndexStatus
        )
        let plainTextIDs = Set(
            overlaidDocuments
                .filter { $0.kind == .plainText }
                .map(\.id)
        )
        sourceModeDocumentIDs.formUnion(plainTextIDs)
        sourceModeDocumentIDs.formIntersection(
            Set(overlaidDocuments.map(\.id))
        )
    }

    private func flushPendingEdits(
        ids requestedIDs: [NoteDocumentID]? = nil
    ) async throws {
        let ids = requestedIDs ?? snapshot.documents.map(\.id)
        for id in ids {
            recoveryTasks[id]?.cancel()
            recoveryTasks[id] = nil
            while let content = pendingEdits[id] {
                _ = try await service.updateDocument(id, content: content)
                if pendingEdits[id] == content {
                    pendingEdits[id] = nil
                }
            }
        }
    }

    private func cancelPendingEdits(
        ids requestedIDs: [NoteDocumentID]? = nil
    ) {
        let ids = requestedIDs ?? Array(pendingEdits.keys)
        for id in ids {
            recoveryTasks[id]?.cancel()
            recoveryTasks[id] = nil
            pendingEdits[id] = nil
        }
    }

    private func perform(
        _ operation: @escaping @MainActor () async throws -> Void
    ) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await operation()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
