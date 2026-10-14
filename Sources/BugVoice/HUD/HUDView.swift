import SwiftUI

@MainActor
@Observable
final class HUDModel {
    var state: HUDState?
    var level: Float = 0
}

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 9)
        .background(Color(white: 0.11), in: Capsule())
        .fixedSize()
    }

    @ViewBuilder var content: some View {
        switch model.state {
        case .listening(let handsFree, let app, let startedAt, let limit):
            Circle().fill(.red).frame(width: 9, height: 9)
            if handsFree { Text("Hands-free").fontWeight(.semibold) }
            LevelBars(level: model.level)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.clock(context.date.timeIntervalSince(startedAt)) + (limit.map { " / " + Self.clock($0) } ?? ""))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            if let app { Text(app).font(.caption).padding(.horizontal, 7).background(.white.opacity(0.12), in: Capsule()) }
        case .transcribing(let language):
            ProgressView().controlSize(.small).tint(.white)
            Text("Transcribing").fontWeight(.semibold)
            Text(language).foregroundStyle(.secondary)
        case .cleaning(let modelName, let app):
            ProgressView().controlSize(.small).tint(.white)
            Text(modelName.map { "Cleaning (\($0))" } ?? "Cleaning").fontWeight(.semibold)
            if let app { Text(app).foregroundStyle(.secondary) }
        case .done(let style, let words, let seconds):
            Image(systemName: "checkmark").foregroundStyle(.green)
            Text("Done (\(style))").fontWeight(.semibold)
            Text("\(words) words · \(seconds, specifier: "%.1f") s").foregroundStyle(.secondary)
        case .warning(let title, let detail):
            Circle().fill(.orange).frame(width: 8, height: 8)
            Text(title).fontWeight(.semibold)
            Text(detail).foregroundStyle(.secondary)
        case .failure(let title, let detail):
            RoundedRectangle(cornerRadius: 2).fill(.red).frame(width: 8, height: 8)
            Text(title).fontWeight(.semibold)
            Text(detail).foregroundStyle(.secondary)
        case .nothingHeard:
            Text("Nothing heard").foregroundStyle(.secondary)
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
    private let weights: [Float] = [0.4, 0.7, 1, 0.8, 0.55, 0.9, 0.65, 1, 0.5, 0.75, 0.45, 0.6]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule().frame(width: 3, height: CGFloat(4 + 14 * min(1, level * weights[i])))
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: level)
    }
}
