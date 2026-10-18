import AppKit
import SwiftUI
import VoiceCore

struct DictationHistoryView: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var query = ""

    var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return model.history }
        return model.history.filter {
            $0.text.localizedCaseInsensitiveContains(query) || ($0.appName ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var groups: [(String, [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { day in
            let title = calendar.isDateInToday(day) ? "Today"
                : calendar.isDateInYesterday(day) ? "Yesterday"
                : day.formatted(.dateTime.month(.abbreviated).day())
            return (title, grouped[day]!.sorted { $0.startedAt > $1.startedAt })
        }
    }

    var body: some View {
        let stats = HistoryStats.compute(model.history, now: Date())
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: store.scaled(130)), spacing: LayoutTokens.spacing[1], alignment: .leading)],
                    alignment: .leading, spacing: LayoutTokens.spacing[1]
                ) {
                    StatTile(value: stats.wordsToday.formatted(), label: "words today")
                    StatTile(value: "\(stats.wordsPerMinute)", label: "words per minute")
                    StatTile(value: "\(stats.dictationsToday)", label: "dictations today")
                    StatTile(value: stats.medianReleaseToText.map { String(format: "%.1f s", $0) } ?? "–", label: "median release → text")
                }
                if model.history.isEmpty {
                    EmptyState("No dictations yet", systemImage: "mic", message: "Hold \(model.settings.hotkey.spokenName) anywhere and speak.")
                }
                ForEach(groups, id: \.0) { title, entries in
                    Text(title.uppercased()).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    ForEach(entries) { entry in row(entry) }
                }
            }
            .padding(LayoutTokens.spacing[4])
        }
        .searchable(text: $query, prompt: "Search dictations")
        .navigationTitle("Dictation")
        .task { await model.reloadHistory() }
    }

    func row(_ e: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: LayoutTokens.spacing[2]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                Text(e.startedAt.formatted(date: .omitted, time: .shortened)).bvFont(.body)
                HStack(spacing: LayoutTokens.spacing[0]) {
                    Text(e.appName ?? "Unknown").bvFont(.caption).foregroundStyle(.bvSecondary)
                    if let reason = e.rawReason, [.modelError, .modelTimeout, .placeholderLost].contains(reason) {
                        Text("raw").bvFont(.caption).foregroundStyle(.bvWarning)
                    }
                }
            }
            .frame(width: store.scaled(80), alignment: .leading)
            Text(e.text).bvFont(.reading).textSelection(.enabled).frame(maxWidth: store.readingWidth, alignment: .leading).frame(maxWidth: .infinity)
            HStack(spacing: LayoutTokens.spacing[1]) {
                Button { model.dictation?.copy(e.text) } label: { Image(systemName: "doc.on.doc") }.help("Copy")
                Button { model.dictation?.pasteAgain(e.text) } label: { Image(systemName: "arrow.uturn.right") }.help("Paste again")
                Button { Task { await model.deleteHistory(id: e.id) } } label: { Image(systemName: "trash") }.help("Delete")
            }
            .buttonStyle(.borderless)
        }
        .padding(LayoutTokens.spacing[2])
        .background(.bvCard, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(.bvSeparator))
    }
}

struct StatTile: View {
    @Environment(AppearanceStore.self) private var store
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            Text(value).bvFont(.title2).monospacedDigit()
            Text(label).bvFont(.footnote).foregroundStyle(.bvSecondary).lineLimit(1)
        }
        .padding(.horizontal, LayoutTokens.spacing[2]).padding(.vertical, LayoutTokens.spacing[1])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bvCard, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(.bvSeparator))
    }
}
