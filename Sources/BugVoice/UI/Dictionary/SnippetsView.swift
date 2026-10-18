import SwiftUI
import VoiceCore

struct SnippetsView: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var draft: SnippetDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            HeroCard(
                title: "Stuff you shouldn't have to say twice",
                text: "Say a trigger phrase and BugVoice puts in what you saved: links, intros, sign-offs, prompts. The saved text is pasted exactly, never reworded.",
                placeholder: "Add a trigger phrase — \"my linkedin\", \"cal link\"",
                isDisabled: model.dictionaryReadOnly,
                onAdd: { trigger in draft = SnippetDraft(snippetID: nil, trigger: trigger, text: "") }
            ) {
                HeroIllustration(symbol: "text.badge.plus") {
                    HeroChip { Text("\"Sign off\"").bold(); Text("↳ Best, Kael · kael@example.com").foregroundStyle(.bvSecondary) }
                    HeroChip { Text("\"My LinkedIn\"").bold(); Text("↳ linkedin.com/in/kael").foregroundStyle(.bvSecondary) }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.dictionary.snippets.count == 1 ? "1 snippet" : "\(model.dictionary.snippets.count) snippets").bvFont(.bodyStrong)
                    Spacer()
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: store.scaled(220))
                }
                .padding(.bottom, LayoutTokens.spacing[1])
                if model.dictionary.snippets.isEmpty {
                    Text("No snippets yet.").foregroundStyle(.bvSecondary).padding(.vertical, LayoutTokens.spacing[1])
                } else if filtered.isEmpty {
                    Text("No snippets match.").foregroundStyle(.bvSecondary).padding(.vertical, LayoutTokens.spacing[1])
                }
                ForEach(filtered) { snippet in
                    Divider()
                    row(snippet).padding(.vertical, LayoutTokens.spacing[1])
                }
            }
            .insightsCard()
        }
        .task(id: model.dictionaryAddRequest) {
            if model.dictionaryAddTarget == .snippets {
                draft = SnippetDraft(snippetID: nil, trigger: "", text: "")
                model.dictionaryAddTarget = nil
            }
        }
        .sheet(item: $draft) { SnippetEditorSheet(model: model, draft: $0) }
    }

    private func row(_ snippet: Snippet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing[2]) {
            Text("“\(snippet.trigger)”").bold().frame(minWidth: store.scaled(140), alignment: .leading)
            Text("↳ " + snippet.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                .bvCode(.body).foregroundStyle(.bvSecondary)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: LayoutTokens.spacing[1]) {
                Button("Edit") { draft = SnippetDraft(snippetID: snippet.id, trigger: snippet.trigger, text: snippet.text) }
                Button("Delete") { Task { await model.editDictionary { $0.deleteSnippet(snippet.id) } } }
            }
            .buttonStyle(.borderless).disabled(model.dictionaryReadOnly)
        }
    }

    private var filtered: [Snippet] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.dictionary.snippets }
        return model.dictionary.snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query)
        }
    }
}
