import SwiftUI
import VoiceCore

enum DictionaryTab: Hashable { case words, snippets }

struct DictionaryPage: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                RoundPills("Dictionary list", items: [(.words, "Words"), (.snippets, "Snippets")], selection: $model.dictionaryTab)
                if model.dictionaryReadOnly {
                    Text("Dictionary was saved by a newer BugVoice.").foregroundStyle(.bvSecondary)
                }
                switch model.dictionaryTab {
                case .words: DictionaryWordsView(model: model)
                case .snippets: SnippetsView(model: model)
                }
            }
            .bvPageColumn(.wide)

        }
    }
}
