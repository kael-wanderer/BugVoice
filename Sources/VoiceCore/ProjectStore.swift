import Foundation

public struct ProjectFile: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let maxProjects = 20

    public var schemaVersion: Int
    public var projects: [Project]

    public init(schemaVersion: Int = supportedSchemaVersion, projects: [Project] = []) {
        self.schemaVersion = schemaVersion
        self.projects = Array(projects.prefix(Self.maxProjects))
    }

    public mutating func add(path: String) -> (id: UUID, added: Bool) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if let project = projects.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == standardized }) {
            return (project.id, false)
        }
        guard projects.count < Self.maxProjects else { return (UUID(), false) }
        let name = URL(fileURLWithPath: standardized).lastPathComponent
        let project = Project(path: standardized, name: name)
        projects.append(project)
        return (project.id, true)
    }

    public mutating func remove(id: UUID) { projects.removeAll { $0.id == id } }

    public mutating func rename(id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = name
    }

    public mutating func setEnabled(id: UUID, _ on: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].enabled = on
    }

    public mutating func hide(_ word: String, in id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        if !projects[index].hidden.contains(word) { projects[index].hidden.append(word) }
        projects[index].words.removeAll { $0.word == word }
    }

    public mutating func show(_ word: String, in id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].hidden.removeAll { $0 == word }
    }

    public mutating func applyScan(id: UUID, words: [ProjectWord], fileCount: Int, at: Date) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let hidden = Set(projects[index].hidden)
        projects[index].words = words.filter { !hidden.contains($0.word) }.prefix(ProjectWordExtractor.maxWords).map { $0 }
        projects[index].fileCount = fileCount
        projects[index].scannedAt = at
        projects[index].missing = false
    }

    public mutating func relocate(id: UUID, to path: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].path = URL(fileURLWithPath: path).standardizedFileURL.path
        projects[index].missing = false
    }

    public func needsDailyScan(_ project: Project, now: Date) -> Bool {
        guard !project.missing else { return false }
        guard let scannedAt = project.scannedAt else { return true }
        return now.timeIntervalSince(scannedAt) >= 24 * 60 * 60
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, projects }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, default: Self.supportedSchemaVersion)
        projects = Array(c.value(.projects, default: [Project]()).prefix(Self.maxProjects))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(projects, forKey: .projects)
    }
}

public actor ProjectStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> ProjectFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return ProjectFile() }
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(ProjectFile.self, from: data) else {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("projects.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return ProjectFile()
        }
        return file
    }

    public func save(_ file: ProjectFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }
}
