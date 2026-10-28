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
                && (query.isEmpty || AskText.fold($0.text).contains(query) || AskText.fold($0.appName ?? "").contains(query) || AskText.fold($0.command ?? "").contains(query))
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
                if !model.failedDictations.isEmpty {
                    Text("NEEDS ATTENTION").bvFont(.footnote).foregroundStyle(.bvSecondary)
                    ForEach(model.failedDictations) { failedRow($0) }
                }
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

        .task {
            model.reloadFailedDictations()
            await model.reloadHistory()
        }
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

    func failedRow(_ item: FailedDictation) -> some View {
        let running = model.retryingFailedID == item.id
        let expiry = item.startedAt.addingTimeInterval(FailedDictationStore.maxAge)
        let until = expiry.formatted(date: .omitted, time: .shortened) + (Calendar.current.isDateInToday(expiry) ? " today" : " tomorrow")
        return HStack(alignment: .top, spacing: LayoutTokens.spacing[2]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                Text(item.startedAt.formatted(date: .omitted, time: .shortened)).bvFont(.body)
                Text("\(item.appName ?? "Unknown") · \(Int(item.duration.rounded())) s").bvFont(.caption).foregroundStyle(.bvSecondary)
            }
            .frame(width: store.scaled(120), alignment: .leading)
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                if running {
                    Text("Transcribing…").bvFont(.body)
                } else {
                    Text("Transcription failed").bvFont(.body).foregroundStyle(.bvWarning)
                    Text("\(item.reason) The recording is kept until \(until).")
                        .bvFont(.caption).foregroundStyle(.bvSecondary).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: LayoutTokens.spacing[1]) {
                Button("Retry") { model.dictation?.retryFailed(item) }
                    .help("Transcribe again and copy the text")
                Menu {
                    ForEach(RetryLanguage.options(model.settings.speech.dictationLanguages), id: \.language) { option in
                        Button(option.label) { model.dictation?.retryFailed(item, language: option.language) }
                    }
                } label: { Image(systemName: "chevron.down") }
                .help("Choose a retry language")
                .accessibilityLabel("Choose a retry language")
                Button { model.deleteFailedDictation(item.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete the recording").accessibilityLabel("Delete the recording")
            }
            .disabled(model.retryingFailedID != nil)
        }
        .padding(LayoutTokens.spacing[2])
        .background(.bvCard, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(.bvSeparator))
    }

    func row(_ e: HistoryEntry) -> some View {
        let issues = e.fidelityIssues ?? []
        return HStack(alignment: .top, spacing: LayoutTokens.spacing[2]) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                Text(e.startedAt.formatted(date: .omitted, time: .shortened)).bvFont(.body)
                HStack(spacing: LayoutTokens.spacing[0]) {
                    Text(e.appName ?? "Unknown").bvFont(.caption).foregroundStyle(.bvSecondary)
                    if e.command != nil {
                        Text("Command").bvFont(.caption).foregroundStyle(.bvAccent).fixedSize()
                            .padding(.horizontal, LayoutTokens.spacing[0])
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.bvSeparator))
                    }
                    if !issues.isEmpty {
                        Text(e.rawReason == .detailChanged ? "raw · detail" : "check")
                            .bvFont(.caption).foregroundStyle(.bvWarning).fixedSize()
                            .padding(.horizontal, LayoutTokens.spacing[0])
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.bvWarning))
                            .help((["Cleanup changed"] + FidelityCheck.describe(issues)).joined(separator: "\n"))
                    }
                    if issues.isEmpty, let reason = e.rawReason, [.modelError, .modelTimeout, .placeholderLost].contains(reason) {
                        Text("raw").bvFont(.caption).foregroundStyle(.bvWarning)
                    }
                }
            }
            .frame(width: store.scaled(e.command == nil && issues.isEmpty ? 80 : 160), alignment: .leading)
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                if let command = e.command {
                    Text("“\(command)”").italic().bvFont(.body).foregroundStyle(.bvSecondary)
                        .textSelection(.enabled)
                }
                Text(e.text).bvFont(.reading).textSelection(.enabled)
            }
            .frame(maxWidth: store.readingWidth, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: LayoutTokens.spacing[1]) {
                Button { model.dictation?.copy(e.text) } label: { Image(systemName: "doc.on.doc") }.help("Copy").accessibilityLabel("Copy")
                if !issues.isEmpty {
                    Button {
                        if e.rawReason == .detailChanged {
                            if let cleaned = e.cleaned { model.dictation?.pasteAgain(cleaned) }
                        } else {
                            model.dictation?.pasteAgain(e.raw)
                        }
                    } label: { Image(systemName: "arrow.left.arrow.right") }
                    .help(e.rawReason == .detailChanged ? "Paste the cleaned version" : "Paste the raw version")
                    .accessibilityLabel(e.rawReason == .detailChanged ? "Paste the cleaned version" : "Paste the raw version")
                }
                Button { model.dictation?.pasteAgain(e.text) } label: { Image(systemName: "arrow.uturn.right") }.help("Paste again").accessibilityLabel("Paste again")
                Button { Task { await model.deleteHistory(id: e.id) } } label: { Image(systemName: "trash") }.help("Delete").accessibilityLabel("Delete")
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
