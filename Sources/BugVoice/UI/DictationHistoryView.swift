import AppKit
import SwiftUI
import VoiceCore

struct DictationHistoryView: View {
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    StatTile(value: stats.wordsToday.formatted(), label: "words today")
                    StatTile(value: "\(stats.wordsPerMinute)", label: "words per minute")
                    StatTile(value: "\(stats.dictationsToday)", label: "dictations today")
                    StatTile(value: stats.medianReleaseToText.map { String(format: "%.1f s", $0) } ?? "–", label: "median release → text")
                }
                if model.history.isEmpty {
                    ContentUnavailableView("No dictations yet", systemImage: "mic", description: Text("Hold Right Option anywhere and speak."))
                }
                ForEach(groups, id: \.0) { title, entries in
                    Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(entries) { entry in row(entry) }
                }
            }
            .padding(22)
        }
        .searchable(text: $query, prompt: "Search dictations")
        .navigationTitle("Dictation")
        .task { await model.reloadHistory() }
    }

    func row(_ e: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.startedAt.formatted(date: .omitted, time: .shortened)).font(.callout)
                HStack(spacing: 4) {
                    Text(e.appName ?? "Unknown").font(.caption2).foregroundStyle(.secondary)
                    if let reason = e.rawReason, [.modelError, .modelTimeout, .placeholderLost].contains(reason) {
                        Text("raw").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .frame(width: 80, alignment: .leading)
            Text(e.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button { model.dictation?.copy(e.text) } label: { Image(systemName: "doc.on.doc") }.help("Copy")
                Button { model.dictation?.pasteAgain(e.text) } label: { Image(systemName: "arrow.uturn.right") }.help("Paste again")
                Button { Task { await model.deleteHistory(id: e.id) } } label: { Image(systemName: "trash") }.help("Delete")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.separator))
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minWidth: 130, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}
