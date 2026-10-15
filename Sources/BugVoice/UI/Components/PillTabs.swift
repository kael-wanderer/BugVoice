import AppKit
import SwiftUI

/// Rounded segmented control: a capsule track with the selected pill raised.
/// Used for page tabs and small filters.
struct PillTabs<Value: Hashable>: View {
    struct Item {
        var value: Value
        var title: String
        var badge: String? = nil
        var isEnabled = true
    }

    enum Size { case regular, small }

    let items: [Item]
    @Binding var selection: Value
    var size: Size = .regular

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                pill(items[index])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func pill(_ item: Item) -> some View {
        let selected = item.value == selection
        return Button {
            selection = item.value
        } label: {
            HStack(spacing: 5) {
                Text(item.title)
                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .font(size == .small ? .callout : .body)
            .fontWeight(selected ? .semibold : .regular)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, size == .small ? 10 : 14)
            .padding(.vertical, size == .small ? 3 : 5)
            .background {
                if selected {
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.55)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
