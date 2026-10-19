import SwiftUI
import VoiceCore

struct SearchField: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    @State private var available: CGFloat = 0
    @State private var iconPopover = false
    @State private var hits: [SearchHit] = []
    @State private var selected = 0
    @FocusState private var focused: Bool
    private var compact: Bool { available < store.scaled(200) }
    private var hasQuery: Bool { !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// On these pages the field filters the page's own list, and the panel
    /// lists only matches from other pages.
    private var listKind: SearchKind? {
        switch model.page {
        case .meetings: .meeting
        case .notes: .note
        case .dictation: .dictation
        default: nil
        }
    }
    private var showsResults: Bool { model.page != .actions && hasQuery && (listKind == nil || !hits.isEmpty) }
    private var placeholder: String {
        switch model.page {
        case .actions: "Search action items"
        case .meetings: "Search meetings"
        case .notes: "Search notes"
        case .dictation: "Search dictations"
        default: "Search notes, meetings, dictations"
        }
    }

    var body: some View {
        Group {
            if compact {
                Button { iconPopover = true; model.searchIsPresented = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).help("Search notes, meetings, dictations ⌘K")
                    .popover(isPresented: $iconPopover, arrowEdge: .bottom) {
                        // The popover is its own window: it needs its own focus
                        // state, set once that window is key.
                        FocusedOnAppear { focus in
                            VStack(spacing: LayoutTokens.spacing[1]) {
                                field(focus)
                                if showsResults { results }
                            }
                            .padding(LayoutTokens.spacing[2])
                            .frame(width: store.scaled(360))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .bvTheme(store)
                    }
            } else {
                field($focused)
                    .overlay(alignment: .top) {
                        if model.searchIsPresented && showsResults {
                            results
                                .frame(width: max(available, store.scaled(320)))
                                .offset(y: store.scaled(40) + LayoutTokens.spacing[1])
                                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.searchResultsFrame = $0 }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, minHeight: store.scaled(32))
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { available = $0.width }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.searchFieldFrame = $0 }
        .onChange(of: model.searchFocusRequest) { _, _ in
            model.searchIsPresented = true
            if compact { iconPopover = true } else { focused = true }
        }
        .onChange(of: model.searchIsPresented) { _, shown in
            if !shown { iconPopover = false; model.searchResultsFrame = .zero }
        }
        .onChange(of: iconPopover) { _, shown in
            if !shown && compact { model.searchIsPresented = false }
        }
        .onChange(of: model.searchQuery) { _, query in model.searchIsPresented = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty; selected = 0 }
        .onChange(of: model.mainWindowIsKey) { _, key in
            if !key && !iconPopover { model.searchIsPresented = false }
        }
        .onChange(of: focused) { _, isFocused in if isFocused { model.searchIsPresented = true } }
        .task(id: model.searchQuery + "\u{0}" + model.page.rawValue) { await search() }
    }

    private func field(_ focus: FocusState<Bool>.Binding) -> some View {
        HStack(spacing: LayoutTokens.spacing[1]) {
            Image(systemName: "magnifyingglass").foregroundStyle(.bvSecondary)
            TextField(placeholder, text: $model.searchQuery)
                .textFieldStyle(.plain).focused(focus)
                .accessibilityLabel(placeholder)
                .onSubmit(openSelected)
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
            if model.searchQuery.isEmpty { Text("⌘K").bvFont(.caption).foregroundStyle(.bvSecondary) }
            else {
                Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .bvFont(.body)
        .padding(.horizontal, LayoutTokens.spacing[2]).padding(.vertical, LayoutTokens.spacing[1])
        .background(.bvHover, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).stroke(.bvSeparator))
        .simultaneousGesture(TapGesture().onEnded { model.searchIsPresented = true })
    }
    private var results: some View {
        SearchResults(
            hits: hits, selected: selected, model: model, open: open,
            header: listKind == nil ? nil : "Other pages",
            footer: listKind == nil ? "Results from this page come first." : nil)
    }
    private func move(_ offset: Int) {
        model.searchIsPresented = true
        selected = min(max(0, selected + offset), max(0, hits.count - 1))
    }
    private func openSelected() { if hits.indices.contains(selected) { open(hits[selected]) } }
    private func open(_ hit: SearchHit) { focused = false; iconPopover = false; model.open(hit) }
    private func dismiss() {
        model.searchQuery = ""
        model.searchIsPresented = false
        iconPopover = false
        hits = []
    }
    private func search() async {
        guard model.page != .actions else { hits = []; return }
        let query = model.searchQuery
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { hits = []; return }
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        let inputs = model.searchIndexer.searchInputs()
        let first: SearchKind? = switch model.page {
        case .meetings: .meeting
        case .notes: .note
        case .dictation: .dictation
        case .settings: .settings
        default: nil
        }
        let excluded = listKind
        let found = await Task.detached(priority: .userInitiated) {
            // The page's own matches are in its list; ask for more so the cut
            // to `GlobalSearch.limit` happens after they are dropped.
            let all = GlobalSearch.search(query, passages: inputs.passages, titles: inputs.titles, first: first, limit: excluded == nil ? GlobalSearch.limit : 200)
            return Array(all.filter { $0.kind != excluded }.prefix(GlobalSearch.limit))
        }.value
        guard !Task.isCancelled, query == model.searchQuery else { return }
        hits = found
        selected = min(selected, max(0, found.count - 1))
    }
}

private struct FocusedOnAppear<Content: View>: View {
    @FocusState private var focused: Bool
    @ViewBuilder var content: (FocusState<Bool>.Binding) -> Content

    var body: some View {
        content($focused).task {
            try? await Task.sleep(for: .milliseconds(100))
            focused = true
        }
    }
}
