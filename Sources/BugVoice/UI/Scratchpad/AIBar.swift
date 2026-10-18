import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore

/// The AI bar: Polish, More professional, More casual, Run again, and a box
/// for follow-ups or questions. While a request runs it shows Working… and Cancel.
struct AIBar: View {
    @Environment(AppearanceStore.self) private var store
    @Bindable var assistant: ScratchpadAssistant
    let model: AppModel
    let noteID: NoteID
    let input: () -> TransformInput?

    @FocusState private var questionFocused: Bool
    @State private var choosingMeeting = false

    var body: some View {
        content.sheet(isPresented: $choosingMeeting) { meetingPicker }
            .task(id: assistant.questionFocusRequest) {
                if assistant.questionFocusRequest > 0 { questionFocused = true }
            }
    }

    @ViewBuilder private var content: some View {
        switch assistant.phase {
        case .running(let label):
            HStack(spacing: LayoutTokens.spacing[1]) {
                if assistant.askStep == nil {
                    ProgressView().controlSize(.small)
                    Text(label).foregroundStyle(.bvSecondary)
                }
                Spacer()
                Button(assistant.askStep == nil ? "Cancel" : "Stop") { assistant.cancel() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.vertical, LayoutTokens.spacing[0])
        case .failed(let message):
            HStack {
                Text(message).foregroundStyle(.bvWarning)
                Spacer()
                Button("OK") { assistant.cancel() }
            }
            .padding(.vertical, LayoutTokens.spacing[0])
        case .idle:
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[1]) {
                // A narrow window puts the scope menu on its own line so the chips keep their titles.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LayoutTokens.spacing[0]) {
                        scopeMenu
                        chips
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
                        scopeMenu
                        FlowLayout(spacing: LayoutTokens.spacing[0]) { chips }
                    }
                }
                Divider()
                HStack(spacing: LayoutTokens.spacing[1]) {
                    TextField("Follow up or ask a question", text: $assistant.message)
                        .textFieldStyle(.plain)
                        .focused($questionFocused)
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").bvFont(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(assistant.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.scope.questionIsTooLong(assistant.message))
                    .accessibilityLabel("Send")
                }
                if assistant.scope.questionIsTooLong(assistant.message) { Text("Shorter question, please.").bvFont(.footnote).foregroundStyle(.bvSecondary) }
            }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(NoteTransform.allCases, id: \.self) { transform in
            Button(transform.title) { run(transform) }
                .disabled(assistant.scope != .note(noteID))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .help("\(transform.title) (⌘\(String(transform.shortcutKey)))")
        }
        Button {
            assistant.runAgain(model: model)
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderless)
        .disabled(!assistant.canRunAgain(noteID: noteID, controller: model.notesController))
        .help("Run again")
        .accessibilityLabel("Run again")
    }

    private var scopeMenu: some View {
        Menu {
            Button("This note") { assistant.changeScope(.note(noteID)) }
            let folder = model.notesController.note(id: noteID)?.frontMatter.folderID
            Button(model.askScopeTitle(.folder(folder))) { assistant.changeScope(.folder(folder)) }
            Button("A meeting…") { choosingMeeting = true }
            Button("All notes and meetings") { assistant.changeScope(.all) }
        } label: {
            Text(Self.shortTitle(model.askScopeTitle(assistant.scope))).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        // Keep the borderless menu to its title so the chips get the remaining space.
        .fixedSize()
        .accessibilityLabel("Search in")
    }

    /// Long meeting titles would push the question field out of the row.
    private static func shortTitle(_ title: String) -> String {
        title.count > 32 ? String(title.prefix(31)) + "…" : title
    }

    private var meetingPicker: some View {
        AskMeetingPicker(meetings: model.meetingManifests) { id in
            assistant.changeScope(.meeting(id))
            choosingMeeting = false
        }
    }

    private func run(_ transform: NoteTransform) {
        guard let input = input() else { return }
        assistant.run(transform, input: input, model: model)
    }

    private func send() {
        guard let input = input() else { return }
        assistant.send(input: input, model: model)
    }
}

/// A question's answer above the bar: Copy, Insert below, Dismiss.
struct AIReplyView: View {
    @Environment(AppearanceStore.self) private var store
    let reply: AssistantReply
    let onInsert: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[0]) {
            Text(reply.message).bvFont(.body).foregroundStyle(.bvSecondary).lineLimit(2)
            ScrollView {
                Text(LocalizedStringKey(reply.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 44, maxHeight: 140)
            HStack {
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reply.text, forType: .string)
                }
                Button("Insert below", action: onInsert)
                Button("Dismiss", action: onDismiss)
            }
        }
        .padding(LayoutTokens.spacing[1])
        .background(store.theme.background, in: RoundedRectangle(cornerRadius: LayoutTokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutTokens.cardRadius).stroke(store.theme.secondaryText.opacity(0.25)))
    }
}
