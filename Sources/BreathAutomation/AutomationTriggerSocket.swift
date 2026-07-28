import Darwin
import Dispatch
import Foundation

public enum AutomationTriggerResponseStatus: String, Codable, Sendable {
    case accepted
    case queued
    case rejected
}

public struct AutomationTriggerResponse: Equatable, Codable, Sendable {
    public let status: AutomationTriggerResponseStatus
    public let message: String

    public init(status: AutomationTriggerResponseStatus, message: String) {
        self.status = status
        self.message = message
    }
}

public enum AutomationTriggerSocketError: Error, Equatable, Sendable {
    case pathTooLong
    case payloadTooLarge
    case invalidRequest
    case invalidResponse
    case timedOut
    case posix(function: String, code: Int32)
}

private struct AutomationTriggerRequest: Codable {
    let version: Int
    let shortcode: String
}

public final class UnixAutomationTriggerServer: @unchecked Sendable {
    public typealias Handler =
        @Sendable (String) async -> AutomationTriggerResponse

    private let socketURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "app.breath.automation-trigger")
    private let clientQueue = DispatchQueue(
        label: "app.breath.automation-trigger.clients",
        attributes: .concurrent
    )
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?

    public init(
        socketURL: URL,
        handler: @escaping Handler
    ) {
        self.socketURL = socketURL
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor == -1 else { return }

        try? FileManager.default.removeItem(at: socketURL)
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw triggerSocketPOSIXError("socket")
        }
        do {
            let bindResult = try withTriggerSocketAddress(
                path: socketURL.path
            ) { address, length in
                Darwin.bind(fileDescriptor, address, length)
            }
            guard bindResult == 0 else {
                throw triggerSocketPOSIXError("bind")
            }
            guard chmod(socketURL.path, 0o600) == 0 else {
                throw triggerSocketPOSIXError("chmod")
            }
            guard listen(fileDescriptor, 16) == 0 else {
                throw triggerSocketPOSIXError("listen")
            }

            descriptor = fileDescriptor
            let source = DispatchSource.makeReadSource(
                fileDescriptor: fileDescriptor,
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.acceptConnection()
            }
            source.setCancelHandler { [socketURL] in
                Darwin.close(fileDescriptor)
                try? FileManager.default.removeItem(at: socketURL)
            }
            self.source = source
            source.resume()
        } catch {
            Darwin.close(fileDescriptor)
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

    private func acceptConnection() {
        let fileDescriptor = lock.withLock { descriptor }
        guard fileDescriptor >= 0 else { return }
        let client = accept(fileDescriptor, nil, nil)
        guard client >= 0 else { return }
        clientQueue.async { [weak self] in
            guard let self else {
                Darwin.close(client)
                return
            }
            self.handleConnection(client)
        }
    }

    private func handleConnection(_ client: Int32) {
        defer { Darwin.close(client) }
        configureTriggerSocketTimeout(client, seconds: 5)
        guard let requestData = readTriggerFrame(from: client),
              let request = decodeRequest(requestData)
        else {
            try? writeTriggerResponse(
                AutomationTriggerResponse(
                    status: .rejected,
                    message: "Invalid automation trigger request."
                ),
                to: client
            )
            return
        }
        let result = TriggerResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let response = await handler(request.shortcode)
            result.store(response)
            semaphore.signal()
        }
        semaphore.wait()
        guard let response = result.load() else { return }
        try? writeTriggerResponse(response, to: client)
    }

    private func decodeRequest(_ data: Data) -> AutomationTriggerRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            Set(object.keys) == Set(["version", "shortcode"]),
            let request = try? JSONDecoder().decode(
                AutomationTriggerRequest.self,
                from: data
            ),
            request.version == 1,
            !request.shortcode.isEmpty
        else {
            return nil
        }
        return request
    }

    private func writeTriggerResponse(
        _ response: AutomationTriggerResponse,
        to client: Int32
    ) throws {
        let data = try JSONEncoder().encode(response)
        try writeTriggerFrame(data, to: client)
    }
}

public struct UnixAutomationTriggerClient: Sendable {
    public init() {}

