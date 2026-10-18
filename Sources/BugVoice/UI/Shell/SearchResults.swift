import SwiftUI
import VoiceCore

struct SearchResults: View {
    @Environment(AppearanceStore.self) private var store
    let hits: [SearchHit]
    let selected: Int
    let model: AppModel
    let open: (SearchHit) -> Void
    var header: String? = nil
    var footer: String? = nil
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            if let header {
                Text(header.uppercased()).bvFont(.caption).foregroundStyle(.bvSecondary)
                    .padding(.horizontal, LayoutTokens.spacing[2]).padding(.top, LayoutTokens.spacing[1])
            }
            if hits.isEmpty {
                Text("No matches").bvFont(.body).foregroundStyle(.bvSecondary).padding(LayoutTokens.spacing[2])
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    Button { open(hit) } label: {
                        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                            Text(title(hit)).bvFont(.bodyStrong).lineLimit(1)
                            Text(secondLine(hit)).bvFont(.footnote).foregroundStyle(.bvSecondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LayoutTokens.spacing[2])
                        .background(index == selected ? AnyShapeStyle(.bvAccentSoft) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).id(hit.id)
                    .accessibilityLabel("\(title(hit)), \(secondLine(hit))")
                    .accessibilityAddTraits(index == selected ? .isSelected : [])
                }
                        }
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { rowsHeight = $0 }
                    }
                    .frame(height: min(rowsHeight, max(store.scaled(80), model.mainContentHeight - store.scaled(160))))
                    .onChange(of: selected) { _, _ in
                        if hits.indices.contains(selected) { reader.scrollTo(hits[selected].id) }
                    }
                }
            }
            if let footer {
                Rectangle().fill(.bvSeparator).frame(height: 1)
                Text(footer).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    .padding(LayoutTokens.spacing[2]).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LayoutTokens.spacing[0])
        .background(.bvCard, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(.bvSeparator))
        .shadow(color: store.theme.text.opacity(0.2), radius: LayoutTokens.spacing[1], y: LayoutTokens.spacing[0])
        .accessibilityElement(children: .contain).accessibilityLabel("Search results")
    }

    private func title(_ hit: SearchHit) -> String {
        // Passage hits need the current item title even when only the body matched.
        switch hit.target {
        case .meeting(let id, _, _): return model.meetingManifests.first { $0.id == id }?.title ?? hit.title
        case .note(let id): return model.notesController.notes.first { $0.id == id }?.title ?? hit.title
        default: return hit.title
        }
    }
    private func secondLine(_ hit: SearchHit) -> String {
        let kind: String
        switch hit.kind {
        case .meeting: kind = "Meeting"
        case .note: kind = "Note"
        case .dictation: kind = "Dictation" + (hit.date.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
        case .settings:
            if case .settings(let section) = hit.target {
                return "Settings · " + (GlobalSearch.settingsEntries.first { $0.section == section }?.label ?? section)
            }
            kind = "Settings"
        }
        return kind + (hit.snippet.isEmpty ? "" : " · \(hit.snippet)")
    }
}
