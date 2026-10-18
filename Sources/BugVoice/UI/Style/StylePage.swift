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
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                RoundPills("Style sections", items: Style.allCases.map { ($0, $0.title) }, selection: $selected)
                VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                    Text("Each app is matched to a style when you start dictating. The style sets how the text model cleans your words.")
                        .foregroundStyle(.bvSecondary)
                    StyleDetailView(model: model, style: selected)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.bvPageColumn(.wide)
        }
    }
}
