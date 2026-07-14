import BreathCore
import Darwin
import Dispatch
import Foundation

public enum UnixAgentEventSocketError: Error, Equatable {
    case pathTooLong
    case posix(function: String, code: Int32)
    case payloadTooLarge
}

public final class UnixAgentEventServer: @unchecked Sendable {
    private let socketURL: URL
    private let decoder: StrictAgentEventDecoder
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let queue = DispatchQueue(label: "app.breath.agent-events")
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?

    public init(
        socketURL: URL,
        decoder: StrictAgentEventDecoder = StrictAgentEventDecoder(),
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) {
        self.socketURL = socketURL
        self.decoder = decoder
        self.onEvent = onEvent
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor == -1 else { return }

        try? FileManager.default.removeItem(at: socketURL)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        do {
            let bindResult = try withAddress(path: socketURL.path) { address, length in
                Darwin.bind(fd, address, length)
            }
            guard bindResult == 0 else { throw posixError("bind") }
            guard chmod(socketURL.path, 0o600) == 0 else { throw posixError("chmod") }
            guard listen(fd, 16) == 0 else { throw posixError("listen") }

            descriptor = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.acceptOneConnection()
            }
            source.setCancelHandler { [socketURL] in
                Darwin.close(fd)
                try? FileManager.default.removeItem(at: socketURL)
            }
            self.source = source
            source.resume()
        } catch {
            Darwin.close(fd)
            try? FileManager.default.removeItem(at: socketURL)
            throw error
        }
    }

    public func stop() {
        lock.lock()
        let source = self.source
        self.source = nil
        descriptor = -1
        lock.unlock()
        source?.cancel()
    }

    private func acceptOneConnection() {
        let fd = lock.withLock { descriptor }
        guard fd >= 0 else { return }
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { Darwin.close(client) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.count <= 65_536 {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(client, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        guard data.count <= 65_536,
              let event = try? decoder.decode(data)
        else {
            return
        }
        onEvent(event)
    }
}

public protocol AgentEventSending: Sendable {
    func send(_ event: AgentEvent, to socketURL: URL) throws
}

public struct UnixAgentEventClient: AgentEventSending, Sendable {
    public init() {}

    public func send(_ event: AgentEvent, to socketURL: URL) throws {
        let data = try JSONEncoder().encode(event)
        guard data.count <= 65_536 else {
            throw UnixAgentEventSocketError.payloadTooLarge
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        defer { Darwin.close(fd) }

        let connectResult = try withAddress(path: socketURL.path) { address, length in
            Darwin.connect(fd, address, length)
        }
        guard connectResult == 0 else { throw posixError("connect") }

        try data.withUnsafeBytes { rawBuffer in
            var written = 0
            while written < rawBuffer.count {
                let count = Darwin.write(
                    fd,
                    rawBuffer.baseAddress?.advanced(by: written),
                    rawBuffer.count - written
                )
                guard count > 0 else { throw posixError("write") }
                written += count
            }
        }
        _ = shutdown(fd, SHUT_WR)
    }
}

private func withAddress<T>(
    path: String,
    body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= capacity else {
        throw UnixAgentEventSocketError.pathTooLong
    }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        let destination = UnsafeMutableRawPointer(pointer)
            .assumingMemoryBound(to: CChar.self)
        bytes.withUnsafeBufferPointer { source in
            destination.update(from: source.baseAddress!, count: bytes.count)
        }
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            try body(socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

private func posixError(_ function: String) -> UnixAgentEventSocketError {
    UnixAgentEventSocketError.posix(function: function, code: errno)
}
