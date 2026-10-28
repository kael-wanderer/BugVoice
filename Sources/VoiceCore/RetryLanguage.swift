import Foundation

public enum RetryLanguage {
    public struct Option: Sendable {
        public let language: SpeechLanguage
        public let label: String
    }
    public static func options(_ languages: [SpeechLanguage]) -> [Option] {
        languages.filter { $0 != .auto }.map { Option(language: $0, label: "Retry in \($0.displayName)") }
            + [Option(language: .auto, label: "Retry with automatic language")]
    }
}
