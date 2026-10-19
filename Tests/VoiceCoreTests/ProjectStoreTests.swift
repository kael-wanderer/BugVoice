import Foundation
import Testing
@testable import VoiceCore

struct ProjectStoreTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bv-projects-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func addDedupesPath() {
        var file = ProjectFile()
        let first = file.add(path: "/a/BugVoice")
        let second = file.add(path: "/a/BugVoice/")
        #expect(first.added)
        #expect(!second.added)
        #expect(first.id == second.id)
        #expect(file.projects.count == 1)
        #expect(file.projects[0].name == "BugVoice")
    }

    @Test func addStopsAtTwenty() {
        var file = ProjectFile()
        for index in 0..<20 { #expect(file.add(path: "/p/\(index)").added) }
        #expect(!file.add(path: "/p/extra").added)
        #expect(file.projects.count == 20)
    }

    @Test func rescanKeepsHidden() {
        var file = ProjectFile()
        let id = file.add(path: "/a/BugVoice").id
        file.hide("TODO_ITEM", in: id)
        file.applyScan(id: id, words: [ProjectWord(word: "TODO_ITEM", rank: 8), ProjectWord(word: "AppModel", rank: 5)], fileCount: 3, at: Date())
        #expect(file.projects[0].hidden == ["TODO_ITEM"])
        #expect(file.projects[0].words.map(\.word) == ["AppModel"])
    }

    @Test func showRemovesFromHidden() {
        var file = ProjectFile()
        let id = file.add(path: "/a").id
        file.hide("AppModel", in: id)
        file.show("AppModel", in: id)
        #expect(file.projects[0].hidden.isEmpty)
    }

    @Test func renameTrimsAndIgnoresEmpty() {
        var file = ProjectFile()
        let id = file.add(path: "/a/BugVoice").id
        file.rename(id: id, to: "  Worktree  ")
        #expect(file.projects[0].name == "Worktree")
        file.rename(id: id, to: "  \n")
        #expect(file.projects[0].name == "Worktree")
    }

    @Test func relocateClearsMissing() {
        var file = ProjectFile()
        let id = file.add(path: "/old").id
        file.projects[0].missing = true
        file.relocate(id: id, to: "/new")
        #expect(file.projects[0].path == "/new")
        #expect(!file.projects[0].missing)
    }

    @Test func needsDailyScan() {
        let now = Date(timeIntervalSince1970: 100_000)
        let id = UUID()
        let new = Project(id: id, path: "/p", name: "p")
        #expect(ProjectFile().needsDailyScan(new, now: now))
        var recent = new
        recent.scannedAt = now.addingTimeInterval(-23 * 3_600)
        #expect(!ProjectFile().needsDailyScan(recent, now: now))
        recent.scannedAt = now.addingTimeInterval(-25 * 3_600)
        #expect(ProjectFile().needsDailyScan(recent, now: now))
        recent.missing = true
        #expect(!ProjectFile().needsDailyScan(recent, now: now))
    }

    @Test func roundTripAndTolerantDecode() throws {
        var file = ProjectFile()
        let id = file.add(path: "/x").id
        file.applyScan(id: id, words: [ProjectWord(word: "AppModel", rank: 6)], fileCount: 4, at: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try JSONDecoder().decode(ProjectFile.self, from: JSONEncoder().encode(file))
        #expect(decoded.projects.count == 1)
        #expect(decoded.projects[0].id == file.projects[0].id)
        #expect(decoded.projects[0].path == file.projects[0].path)
        #expect(decoded.projects[0].words == file.projects[0].words)
        #expect(!decoded.projects[0].missing)

        let tolerant = try JSONDecoder().decode(ProjectFile.self, from: Data(#"{"projects":[{"path":"/x","name":"x"}]}"#.utf8))
        #expect(tolerant.projects.count == 1)
        #expect(tolerant.projects[0].enabled)
        #expect(tolerant.projects[0].words.isEmpty)
        #expect(tolerant.projects[0].id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test func storeLoadsMissingAsEmpty() async {
        let store = ProjectStore(url: tempDir().appendingPathComponent("projects.json"))
        #expect(await store.load() == ProjectFile())
    }

    @Test func storeSurvivesCorruptFile() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("projects.json")
        try Data("garbage".utf8).write(to: url)
        let store = ProjectStore(url: url)
        #expect(await store.load() == ProjectFile())
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix("projects.corrupt-") })
    }
}
