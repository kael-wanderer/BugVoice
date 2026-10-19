import Foundation

public struct ProjectWord: Codable, Equatable, Sendable {
    public var word: String
    public var rank: Int

    public init(word: String, rank: Int) {
        self.word = word
        self.rank = rank
    }
}

public struct ProjectSourceFile: Sendable {
    public var path: String
    public var contents: String?

    public init(path: String, contents: String?) {
        self.path = path
        self.contents = contents
    }
}

public enum ProjectWordExtractor {
    public static let maxWords = 1_000
    public static let sourceExtensions: Set<String> = [
        "swift", "m", "h", "c", "cc", "cpp", "rs", "go", "py", "rb", "js", "jsx", "ts", "tsx", "java", "kt", "cs", "php", "scala", "sh", "sql"
    ]

    private static let declarationKeywords: Set<String> = [
        "class", "struct", "enum", "protocol", "actor", "extension", "func", "def", "fn", "type", "interface", "trait", "function"
    ]
    private static let tokenPattern = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]{3,39}"#)

    public static func shouldRead(path: String) -> Bool {
        guard !isSecretLooking(path: path), sourceExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { return false }
        return true
    }

    public static func isSecretLooking(path: String) -> Bool {
        let parts = path.lowercased().split(separator: "/").map(String.init)
        for part in parts {
            if part.hasPrefix(".env") || part.hasSuffix(".pem") || part.hasSuffix(".key") || part.contains("credentials") || part.contains("secret") {
                return true
            }
        }
        return false
    }

    public static func isCodeShaped(_ token: String) -> Bool {
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard tokenPattern.firstMatch(in: token, range: range)?.range == range else { return false }

        let letters = token.filter(\.isLetter)
        let digits = token.filter(\.isNumber)
        guard digits.count <= letters.count else { return false }
        if token.count >= 8, token.allSatisfy({ $0.isHexDigit }) { return false }

        var parts: [String] = []
        var current = ""
        let chars = Array(token)
        for index in chars.indices {
            let char = chars[index]
            if char == "_" {
                if !current.isEmpty { parts.append(current); current = "" }
                continue
            }
            let previous = index > 0 ? chars[index - 1] : nil
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            let lowerToUpper = (previous?.isLowercase == true || previous?.isNumber == true) && char.isUppercase
            let acronymBoundary = previous?.isUppercase == true && char.isUppercase && next?.isLowercase == true
            if (lowerToUpper || acronymBoundary), !current.isEmpty {
                parts.append(current)
                current = ""
            }
            current.append(char)
        }
        if !current.isEmpty { parts.append(current) }
        return parts.filter { !$0.isEmpty }.count >= 2
    }

    public static func fileNameWords(path: String) -> [String] {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        if stem.contains("-") || stem.contains(".") { return [name] }
        let pieces = stem.split(separator: "+").map(String.init)
        if pieces.count > 1 {
            return pieces.filter { isCodeShaped($0) || ($0.first?.isUppercase == true && $0.count >= 4) }
        }
        return pieces.filter(isCodeShaped)
    }

    public static func identifiers(in contents: String) -> [String] {
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        var seen = Set<String>()
        var result: [String] = []
        for match in tokenPattern.matches(in: contents, range: range) {
            guard let swiftRange = Range(match.range, in: contents) else { continue }
            let token = String(contents[swiftRange])
            if isCodeShaped(token), seen.insert(token).inserted { result.append(token) }
        }
        return result
    }

    public static func declared(in contents: String) -> Set<String> {
        let tokenRegex = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*"#)
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        let matches = tokenRegex.matches(in: contents, range: range)
        let tokens = matches.compactMap { match -> String? in
            guard let tokenRange = Range(match.range, in: contents) else { return nil }
            return String(contents[tokenRange])
        }
        var result = Set<String>()
        for index in tokens.indices where declarationKeywords.contains(tokens[index]) {
            let next = tokens.index(after: index)
            if next < tokens.endIndex, isCodeShaped(tokens[next]) { result.insert(tokens[next]) }
        }
        return result
    }

    public static func extract(files: [ProjectSourceFile], hidden: Set<String>) -> [ProjectWord] {
        var fileCounts: [String: Int] = [:]
        var boosted = Set<String>()
        for file in files {
            let fileWords = Set(fileNameWords(path: file.path))
            let identifiers = Set(file.contents.map(identifiers(in:)) ?? [])
            let words = fileWords.union(identifiers)
            for word in words { fileCounts[word, default: 0] += 1 }
            boosted.formUnion(fileWords)
            if let contents = file.contents { boosted.formUnion(declared(in: contents)) }
        }
        return fileCounts.compactMap { word, count -> ProjectWord? in
            guard !hidden.contains(word) else { return nil }
            return ProjectWord(word: word, rank: count + (boosted.contains(word) ? 5 : 0))
        }
        .sorted { lhs, rhs in lhs.rank == rhs.rank ? lhs.word < rhs.word : lhs.rank > rhs.rank }
        .prefix(maxWords)
        .map { $0 }
    }
}
