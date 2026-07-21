import Darwin
import Dispatch
import Foundation

final class SkillDirectoryEventMonitor: @unchecked Sendable {
    let events: AsyncStream<Void>

    private let lock = NSLock()
    private var continuation: AsyncStream<Void>.Continuation?
    private var sources: [DispatchSourceFileSystemObject] = []
    private var isCancelled = false

    init(directories: [URL]) {
        var capturedContinuation: AsyncStream<Void>.Continuation?
        events = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation
        continuation?.onTermination = { [weak self] _ in self?.cancel() }

        let queue = DispatchQueue(label: "app.breath.skills.directory-events")
        let uniqueDirectories = Dictionary(
            directories.map { ($0.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values
        for directory in uniqueDirectories {
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.emit() }
            source.setCancelHandler { close(descriptor) }
            sources.append(source)
            source.resume()
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let activeSources = sources
        sources.removeAll()
        let activeContinuation = continuation
        continuation = nil
        lock.unlock()

        activeSources.forEach { $0.cancel() }
        activeContinuation?.finish()
    }

    deinit {
        cancel()
    }

    private func emit() {
        lock.lock()
        let activeContinuation = isCancelled ? nil : continuation
        lock.unlock()
        activeContinuation?.yield(())
    }
}
