import AppKit
import SwiftUI
import VoiceCore

struct ProjectsView: View {
    @Bindable var model: AppModel
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            HStack {
                Spacer()
                Button("Add folder…", action: chooseFolder)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.projects.projects.count >= ProjectFile.maxProjects)
                    .help(model.projects.projects.count >= ProjectFile.maxProjects ? "20 projects at most" : "")
            }
            if model.projects.projects.isEmpty {
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
                    Text("No projects yet").bvFont(.bodyStrong)
                    Text("Add a repo folder. Its file and code names help dictation spell them right in Terminal, VS Code, Cursor and Orca.")
                        .foregroundStyle(.bvSecondary)
                    Button("Add folder…", action: chooseFolder).buttonStyle(.borderedProminent)
                        .disabled(model.projects.projects.count >= ProjectFile.maxProjects)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .insightsCard()
            } else {
                ForEach(model.projects.projects) { project in
                    projectCard(project)
                }
                if let last = model.lastProjectMatch {
                    Text("Last match: \(last.name) in \(last.app), \(shortRelative(last.at))")
                        .bvFont(.footnote).foregroundStyle(.bvSecondary)
                }
            }
        }
        .task { model.projectsController.scanDueProjects() }
    }

    @ViewBuilder
    private func projectCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            HStack(spacing: LayoutTokens.spacing[2]) {
                ProjectNameField(name: project.name) { model.projectsController.rename(id: project.id, to: $0) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Project enabled", isOn: Binding(
                    get: { project.enabled },
                    set: { model.projectsController.setEnabled(id: project.id, $0) }
                )).labelsHidden().toggleStyle(.switch).fixedSize()
            }
            Text(URL(fileURLWithPath: project.path).path.abbreviatingWithTildeInPath)
                .bvCode(.footnote).foregroundStyle(.bvSecondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Text(summary(project)).bvFont(.footnote).foregroundStyle(.bvSecondary)
                Spacer()
                Button("Rescan") { model.projectsController.rescan(id: project.id) }
                Button("Remove", role: .destructive) { model.projectsController.remove(id: project.id) }
            }
            if project.missing {
                HStack {
                    Text("Folder not found — words kept from the last scan").foregroundStyle(.bvSecondary)
                    Spacer()
                    Button("Locate…") { locate(project) }
                }
            }
            if let status = model.projectScanState[project.id] {
                switch status {
                case .scanning(let files):
                    Text("Scanning… \(files.formatted()) files").bvFont(.footnote).foregroundStyle(.bvSecondary)
                    ProgressView().controlSize(.small)
                case .failed(let message):
                    Text(message).bvFont(.footnote).foregroundStyle(.bvSecondary)
                case .stopped(let files):
                    Text("Stopped after 30 s — \(files.formatted()) files read").bvFont(.footnote).foregroundStyle(.bvSecondary)
                }
            }
            if !project.words.isEmpty {
                Divider()
                let shown = expanded.contains(project.id) ? project.words : Array(project.words.prefix(30))
                FlowLayout(spacing: LayoutTokens.spacing[1]) {
                    ForEach(shown, id: \.word) { word in
                        HStack(spacing: 4) {
                            Button(word.word) { model.projectsController.addToDictionary(word.word) }
                                .buttonStyle(.borderless).help("Add to Dictionary")
                            Text("\(word.rank)").bvFont(.caption).foregroundStyle(.bvSecondary)
                            Button("×") { model.projectsController.hide(word.word, in: project.id) }
                                .buttonStyle(.borderless).foregroundStyle(.bvSecondary).help("Hide")
                        }
                        .bvCode(.footnote).padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, 3)
                        .background(store.theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                if project.words.count > 30 {
                    Button(expanded.contains(project.id) ? "Show less" : "Show all \(project.words.count)") {
                        if expanded.contains(project.id) { expanded.remove(project.id) }
                        else { expanded.insert(project.id) }
                    }.buttonStyle(.borderless)
                }
            }
            if !project.hidden.isEmpty {
                HStack(spacing: LayoutTokens.spacing[1]) {
                    Text("Hidden:").bvFont(.footnote).foregroundStyle(.bvSecondary)
                    FlowLayout(spacing: LayoutTokens.spacing[1]) {
                        ForEach(project.hidden, id: \.self) { word in
                            HStack(spacing: 3) {
                                Text(word).strikethrough()
                                Button("↺") { model.projectsController.show(word, in: project.id) }
                                    .buttonStyle(.borderless).help("Show again")
                            }
                            .bvCode(.footnote).foregroundStyle(.bvSecondary)
                        }
                    }
                }
            }
        }
        .insightsCard()
    }

    private var store: AppearanceStore { model.appearance }

    private func summary(_ project: Project) -> String {
        let wordLabel = project.words.count == 1 ? "1 word" : "\(project.words.count) words"
        let fileLabel = project.fileCount == 1 ? "1 file" : "\(project.fileCount) files"
        guard let date = project.scannedAt else { return "\(wordLabel) · \(fileLabel)" }
        return "\(wordLabel) · \(fileLabel) · scanned \(shortRelative(date))"
    }

    private func shortRelative(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) h ago" }
        return "\(Int(seconds / 86_400)) d ago"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add folder"
        panel.begin { response in
            if response == .OK, let url = panel.url { model.projectsController.add(url: url) }
        }
    }

    private func locate(_ project: Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Locate folder"
        panel.begin { response in
            if response == .OK, let url = panel.url { model.projectsController.relocate(id: project.id, to: url.path) }
        }
    }
}

private struct ProjectNameField: View {
    let name: String
    let rename: (String) -> Void
    @State private var draft: String?

    var body: some View {
        TextField("Project name", text: Binding(get: { draft ?? name }, set: { draft = $0 }))
            .textFieldStyle(.plain).bvFont(.bodyStrong)
            .onSubmit { if let draft { rename(draft) }; draft = nil }
            .onExitCommand { draft = nil }
    }
}

private extension String {
    var abbreviatingWithTildeInPath: String { (self as NSString).abbreviatingWithTildeInPath }
}
