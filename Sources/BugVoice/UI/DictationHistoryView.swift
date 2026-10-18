import AppKit
import SwiftUI
import VoiceCore

struct DictationHistoryView: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var filter: Style?
    @State private var highlighted: UUID?

    var filtered: [HistoryEntry] {
        let query = AskText.fold(model.dictationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        return model.history.filter {
            (filter == nil || $0.style == filter)
                && (query.isEmpty || AskText.fold($0.text).contains(query) || AskText.fold($0.appName ?? "").contains(query))
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
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[2]) {
                CardGrid(minCardWidth: store.scaled(150), spacing: LayoutTokens.spacing[1]) {
                    StatTile(value: stats.wordsToday.formatted(), label: "words today")
                    StatTile(value: "\(stats.wordsPerMinute)", label: "words per minute")
                    StatTile(value: "\(stats.dictationsToday)", label: "dictations today")
                    StatTile(value: stats.medianReleaseToText.map { String(format: "%.1f s", $0) } ?? "–", label: "median release → text")
                }
                RoundPills("Filter by style", items: [(Style?.none, "All")] + Style.allCases.map { (Optional($0), $0.rawValue.capitalized) }, selection: $filter)
                if filtered.isEmpty && !model.history.isEmpty {
                    if model.dictationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EmptyState("No dictations with this style", systemImage: "line.3.horizontal.decrease")
                    } else {
                        EmptyState("No matching dictations", systemImage: "magnifyingglass")
                    }
                }
                if model.history.isEmpty {
                    EmptyState("No dictations yet", systemImage: "mic", message: "Hold \(model.settings.hotkey.spokenName) anywhere and speak.")
                }
                ForEach(groups, id: \.0) { title, entries in
                    Text(title.uppercased()).bvFont(.footnote).foregroundStyle(.bvSecondary)
                    ForEach(entries) { entry in row(entry).id(entry.id) }
                }
            }
            .bvPageColumn(.wide)
        }

        .task { await model.reloadHistory() }
        .task(id: model.dictationHighlight) {
            guard let id = model.dictationHighlight else { return }
            filter = nil
            // Let the All filter lay out the requested row before scrolling.
            await Task.yield()
            reader.scrollTo(id, anchor: .center)
            highlighted = id
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            withAnimation(.easeOut(duration: 1.5)) { highlighted = nil }
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            if model.dictationHighlight == id { model.dictationHighlight = nil }
        }
        }
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
        .background(highlighted == e.id ? AnyShapeStyle(.bvAccentSoft) : AnyShapeStyle(.bvCard), in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
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
            Text(label).bvFont(.footnote).foregroundStyle(.bvSecondary)
        }
        .padding(.horizontal, LayoutTokens.spacing[2]).padding(.vertical, LayoutTokens.spacing[1])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.bvCard, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(.bvSeparator))
    }
}
