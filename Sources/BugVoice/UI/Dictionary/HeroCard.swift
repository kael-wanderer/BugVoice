import AppKit
import SwiftUI

struct HeroCard<Illustration: View>: View {
    let title: String
    let text: String
    let placeholder: String
    var hint: String?
    var isDisabled = false
    let onAdd: (String) -> Void
    @ViewBuilder var illustration: Illustration

    @State private var input = ""
    @State private var cardWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.semibold))
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField(placeholder, text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmed.isEmpty || isDisabled)
                }
                .disabled(isDisabled)
                if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: 520, alignment: .leading)
            if cardWidth >= 700 {
                Spacer(minLength: 0)
                illustration.frame(width: 260, height: 150)
            }
        }
        .insightsCard()
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
    let symbol: String
    @ViewBuilder var chips: Chips

    var body: some View {
        ZStack {
            ForEach([150.0, 110.0], id: \.self) { size in
                Circle().strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: size, height: size)
            }
            VStack(alignment: .leading, spacing: 8) { chips }
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                .offset(x: 105, y: -55)
        }
    }
}

struct HeroChip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
