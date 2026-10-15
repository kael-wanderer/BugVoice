import SwiftUI
import VoiceCore

struct SnippetDraft: Identifiable {
    let id = UUID()
    var snippetID: Snippet.ID?
    var trigger: String
    var text: String
}

struct SnippetEditorSheet: View {
    let model: AppModel
    let draft: SnippetDraft
    @State private var trigger: String
    @State private var text: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, draft: SnippetDraft) {
        self.model = model
        self.draft = draft
        _trigger = State(initialValue: draft.trigger)
        _text = State(initialValue: draft.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.snippetID == nil ? "New snippet" : "Edit snippet").font(.headline)
            TextField("Trigger", text: $trigger).textFieldStyle(.roundedBorder)
            Text("Text").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.body).frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
                    .disabled(isBlank(text) || isBlank(trigger) || model.dictionaryReadOnly)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let snippetID = draft.snippetID
        let trigger = trigger
        let text = text
        Task {
            do {
                try await model.editDictionary { file in
                    if let snippetID { try file.updateSnippet(snippetID, trigger: trigger, text: text) }
                    else { try file.addSnippet(trigger: trigger, text: text) }
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
