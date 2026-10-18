import SwiftUI
import VoiceCore

struct SplitButton<Items: View>: View {
    let title: String
    var systemImage: String?
    let action: () -> Void
    @ViewBuilder var menu: Items

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void, @ViewBuilder menu: () -> Items) {
        self.title = title; self.systemImage = systemImage; self.action = action; self.menu = menu()
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: LayoutTokens.spacing[0]) {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(title).fixedSize(horizontal: false, vertical: true)
                }
            }
            Menu { menu } label: { Image(systemName: "chevron.down") }
                .menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More \(title.lowercased()) actions")
        }
        .bvFont(.body)
        .buttonStyle(.borderedProminent)
    }
}