    public func trigger(
        shortcode: String,
        at socketURL: URL
    ) throws -> AutomationTriggerResponse {
        let request = AutomationTriggerRequest(
            version: 1,
            shortcode: shortcode
        )
        let data = try JSONEncoder().encode(request)
        guard data.count <= 65_536 else {
            throw AutomationTriggerSocketError.payloadTooLarge
        }
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw triggerSocketPOSIXError("socket")
        }
        defer { Darwin.close(fileDescriptor) }
        var noSignal: Int32 = 1
        _ = withUnsafePointer(to: &noSignal) {
            setsockopt(
                fileDescriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                $0,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }
        configureTriggerSocketTimeout(fileDescriptor, seconds: 5)
        let connectResult = try withTriggerSocketAddress(
            path: socketURL.path
        ) { address, length in
            Darwin.connect(fileDescriptor, address, length)
        }
        guard connectResult == 0 else {
            throw triggerSocketPOSIXError("connect")
        }
        try writeTriggerFrame(data, to: fileDescriptor)
        _ = shutdown(fileDescriptor, SHUT_WR)
        guard let responseData = readTriggerFrame(from: fileDescriptor),
              let response = try? JSONDecoder().decode(
                  AutomationTriggerResponse.self,
                  from: responseData
              )
        else {
            throw AutomationTriggerSocketError.invalidResponse
        }
        return response
    }
}

private final class TriggerResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var response: AutomationTriggerResponse?

    func store(_ response: AutomationTriggerResponse) {
        lock.withLock {
            self.response = response
        }
    }

    func load() -> AutomationTriggerResponse? {
        lock.withLock { response }
    }
}

private func configureTriggerSocketTimeout(
    _ fileDescriptor: Int32,
    seconds: Int
) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    _ = withUnsafePointer(to: &timeout) {
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            $0,
            socklen_t(MemoryLayout<timeval>.size)
        )
    }
    _ = withUnsafePointer(to: &timeout) {
        setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            $0,
            socklen_t(MemoryLayout<timeval>.size)
        )
    }
}

private func readTriggerFrame(from fileDescriptor: Int32) -> Data? {
    guard let header = readTriggerBytes(4, from: fileDescriptor) else {
        return nil
    }
    let length = header.reduce(UInt32(0)) {
        ($0 << 8) | UInt32($1)
    }
    guard length <= 65_536 else { return nil }
    return readTriggerBytes(Int(length), from: fileDescriptor)
}

private func writeTriggerFrame(
    _ data: Data,
    to fileDescriptor: Int32
) throws {
    guard data.count <= 65_536 else {
        throw AutomationTriggerSocketError.payloadTooLarge
    }
    var length = UInt32(data.count).bigEndian
    let header = withUnsafeBytes(of: &length) { Data($0) }
    try writeTriggerBytes(header, to: fileDescriptor)
    try writeTriggerBytes(data, to: fileDescriptor)
}

private func readTriggerBytes(
    _ length: Int,
    from fileDescriptor: Int32
) -> Data? {
    if length == 0 { return Data() }
    var data = Data(count: length)
    let completed = data.withUnsafeMutableBytes { rawBuffer -> Bool in
        var offset = 0
        while offset < length {
            let count = Darwin.read(
                fileDescriptor,
                rawBuffer.baseAddress?.advanced(by: offset),
                length - offset
            )
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
    return completed ? data : nil
}

private func writeTriggerBytes(
    _ data: Data,
    to fileDescriptor: Int32
) throws {
    try data.withUnsafeBytes { rawBuffer in
        var offset = 0
        while offset < rawBuffer.count {
            let count = Darwin.write(
                fileDescriptor,
                rawBuffer.baseAddress?.advanced(by: offset),
                rawBuffer.count - offset
            )
            guard count > 0 else {
                throw triggerSocketPOSIXError("write")
            }
            offset += count
        }
    }
}

private func withTriggerSocketAddress<T>(
    path: String,
    body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= capacity else {
        throw AutomationTriggerSocketError.pathTooLong
    }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        let destination = UnsafeMutableRawPointer(pointer)
            .assumingMemoryBound(to: CChar.self)
        bytes.withUnsafeBufferPointer { source in
            destination.update(
                from: source.baseAddress!,
                count: bytes.count
            )
        }
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(
            to: sockaddr.self,
            capacity: 1
        ) { socketAddress in
            try body(
                socketAddress,
                socklen_t(MemoryLayout<sockaddr_un>.size)
            )
        }
    }
}

private func triggerSocketPOSIXError(
    _ function: String
) -> AutomationTriggerSocketError {
    AutomationTriggerSocketError.posix(
        function: function,
        code: errno
    )
}
