import SwiftUI
import VoiceCore

/// Folder, Tags and (meetings only) Suggested rows under an item's title.
struct LabelsBox: View {
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
                Text("Folder").font(.caption).foregroundStyle(.secondary)
                FolderPicker(model: model, folderID: labels.folderID) { id in
                    onChange(ItemLabels(folderID: id, tags: labels.tags))
                }
            }
            GridRow {
                Text("Tags").font(.caption).foregroundStyle(.secondary)
                TagField(tags: labels.tags, catalog: catalog, noun: noun) { tags in
                    onChange(ItemLabels(folderID: labels.folderID, tags: tags))
                }
            }
            if !suggested.isEmpty {
                GridRow {
                    Text("Suggested").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(suggested, id: \.self) { tag in
                            Button("+ #\(tag)") { onAcceptSuggestion(tag) }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(.purple)
                                .overlay(Capsule().strokeBorder(.purple, style: StrokeStyle(lineWidth: 1, dash: [3])))
                        }
                        Text("From the summary · \(suggestionSource) · click to add")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(action: onDismissSuggestions) { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Dismiss suggestions")
                            .accessibilityLabel("Dismiss suggestions")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
    }
}
