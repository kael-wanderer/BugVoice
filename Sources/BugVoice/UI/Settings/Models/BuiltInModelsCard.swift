import SwiftUI
import VoiceCore

/// Settings › Models: the built-in catalog with Download, Cancel and Delete per model.
struct BuiltInModelsCard: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var confirmDelete: BuiltInModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Built-in models").bvFont(.bodyStrong)
            Text("Run by BugVoice on this Mac. Nothing else to install. Unloaded after \(model.settings.models.builtInIdleMinutes) minutes idle to free memory.")
                .bvFont(.footnote).foregroundStyle(.bvSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, LayoutTokens.spacing[1])
            ForEach(BuiltInCatalog.models) { item in
                Divider()
                row(item).padding(.vertical, LayoutTokens.spacing[1])
            }
            Divider()
            HStack {
                Picker("Unload after", selection: $model.settings.models.builtInIdleMinutes) {
                    ForEach(ModelSettings.allowedBuiltInIdleMinutes, id: \.self) { Text("\($0) minutes idle").tag($0) }
                }
                .fixedSize()
                Text("Top bar speed, bottom bar quality.").bvFont(.footnote).foregroundStyle(.bvSecondary)
            }
            .padding(.top, LayoutTokens.spacing[1])
        }
        .insightsCard()
        .confirmationDialog(
            confirmDelete.map(BuiltInChoices.deleteQuestion) ?? "",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible,
            presenting: confirmDelete
        ) { item in
            Button("Delete", role: .destructive) { Task { await model.deleteBuiltIn(item) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ item: BuiltInModel) -> some View {
        let fraction = model.builtInDownloads[item.id]
        let installed = model.builtInInstalled.contains(item.id)
        let inUse = installed && BuiltInChoices.isInUse(item.id, models: model.settings.models)
        return VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            HStack(alignment: .center, spacing: LayoutTokens.spacing[2]) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: LayoutTokens.spacing[1]) {
                        Text(item.name).fontWeight(.semibold)
                        if inUse { BuiltInBadge(text: "In use") }
                    }
                    Text(detail(item, fraction: fraction)).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    if let fraction {
                        ProgressView(value: fraction).frame(maxWidth: store.scaled(180))
                            .accessibilityLabel("\(item.name) download")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BuiltInMeters(model: item)
                Text(BuiltInChoices.gigabytes(item.bytes)).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    .monospacedDigit()
                button(item, fraction: fraction, installed: installed, inUse: inUse)
            }
            if let message = model.builtInDownloadErrors[item.id] ?? (installed ? model.builtInLoadFailures[item.id] : nil) {
                Text(message).bvFont(.footnote).foregroundStyle(.bvWarning)
            }
        }
    }

    /// "Qwen3 8B · Downloading, 41%" while downloading, else the catalog line.
    private func detail(_ item: BuiltInModel, fraction: Double?) -> String {
        guard let fraction else { return item.summary }
        let family = item.summary.components(separatedBy: " · ").first ?? item.name
        if BuiltInChoices.isChecking(fraction) { return "\(family) · Checking the file" }
        return "\(family) · Downloading, \(Int(fraction * 100))%"
    }

    @ViewBuilder
    private func button(_ item: BuiltInModel, fraction: Double?, installed: Bool, inUse: Bool) -> some View {
        if let fraction {
            // The hash check cannot be cancelled; it ends on its own.
            if !BuiltInChoices.isChecking(fraction) {
                Button("Cancel") { model.cancelBuiltInDownload(item.id) }
                    .accessibilityLabel("Cancel \(item.name) download")
            }
        } else if installed {
            Button("Delete") {
                if inUse { confirmDelete = item } else { Task { await model.deleteBuiltIn(item) } }
            }
            .accessibilityLabel("Delete \(item.name)")
        } else {
            Button(model.builtInDownloadErrors[item.id] == nil ? "Download" : "Try again") { model.downloadBuiltIn(item) }
                .disabled(model.builtInDownloadingID != nil)
                .help(model.builtInDownloadingID != nil ? "One download at a time." : "")
                .accessibilityLabel("Download \(item.name)")
        }
    }
}

/// Speed on top, quality below, as three-segment bars.
struct BuiltInMeters: View {
    let model: BuiltInModel

    var body: some View {
        VStack(spacing: 3) {
            meter(model.speed)
            meter(model.quality)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed \(model.speed) of 3, quality \(model.quality) of 3")
    }

    private func meter(_ filled: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(i < filled ? AnyShapeStyle(.bvAccent) : AnyShapeStyle(.bvHover))
                    .frame(width: 14, height: 4)
            }
        }
    }
}

/// A small pill such as "In use" or "Fits this Mac".
struct BuiltInBadge: View {
    let text: String

    var body: some View {
        Text(text).bvFont(.footnote)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(.bvAccentSoft))
            .foregroundStyle(.bvAccent)
    }
}
