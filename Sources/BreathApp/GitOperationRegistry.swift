import Foundation
import SwiftUI

struct GitOperationID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum GitOperationStatus: String, Equatable, Codable, Sendable {
    case waiting
    case running
    case waitingForAuthentication
    case waitingForConfirmation
    case succeeded
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .waiting, .running, .waitingForAuthentication,
             .waitingForConfirmation:
            true
        case .succeeded, .failed, .cancelled:
            false
        }
    }
}

struct GitOperationRecord: Equatable, Identifiable, Codable, Sendable {
    var id: GitOperationID
    var workspacePath: String
    var rootPath: String
    var title: String
    var command: String?
    var startedAt: Date
    var endedAt: Date?
    var status: GitOperationStatus
    var exitCode: Int32?
    var output: String
    var isMutation: Bool
}

@MainActor
final class GitOperationRegistry: ObservableObject {
    static let shared = GitOperationRegistry()

    @Published private(set) var records: [GitOperationRecord] = []

    private var rootQueues: [String: GitRootWriteLock] = [:]
    private var activeCancellations:
        [GitOperationID: @Sendable () -> Void] = [:]
    private let store: GitConsoleStore
    private var loaded = false

    init(store: GitConsoleStore = GitConsoleStore()) {
        self.store = store
    }

    var runningCount: Int {
        records.filter { $0.status.isActive }.count
    }

    var failedCount: Int {
        records.filter { $0.status == .failed }.count
    }

    func loadPersistedIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        var repairedInterruptedRecords = false
        if GitPreferencesStore.shared.preferences.persistConsole {
            let now = Date()
            records = await store.load().map { record in
                guard record.status.isActive else { return record }
                repairedInterruptedRecords = true
                var interrupted = record
                interrupted.status = .failed
                interrupted.endedAt = now
                let message = "Interrupted when Breath previously exited."
                interrupted.output = interrupted.output.isEmpty
                    ? message
                    : interrupted.output + "\n" + message
                return interrupted
            }
        } else {
            await store.clear()
            records = []
        }
        trim()
        if repairedInterruptedRecords {
            await persist()
        }
    }

    func setPersistenceEnabled(_ enabled: Bool) async {
        if enabled {
            await persist()
        } else {
            await store.clear()
        }
    }

    func records(workspacePath: String) -> [GitOperationRecord] {
        records.filter { $0.workspacePath == workspacePath }
    }

    func clear(workspacePath: String? = nil) async {
        records.removeAll { record in
            let isInScope = workspacePath == nil
                || record.workspacePath == workspacePath
            return isInScope && !record.status.isActive
        }
        await persist()
    }

    func setStatus(_ status: GitOperationStatus, for id: GitOperationID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].status = status
    }

    func run<T: Sendable>(
        workspaceURL: URL,
        rootURL: URL,
        title: String,
        command: String? = nil,
        isMutation: Bool,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        await loadPersistedIfNeeded()
        let id = GitOperationID()
        records.insert(
            GitOperationRecord(
                id: id,
                workspacePath: workspaceURL.standardizedFileURL.path,
                rootPath: rootURL.standardizedFileURL.path,
                title: title,
                command: command.map(GitSecretRedactor.redact),
                startedAt: Date(),
                endedAt: nil,
                status: isMutation ? .waiting : .running,
                exitCode: nil,
                output: "",
                isMutation: isMutation
            ),
            at: 0
        )
        let lock = writeLock(for: rootURL)
        if isMutation {
            await lock.acquire()
        }
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index].status = .running
        }
        let streamBuffer = GitConsoleStreamBuffer()
        let recorder: @Sendable (GitCommandResult) async -> Void = {
            [weak self] result in
            let finalOutput = await streamBuffer.finish()
            await MainActor.run {
                if !finalOutput.isEmpty {
                    self?.append(output: finalOutput, to: id)
                }
                self?.append(
                    output: "",
                    command: result.displayCommand,
                    exitCode: result.exitCode,
                    to: id
                )
            }
        }
        let outputRecorder: @Sendable (String) async -> Void = {
            [weak self] output in
            let readyOutput = await streamBuffer.consume(output)
            guard !readyOutput.isEmpty else { return }
            await MainActor.run {
                guard let self else { return }
                if let index = self.records.firstIndex(where: {
                    $0.id == id
                }), [
                    GitOperationStatus.waitingForAuthentication,
                    .waitingForConfirmation,
                ].contains(self.records[index].status)
                {
                    self.records[index].status = .running
                }
                self.append(output: readyOutput, to: id)
            }
        }
        let statusRecorder: @Sendable (GitOperationStatus) async -> Void = {
            [weak self] status in
            await MainActor.run {
                self?.setStatus(status, for: id)
            }
        }
        let operationTask = Task<T, Error> {
            try await GitOperationContext.$recorder.withValue(recorder) {
                try await GitOperationContext.$statusRecorder.withValue(
                    statusRecorder
                ) {
                    try await GitOperationContext.$outputRecorder.withValue(
                        outputRecorder
                    ) {
                        try await operation()
                    }
                }
            }
        }
        activeCancellations[id] = {
            operationTask.cancel()
        }
        do {
            let value = try await operationTask.value
            activeCancellations[id] = nil
            finish(id: id, status: .succeeded, output: "")
            if isMutation { await lock.release() }
            await persist()
            return value
        } catch is CancellationError {
            activeCancellations[id] = nil
            finish(id: id, status: .cancelled, output: "Cancelled")
            if isMutation { await lock.release() }
            await persist()
            throw CancellationError()
        } catch {
            activeCancellations[id] = nil
            finish(
                id: id,
                status: .failed,
                output: error.localizedDescription
            )
            if isMutation { await lock.release() }
            await persist()
            throw error
        }
    }

    func append(
        output: String,
        command: String? = nil,
        exitCode: Int32? = nil,
        to id: GitOperationID
    ) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        if let command {
            records[index].command = GitSecretRedactor.redact(command)
        }
        if let exitCode {
            records[index].exitCode = exitCode
        }
        let redacted = GitSecretRedactor.redact(output)
        if records[index].output.isEmpty {
            records[index].output = redacted
        } else {
            let separator = records[index].output.hasSuffix("\n")
                || records[index].output.hasSuffix("\r")
                ? ""
                : "\n"
            records[index].output += separator + redacted
        }
    }

    func prepareForTermination() async {
        await cancelReadOnlyOperations()
        while records.contains(where: {
            $0.isMutation && $0.status.isActive
        }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await persist()
    }

    func cancelReadOnlyOperations() async {
        let ids = records.filter {
            !$0.isMutation
                && $0.status.isActive
        }.map(\.id)
        for id in ids {
            activeCancellations[id]?()
        }
    }

    private func finish(
        id: GitOperationID,
        status: GitOperationStatus,
        output: String
    ) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].status = status
        records[index].endedAt = Date()
        if !output.isEmpty {
            let redacted = GitSecretRedactor.redact(output)
            if records[index].output.isEmpty {
                records[index].output = redacted
            } else if !records[index].output.contains(redacted) {
                records[index].output += "\n" + redacted
            }
        }
        trim()
    }

    private func trim() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let active = records.filter { $0.status.isActive }
        let completedLimit = max(0, 500 - active.count)
        let completed = records
            .filter { !$0.status.isActive && $0.startedAt >= cutoff }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(completedLimit)
        records = (active + completed)
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func writeLock(for rootURL: URL) -> GitRootWriteLock {
        let path = rootURL.standardizedFileURL.path
        if let lock = rootQueues[path] { return lock }
        let lock = GitRootWriteLock()
        rootQueues[path] = lock
        return lock
    }

    private func persist() async {
        let preferences = GitPreferencesStore.shared.preferences
        if preferences.persistConsole {
            await store.save(records)
        } else {
            await store.clear()
        }
    }
}

