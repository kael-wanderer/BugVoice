import CryptoKit
import Foundation
import VoiceCore

public enum BuiltInDownloadError: Error, Equatable {
    case hashMismatch
    case notEnoughSpace(neededBytes: Int64)
    case insecureURL
    case badStatus(Int)
    case incomplete
}

/// Downloads a built-in model over HTTPS with resume, then checks its SHA-256.
/// A file that fails the hash is deleted. Cancelling the task keeps the `.part`
/// file so the next attempt resumes.
public final class BuiltInDownloader: Sendable {
    public init() {}

    private static let chunkSize = 1 << 20

    public func download(
        _ model: BuiltInModel,
        into dir: URL,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL {
        try Self.requireHTTPS(model.url)

        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let part = BuiltInDownloadPlan.partialURL(for: model, in: dir)
        let final = BuiltInDownloadPlan.finalURL(for: model, in: dir)

        var step = BuiltInDownloadPlan.next(partialBytes: Self.size(of: part), expected: model.bytes)
        if step == .restart {
            try? fm.removeItem(at: part)
            step = .start
        }

        // Up to two passes: a server that rejects the range (416) gets one restart from zero.
        var attempts = 0
        while step != .verify {
            attempts += 1
            let have = Self.size(of: part) ?? 0
            try Self.checkFreeSpace(model: model, partialBytes: have, in: dir)
            do {
                try await fetch(model, step: step, part: part, progress: progress)
                break
            } catch RangeRejected.rejected where attempts < 2 {
                try? fm.removeItem(at: part)
                step = .start
            }
        }

        guard Self.size(of: part) == model.bytes else { throw BuiltInDownloadError.incomplete }
        progress(1)
        try Self.verify(part, sha256: model.sha256)
        if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
        try fm.moveItem(at: part, to: final)
        return final
    }

    private enum RangeRejected: Error { case rejected }

    private func fetch(
        _ model: BuiltInModel,
        step: DownloadStep,
        part: URL,
        progress: @Sendable (Double) -> Void
    ) async throws {
        var request = URLRequest(url: model.url)
        request.timeoutInterval = 60
        var offset: Int64 = 0
        if case .resume(let header) = step {
            request.setValue(header, forHTTPHeaderField: "Range")
            offset = Self.size(of: part) ?? 0
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: HTTPSOnlyRedirects())
        guard let http = response as? HTTPURLResponse else { throw BuiltInDownloadError.badStatus(-1) }
        switch http.statusCode {
        case 206 where offset > 0:
            break
        case 200:
            offset = 0   // full body, even if a range was asked for: start over
        case 416 where offset > 0:
            throw RangeRejected.rejected
        default:
            throw BuiltInDownloadError.badStatus(http.statusCode)
        }

        let fm = FileManager.default
        if offset == 0 || !fm.fileExists(atPath: part.path) {
            fm.createFile(atPath: part.path, contents: nil, attributes: [.posixPermissions: 0o600])
            offset = 0
        }
        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }
        if offset == 0 { try handle.truncate(atOffset: 0) }
        try handle.seekToEnd()

        var written = offset
        var buffer = Data()
        buffer.reserveCapacity(Self.chunkSize)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= Self.chunkSize {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(min(1, Double(written) / Double(model.bytes)))
                try Task.checkCancellation()
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        progress(min(1, Double(written) / Double(model.bytes)))
    }

    /// Only HTTPS URLs are fetched.
    static func requireHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else { throw BuiltInDownloadError.insecureURL }
    }

    private static func size(of url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = attrs[.size] as? NSNumber else { return nil }
        return n.int64Value
    }

    /// Needs the rest of the file plus 10% headroom.
    private static func checkFreeSpace(model: BuiltInModel, partialBytes: Int64, in dir: URL) throws {
        let remaining = max(0, model.bytes - partialBytes)
        let needed = remaining + remaining / 10
        let values = try dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < needed {
            throw BuiltInDownloadError.notEnoughSpace(neededBytes: needed)
        }
    }

    /// Checks the file's SHA-256. On mismatch the file is deleted.
    public static func verify(_ file: URL, sha256 expected: String) throws {
        let actual = try sha256Hex(of: file)
        guard actual == expected.lowercased() else {
            try? FileManager.default.removeItem(at: file)
            throw BuiltInDownloadError.hashMismatch
        }
    }

    /// Lowercase hex SHA-256, read in 1 MB chunks.
    public static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Refuses redirects that leave HTTPS.
private final class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        request.url?.scheme?.lowercased() == "https" ? request : nil
    }
}
