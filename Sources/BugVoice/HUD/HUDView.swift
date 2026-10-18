import SwiftUI
import VoiceCore

@MainActor
@Observable
final class HUDModel {
    var state: HUDState?
    var level: Float = 0
}

struct HUDView: View {
    @Environment(AppearanceStore.self) private var store
    private var factor: CGFloat { store.settings.hudSize.factor }
    private var type: BVTypography {
        var settings = store.settings
        settings.textScale = Int((factor * 100).rounded())
        return BVTypography(settings: settings)
    }
    let model: HUDModel

    var body: some View {
        HStack(spacing: LayoutTokens.spacing[2] * factor) {
            content
        }
        .font(type.font(TextToken.body))
        .foregroundStyle(.bvText)
        .padding(.leading, LayoutTokens.spacing[2] * factor)
        .padding(.trailing, LayoutTokens.spacing[3] * factor)
        .padding(.vertical, LayoutTokens.spacing[1] * factor)
        .background(.bvCard, in: Capsule())
        .overlay(Capsule().strokeBorder(.bvSeparator, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .padding(LayoutTokens.spacing[1])
        .fixedSize()
    }

    @ViewBuilder var content: some View {
        switch model.state {
        case .listening(let handsFree, let app, let startedAt, let limit):
            Circle().fill(.bvRecording).frame(width: 9 * factor, height: 9 * factor)
            if handsFree { Text("Hands-free").fontWeight(.semibold) }
            LevelBars(level: model.level, factor: factor)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.clock(context.date.timeIntervalSince(startedAt)) + (limit.map { " / " + Self.clock($0) } ?? ""))
                    .monospacedDigit().foregroundStyle(.bvSecondary)
            }
            if let app { Text(app).padding(.horizontal, LayoutTokens.spacing[1] * factor).background(.bvHover, in: Capsule()) }
        case .transcribing(let language):
            ProgressView().controlSize(.small).tint(store.theme.text)
            Text("Transcribing").fontWeight(.semibold)
            Text(language).foregroundStyle(.bvSecondary)
        case .cleaning(let modelName, let app):
            ProgressView().controlSize(.small).tint(store.theme.text)
            Text(modelName.map { "Cleaning (\($0))" } ?? "Cleaning").fontWeight(.semibold)
            if let app { Text(app).foregroundStyle(.bvSecondary) }
        case .done(let style, let words, let seconds):
            Image(systemName: "checkmark").foregroundStyle(.bvSuccess)
            Text("Done (\(style))").fontWeight(.semibold)
            Text("\(words) words · \(seconds, specifier: "%.1f") s").foregroundStyle(.bvSecondary)
        case .warning(let title, let detail):
            Circle().fill(.bvWarning).frame(width: 8 * factor, height: 8 * factor)
            Text(title).fontWeight(.semibold)
            Text(detail).foregroundStyle(.bvSecondary)
        case .failure(let title, let detail):
            RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).fill(.bvRecording).frame(width: 8 * factor, height: 8 * factor)
            Text(title).fontWeight(.semibold)
            Text(detail).foregroundStyle(.bvSecondary)
        case .nothingHeard:
            Text("Nothing heard").foregroundStyle(.bvSecondary)
        case nil:
            EmptyView()
        }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct LevelBars: View {
    let level: Float
    var factor: CGFloat = 1
    private let weights: [Float] = [0.4, 0.7, 1, 0.8, 0.55, 0.9, 0.65, 1, 0.5, 0.75, 0.45, 0.6]

    var body: some View {
        HStack(spacing: 2 * factor) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule().frame(width: 3 * factor, height: CGFloat(4 + 14 * min(1, level * weights[i])) * factor)
            }
        }
        .frame(height: 18 * factor)
        .animation(.linear(duration: 0.08), value: level)
    }
}
