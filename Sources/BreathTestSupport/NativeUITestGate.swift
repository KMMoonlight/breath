import Foundation

public final class NativeUITestGate: @unchecked Sendable {
    public static let shared = NativeUITestGate()

    private let lock = NSLock()
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    public func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isHeld {
                waiters.append(continuation)
                lock.unlock()
            } else {
                isHeld = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    public func release() {
        lock.lock()
        if waiters.isEmpty {
            isHeld = false
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }
}

@MainActor
public enum NativeUITestLifetime {
    private static var retainedObjects: [AnyObject] = []

    /// Keeps closed native test fixtures out of async autorelease teardown.
    ///
    /// AppKit, WebKit, and libghostty can enqueue native cleanup beyond the
    /// logical end of a test. Retaining those fixtures avoids overlapping that
    /// cleanup with another native test in the same Swift Testing process.
    public static func retainUntilProcessExit(_ object: AnyObject) {
        retainedObjects.append(object)
    }
}
