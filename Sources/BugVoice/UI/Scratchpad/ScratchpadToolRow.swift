import SwiftUI
import VoiceCore

/// AI and labels, with the editor's actions on the right or on a second line.
struct ScratchpadToolRow<Trailing: View>: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    let note: NoteDocument
    let trailing: Trailing

    init(model: AppModel, note: NoteDocument, @ViewBuilder trailing: () -> Trailing) {
        self.model = model
        self.note = note
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                left
                Spacer(minLength: LayoutTokens.spacing[2])
                trailing
            }
            VStack(alignment: .trailing, spacing: LayoutTokens.spacing[0]) {
                left.frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        }
        .padding(.horizontal, LayoutTokens.spacing[3])
        .padding(.bottom, LayoutTokens.spacing[0])
    }

    private var left: some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            aiToggle
            FolderPicker(model: model, folderID: note.frontMatter.folderID) { id in
                Task { await model.setNoteLabels(id: note.id, folderID: id, tags: note.frontMatter.tags) }
            }
            TagField(tags: note.frontMatter.tags, catalog: model.allTagCatalog, noun: "note") { tags in
                Task { await model.setNoteLabels(id: note.id, folderID: note.frontMatter.folderID, tags: tags) }
            }
        }
    }

    private var aiToggle: some View {
        let on = model.settings.scratchpad.aiBarShown
        return Button {
            model.settings.scratchpad.aiBarShown.toggle()
        } label: {
            Label("AI", systemImage: "sparkles")
                .padding(.horizontal, LayoutTokens.spacing[1])
                .padding(.vertical, LayoutTokens.spacing[0])
                .background(on ? AnyShapeStyle(.bvAccentSoft) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                .overlay {
                    if on {
                        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius + 2)
                            .stroke(store.theme.accent.opacity(0.5), lineWidth: 3)
                            .padding(-2)
                    } else {
                        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius)
                            .stroke(.bvSeparator, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "on" : "off")
        .help("AI (show or hide the AI bar)")
    }
}
