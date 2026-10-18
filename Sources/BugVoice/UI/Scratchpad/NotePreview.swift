import SwiftUI
import VoiceCore

struct NotePreview: View {
    let note: NoteDocument
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
                Text("Edited \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))" + (model.folderName(note.frontMatter.folderID).map { " · \($0)" } ?? ""))
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Text(note.title).bvFont(.title2)
                if !note.frontMatter.tags.isEmpty {
                    FlowLayout { ForEach(note.frontMatter.tags, id: \.self) { TagChip(name: $0) } }
                }
                HStack {
                    Spacer(minLength: 0)
                    Button("Open in window") { Task { await model.openNoteInWindow(note.id) } }
                        .buttonStyle(.borderedProminent)
                }
                MarkdownDocView(text: note.body, onToggleTask: { _ in }, scrolls: false, pagePadding: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .bvPageColumn(.reading)
        }
    }
}
