import AppKit
import SwiftUI
import VoiceCore

struct ActionItemsPage: View {
    @Bindable var model: AppModel
    @State private var status: ActionItemStatus = .open
    @State private var owner: ActionItemOwnerFilter = .anyone
    @State private var range: ActionItemRange = .all
    @State private var keepVisible: Set<String> = []
    @State private var expiryTasks: [String: Task<Void, Never>] = [:]
    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?

    private var board: ActionItemBoard {
        ActionItemBoard(meetings: model.meetingManifests, done: model.actionItemsDone, status: status,
                        owner: owner, range: range, query: model.actionItemsSearchQuery, now: Date(), keepVisible: keepVisible)
    }
    private var ownerTitle: String {
        switch owner { case .anyone: "Anyone"; case .none: "No owner"; case .owner(let name): name }
    }
    private func rangeTitle(_ range: ActionItemRange) -> String {
        switch range { case .week: "Last 7 days"; case .month: "Last 30 days"; case .all: "All time" }
    }

    var body: some View {
        let board = board
        VStack(spacing: LayoutTokens.spacing[2]) {
            ViewThatFits(in: .horizontal) {
                HStack { filters(board); Spacer(minLength: 0); copyButton(board) }
                VStack(alignment: .leading) { filters(board); copyButton(board) }
            }
            .padding(.horizontal, LayoutTokens.spacing[3]).padding(.top, LayoutTokens.spacing[2])
            if board.groups.isEmpty {
                if board.openTotal + board.doneTotal == 0 {
                    EmptyState("No action items yet", systemImage: "checklist", message: "Generate them on a meeting's Action items tab.")
                } else if status == .open {
                    EmptyState("Nothing open", systemImage: "checklist", message: "Good work.")
                } else {
                    EmptyState("No items match.", systemImage: "checklist")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: LayoutTokens.spacing[2]) {
                        ForEach(board.groups) { group in groupView(group) }
                    }.padding(.horizontal, LayoutTokens.spacing[3]).padding(.bottom, LayoutTokens.spacing[3])
                }
            }
        }
        .onDisappear {
            expiryTasks.values.forEach { $0.cancel() }; expiryTasks = [:]; keepVisible = []
            copyTask?.cancel(); copied = false
        }
    }

    private func filters(_ board: ActionItemBoard) -> some View {
        HStack(spacing: LayoutTokens.spacing[2]) {
            RoundPills("Status", items: [(.open, "Open"), (.done, "Done"), (.all, "All")], selection: $status, size: .small)
                .fixedSize()
            Menu("Owner: \(ownerTitle)") {
                Button("Anyone") { owner = .anyone }
                ForEach(board.owners, id: \.self) { name in Button(name) { owner = .owner(name) } }
                Button("No owner") { owner = .none }
            }.fixedSize()
            Menu("Meetings from: \(rangeTitle(range))") {
                ForEach(ActionItemRange.allCases, id: \.self) { value in
                    Button(rangeTitle(value)) { range = value }
                }
            }.fixedSize()
        }.bvFont(.body)
    }

    private func copyButton(_ board: ActionItemBoard) -> some View {
        Button(copied ? "Copied" : "Copy open items") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(board.copyMarkdown(), forType: .string)
            copied = true
            copyTask?.cancel()
            copyTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
                copied = false
            }
        }.disabled(board.copyMarkdown().isEmpty)
    }

    private func groupView(_ group: ActionItemGroup) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(group.title) { model.openMeetingActionItems(group.meetingID) }
                    .buttonStyle(.plain).bvFont(.bodyStrong).foregroundStyle(.bvAccent)
                Spacer()
                Text("\(Self.date(group.date)) · \(status == .done ? "\(group.doneCount) done" : "\(group.openCount) open")")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
            }.padding(LayoutTokens.spacing[2])
            Rectangle().fill(.bvSeparator).frame(height: 1)
            ForEach(Array(group.rows.enumerated()), id: \.offset) { index, row in
                ActionItemRowView(row: row, showsUndo: status == .open && keepVisible.contains(row.id)) {
                    toggle(row.item, done: $0)
                }
                if index < group.rows.count - 1 { Rectangle().fill(.bvSeparator).frame(height: 1) }
            }
        }
        .background(.bvCard, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.controlRadius).stroke(.bvSeparator))
    }

    private func toggle(_ item: ActionItem, done: Bool) {
        expiryTasks[item.id]?.cancel()
        expiryTasks[item.id] = nil
        if done && status == .open {
            keepVisible.insert(item.id)
            expiryTasks[item.id] = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                keepVisible.remove(item.id)
                expiryTasks[item.id] = nil
            }
        } else { keepVisible.remove(item.id) }
        model.setActionItemDone(item, done)
    }

    private static func date(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }
}
