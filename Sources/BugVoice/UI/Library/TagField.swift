import SwiftUI
import VoiceCore

/// Tag chips with `+ Add tag`. Typing shows catalog tags containing the text
/// (prefix matches first) and `Create tag "#x"` for a new name. Return picks
/// the first entry; Escape cancels.
struct TagField: View {
    let tags: [String]
    let catalog: [TagCount]
    /// "meeting" or "note", for the limit message.
    let noun: String
    let onChange: ([String]) -> Void
    @State private var editing = false
    @State private var text = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowRow {
                ForEach(tags, id: \.self) { tag in
                    TagChip(name: tag) { onChange(tags.filter { $0 != tag }) }
                }
                if editing {
                    TextField("#tag", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .focused($focused)
                        .onSubmit { pick(options.first) }
                        .onExitCommand(perform: cancel)
                        .onAppear { focused = true }
                } else {
                    Button("+ Add tag") { editing = true; message = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if editing, !options.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options, id: \.self) { option in
                        Button { pick(option) } label: { optionLabel(option) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private enum Option: Hashable {
        case existing(String, Int)
        case create(String)
    }

    private var options: [Option] {
        let needle = TagName.normalize(text)
        guard let needle else { return [] }
        let matches = catalog
            .filter { $0.name.contains(needle) && !tags.contains($0.name) }
            .sorted { lhs, rhs in
                let left = lhs.name.hasPrefix(needle), right = rhs.name.hasPrefix(needle)
                return left != right ? left : lhs.count > rhs.count
            }
            .prefix(6)
            .map { Option.existing($0.name, $0.count) }
        let exists = catalog.contains { $0.name == needle } || tags.contains(needle)
        return matches + (exists ? [] : [.create(needle)])
    }

    @ViewBuilder private func optionLabel(_ option: Option) -> some View {
        switch option {
        case .existing(let name, let count):
            HStack { Text("#\(name)"); Spacer(); Text("\(count)").foregroundStyle(.secondary) }
                .font(.caption).frame(width: 200)
        case .create(let name):
            Text("Create tag \"#\(name)\"").font(.caption).frame(width: 200, alignment: .leading)
        }
    }

    private func pick(_ option: Option?) {
        guard let option else {
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                message = "Tags use letters, numbers, - _ and /, up to 32 characters."
            }
            return
        }
        let name: String
        switch option {
        case .existing(let value, _): name = value
        case .create(let value): name = value
        }
        var labels = ItemLabels(tags: tags)
        switch labels.addTag(name) {
        case .added: onChange(labels.tags)
        case .full: message = "A \(noun) can have up to 10 tags."
        case .invalid: message = "Tags use letters, numbers, - _ and /, up to 32 characters."
        case .duplicate: break
        }
        cancel()
    }

    private func cancel() {
        text = ""
        editing = false
    }
}

/// Wraps chips onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
