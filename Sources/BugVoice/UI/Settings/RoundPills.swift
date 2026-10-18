import SwiftUI
import VoiceCore

struct RoundPills<Value: Hashable>: View {
    let items: [(Value, String)]
    @Binding var selection: Value
    var small = false

    var body: some View {
        HStack(spacing: LayoutTokens.spacing[0]) {
            ForEach(items, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title)
                        .bvFont(small ? .footnote : selection == value ? .bodyStrong : .body)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, LayoutTokens.spacing[2])
                        .padding(.vertical, LayoutTokens.spacing[1])
                        .background(selection == value ? AnyShapeStyle(.bvBackground) : AnyShapeStyle(.clear), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(LayoutTokens.spacing[0])
        .background(.bvHover, in: Capsule())
        .overlay(Capsule().stroke(.bvSeparator))
    }
}

struct AppearanceCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
            Text(title).bvFont(.title3)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LayoutTokens.spacing[3])
        .bvCard()
    }
}
