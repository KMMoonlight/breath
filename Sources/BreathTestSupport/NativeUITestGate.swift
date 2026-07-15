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
