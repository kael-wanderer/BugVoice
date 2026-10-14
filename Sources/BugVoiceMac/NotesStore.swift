import Darwin
import Foundation
import VoiceCore

public enum NotesStoreOutcome: Equatable, Sendable {
    case unchanged(NoteFileVersion)
    case reloaded(NoteDocument, NoteFileVersion)
    case saved(NoteDocument, NoteFileVersion)
    case conflict(NoteFileVersion)
    case stale(NoteDocument, NoteFileVersion)
}

public enum NotesStoreError: Error, Equatable {
    case missing(NoteID)
    case invalidFilename(String)
}

/// The sole owner of Markdown files in the Notes directory.
public actor NotesStore {
    private let directory: URL
    private var pathsByID: [NoteID: String] = [:]
    private var highestSavedRevision: [NoteID: UInt64] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    public func list() throws -> [NoteDocument] {
        try ensureDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            $0.pathExtension.lowercased() == "md"
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }

        var notes = [NoteDocument]()
        for url in urls.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let slug = url.deletingPathExtension().lastPathComponent
            let id: NoteID
            if let existing = pathsByID.first(where: { $0.value == url.lastPathComponent })?.key {
                id = existing
            } else if pathsByID[NoteID(rawValue: slug)] == nil {
                id = NoteID(rawValue: slug)
            } else {
                id = NoteID()
            }
            pathsByID[id] = url.lastPathComponent
            notes.append(try read(id: id, url: url))
        }
        let present = Set(urls.map(\.lastPathComponent))
        pathsByID = pathsByID.filter { present.contains($0.value) }
        return notes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func open(id: NoteID) throws -> NoteDocument {
        let url = try url(for: id)
        return try read(id: id, url: url)
    }

    public func create(title: String, body: String = "") throws -> NoteDocument {
        try ensureDirectory()
        let existing = try markdownFilenames()
        let slug = NotesSlug.available(title, existingFilenames: existing)
        let candidateID = NoteID(rawValue: slug)
        let id = pathsByID[candidateID] == nil ? candidateID : NoteID()
        let url = directory.appendingPathComponent("\(slug).md")
        let data = NotesMarkdownDocument.serialize(title: title, body: body)
        try durableReplace(data, at: url)
        let version = try fingerprint(at: url)
        pathsByID[id] = url.lastPathComponent
        highestSavedRevision[id] = 0
        return NoteDocument(id: id, title: title, body: body, modifiedAt: version.modifiedAt, fileVersion: version)
    }

    public func save(
        _ note: NoteDocument,
        expectedVersion: NoteFileVersion,
        isDirty: Bool,
        keepMine: Bool = false
    ) throws -> NotesStoreOutcome {
        let url = try url(for: note.id)
        let savedRevision = highestSavedRevision[note.id] ?? 0
        guard NotesAutosavePolicy.mayWrite(requestedRevision: note.revision, storedRevision: savedRevision) else {
            return .stale(note, try fingerprint(at: url))
        }
        let currentVersion = try fingerprint(at: url)
        if NotesAutosavePolicy.fileVersionChanged(from: expectedVersion, to: currentVersion) {
            guard isDirty else {
                let external = try read(id: note.id, url: url)
                return .reloaded(external, currentVersion)
            }
            guard keepMine else { return .conflict(currentVersion) }
        }

        let data = NotesMarkdownDocument.serialize(title: note.title, body: note.body)
        try durableReplace(data, at: url)
        let version = try fingerprint(at: url)
        highestSavedRevision[note.id] = note.revision
        var result = note
        result.modifiedAt = version.modifiedAt
        result.fileVersion = version
        result.needsNormalization = false
        return .saved(result, version)
    }

    public func rename(id: NoteID, title: String, expectedVersion: NoteFileVersion) throws -> NoteDocument {
        let source = try url(for: id)
        let currentVersion = try fingerprint(at: source)
        guard currentVersion == expectedVersion else {
            throw NotesStoreError.invalidFilename("The note changed outside BugVoice")
        }
        let previous = try read(id: id, url: source)
        let filenames = try markdownFilenames()
        let slug = NotesSlug.available(title, existingFilenames: filenames, excludingFilename: source.lastPathComponent)
        let destination = directory.appendingPathComponent("\(slug).md")
        let data = NotesMarkdownDocument.serialize(title: title, body: previous.body)
        try durableReplace(data, at: destination)
        if source != destination {
            guard unlink(source.path) == 0 else { throw posixError() }
            try synchronizeDirectory()
        }
        pathsByID[id] = destination.lastPathComponent
        let version = try fingerprint(at: destination)
        var result = previous
        result.title = title
        result.modifiedAt = version.modifiedAt
        result.fileVersion = version
        result.needsNormalization = false
        return result
    }

    public func checkExternalChange(
        id: NoteID,
        knownVersion: NoteFileVersion,
        isDirty: Bool
    ) throws -> NotesStoreOutcome {
        let url = try url(for: id)
        let version = try fingerprint(at: url)
        guard NotesAutosavePolicy.fileVersionChanged(from: knownVersion, to: version) else {
            return .unchanged(version)
        }
        guard isDirty else { return .reloaded(try read(id: id, url: url), version) }
        return .conflict(version)
    }

    public func delete(id: NoteID, confirmed: Bool) throws {
        guard confirmed else { return }
        let url = try url(for: id)
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        pathsByID[id] = nil
        highestSavedRevision[id] = nil
    }

    private func read(id: NoteID, url: URL) throws -> NoteDocument {
        let data = try Data(contentsOf: url)
        let parsed = try NotesMarkdownDocument.parse(data: data, filename: url.lastPathComponent)
        let version = try fingerprint(data: data, at: url)
        return NoteDocument(
            id: id,
            title: parsed.title,
            body: parsed.body,
            revision: highestSavedRevision[id] ?? 0,
            modifiedAt: version.modifiedAt,
            fileVersion: version,
            needsNormalization: parsed.needsNormalization
        )
    }

    private func url(for id: NoteID) throws -> URL {
        let filename = pathsByID[id] ?? "\(id.rawValue).md"
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.lowercased().hasSuffix(".md") else {
            throw NotesStoreError.invalidFilename(filename)
        }
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw NotesStoreError.missing(id) }
        pathsByID[id] = filename
        return url
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func markdownFilenames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.lowercased().hasSuffix(".md") }
    }

    private func fingerprint(at url: URL) throws -> NoteFileVersion {
        let data = try Data(contentsOf: url)
        return try fingerprint(data: data, at: url)
    }

    private func fingerprint(data: Data, at url: URL) throws -> NoteFileVersion {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        return .fingerprint(data: data, modifiedAt: modifiedAt)
    }

    private func durableReplace(_ data: Data, at destination: URL) throws {
        try ensureDirectory()
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = temporary.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR) }
        guard descriptor >= 0 else { throw posixError() }
        var descriptorOpen = true
        do {
            try data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let count = write(descriptor, base.advanced(by: offset), buffer.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw posixError() }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0 else { throw posixError() }
            guard close(descriptor) == 0 else { throw posixError() }
            descriptorOpen = false
            let renameResult = temporary.path.withCString { oldPath in
                destination.path.withCString { newPath in Darwin.rename(oldPath, newPath) }
            }
            guard renameResult == 0 else { throw posixError() }
            try synchronizeDirectory()
        } catch {
            if descriptorOpen { _ = close(descriptor) }
            _ = unlink(temporary.path)
            throw error
        }
    }

    private func synchronizeDirectory() throws {
        let descriptor = directory.path.withCString { Darwin.open($0, O_RDONLY) }
        guard descriptor >= 0 else { throw posixError() }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
