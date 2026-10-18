import SwiftUI
import VoiceCore

struct TitleBar<Action: View>: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    let title: String
    @ViewBuilder var action: Action

    var body: some View {
        ShellTitleLayout(gap: LayoutTokens.spacing[2], searchWidth: store.scaled(460)) {
            HStack(spacing: LayoutTokens.spacing[1]) {
                if model.sidebarHidden { WindowButtonsSpace() }
                Button { model.toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.plain)
                    .help(model.sidebarHidden ? "Show sidebar ⌃⌘S" : "Hide sidebar ⌃⌘S")
                Text(title).bvFont(.title2).lineLimit(1).truncationMode(.tail)
            }
            Color.clear.frame(height: store.scaled(28))
            action
        }
        .padding(.horizontal, LayoutTokens.spacing[3])
        .padding(.vertical, LayoutTokens.spacing[1])
        .frame(minHeight: store.scaled(52))
        .background(WindowDragArea())
        .background(.bvBackground)
    }
}

/// Equal side columns keep search on the panel's centerline. At small widths
/// the search slot collapses to an icon; the title can truncate independently.
struct ShellTitleLayout: Layout {
    var gap: CGFloat
    var searchWidth: CGFloat
    private func widths(_ width: CGFloat, _ views: Subviews) -> (CGFloat, CGFloat) {
        let side = min(max(views[0].sizeThatFits(.unspecified).width, views[2].sizeThatFits(.unspecified).width), max(0, (width - 2 * gap) / 2 - 20))
        return (side, min(searchWidth, max(0, width - side * 2 - gap * 2)))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1000
        let (side, center) = widths(width, subviews)
        let height = max(subviews[0].sizeThatFits(.init(width: side, height: nil)).height,
                         subviews[1].sizeThatFits(.init(width: center, height: nil)).height,
                         subviews[2].sizeThatFits(.init(width: side, height: nil)).height)
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (side, center) = widths(bounds.width, subviews)
        subviews[0].place(at: .init(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .init(width: side, height: bounds.height))
        subviews[1].place(at: .init(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .init(width: center, height: bounds.height))
        subviews[2].place(at: .init(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .init(width: side, height: bounds.height))
    }
}
