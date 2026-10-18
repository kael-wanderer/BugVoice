import AppKit
import SwiftUI
import VoiceCore

struct HeroCard<Illustration: View>: View {
    @Environment(AppearanceStore.self) private var store
    let title: String
    let text: String
    let placeholder: String
    var hint: String?
    var isDisabled = false
    var focusRequest: UInt64 = 0
    @FocusState private var inputFocused: Bool
    let onAdd: (String) -> Void
    @ViewBuilder var illustration: Illustration

    @State private var input = ""
    @State private var cardWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: LayoutTokens.spacing[4]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                Text(title).bvFont(.title3)
                Text(text).foregroundStyle(.bvSecondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField(placeholder, text: $input)
                        .textFieldStyle(.roundedBorder)
                        .focused($inputFocused)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmed.isEmpty || isDisabled)
                }
                .disabled(isDisabled)
                if let hint { Text(hint).bvFont(.footnote).foregroundStyle(.bvSecondary) }
            }
            .frame(maxWidth: store.scaled(520), alignment: .leading)
            if cardWidth >= 700 {
                Spacer(minLength: 0)
                illustration.frame(width: store.scaled(260), height: 150)
            }
        }
        .insightsCard()
        .task(id: focusRequest) { if focusRequest > 0 { inputFocused = true } }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { cardWidth = $0 }
    }

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        guard !trimmed.isEmpty, !isDisabled else { return }
        onAdd(trimmed)
        input = ""
    }
}

struct HeroIllustration<Chips: View>: View {
    @Environment(AppearanceStore.self) private var store
    let symbol: String
    @ViewBuilder var chips: Chips

    var body: some View {
        ZStack {
            ForEach([150.0, 110.0], id: \.self) { size in
                Circle().strokeBorder(store.theme.secondaryText.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: size, height: size)
            }
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) { chips }
            Image(systemName: symbol).bvFont(.title3).foregroundStyle(.bvOnAccent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).fill(store.theme.accent))
                .offset(x: 105, y: -55)
        }
    }
}

struct HeroChip<Content: View>: View {
    @Environment(AppearanceStore.self) private var store
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: LayoutTokens.spacing[0]) { content }
            .bvFont(.body)
            .padding(.horizontal, LayoutTokens.spacing[1]).padding(.vertical, LayoutTokens.spacing[0])
            .background(Capsule().fill(store.theme.background))
            .overlay(Capsule().strokeBorder(store.theme.separator))
            .shadow(color: store.theme.separator.opacity(0.08), radius: 2, y: 1)
    }
}
