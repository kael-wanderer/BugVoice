import SwiftUI
import VoiceCore

enum PageColumnWidth { case reading, wide, sectioned, sectionedWide }

extension View {
    func bvPageColumn(_ width: PageColumnWidth) -> some View { modifier(PageColumnModifier(width: width)) }
}

private struct PageColumnModifier: ViewModifier {
    @Environment(AppearanceStore.self) private var store
    let width: PageColumnWidth
    private var maximum: CGFloat {
        let section = ShellLayout.sectionListWidth(scale: store.settings.textScale) + LayoutTokens.spacing[4]
        switch width {
        case .reading: return store.readingWidth
        case .wide: return store.readingWidth + store.scaled(260)
        case .sectioned: return section + store.readingWidth
        case .sectionedWide: return section + store.readingWidth + store.scaled(260)
        }
    }
    func body(content: Content) -> some View {
        PageColumnLayout(maximum: maximum) { content }
    }
}

/// Receives the full ScrollView proposal, measures its one content block at
/// ShellLayout's width, and places it on the horizontal centerline.
private struct PageColumnLayout: Layout {
    let maximum: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? maximum + 2 * LayoutTokens.spacing[5]
        let width = ShellLayout.blockWidth(available: available, block: maximum)
        let height = subviews[0].sizeThatFits(.init(width: width, height: nil)).height
        return .init(width: available, height: height + 2 * LayoutTokens.spacing[5])
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = ShellLayout.blockWidth(available: bounds.width, block: maximum)
        subviews[0].place(at: .init(x: bounds.midX - width / 2, y: bounds.minY + LayoutTokens.spacing[5]), proposal: .init(width: width, height: nil))
    }
}
