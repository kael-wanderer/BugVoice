import BugVoiceMac
import SwiftUI
import VoiceCore

struct SuggestionsCard: View {
    let model: AppModel

    var body: some View {
        if !model.suggestions.pending.isEmpty {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
                HStack {
                    Text("Suggestions").bvFont(.bodyStrong)
                    Spacer()
                    Button("Add all") { Task { await model.acceptAllSuggestions() } }
                        .disabled(model.dictionaryReadOnly)
                }
                Text("Words you fixed after a paste.").bvFont(.footnote).foregroundStyle(.bvSecondary)
                ForEach(model.suggestions.pending) { suggestion in
                    Divider()
                    VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                        ViewThatFits(in: .horizontal) {
                            HStack { details(suggestion); Spacer(); actions(suggestion) }
                            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                                details(suggestion)
                                actions(suggestion)
                            }
                        }
                        Text(note(suggestion)).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    }
                }
            }
            .insightsCard()
        }
    }

    private func details(_ suggestion: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            Text(suggestion.written).bvFont(.bodyStrong)
            Text(metadata(suggestion)).bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
    }

    private func actions(_ suggestion: Suggestion) -> some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            Toggle("Replace every time", isOn: Binding(
                get: { model.suggestions.pending.first(where: { $0.id == suggestion.id })?.replace ?? suggestion.replace },
                set: { model.setSuggestionReplace(suggestion, $0) }))
                .toggleStyle(.switch).fixedSize()
            Button("Add") { Task { await model.acceptSuggestion(suggestion) } }
                .disabled(model.dictionaryReadOnly)
            Button("Dismiss") { model.dismissSuggestion(suggestion) }
        }
    }

    private func metadata(_ s: Suggestion) -> String {
        (["heard as “\(s.heard)”"] + (s.app.map { [$0] } ?? [])
            + ["\(s.count) \(s.count == 1 ? "time" : "times")"]).joined(separator: " · ")
    }

    private func note(_ s: Suggestion) -> String {
        if !s.replace, RealWords.isRealWord(s.heard), RealWords.isRealWord(s.written) {
            return "“\(s.heard)” and “\(s.written)” are both real words — added as a spelling hint only"
        }
        if CorrectionFilter.fold(s.heard) == CorrectionFilter.fold(s.written) {
            return "Vietnamese tone fix"
        }
        return "Last seen \(s.lastSeen.formatted(date: .omitted, time: .shortened))"
    }
}
