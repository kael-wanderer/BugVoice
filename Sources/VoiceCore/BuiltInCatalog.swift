import Foundation

/// One cleanup model BugVoice can download and run with its bundled llama-server.
public struct BuiltInModel: Equatable, Sendable, Identifiable {
    public enum Tier: String, Sendable { case small, medium, large }

    public let id: String
    public let tier: Tier
    public let name: String
    public let summary: String
    public let fileName: String
    public let url: URL
    public let sha256: String
    public let bytes: Int64
    public let memoryBytes: Int64
    public let speed: Int
    public let quality: Int
}

public enum BuiltInCatalog {
    /// Share of physical memory a model may use.
    public static let memoryShare: Double = 0.30

    // Ids are the bench `--llm-model` ids. They must contain "qwen":
    // PromptBuilder turns thinking off only then.
    // memoryBytes = bench RSS MB x 1_048_576, rounded up to the next 100 MB.
    public static let models: [BuiltInModel] = [
        BuiltInModel(
            id: "qwen3-vl-2b-instruct-q4_k_m",
            tier: .small,
            name: "Small",
            summary: "Qwen3-VL 2B · fastest, English best",
            fileName: "Qwen3VL-2B-Instruct-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/52d6c8ffea26cc873ac5ad116f8631268d7eb503/Qwen3VL-2B-Instruct-Q4_K_M.gguf")!,
            sha256: "089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae",
            bytes: 1_107_409_952,
            memoryBytes: 2_200_000_000,
            speed: 3, quality: 1),
        BuiltInModel(
            id: "qwen3-4b-q4_k_m",
            tier: .medium,
            name: "Medium",
            summary: "Qwen3 4B · good English and Vietnamese",
            fileName: "Qwen3-4B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/bc640142c66e1fdd12af0bd68f40445458f3869b/Qwen3-4B-Q4_K_M.gguf")!,
            sha256: "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5",
            bytes: 2_497_280_256,
            memoryBytes: 3_700_000_000,
            speed: 2, quality: 2),
        BuiltInModel(
            id: "qwen3-8b-q4_k_m",
            tier: .large,
            name: "Large",
            summary: "Qwen3 8B · best text, needs 24 GB+",
            fileName: "Qwen3-8B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/7c41481f57cb95916b40956ab2f0b139b296d974/Qwen3-8B-Q4_K_M.gguf")!,
            sha256: "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785",
            bytes: 5_027_783_488,
            memoryBytes: 6_200_000_000,
            speed: 1, quality: 3),
    ]

    public static func model(id: String) -> BuiltInModel? {
        models.first { $0.id == id }
    }

    /// The largest model whose memory fits within `memoryShare` of RAM.
    public static func recommended(physicalMemory: UInt64) -> BuiltInModel? {
        let budget = memoryShare * Double(physicalMemory)
        return models.last { Double($0.memoryBytes) <= budget }
    }
}
