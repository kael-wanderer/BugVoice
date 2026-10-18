import SwiftUI
import VoiceCore

/// Folder, Tags and (meetings only) Suggested rows under an item's title.
struct LabelsBox: View {
    @Environment(AppearanceStore.self) private var store
    let model: AppModel
    let labels: ItemLabels
    let catalog: [TagCount]
    let noun: String
    var suggested: [String] = []
    var suggestionSource: String = ""
    let onChange: (ItemLabels) -> Void
    var onAcceptSuggestion: (String) -> Void = { _ in }
    var onDismissSuggestions: () -> Void = {}

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Folder").bvFont(.footnote).foregroundStyle(.bvSecondary)
                FolderPicker(model: model, folderID: labels.folderID) { id in
                    onChange(ItemLabels(folderID: id, tags: labels.tags))
                }
            }
            GridRow {
                Text("Tags").bvFont(.footnote).foregroundStyle(.bvSecondary)
                TagField(tags: labels.tags, catalog: catalog, noun: noun) { tags in
                    onChange(ItemLabels(folderID: labels.folderID, tags: tags))
                }
            }
            if !suggested.isEmpty {
                GridRow {
                    Text("Suggested").bvFont(.footnote).foregroundStyle(.bvSecondary)
                    HStack(spacing: LayoutTokens.spacing[0]) {
                        ForEach(suggested, id: \.self) { tag in
                            Button("+ #\(tag)") { onAcceptSuggestion(tag) }
                                .buttonStyle(.plain)
                                .bvFont(.footnote)
                                .padding(.horizontal, LayoutTokens.spacing[1])
                                .padding(.vertical, LayoutTokens.spacing[0])
                                .foregroundStyle(.bvAccent)
                                .overlay(Capsule().strokeBorder(.purple, style: StrokeStyle(lineWidth: 1, dash: [3])))
                        }
                        Text("From the summary · \(suggestionSource) · click to add")
                            .bvFont(.footnote).foregroundStyle(.bvSecondary)
                        Button(action: onDismissSuggestions) { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.bvSecondary)
                            .help("Dismiss suggestions")
                            .accessibilityLabel("Dismiss suggestions")
                    }
                }
            }
        }
        .padding(LayoutTokens.spacing[1])
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).strokeBorder(store.theme.secondaryText.opacity(0.25)))
    }
}
