import AppKit
import SwiftUI
import VoiceCore

struct StyleAppEntry: Identifiable, Hashable {
    var id: String
    var name: String
    var bundleID: String?
    var isOverride: Bool
}

@MainActor
enum StyleApps {
    static func entries(for style: Style, overrides: [String: Style]) -> [StyleAppEntry] {
        let builtIn = StyleRouter.builtInApps(for: style)
            .filter { overrides[$0] == nil || overrides[$0] == style }
            .map { StyleAppEntry(id: $0, name: appName($0), bundleID: $0, isOverride: overrides[$0] != nil) }
        let moved = overrides
            .filter { $0.value == style && StyleRouter.defaultApps[$0.key] != style }
            .keys
            .map { StyleAppEntry(id: $0, name: appName($0), bundleID: $0, isOverride: true) }
        let apps = (builtIn + moved).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let sites = StyleRouter.websites(for: style).map { StyleAppEntry(id: $0, name: $0, bundleID: nil, isOverride: false) }
        return apps + sites
    }

    static func summary(for style: Style, overrides: [String: Style]) -> String {
        if style == .other { return "Every app not listed" }
        let names = entries(for: style, overrides: overrides).filter { $0.bundleID != nil }.prefix(4).map(\.name)
        return names.isEmpty ? "No apps" : names.joined(separator: ", ")
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

struct StylePage: View {
    @Bindable var model: AppModel
    @State private var selected: Style = .personal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style").font(.title2.weight(.semibold))
            Text("Each app is matched to a style when you start dictating. The style sets how the text model cleans your words.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    ForEach(Style.allCases, id: \.self) { style in
                        Button { selected = style } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).fontWeight(.semibold)
                                Text(StyleApps.summary(for: style, overrides: model.settings.styles.appOverrides))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(selected == style ? Color.primary.opacity(0.08) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 230)
                ScrollView { StyleDetailView(model: model, style: selected) }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
