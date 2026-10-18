import SwiftUI
import VoiceCore

enum DictionaryTab: Hashable { case words, snippets }

struct DictionaryPage: View {
    @Bindable var model: AppModel
    @State private var tab: DictionaryTab = .words

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                Text("Dictionary").bvFont(.title2)
                PillTabs(
                    items: [
                        .init(value: DictionaryTab.words, title: "Dictionary"),
                        .init(value: DictionaryTab.snippets, title: "Snippets"),
                    ],
                    selection: $tab
                )
                if model.dictionaryReadOnly {
                    Text("Dictionary was saved by a newer BugVoice.").foregroundStyle(.bvSecondary)
                }
                switch tab {
                case .words: DictionaryWordsView(model: model)
                case .snippets: SnippetsView(model: model)
                }
            }
            .padding(LayoutTokens.spacing[4])
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
