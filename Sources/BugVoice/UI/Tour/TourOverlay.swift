import SwiftUI
import VoiceCore

/// The tour: dims the main window, rings the current target and shows its card.
/// It swallows every click outside the card, so nothing underneath can start a
/// recording, open a meeting window or paste.
struct TourOverlay: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    let anchors: [TourStop: Anchor<CGRect>]
    @FocusState private var focused: Bool

    private let cardWidth: CGFloat = 300
    private let margin: CGFloat = 12

    var body: some View {
        if let index = model.tourIndex, model.tourCards.indices.contains(index) {
            let card = model.tourCards[index]
            GeometryReader { proxy in
                let target = anchors[card.stop].map { proxy[$0].insetBy(dx: -4, dy: -3) }
                ZStack(alignment: .topLeading) {
                    Dim(hole: target, radius: LayoutTokens.controlRadius + 2)
                        .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture {}
                    if let target {
                        RoundedRectangle(cornerRadius: LayoutTokens.controlRadius + 2)
                            .stroke(store.theme.accent, lineWidth: 2)
                            .frame(width: target.width, height: target.height)
                            .offset(x: target.minX, y: target.minY)
                            .allowsHitTesting(false)
                    }
                    cardView(card, index: index, target: target, size: proxy.size)
                }
            }
            .focusable().focused($focused).focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.escape) { model.endTour(); return .handled }
            .onKeyPress(.rightArrow) { model.tourNext(); return .handled }
            .onKeyPress(.leftArrow) { model.tourBack(); return .handled }
            .onKeyPress { _ in .handled }
            .onChange(of: model.page) { _, page in
                if page != card.stop.page { model.endTour() }
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    private enum Side { case right, below }

    private func cardView(_ card: TourCard, index: Int, target: CGRect?, size: CGSize) -> some View {
        let last = index == model.tourCards.count - 1
        let side: Side
        var origin: CGPoint
        var arrow: CGFloat // offset of the arrow along the card edge
        switch (card.stop, target) {
        case (.menuBar, _), (_, nil):
            // Top-right corner of the window, arrow up toward the menu bar.
            side = .below
            origin = CGPoint(x: size.width - cardWidth - 20, y: 24)
            arrow = cardWidth - 28
        case (_, let target?) where card.stop == .recordMeeting:
            side = .below
            origin = CGPoint(x: min(target.maxX - cardWidth, size.width - cardWidth - margin), y: target.maxY + margin)
            origin.x = max(margin, origin.x)
            arrow = min(max(target.midX - origin.x, 16), cardWidth - 16)
        case (_, let target?):
            side = .right
            origin = CGPoint(x: target.maxX + margin + 4, y: target.midY - 40)
            origin.y = max(margin, origin.y)
            arrow = 40
        }
        return VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
            Text(card.title).bvFont(.bodyStrong).foregroundStyle(.bvText)
            Text(card.body).bvFont(.body).foregroundStyle(.bvText).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: LayoutTokens.spacing[1]) {
                Text("\(index + 1) of \(model.tourCards.count)").bvFont(.caption).foregroundStyle(.bvSecondary)
                Spacer(minLength: 0)
                if !last { Button("End tour") { model.endTour() }.buttonStyle(.plain).foregroundStyle(.bvSecondary) }
                if index > 0 { Button("Back") { model.tourBack() } }
                Button(last ? "Done" : "Next") { last ? model.endTour() : model.tourNext() }
                    .buttonStyle(.borderedProminent)
            }.bvFont(.body)
        }
        .padding(LayoutTokens.spacing[2])
        .frame(width: cardWidth, alignment: .leading)
        .background(.bvCard, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius + 2))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius + 2).stroke(store.theme.secondaryText.opacity(0.25)))
        .overlay(alignment: .topLeading) {
            Rectangle().fill(.bvCard).frame(width: 12, height: 12).rotationEffect(.degrees(45))
                .overlay(Rectangle().stroke(store.theme.secondaryText.opacity(0.25)).rotationEffect(.degrees(45)))
                .mask(Rectangle().frame(width: 24, height: 24).offset(side == .below ? CGSize(width: 0, height: -12) : CGSize(width: -12, height: 0)))
                .offset(side == .below ? CGSize(width: arrow - 6, height: -6) : CGSize(width: -6, height: arrow - 6))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .offset(x: origin.x, y: origin.y)
    }

    /// The whole window with an optional rounded hole.
    private struct Dim: Shape {
        let hole: CGRect?
        let radius: CGFloat
        func path(in rect: CGRect) -> Path {
            var path = Path(rect)
            if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius)) }
            return path
        }
    }
}
