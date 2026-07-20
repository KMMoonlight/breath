import Foundation
import SwiftUI

enum GitChangeWorkflow: String, CaseIterable, Codable, Sendable {
    case changelists
    case staging
}

enum GitDiffLayout: String, CaseIterable, Codable, Sendable {
    case sideBySide
    case unified
}

struct GitDiffPreferences: Equatable, Codable, Sendable {
    var layout: GitDiffLayout = .sideBySide
    var ignoreWhitespace = false
    var showWhitespace = false
    var softWrap = false
    var foldUnchanged = true
}

struct GitShortcutBinding: Equatable, Codable, Identifiable, Sendable {
    let commandID: String
    var keys: String
    var scope: GitShortcutScope

    var id: String { commandID }
}

enum GitShortcutScope: String, Codable, Sendable {
    case global
    case gitWorkbench
}

struct GitGlobalPreferences: Equatable, Codable, Sendable {
    var gitExecutablePath: String?
    var autoFetchMinutes = 20
    var snapshotRetentionWorkingDays = 5
    var persistConsole = true
    var combineStashAndShelf = false
    var diff = GitDiffPreferences()
    var shortcuts = GitCommandCatalog.defaultBindings
}

@MainActor
final class GitPreferencesStore: ObservableObject {
    static let shared = GitPreferencesStore()

    @Published var preferences: GitGlobalPreferences {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "gitWorkbench.preferences.v1"
    ) {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(GitGlobalPreferences.self, from: data)
        {
            var merged = decoded
            for binding in GitCommandCatalog.defaultBindings
            where !merged.shortcuts.contains(where: {
                $0.commandID == binding.commandID
            }) {
                merged.shortcuts.append(binding)
            }
            preferences = merged
        } else {
            preferences = GitGlobalPreferences()
        }
    }

    var resolvedGitExecutableURL: URL {
        if let path = preferences.gitExecutablePath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let candidates = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
        ]
        return URL(
            fileURLWithPath: candidates.first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            }) ?? "/usr/bin/git"
        )
    }

    func setDiffLayout(_ layout: GitDiffLayout) {
        guard preferences.diff.layout != layout else { return }
        var updated = preferences
        updated.diff.layout = layout
        preferences = updated
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}

struct GitWorkbenchLayoutState: Equatable, Codable, Sendable {
    var leftWidth: Double = 280
    var centerWidth: Double = 460
    var consoleHeight: Double = 180
    var isConsoleVisible = false
}

struct GitChangelist: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var entries: [GitChangelistEntry]

    init(id: UUID = UUID(), name: String, entries: [GitChangelistEntry] = []) {
        self.id = id
        self.name = name
        self.entries = entries
    }
}

struct GitChangelistEntry: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var rootPath: String
    var path: String
    var patch: String?
    var fingerprint: String?
    var needsConfirmation: Bool

    init(
        id: UUID = UUID(),
        rootPath: String,
        path: String,
        patch: String? = nil,
        fingerprint: String? = nil,
        needsConfirmation: Bool = false
    ) {
        self.id = id
        self.rootPath = rootPath
        self.path = path
        self.patch = patch
        self.fingerprint = fingerprint
        self.needsConfirmation = needsConfirmation
    }
}

struct GitShelf: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var rootPath: String
    var patchFileName: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        rootPath: String,
        patchFileName: String
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.rootPath = rootPath
        self.patchFileName = patchFileName
    }
}

struct GitWorkspaceMetadata: Equatable, Codable, Sendable {
    var authorizedExternalRootPaths: Set<String> = []
    var selectedRootPath: String?
    var workflow: GitChangeWorkflow = .changelists
    var changelists = [GitChangelist(name: "Default")]
    var defaultChangelistID: UUID?
    var commitDrafts: [String: String] = [:]
    var layout = GitWorkbenchLayoutState()
    var protectedBranchPatterns = ["main", "master"]
    var preCommitCommands: [String] = []
    var synchronizeMultiRootOperations = false
    var shelves: [GitShelf] = []
    var selectedLocalPath: String?
    var selectedCommitOID: String?
    var lastDetailSelection: String?
    var favoriteReferenceNames: Set<String>?
    var branchFilter: String?
    var preferredPullStrategy: GitPullStrategy?
    var localScrollAnchor: String?
    var logScrollAnchor: String?
    var localFilter = ""
    var logFilter = ""

    init() {
        defaultChangelistID = changelists.first?.id
    }
}

actor GitWorkspaceMetadataStore {
    private let baseURL: URL

    init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.baseURL = applicationSupport
                .appendingPathComponent("Breath", isDirectory: true)
                .appendingPathComponent("GitWorkbench", isDirectory: true)
        }
    }

    func load(workspaceURL: URL) -> GitWorkspaceMetadata {
        let url = metadataURL(for: workspaceURL)
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder.gitWorkbench.decode(
                  GitWorkspaceMetadata.self,
                  from: data
              )
        else {
            return GitWorkspaceMetadata()
        }
        return metadata
    }

    func save(_ metadata: GitWorkspaceMetadata, workspaceURL: URL) throws {
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.gitWorkbench.encode(metadata)
        try data.write(to: metadataURL(for: workspaceURL), options: .atomic)
    }

    func shelfDirectory(workspaceURL: URL) throws -> URL {
        let directory = baseURL
            .appendingPathComponent(workspaceKey(workspaceURL), isDirectory: true)
            .appendingPathComponent("Shelves", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    func shelfPatchURL(
        workspaceURL: URL,
        fileName: String
    ) throws -> URL {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.contains("/"),
              !fileName.contains("\0")
        else {
            throw GitMutationError.invalidSelection(
                "The selected shelf contains an invalid storage path."
            )
        }
        let directory = try shelfDirectory(workspaceURL: workspaceURL)
        let candidate = directory.appendingPathComponent(fileName)
        let resolvedDirectory = directory.resolvingSymlinksInPath()
            .standardizedFileURL.path
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
            .standardizedFileURL.path
        guard resolvedCandidate == resolvedDirectory
                || resolvedCandidate.hasPrefix(resolvedDirectory + "/")
        else {
            throw GitMutationError.invalidSelection(
                "The selected shelf points outside its storage directory."
            )
        }
        return candidate
    }

    private func metadataURL(for workspaceURL: URL) -> URL {
        baseURL.appendingPathComponent("\(workspaceKey(workspaceURL)).json")
    }

    private func workspaceKey(_ workspaceURL: URL) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in workspaceURL.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private extension JSONEncoder {
    static var gitWorkbench: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var gitWorkbench: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum GitCommandCatalog {
    static let defaultBindings: [GitShortcutBinding] = [
        GitShortcutBinding(commandID: "git.open", keys: "⌘9", scope: .global),
        GitShortcutBinding(commandID: "git.commit", keys: "⌘K", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.commitAndPush", keys: "⌘⌥K", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.push", keys: "⌘⇧K", scope: .global),
        GitShortcutBinding(commandID: "git.fetch", keys: "⌘⌥F", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.refresh", keys: "⌘R", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.nextDifference", keys: "F7", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.previousDifference", keys: "⇧F7", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.branches", keys: "⌃V", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.logSearch", keys: "⌘F", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.pullMerge", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.pullRebase", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.newBranch", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.merge", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.rebase", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.cherryPick", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.revert", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.fileHistory", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.blame", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.stash", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.shelf", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.console", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.resolveConflicts", keys: "", scope: .gitWorkbench),
        GitShortcutBinding(commandID: "git.undoLastCommit", keys: "", scope: .gitWorkbench),
    ]
}
