import SwiftUI
import VoiceCore

enum DictionaryTab: Hashable { case words, snippets }

struct DictionaryPage: View {
    @Bindable var model: AppModel
    @State private var tab: DictionaryTab = .words

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dictionary").font(.title2.weight(.semibold))
                PillTabs(
                    items: [
                        .init(value: DictionaryTab.words, title: "Dictionary"),
                        .init(value: DictionaryTab.snippets, title: "Snippets"),
                    ],
                    selection: $tab
                )
                if model.dictionaryReadOnly {
                    Text("Dictionary was saved by a newer BugVoice.").foregroundStyle(.secondary)
                }
                switch tab {
                case .words: DictionaryWordsView(model: model)
                case .snippets: SnippetsView(model: model)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
