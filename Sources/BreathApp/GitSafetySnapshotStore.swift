import Foundation

struct GitSafetySnapshot: Equatable, Codable, Identifiable, Sendable {
    let id: UUID
    let rootPath: String
    let action: String
    let createdAt: Date
    let directoryName: String
    let files: [GitSafetySnapshotFile]
    let stagedPatchFileName: String?
    let workingPatchFileName: String?
}

struct GitSafetySnapshotFile: Equatable, Codable, Identifiable, Sendable {
    var id: String { path }

    let path: String
    let copyFileName: String?
    let wasAbsent: Bool
}

actor GitSafetySnapshotStore {
    private let baseURL: URL
    private let gitExecutableURL: URL

    init(
        baseURL: URL? = nil,
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let caches = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.baseURL = caches
                .appendingPathComponent("Breath", isDirectory: true)
                .appendingPathComponent("GitSafetySnapshots", isDirectory: true)
        }
        self.gitExecutableURL = gitExecutableURL
    }

    func create(
        rootURL: URL,
        action: String,
        retentionWorkingDays: Int
    ) async -> GitSafetySnapshot? {
        guard retentionWorkingDays > 0 else {
            try? FileManager.default.removeItem(at: rootDirectory(rootURL))
            return nil
        }
        do {
            let service = GitWorkbenchService(
                workspaceURL: rootURL,
                gitExecutableURL: gitExecutableURL
            )
            let root = try await service.loadRootSnapshot(rootURL)
            let stagedPatch = try await service.diff(rootURL: rootURL, source: .staged).patch
            let workingPatch = try await service.diff(rootURL: rootURL, source: .workingTree).patch
            let snapshotID = UUID()
            let directoryName = snapshotID.uuidString
            let directory = rootDirectory(rootURL)
                .appendingPathComponent(directoryName, isDirectory: true)
            let filesDirectory = directory.appendingPathComponent("files", isDirectory: true)
            try FileManager.default.createDirectory(
                at: filesDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            var files: [GitSafetySnapshotFile] = []
            for (offset, change) in root.changes.enumerated() {
                let source = try repositoryFileURL(
                    rootURL: rootURL,
                    relativePath: change.path
                )
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(
                    atPath: source.path,
                    isDirectory: &isDirectory
                ), !isDirectory.boolValue {
                    let fileName = String(format: "%05d", offset)
                    let destination = filesDirectory.appendingPathComponent(fileName)
                    try FileManager.default.copyItem(at: source, to: destination)
                    files.append(
                        GitSafetySnapshotFile(
                            path: change.path,
                            copyFileName: fileName,
                            wasAbsent: false
                        )
                    )
                } else if !isDirectory.boolValue {
                    files.append(
                        GitSafetySnapshotFile(
                            path: change.path,
                            copyFileName: nil,
                            wasAbsent: true
                        )
                    )
                }
            }
            let stagedName = try writePatchIfNeeded(
                stagedPatch,
                name: "staged.patch",
                directory: directory
            )
            let workingName = try writePatchIfNeeded(
                workingPatch,
                name: "working.patch",
                directory: directory
            )
            let snapshot = GitSafetySnapshot(
                id: snapshotID,
                rootPath: rootURL.standardizedFileURL.path,
                action: action,
                createdAt: Date(),
                directoryName: directoryName,
                files: files,
                stagedPatchFileName: stagedName,
                workingPatchFileName: workingName
            )
            try writeManifest(snapshot, directory: directory)
            try prune(rootURL: rootURL, retentionWorkingDays: retentionWorkingDays)
            return snapshot
        } catch {
            return nil
        }
    }

    func list(rootURL: URL) -> [GitSafetySnapshot] {
        let directory = rootDirectory(rootURL)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return children.compactMap { child in
            guard let data = try? Data(
                contentsOf: child.appendingPathComponent("manifest.json")
            ) else {
                return nil
            }
            return try? JSONDecoder.gitWorkbench.decode(
                GitSafetySnapshot.self,
                from: data
            )
        }.filter { snapshot in
            isValid(snapshot: snapshot, rootURL: rootURL)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func restore(
        _ snapshot: GitSafetySnapshot,
        rootURL: URL,
        paths: Set<String>? = nil,
        restoreIndex: Bool = true
    ) async throws {
        let directory = try snapshotDirectory(snapshot, rootURL: rootURL)
        for file in snapshot.files where paths == nil || paths?.contains(file.path) == true {
            let destination = try repositoryFileURL(
                rootURL: rootURL,
                relativePath: file.path
            )
            if file.wasAbsent {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                continue
            }
            guard let copyFileName = file.copyFileName else { continue }
            let source = try snapshotStorageURL(
                directory: directory.appendingPathComponent(
                    "files",
                    isDirectory: true
                ),
                component: copyFileName
            )
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
        guard restoreIndex,
              paths == nil,
              let stagedPatchFileName = snapshot.stagedPatchFileName
        else {
            return
        }
        let service = GitWorkbenchService(
            workspaceURL: rootURL,
            gitExecutableURL: gitExecutableURL
        )
        _ = try await service.requiredGit(
            rootURL: rootURL,
            arguments: ["read-tree", "HEAD"]
        )
        let patch = try String(
            contentsOf: snapshotStorageURL(
                directory: directory,
                component: stagedPatchFileName
            ),
            encoding: .utf8
        )
        if !patch.isEmpty {
            try await service.applyPatch(
                rootURL: rootURL,
                patch: patch,
                cached: true,
                threeWay: true
            )
        }
    }

    func restoreFragment(
        patch: String,
        rootURL: URL,
        cached: Bool = false
    ) async throws {
        let service = GitWorkbenchService(
            workspaceURL: rootURL,
            gitExecutableURL: gitExecutableURL
        )
        try await service.applyPatch(
            rootURL: rootURL,
            patch: patch,
            cached: cached,
            threeWay: false
        )
    }

    func comparisonDiff(
        _ snapshot: GitSafetySnapshot,
        rootURL: URL,
        path: String
    ) async throws -> GitFileDiff {
        let standardizedRoot = rootURL.standardizedFileURL
        guard snapshot.rootPath == standardizedRoot.path,
              let file = snapshot.files.first(where: { $0.path == path })
        else {
            throw GitMutationError.invalidSelection(
                "The selected snapshot file does not belong to this Git Root."
            )
        }
        let snapshotDirectory = try snapshotDirectory(
            snapshot,
            rootURL: standardizedRoot
        )

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "breath-snapshot-compare-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let beforeURL = temporaryDirectory
            .appendingPathComponent("before", isDirectory: true)
            .appendingPathComponent(path)
        let afterURL = temporaryDirectory
            .appendingPathComponent("after", isDirectory: true)
            .appendingPathComponent(path)
        let currentURL = try repositoryFileURL(
            rootURL: standardizedRoot,
            relativePath: path
        )

        if FileManager.default.fileExists(atPath: currentURL.path) {
            try copyFile(currentURL, to: beforeURL)
        }
        if !file.wasAbsent, let copyFileName = file.copyFileName {
            let source = try snapshotStorageURL(
                directory: snapshotDirectory.appendingPathComponent(
                    "files",
                    isDirectory: true
                ),
                component: copyFileName
            )
            try copyFile(source, to: afterURL)
        }

        let beforeArgument = FileManager.default.fileExists(
            atPath: beforeURL.path
        ) ? "before/\(path)" : "/dev/null"
        let afterArgument = FileManager.default.fileExists(
            atPath: afterURL.path
        ) ? "after/\(path)" : "/dev/null"
        let result = try await GitCommandRunner(
            executableURL: gitExecutableURL
        ).run(
            arguments: [
                "-C",
                temporaryDirectory.path,
                "diff",
                "--no-index",
                "--binary",
                "--no-renames",
                "--",
                beforeArgument,
                afterArgument,
            ]
        )
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw GitCommandError.failed(
                command: result.displayCommand,
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        let patch = result.standardOutput
            .replacingOccurrences(of: "a/before/", with: "a/")
            .replacingOccurrences(of: "b/after/", with: "b/")
        return GitFileDiff(
            rootID: GitRootID(rawValue: standardizedRoot.path),
            path: path,
            source: .stash("Git Safety Snapshot · \(snapshot.action)"),
            patch: patch,
            isBinary: patch.contains("GIT binary patch")
                || patch.contains("Binary files "),
            byteCount: patch.utf8.count
        )
    }

    private func writePatchIfNeeded(
        _ patch: String,
        name: String,
        directory: URL
    ) throws -> String? {
        guard !patch.isEmpty else { return nil }
        try Data(patch.utf8).write(
            to: directory.appendingPathComponent(name),
            options: .atomic
        )
        return name
    }

    private func copyFile(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func writeManifest(
        _ snapshot: GitSafetySnapshot,
        directory: URL
    ) throws {
        let data = try JSONEncoder.gitWorkbench.encode(snapshot)
        try data.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    private func prune(rootURL: URL, retentionWorkingDays: Int) throws {
        let snapshots = list(rootURL: rootURL)
        let calendar = Calendar(identifier: .gregorian)
        var retainedDays: [Date] = []
        for snapshot in snapshots {
            let day = calendar.startOfDay(for: snapshot.createdAt)
            if !retainedDays.contains(day) {
                retainedDays.append(day)
            }
            if retainedDays.count > retentionWorkingDays {
                let directory = rootDirectory(rootURL)
                    .appendingPathComponent(snapshot.directoryName)
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    private func isValid(
        snapshot: GitSafetySnapshot,
        rootURL: URL
    ) -> Bool {
        guard snapshot.rootPath == rootURL.standardizedFileURL.path,
              snapshot.directoryName == snapshot.id.uuidString,
              isSafeStorageComponent(snapshot.directoryName),
              snapshot.files.allSatisfy({ file in
                  isSafeRepositoryRelativePath(file.path)
                      && file.copyFileName.map(isSafeStorageComponent) ?? true
              }),
              snapshot.stagedPatchFileName.map(isSafeStorageComponent) ?? true,
              snapshot.workingPatchFileName.map(isSafeStorageComponent) ?? true
        else {
            return false
        }
        let directory = rootDirectory(rootURL)
            .appendingPathComponent(snapshot.directoryName, isDirectory: true)
        return isContained(
            directory.resolvingSymlinksInPath(),
            in: rootDirectory(rootURL).resolvingSymlinksInPath()
        )
    }

    private func snapshotDirectory(
        _ snapshot: GitSafetySnapshot,
        rootURL: URL
    ) throws -> URL {
        guard isValid(snapshot: snapshot, rootURL: rootURL) else {
            throw GitMutationError.invalidSelection(
                "The selected safety snapshot is invalid or belongs to another Git Root."
            )
        }
        return rootDirectory(rootURL)
            .appendingPathComponent(snapshot.directoryName, isDirectory: true)
    }

    private func snapshotStorageURL(
        directory: URL,
        component: String
    ) throws -> URL {
        guard isSafeStorageComponent(component) else {
            throw GitMutationError.invalidSelection(
                "The selected safety snapshot contains an invalid storage path."
            )
        }
        let candidate = directory.appendingPathComponent(component)
        guard isContained(
            candidate.resolvingSymlinksInPath(),
            in: directory.resolvingSymlinksInPath()
        ) else {
            throw GitMutationError.invalidSelection(
                "The selected safety snapshot points outside its storage directory."
            )
        }
        return candidate
    }

    private func repositoryFileURL(
        rootURL: URL,
        relativePath: String
    ) throws -> URL {
        guard isSafeRepositoryRelativePath(relativePath) else {
            throw GitMutationError.invalidSelection(
                "The selected path points outside the Git Root."
            )
        }
        let root = rootURL.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath)
            .standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath()
        let resolvedParent = candidate.deletingLastPathComponent()
            .resolvingSymlinksInPath()
        guard isContained(resolvedParent, in: resolvedRoot) else {
            throw GitMutationError.invalidSelection(
                "The selected path resolves outside the Git Root."
            )
        }
        return candidate
    }

    private func isSafeRepositoryRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else {
            return false
        }
        return path.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).allSatisfy { component in
            component != "." && component != ".." && !component.isEmpty
        }
    }

    private func isSafeStorageComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.contains("\0")
    }

    private func isContained(_ candidate: URL, in directory: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return candidatePath == directoryPath
            || candidatePath.hasPrefix(directoryPath + "/")
    }

    private func rootDirectory(_ rootURL: URL) -> URL {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in rootURL.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return baseURL.appendingPathComponent(String(hash, radix: 16), isDirectory: true)
    }
}

extension GitWorkspaceMetadataStore {
    func createShelf(
        workspaceURL: URL,
        rootURL: URL,
        name: String,
        patch: String
    ) throws -> GitShelf {
        let directory = try shelfDirectory(workspaceURL: workspaceURL)
        let fileName = "\(UUID().uuidString).patch"
        try Data(patch.utf8).write(
            to: directory.appendingPathComponent(fileName),
            options: .atomic
        )
        let shelf = GitShelf(
            name: name,
            rootPath: rootURL.standardizedFileURL.path,
            patchFileName: fileName
        )
        var metadata = load(workspaceURL: workspaceURL)
        metadata.shelves.insert(shelf, at: 0)
        try save(metadata, workspaceURL: workspaceURL)
        return shelf
    }

    func shelfPatch(workspaceURL: URL, shelf: GitShelf) throws -> String {
        return try String(
            contentsOf: shelfPatchURL(
                workspaceURL: workspaceURL,
                fileName: shelf.patchFileName
            ),
            encoding: .utf8
        )
    }

    func deleteShelf(workspaceURL: URL, shelf: GitShelf) throws {
        if let patchURL = try? shelfPatchURL(
            workspaceURL: workspaceURL,
            fileName: shelf.patchFileName
        ) {
            try? FileManager.default.removeItem(at: patchURL)
        }
        var metadata = load(workspaceURL: workspaceURL)
        metadata.shelves.removeAll { $0.id == shelf.id }
        try save(metadata, workspaceURL: workspaceURL)
    }

    func importShelf(
        workspaceURL: URL,
        rootURL: URL,
        sourceURL: URL
    ) throws -> GitShelf {
        let patch = try String(contentsOf: sourceURL, encoding: .utf8)
        return try createShelf(
            workspaceURL: workspaceURL,
            rootURL: rootURL,
            name: sourceURL.deletingPathExtension().lastPathComponent,
            patch: patch
        )
    }

    func exportShelf(
        workspaceURL: URL,
        shelf: GitShelf,
        destinationURL: URL
    ) throws {
        let patch = try shelfPatch(workspaceURL: workspaceURL, shelf: shelf)
        try Data(patch.utf8).write(to: destinationURL, options: .atomic)
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
