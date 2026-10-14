import Foundation

public enum NotesExporter {
    public static func markdown(title: String, body: String) -> String {
        String(decoding: NotesMarkdownDocument.serialize(title: title, body: body), as: UTF8.self)
    }
}
