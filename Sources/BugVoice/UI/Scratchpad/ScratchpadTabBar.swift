import BugVoiceMac
import SwiftUI
import VoiceCore

/// Top of the Scratchpad window: one tab per open note and "+", then Keep on
/// top, Smaller/Larger and Close.
struct ScratchpadTabBar: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var model: AppModel
    let onNew: () -> Void

    var body: some View {
        HStack(spacing: LayoutTokens.spacing[0]) {
            Image(systemName: "waveform")
                .foregroundStyle(store.theme.accent)
                .padding(.leading, LayoutTokens.spacing[2])
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutTokens.spacing[0]) {
                    ForEach(model.scratchpadTabs.ids, id: \.self) { id in
                        tab(id)
                    }
                    Button(action: onNew) {
                        Image(systemName: "plus").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("New note (⌘N)")
                    .accessibilityLabel("New note")
                }
                .padding(.horizontal, LayoutTokens.spacing[0])
            }
            Spacer(minLength: 8)
            Toggle(isOn: $model.settings.scratchpad.keepOnTop) {
                Image(systemName: model.settings.scratchpad.keepOnTop ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Keep on top")
            .accessibilityLabel("Keep on top")
            Button {
                model.settings.scratchpad.compact.toggle()
            } label: {
                Image(systemName: model.settings.scratchpad.compact
                    ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help(model.settings.scratchpad.compact ? "Larger" : "Smaller")
            .accessibilityLabel(model.settings.scratchpad.compact ? "Larger" : "Smaller")
            Button {
                model.closeScratchpadWindow(returnToPreviousApp: false)
            } label: {
                Image(systemName: "xmark").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityLabel("Close")
            .padding(.trailing, LayoutTokens.spacing[1])
        }
        .frame(height: 40)
    }

    private func tab(_ id: NoteID) -> some View {
        let active = model.scratchpadTabs.active == id
        let title = model.notesController.notes.first { $0.id == id }?.title ?? "Untitled"
        return HStack(spacing: LayoutTokens.spacing[0]) {
            Text(title).lineLimit(1).frame(maxWidth: store.scaled(160), alignment: .leading)
                .fontWeight(active ? .semibold : .regular)
            Button {
                Task { await model.closeNoteTab(id) }
            } label: {
                Image(systemName: "xmark").bvFont(.caption)
            }
            .buttonStyle(.borderless)
            .help("Close tab (⌘W)")
            .accessibilityLabel("Close \(title)")
        }
        .padding(.horizontal, LayoutTokens.spacing[1])
        .padding(.vertical, LayoutTokens.spacing[0])
        .background(active ? store.theme.background : .clear, in: RoundedRectangle(cornerRadius: LayoutTokens.controlRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                do { try await model.openNoteTab(id) }
                catch { model.saveError = "Could not save the current note: \(error.localizedDescription)" }
            }
        }
    }
}
