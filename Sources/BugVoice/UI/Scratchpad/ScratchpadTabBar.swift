import BugVoiceMac
import SwiftUI
import VoiceCore

/// Top of the Scratchpad window: one tab per open note and "+", then Keep on
/// top, Smaller/Larger and Close.
struct ScratchpadTabBar: View {
    @Bindable var model: AppModel
    let onNew: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.accentColor)
                .padding(.leading, 12)
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
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
                .padding(.horizontal, 6)
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
            .padding(.trailing, 10)
        }
        .frame(height: 40)
    }

    private func tab(_ id: NoteID) -> some View {
        let active = model.scratchpadTabs.active == id
        let title = model.notesController.notes.first { $0.id == id }?.title ?? "Untitled"
        return HStack(spacing: 6) {
            Text(title).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                .fontWeight(active ? .semibold : .regular)
            Button {
                Task { await model.closeNoteTab(id) }
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Close tab (⌘W)")
            .accessibilityLabel("Close \(title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? Color(nsColor: .textBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                do { try await model.openNoteTab(id) }
                catch { model.saveError = "Could not save the current note: \(error.localizedDescription)" }
            }
        }
    }
}
