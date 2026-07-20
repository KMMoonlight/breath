import Compression
import Foundation

struct SecureZIPLimits: Sendable {
    let maximumArchiveBytes: Int = 64 * 1_024 * 1_024
    let maximumExpandedBytes: Int = 256 * 1_024 * 1_024
    let maximumFiles: Int = 4_096
    let maximumDepth: Int = 16
}

enum SecureZIPArchive {
    static func extract(
        archiveURL: URL,
        to destination: URL,
        limits: SecureZIPLimits = SecureZIPLimits(),
        fileManager: FileManager = .default
    ) throws {
        let archive = try Data(contentsOf: archiveURL, options: [.mappedIfSafe])
        guard archive.count <= limits.maximumArchiveBytes else {
            throw SkillSourceError.archiveLimitExceeded
        }
        let entries = try parseEntries(archive, limits: limits)
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            for entry in entries {
                let output = destination.appendingPathComponent(entry.path)
                if entry.isDirectory {
                    try fileManager.createDirectory(
                        at: output,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                    continue
                }
                try fileManager.createDirectory(
                    at: output.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                let contents = try extract(entry, from: archive)
                guard crc32(contents) == entry.checksum else {
                    throw SkillSourceError.invalidArchive
                }
                try contents.write(to: output, options: [.atomic])
                try fileManager.setAttributes(
                    [.posixPermissions: entry.permissions],
                    ofItemAtPath: output.path
                )
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private static func parseEntries(
        _ archive: Data,
        limits: SecureZIPLimits
    ) throws -> [Entry] {
        guard let endOffset = findEndOfCentralDirectory(in: archive),
              archive.uint32(at: endOffset) == 0x0605_4B50
        else {
            throw SkillSourceError.invalidArchive
        }
        let diskNumber = try archive.uint16Checked(at: endOffset + 4)
        let centralDirectoryDisk = try archive.uint16Checked(at: endOffset + 6)
        let diskEntryCount = try archive.uint16Checked(at: endOffset + 8)
        let entryCount = Int(try archive.uint16Checked(at: endOffset + 10))
        let centralSize = Int(try archive.uint32Checked(at: endOffset + 12))
        let centralOffset = Int(try archive.uint32Checked(at: endOffset + 16))
        let archiveCommentLength = Int(try archive.uint16Checked(at: endOffset + 20))
        guard diskNumber == 0,
              centralDirectoryDisk == 0,
              Int(diskEntryCount) == entryCount,
              endOffset + 22 + archiveCommentLength == archive.count,
              centralOffset >= 0,
              centralSize >= 0,
              centralOffset + centralSize == endOffset
        else {
            throw SkillSourceError.unsupportedArchiveFeature
        }
        guard entryCount <= limits.maximumFiles else {
            throw SkillSourceError.archiveLimitExceeded
        }

        var entries: [Entry] = []
        var offset = centralOffset
        var expandedBytes = 0
        var normalizedPaths: Set<String> = []
        for _ in 0..<entryCount {
            guard try archive.uint32Checked(at: offset) == 0x0201_4B50 else {
                throw SkillSourceError.invalidArchive
            }
            let flags = try archive.uint16Checked(at: offset + 8)
            let method = try archive.uint16Checked(at: offset + 10)
            let checksum = try archive.uint32Checked(at: offset + 16)
            let compressedSize = Int(try archive.uint32Checked(at: offset + 20))
            let expandedSize = Int(try archive.uint32Checked(at: offset + 24))
            let nameLength = Int(try archive.uint16Checked(at: offset + 28))
            let extraLength = Int(try archive.uint16Checked(at: offset + 30))
            let commentLength = Int(try archive.uint16Checked(at: offset + 32))
            let externalAttributes = try archive.uint32Checked(at: offset + 38)
            let localOffset = Int(try archive.uint32Checked(at: offset + 42))
            let nameStart = offset + 46
            let nextOffset = nameStart + nameLength + extraLength + commentLength
            guard nextOffset <= archive.count,
                  compressedSize >= 0,
                  expandedSize >= 0,
                  flags & 0x0001 == 0,
                  method == 0 || method == 8
            else {
                throw SkillSourceError.unsupportedArchiveFeature
            }
            guard let rawName = String(
                data: archive.subdata(in: nameStart..<(nameStart + nameLength)),
                encoding: .utf8
            ) else {
                throw SkillSourceError.invalidArchive
            }
            let path = try safeRelativePath(rawName, maximumDepth: limits.maximumDepth)
            let posixMode = (externalAttributes >> 16) & 0o177777
            let fileType = posixMode & 0o170000
            let isDirectory = rawName.hasSuffix("/") || fileType == 0o040000
            if fileType == 0o120000
                || (fileType != 0 && fileType != 0o040000 && fileType != 0o100000)
            {
                throw SkillSourceError.unsupportedArchiveFeature
            }
            let comparisonPath = path.precomposedStringWithCanonicalMapping.lowercased()
            guard normalizedPaths.insert(comparisonPath).inserted else {
                throw SkillSourceError.invalidArchive
            }
            expandedBytes += expandedSize
            guard expandedBytes <= limits.maximumExpandedBytes else {
                throw SkillSourceError.archiveLimitExceeded
            }
            entries.append(Entry(
                path: path,
                compressionMethod: method,
                checksum: checksum,
                compressedSize: compressedSize,
                expandedSize: expandedSize,
                localHeaderOffset: localOffset,
                isDirectory: isDirectory,
                permissions: posixMode & 0o111 == 0 ? 0o600 : 0o700
            ))
            offset = nextOffset
        }
        return entries
    }

    private static func extract(_ entry: Entry, from archive: Data) throws -> Data {
        guard try archive.uint32Checked(at: entry.localHeaderOffset) == 0x0403_4B50 else {
            throw SkillSourceError.invalidArchive
        }
        let nameLength = Int(try archive.uint16Checked(at: entry.localHeaderOffset + 26))
        let extraLength = Int(try archive.uint16Checked(at: entry.localHeaderOffset + 28))
        let start = entry.localHeaderOffset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= archive.count else {
            throw SkillSourceError.invalidArchive
        }
        let compressed = archive.subdata(in: start..<end)
        if entry.compressionMethod == 0 {
            guard compressed.count == entry.expandedSize else {
                throw SkillSourceError.invalidArchive
            }
            return compressed
        }
        if entry.expandedSize == 0 { return Data() }
        var output = Data(count: entry.expandedSize)
        let decoded = output.withUnsafeMutableBytes { outputBuffer in
            compressed.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    entry.expandedSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    entry.compressedSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded == entry.expandedSize else {
            throw SkillSourceError.invalidArchive
        }
        return output
    }

    private static func safeRelativePath(
        _ rawPath: String,
        maximumDepth: Int
    ) throws -> String {
        guard !rawPath.isEmpty,
              !rawPath.hasPrefix("/"),
              !rawPath.hasPrefix("~"),
              !rawPath.contains("\\"),
              !rawPath.unicodeScalars.contains(where: { $0.value == 0 })
        else {
            throw SkillSourceError.unsafeArchivePath(rawPath)
        }
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              components.count <= maximumDepth,
              components.allSatisfy({ $0 != "." && $0 != ".." })
        else {
            throw SkillSourceError.unsafeArchivePath(rawPath)
        }
        return components.joined(separator: "/")
    }

    private static func findEndOfCentralDirectory(in archive: Data) -> Int? {
        guard archive.count >= 22 else { return nil }
        let lowerBound = max(0, archive.count - 65_557)
        var offset = archive.count - 22
        while offset >= lowerBound {
            if archive.uint32(at: offset) == 0x0605_4B50 { return offset }
            if offset == 0 { break }
            offset -= 1
        }
        return nil
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
            }
        }
        return ~crc
    }

    private struct Entry {
        let path: String
        let compressionMethod: UInt16
        let checksum: UInt32
        let compressedSize: Int
        let expandedSize: Int
        let localHeaderOffset: Int
        let isDirectory: Bool
        let permissions: UInt32
    }
}

private extension Data {
    func uint16Checked(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw SkillSourceError.invalidArchive
        }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32Checked(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw SkillSourceError.invalidArchive
        }
        return uint32(at: offset)!
    }

    func uint32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
