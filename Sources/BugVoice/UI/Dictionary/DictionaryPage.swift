import SwiftUI
import VoiceCore

enum DictionaryTab: Hashable { case words, snippets, projects }

struct DictionaryPage: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                RoundPills("Dictionary list", items: [(.words, "Words"), (.snippets, "Snippets"), (.projects, "Projects")], selection: $model.dictionaryTab)
                if model.dictionaryReadOnly {
                    Text("Dictionary was saved by a newer BugVoice.").foregroundStyle(.bvSecondary)
                }
                switch model.dictionaryTab {
                case .words: DictionaryWordsView(model: model)
                case .snippets: SnippetsView(model: model)
                case .projects: ProjectsView(model: model)
                }
            }
            .bvPageColumn(.wide)

        }
    }
}
