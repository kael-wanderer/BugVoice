import AppKit
import BugVoiceMac
import Foundation
import VoiceCore

enum ProjectScanStatus: Equatable {
    case scanning(files: Int)
    case failed(String)
    case stopped(files: Int)
}

@MainActor
final class ProjectsController {
    private unowned let model: AppModel
    private let store: ProjectStore
    private var queue: [UUID] = []
    private var scanning = false
    private var activeID: UUID?

    init(model: AppModel, store: ProjectStore) {
        self.model = model
        self.store = store
    }

    func load() async {
        model.projects = await store.load()
        for index in model.projects.projects.indices {
            let exists = FileManager.default.fileExists(atPath: model.projects.projects[index].path)
            model.projects.projects[index].missing = !exists
            if !exists { model.projectScanState[model.projects.projects[index].id] = .failed("Folder not found") }
        }
        await save()
        scanDueProjects()
    }

    func add(url: URL) {
        let result = model.projects.add(path: url.standardizedFileURL.path)
        model.selectedProjectID = result.id
        if result.added { persist(); enqueue(result.id) }
    }

    func rescan(id: UUID) { enqueue(id) }

    func remove(id: UUID) {
        model.projects.remove(id: id)
        model.projectScanState[id] = nil
        if model.selectedProjectID == id { model.selectedProjectID = nil }
        persist()
    }

    func rename(id: UUID, to name: String) { model.projects.rename(id: id, to: name); persist() }
    func setEnabled(id: UUID, _ on: Bool) { model.projects.setEnabled(id: id, on); persist() }
    func hide(_ word: String, in id: UUID) { model.projects.hide(word, in: id); persist() }
    func show(_ word: String, in id: UUID) { model.projects.show(word, in: id); persist() }

    func relocate(id: UUID, to path: String) {
        model.projects.relocate(id: id, to: path)
        model.projectScanState[id] = nil
        persist()
        enqueue(id)
    }

    func addToDictionary(_ word: String) {
        Task { await model.editDictionary { $0.addWords(word) } }
    }

    func scanDueProjects(now: Date = Date()) {
        for project in model.projects.projects where model.projects.needsDailyScan(project, now: now) {
            enqueue(project.id)
        }
    }

    private func enqueue(_ id: UUID) {
        guard model.projects.projects.contains(where: { $0.id == id }), !queue.contains(id), activeID != id else { return }
        queue.append(id)
        guard !scanning else { return }
        Task { await drain() }
    }

    private func drain() async {
        guard !scanning else { return }
        scanning = true
        while !queue.isEmpty {
            let id = queue.removeFirst()
            activeID = id
            guard let project = model.projects.projects.first(where: { $0.id == id }) else { activeID = nil; continue }
            model.projectScanState[id] = .scanning(files: 0)
            let folder = URL(fileURLWithPath: project.path, isDirectory: true)
            let hidden = Set(project.hidden)
            let result = await Task.detached(priority: .utility) { () -> Result<ProjectScanResult, Error> in
                do { return .success(try await ProjectScanner.scan(folder: folder, hidden: hidden)) }
                catch { return .failure(error) }
            }.value
            switch result {
            case .success(let scan):
                model.projects.applyScan(id: id, words: scan.words, fileCount: scan.fileCount, at: Date())
                if scan.stoppedEarly { model.projectScanState[id] = .stopped(files: scan.fileCount) }
                else { model.projectScanState[id] = nil }
                await save()
            case .failure(let error):
                if let index = model.projects.projects.firstIndex(where: { $0.id == id }), error as? ProjectScanError == .folderNotFound {
                    model.projects.projects[index].missing = true
                    model.projectScanState[id] = .failed("Folder not found")
                } else if error as? ProjectScanError == .noCodeFiles {
                    model.projectScanState[id] = .failed("No code files found")
                } else {
                    model.projectScanState[id] = .failed(error.localizedDescription)
                }
                await save()
            }
            activeID = nil
        }
        scanning = false
    }

    private func persist() {
        let file = model.projects
        Task {
            do { try await store.save(file) }
            catch { model.saveError = "Could not save projects: \(error.localizedDescription)" }
        }
    }

    private func save() async {
        do { try await store.save(model.projects) }
        catch { model.saveError = "Could not save projects: \(error.localizedDescription)" }
    }
}
