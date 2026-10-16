import BugVoiceMac
import SwiftUI
import VoiceCore

/// One tab per open note, "+", and the Markdown/Doc switch at the right.
struct ScratchpadTabBar: View {
    @Bindable var model: AppModel
    let onNew: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.scratchpadTabs.ids, id: \.self) { id in
                        tab(id)
                    }
                    Button(action: onNew) {
                        Image(systemName: "plus").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("New note")
                    .accessibilityLabel("New note")
                }
                .padding(.horizontal, 8)
            }
            Picker("View", selection: Binding(get: { model.scratchpadView }, set: { model.scratchpadView = $0 })) {
                ForEach(NoteViewMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.trailing, 12)
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tab(_ id: NoteID) -> some View {
        let active = model.scratchpadTabs.active == id
        let title = model.notesController.notes.first { $0.id == id }?.title ?? "Untitled"
        return HStack(spacing: 6) {
            Text(title).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
            Button {
                Task { await model.closeNoteTab(id) }
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Close tab")
            .accessibilityLabel("Close \(title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? Color.secondary.opacity(0.3) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                do { try await model.openNoteTab(id) }
                catch { model.saveError = "Could not save the current note: \(error.localizedDescription)" }
            }
        }
    }
}
