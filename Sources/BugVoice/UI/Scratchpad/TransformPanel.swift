import AppKit
import BugVoiceMac
import SwiftUI
import VoiceCore

/// Under the editor: Working…, the preview with its word diff, Ask, or an error.
struct TransformPanel: View {
    @Bindable var assistant: ScratchpadAssistant
    let model: AppModel
    let noteID: NoteID

    private var controller: NotesController { model.notesController }

    var body: some View {
        switch assistant.phase {
        case .idle:
            EmptyView()
        case .running(let label):
            panel {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(label)
                    Spacer()
                    Button("Cancel") { assistant.cancel() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        case .preview(let preview):
            panel { previewBody(preview) }
        case .ask(let input):
            panel { askBody(input) }
        case .failed(let message):
            panel {
                HStack {
                    Text(message).foregroundStyle(.orange)
                    Spacer()
                    Button("OK") { assistant.close() }
                }
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
    }

    @ViewBuilder private func previewBody(_ preview: TransformPreview) -> some View {
        let stale = assistant.isStale(preview.input, controller: controller)
        HStack {
            Text(preview.title).font(.headline)
            Text("\(preview.input.words) words → \(NoteTransformPrompt.wordCount(preview.result))")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(preview.modelName) · \(preview.seconds) s").font(.caption).foregroundStyle(.secondary)
        }
        ScrollView {
            diffText(WordDiff.diff(preview.input.text, preview.result))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 180)
        if stale {
            Text("The note changed. Run the transform again.").foregroundStyle(.orange)
        }
        HStack {
            Spacer()
            Button("Discard") { assistant.close() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("Insert below") { assistant.insertBelow(preview, controller: controller) }
                .disabled(stale)
            Button("Replace") { assistant.replace(preview, controller: controller) }
                .keyboardShortcut(.defaultAction)
                .disabled(stale)
        }
    }

    private func diffText(_ pieces: [WordDiffPiece]) -> Text {
        pieces.reduce(Text("")) { result, piece in
            switch piece {
            case .same(let text): result + Text(text)
            case .removed(let text): result + Text(text).strikethrough().foregroundColor(.secondary)
            case .added(let text): result + Text(text).foregroundColor(.green)
            }
        }
    }

    @ViewBuilder private func askBody(_ input: TransformInput) -> some View {
        HStack {
            Text("Ask a question").font(.headline)
            Text(input.header).foregroundStyle(.secondary)
            Spacer()
            Button("Done") { assistant.close() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        HStack {
            TextField("What do you want to know about this note?", text: $assistant.question)
                .textFieldStyle(.roundedBorder)
                .onSubmit { assistant.sendQuestion(model: model) }
                .disabled(assistant.isAsking)
            if assistant.isAsking { ProgressView().controlSize(.small) }
        }
        if let answer = assistant.answer {
            Text("From this note:").font(.caption).foregroundStyle(.secondary)
            ScrollView { Text(LocalizedStringKey(answer)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(maxHeight: 160)
            HStack {
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                }
                Button("Insert below") { assistant.insertAnswer(into: noteID, controller: controller) }
            }
        }
    }
}
