import SwiftUI
import VoiceCore

struct ActionItemRowView: View {
    let row: ActionItemRow
    var showsUndo = false
    var setDone: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: LayoutTokens.spacing[2]) {
            Toggle(isOn: Binding(get: { row.doneAt != nil }, set: { setDone($0) })) { Text(row.item.text) }
                .labelsHidden().toggleStyle(.checkbox)
                .accessibilityLabel(row.item.text)
            Text(row.item.text)
                .bvFont(.body)
                .strikethrough(row.doneAt != nil && !showsUndo)
                .foregroundStyle(row.doneAt == nil ? .bvText : .bvSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let owner = row.item.owner {
                Text(owner).bvFont(.caption).foregroundStyle(.bvAccent)
                    .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, 1)
                    .background(.bvHover, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.bvSeparator))
            }
            if showsUndo {
                HStack(spacing: 3) {
                    Text("Done ·").foregroundStyle(.bvSecondary)
                    Button("Undo") { setDone(false) }.buttonStyle(.plain).foregroundStyle(.bvAccent)
                }.bvFont(.footnote)
            } else if let date = row.doneAt {
                Text("Done \(Self.date(date))").bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
        }
        .padding(.horizontal, LayoutTokens.spacing[2]).padding(.vertical, LayoutTokens.spacing[1])
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func date(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
