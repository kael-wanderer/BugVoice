import AppKit
import SwiftUI

struct VocabularyTab: View {
    @Bindable var model: AppModel
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One term per line. Use  spoken => written  for exact replacements, which apply last in every style. Saved to vocabulary.txt.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 260)
            HStack {
                Button("Save") { model.saveVocabulary(text) }.keyboardShortcut("s")
                Button("Open in editor") { NSWorkspace.shared.open(model.paths.vocabulary) }
                Button("Reload") {
                    text = (try? String(contentsOf: model.paths.vocabulary, encoding: .utf8)) ?? ""
                    model.saveVocabulary(text)
                }
                Spacer()
                Text("\(model.vocabulary.terms.count) terms · \(model.vocabulary.replacements.count) replacements")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { text = model.vocabularyText }
    }
}
