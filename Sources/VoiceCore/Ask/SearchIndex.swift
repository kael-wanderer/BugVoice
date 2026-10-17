import Foundation

/// One item's passage vectors on disk: a JSON header, then Float16 little-endian values.
public struct SearchIndexFile: Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var passageID: String
        public var contentHash: String
        public init(passageID: String, contentHash: String) {
            self.passageID = passageID
            self.contentHash = contentHash
        }
    }

    public var model: String
    public var dimensions: Int
    public var entries: [Entry]
    public var vectors: [[Float]]

    public init(model: String, dimensions: Int, entries: [Entry], vectors: [[Float]]) {
        self.model = model
        self.dimensions = dimensions
        self.entries = entries
        self.vectors = vectors
    }

    private struct Header: Codable {
        var model: String
        var dimensions: Int
        var entries: [Entry]
    }

    public func encoded() throws -> Data {
        guard vectors.count == entries.count, vectors.allSatisfy({ $0.count == dimensions }) else {
            throw CocoaError(.coderInvalidValue)
        }
        let header = try JSONEncoder().encode(Header(model: model, dimensions: dimensions, entries: entries))
        guard header.count <= Int(UInt32.max) else { throw CocoaError(.coderInvalidValue) }
        var data = Data()
        data.reserveCapacity(4 + header.count + entries.count * dimensions * 2)
        withUnsafeBytes(of: UInt32(header.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(header)
        for vector in vectors {
            for value in vector {
                withUnsafeBytes(of: Float16(value).bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    public static func decode(_ data: Data) throws -> SearchIndexFile {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw CocoaError(.coderReadCorrupt) }
        let headerLength = Int(UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
        guard headerLength <= bytes.count - 4 else { throw CocoaError(.coderReadCorrupt) }
        let header = try JSONDecoder().decode(Header.self, from: Data(bytes[4..<(4 + headerLength)]))
        guard header.dimensions >= 0 else { throw CocoaError(.coderReadCorrupt) }
        let (count, overflow) = header.entries.count.multipliedReportingOverflow(by: header.dimensions)
        let valueBytes = bytes.count - 4 - headerLength
        guard !overflow, count <= Int.max / 2, valueBytes == count * 2 else {
            throw CocoaError(.coderReadCorrupt)
        }
        var vectors: [[Float]] = []
        vectors.reserveCapacity(header.entries.count)
        var offset = 4 + headerLength
        for _ in header.entries {
            var vector = [Float](repeating: 0, count: header.dimensions)
            for i in 0..<header.dimensions {
                let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                vector[i] = Float(Float16(bitPattern: bits))
                offset += 2
            }
            vectors.append(vector)
        }
        return SearchIndexFile(
            model: header.model, dimensions: header.dimensions, entries: header.entries, vectors: vectors)
    }
}

/// `SearchIndex/*.idx`: one file per item, owner-only, written through a temp file and replaced.
public actor SearchIndexStore {
    private let folder: URL

    public init(folder: URL) { self.folder = folder }

    public static func fileName(for source: AskSource) -> String { "\(source.key).idx" }

    /// Nil when the id could escape the folder.
    private func url(for source: AskSource) -> URL? {
        let name = Self.fileName(for: source)
        guard !name.contains("/"), !name.contains(".."), !name.contains("\0") else { return nil }
        return folder.appendingPathComponent(name)
    }

    public func load(_ source: AskSource) -> SearchIndexFile? {
        guard let url = url(for: source), let data = try? Data(contentsOf: url) else { return nil }
        return try? SearchIndexFile.decode(data)
    }

    public func save(_ file: SearchIndexFile, for source: AskSource) throws {
        guard let url = url(for: source) else { throw CocoaError(.fileWriteInvalidFileName) }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let data = try file.encoded()
        let temp = folder.appendingPathComponent(".index-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: temp) }
            else { try fm.moveItem(at: temp, to: url) }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove(_ source: AskSource) throws {
        guard let url = url(for: source), FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Removes `.idx` files whose item is not in `sources`; other files stay.
    public func prune(keeping sources: Set<AskSource>) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return }
        let keep = Set(sources.map { Self.fileName(for: $0) })
        for name in try fm.contentsOfDirectory(atPath: folder.path)
        where name.hasSuffix(".idx") && !keep.contains(name) {
            try fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Vectors usable for `passages`: same model and matching hash, keyed by passage id.
    public func vectors(for passages: [AskPassage], source: AskSource, model: String) -> [String: [Float]] {
        guard let file = load(source), file.model == model else { return [:] }
        var byID: [String: (String, [Float])] = [:]
        for (entry, vector) in zip(file.entries, file.vectors) { byID[entry.passageID] = (entry.contentHash, vector) }
        var out: [String: [Float]] = [:]
        for p in passages {
            if let (hash, vector) = byID[p.id], hash == p.contentHash { out[p.id] = vector }
        }
        return out
    }
}

public enum SearchIndexPlanner {
    /// Passages that need a new vector; reuses vectors whose hash is unchanged.
    public static func update(
        _ old: SearchIndexFile?, passages: [AskPassage], model: String
    ) -> (keep: SearchIndexFile, missing: [AskPassage]) {
        guard let old, old.model == model else {
            return (SearchIndexFile(model: model, dimensions: 0, entries: [], vectors: []), passages)
        }
        var byID: [String: (SearchIndexFile.Entry, [Float])] = [:]
        for (entry, vector) in zip(old.entries, old.vectors) { byID[entry.passageID] = (entry, vector) }
        var entries: [SearchIndexFile.Entry] = [], vectors: [[Float]] = [], missing: [AskPassage] = []
        for p in passages {
            if let (entry, vector) = byID[p.id], entry.contentHash == p.contentHash {
                entries.append(entry)
                vectors.append(vector)
            } else {
                missing.append(p)
            }
        }
        let keep = SearchIndexFile(
            model: model, dimensions: entries.isEmpty ? 0 : old.dimensions, entries: entries, vectors: vectors)
        return (keep, missing)
    }
}
