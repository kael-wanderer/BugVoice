import SwiftUI
import VoiceCore

struct DictionaryWordsView: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            HeroCard(
                title: "Add words to your dictionary",
                text: "Names, tools and acronyms BugVoice should always get right. Add what it mishears them as, and those are fixed too.",
                placeholder: "Add words separated by commas — OpenWhispr, Supabase, Kael",
                hint: "Words also guide speech recognition and the text model.",
                isDisabled: model.dictionaryReadOnly,
                onAdd: { text in Task { await model.editDictionary { _ = $0.addWords(text) } } }
            ) {
                HeroIllustration(symbol: "character.book.closed") {
                    HeroChip { Text("open whisper").strikethrough().foregroundStyle(.bvSecondary); Text("OpenWhispr").bold() }
                    HeroChip { Text("bug voice").strikethrough().foregroundStyle(.bvSecondary); Text("BugVoice").bold() }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.dictionary.words.count == 1 ? "1 word" : "\(model.dictionary.words.count) words").bvFont(.bodyStrong)
                    Spacer()
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: store.scaled(220))
                }
                .padding(.bottom, LayoutTokens.spacing[1])
                if model.dictionary.words.isEmpty {
                    Text("No words yet.").foregroundStyle(.bvSecondary).padding(.vertical, LayoutTokens.spacing[1])
                } else if filtered.isEmpty {
                    Text("No words match.").foregroundStyle(.bvSecondary).padding(.vertical, LayoutTokens.spacing[1])
                }
                ForEach(filtered) { word in
                    Divider()
                    WordRow(model: model, word: word).padding(.vertical, LayoutTokens.spacing[1])
                }
            }
            .insightsCard()
        }
    }

    private var filtered: [DictionaryWord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.dictionary.words }
        return model.dictionary.words.filter {
            $0.word.localizedCaseInsensitiveContains(query)
                || $0.heardAs.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

private struct WordRow: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    let word: DictionaryWord
    @State private var newName: String?
    @State private var newHeardAs: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutTokens.spacing[2]) {
            if newName != nil {
                TextField("Word", text: Binding(get: { newName ?? "" }, set: { newName = $0 }))
                    .textFieldStyle(.roundedBorder).frame(width: store.scaled(180))
                    .onSubmit(rename).onExitCommand { newName = nil }
            } else {
                Text(word.word).bold().frame(minWidth: store.scaled(140), alignment: .leading)
            }
            FlowLayout(spacing: LayoutTokens.spacing[0]) {
                if !word.heardAs.isEmpty { Text("Heard as").bvFont(.footnote).foregroundStyle(.bvSecondary) }
                ForEach(word.heardAs, id: \.self) { form in
                    HStack(spacing: LayoutTokens.spacing[0]) {
                        Text(form)
                        Button { edit { $0.removeHeardAs(form, from: word.id) } } label: {
                            Image(systemName: "xmark").bvFont(.caption)
                        }
                        .buttonStyle(.borderless).help("Remove").disabled(model.dictionaryReadOnly)
                    }
                    .bvFont(.body).padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0])
                    .background(Capsule().fill(store.theme.text.opacity(0.07)))
                }
                if newHeardAs != nil {
                    TextField("open whisper, open whispers", text: Binding(get: { newHeardAs ?? "" }, set: { newHeardAs = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: store.scaled(200))
                        .onSubmit(addHeardAs).onExitCommand { newHeardAs = nil }
                } else {
                    Button("+ heard as") { newHeardAs = "" }.buttonStyle(.borderless).disabled(model.dictionaryReadOnly)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: LayoutTokens.spacing[1]) {
                Button("Edit") { newName = word.word }
                Button("Delete") { edit { $0.deleteWord(word.id) } }
            }
            .buttonStyle(.borderless).disabled(model.dictionaryReadOnly)
        }
    }

    private func edit(_ change: @escaping (inout DictionaryFile) -> Void) {
        Task { await model.editDictionary { change(&$0) } }
    }

    private func rename() {
        guard let name = newName else { return }
        edit { _ = $0.renameWord(word.id, to: name) }
        newName = nil
    }

    private func addHeardAs() {
        guard let text = newHeardAs else { return }
        edit { $0.addHeardAs(text, to: word.id) }
        newHeardAs = nil
    }
}
