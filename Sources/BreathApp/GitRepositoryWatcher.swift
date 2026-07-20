import Darwin
import Foundation

final class GitRepositoryWatcher: @unchecked Sendable {
    let watchedPaths: Set<String>

    private let queue = DispatchQueue(
        label: "com.breath.git-workbench.repository-watcher",
        qos: .utility
    )
    private let onChange: @Sendable () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingNotification: DispatchWorkItem?

    init(
        urls: [URL],
        onChange: @escaping @Sendable () -> Void
    ) {
        self.onChange = onChange
        watchedPaths = Set(
            urls.map(\.standardizedFileURL.path)
        )
        for path in watchedPaths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleNotification()
            }
            source.setCancelHandler {
                close(descriptor)
            }
            sources.append(source)
            source.resume()
        }
    }

    deinit {
        pendingNotification?.cancel()
        sources.forEach { $0.cancel() }
    }

    private func scheduleNotification() {
        pendingNotification?.cancel()
        let notification = DispatchWorkItem { [onChange] in
            onChange()
        }
        pendingNotification = notification
        queue.asyncAfter(
            deadline: .now() + .milliseconds(250),
            execute: notification
        )
    }
}