actor GitRootWriteLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

actor GitConsoleStreamBuffer {
    private var pending = ""

    func consume(_ chunk: String) -> String {
        pending += chunk
        guard let boundary = pending.lastIndex(where: {
            $0 == "\n" || $0 == "\r"
        }) else {
            return ""
        }
        let end = pending.index(after: boundary)
        let complete = String(pending[..<end])
        pending = String(pending[end...])
        return complete
    }

    func finish() -> String {
        defer { pending = "" }
        return pending
    }
}

actor GitConsoleStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.fileURL = applicationSupport
                .appendingPathComponent("Breath", isDirectory: true)
                .appendingPathComponent("GitWorkbench", isDirectory: true)
                .appendingPathComponent("console.json")
        }
    }

    func load() -> [GitOperationRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([GitOperationRecord].self, from: data)) ?? []
    }

    func save(_ records: [GitOperationRecord]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: fileURL, options: .atomic)
        } catch {
            // Console persistence is diagnostic and must not block Git operations.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum GitSecretRedactor {
    static func redact(_ value: String) -> String {
        var result = value
        let patterns = [
            #"(?i)(https?://)[^/@\s]+@"#,
            #"(?i)(authorization:\s*(?:bearer|basic)\s+)[^\s]+"#,
            #"(?i)((?:token|password|passwd|passphrase|secret)[=:]\s*)[^\s]+"#,
            #"(?i)(BREATH_GIT_SECRET=)[^\s]+"#,
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            let replacement = pattern.contains("https?")
                ? "$1•••@"
                : "$1•••"
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement
            )
        }
        return result
    }
}
