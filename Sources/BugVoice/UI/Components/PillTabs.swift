import AppKit
import SwiftUI
import VoiceCore

/// Rounded segmented control: a capsule track with the selected pill raised.
/// Used for page tabs and small filters.
struct PillTabs<Value: Hashable>: View {
    @Environment(AppearanceStore.self) private var store
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
        HStack(spacing: LayoutTokens.spacing[0]) {
            ForEach(items.indices, id: \.self) { index in
                pill(items[index])
            }
        }
        .padding(LayoutTokens.spacing[0])
        .background(Capsule().fill(store.theme.text.opacity(0.07)))
    }

    private func pill(_ item: Item) -> some View {
        let selected = item.value == selection
        return Button {
            selection = item.value
        } label: {
            HStack(spacing: LayoutTokens.spacing[0]) {
                Text(item.title)
                if let badge = item.badge {
                    Text(badge)
                        .bvFont(.caption)
                        .padding(.horizontal, LayoutTokens.spacing[0]).padding(.vertical, LayoutTokens.spacing[0])
                        .background(Capsule().fill(store.theme.text.opacity(0.08)))
                }
            }
            .bvFont(size == .small ? .footnote : .body)
            .fontWeight(selected ? .semibold : .regular)
            .foregroundStyle(selected ? store.theme.text : store.theme.secondaryText)
            .padding(.horizontal, size == .small ? LayoutTokens.spacing[1] : LayoutTokens.spacing[3])
            .padding(.vertical, LayoutTokens.spacing[0])
            .background {
                if selected {
                    Capsule()
                        .fill(store.theme.card)
                        .shadow(color: store.theme.separator.opacity(0.12), radius: 1, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.55)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
