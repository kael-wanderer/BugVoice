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
                HStack(alignment: .firstTextBaseline) {
                    Text(note.title).bvFont(.title2)
                    Spacer(minLength: LayoutTokens.spacing[2])
                    Button("Open Scratchpad editor") { Task { await model.openNoteInWindow(note.id) } }
                        .buttonStyle(.borderedProminent)
                }
                if !note.frontMatter.tags.isEmpty {
                    FlowLayout { ForEach(note.frontMatter.tags, id: \.self) { TagChip(name: $0) } }
                }
                MarkdownDocView(text: note.body, onToggleTask: { _ in }, scrolls: false, pagePadding: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .bvPageColumn(.reading)
        }
    }
}
